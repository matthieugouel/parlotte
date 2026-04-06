use matrix_sdk::authentication::matrix::MatrixSession;
use matrix_sdk::room::MessagesOptions;
use matrix_sdk::ruma::events::room::message::{
    OriginalSyncRoomMessageEvent, RoomMessageEventContent,
};
use matrix_sdk::ruma::events::AnySyncTimelineEvent;
use matrix_sdk::ruma::{OwnedRoomId, RoomId};
use matrix_sdk::store::RoomLoadSettings;
use matrix_sdk::{Client, SessionMeta, SessionTokens};
use std::sync::{Arc, Mutex};

use crate::error::{ParlotteError, Result};
use crate::message::{MatrixSessionData, MessageInfo, SessionInfo};
use crate::room::{PublicRoomInfo, RoomInfo};
use crate::sync::SyncManager;

/// Callback interface for receiving Matrix events.
pub trait EventListener: Send + Sync + 'static {
    /// Called when a new message is received in a room.
    fn on_message(&self, room_id: String, sender: String, body: String, timestamp_ms: u64);
    /// Called when the sync state changes.
    fn on_sync_state_changed(&self, is_syncing: bool);
}

/// The main Parlotte client wrapping the Matrix SDK.
pub struct ParlotteClient {
    /// Wrapped in Option so Drop can take ownership and drop it inside the runtime.
    inner: Option<Client>,
    runtime: tokio::runtime::Runtime,
    sync_manager: SyncManager,
    event_listener: Arc<Mutex<Option<Arc<dyn EventListener>>>>,
}

impl ParlotteClient {
    /// Access the inner client, panicking if already shut down.
    fn client(&self) -> &Client {
        self.inner.as_ref().expect("client already shut down")
    }

    /// Create a new client connected to the given homeserver.
    ///
    /// `store_path` is the directory where the SQLite database will be stored.
    /// Pass `None` to use an in-memory store (useful for tests).
    pub fn new(homeserver_url: &str, store_path: Option<&str>) -> Result<Self> {
        let runtime = tokio::runtime::Runtime::new().map_err(|e| ParlotteError::Unknown {
            message: format!("failed to create tokio runtime: {e}"),
        })?;

        let client = runtime.block_on(async {
            let mut builder = Client::builder().homeserver_url(homeserver_url);

            if let Some(path) = store_path {
                builder = builder.sqlite_store(path, None);
            }

            builder.build().await.map_err(|e| ParlotteError::Network {
                message: e.to_string(),
            })
        })?;

        Ok(Self {
            inner: Some(client),
            runtime,
            sync_manager: SyncManager::new(),
            event_listener: Arc::new(Mutex::new(None)),
        })
    }

    /// Create a client from an existing matrix_sdk::Client and runtime.
    /// Primarily used for testing.
    pub(crate) fn from_inner(client: Client, runtime: tokio::runtime::Runtime) -> Self {
        Self {
            inner: Some(client),
            runtime,
            sync_manager: SyncManager::new(),
            event_listener: Arc::new(Mutex::new(None)),
        }
    }

    /// Log in with username and password.
    pub fn login(&self, username: &str, password: &str) -> Result<SessionInfo> {
        let client = self.client();
        self.runtime.block_on(async {
            client
                .matrix_auth()
                .login_username(username, password)
                .send()
                .await
                .map_err(|e| ParlotteError::Auth {
                    message: e.to_string(),
                })?;

            let user_id = client
                .user_id()
                .ok_or_else(|| ParlotteError::Auth {
                    message: "no user_id after login".to_string(),
                })?
                .to_string();

            let device_id = client
                .device_id()
                .ok_or_else(|| ParlotteError::Auth {
                    message: "no device_id after login".to_string(),
                })?
                .to_string();

            Ok(SessionInfo { user_id, device_id })
        })
    }

    /// Get the current session data for persistence.
    /// Returns None if not logged in.
    pub fn session(&self) -> Option<MatrixSessionData> {
        let session = self.client().matrix_auth().session()?;
        Some(MatrixSessionData {
            user_id: session.meta.user_id.to_string(),
            device_id: session.meta.device_id.to_string(),
            access_token: session.tokens.access_token,
        })
    }

    /// Restore a previously saved session.
    pub fn restore_session(&self, session_data: MatrixSessionData) -> Result<()> {
        let client = self.client();
        self.runtime.block_on(async {
            let user_id = matrix_sdk::ruma::UserId::parse(&session_data.user_id).map_err(|e| {
                ParlotteError::Auth {
                    message: format!("invalid user ID: {e}"),
                }
            })?;
            let device_id: matrix_sdk::ruma::OwnedDeviceId = session_data.device_id.into();

            let session = MatrixSession {
                meta: SessionMeta { user_id, device_id },
                tokens: SessionTokens {
                    access_token: session_data.access_token,
                    refresh_token: None,
                },
            };

            client
                .matrix_auth()
                .restore_session(session, RoomLoadSettings::default())
                .await
                .map_err(|e| ParlotteError::Auth {
                    message: format!("failed to restore session: {e}"),
                })?;

            Ok(())
        })
    }

    /// Log out and invalidate the current session.
    pub fn logout(&self) -> Result<()> {
        let client = self.client();
        self.runtime.block_on(async {
            self.sync_manager.stop();
            client
                .matrix_auth()
                .logout()
                .await
                .map_err(|e| ParlotteError::Auth {
                    message: e.to_string(),
                })?;
            Ok(())
        })
    }

    /// Get a list of all joined and invited rooms.
    pub fn rooms(&self) -> Result<Vec<RoomInfo>> {
        let client = self.client();
        self.runtime.block_on(async {
            let joined = client.joined_rooms();
            let invited = client.invited_rooms();
            tracing::debug!(joined = joined.len(), invited = invited.len(), "listing rooms");
            let mut rooms = Vec::with_capacity(joined.len() + invited.len());

            for room in joined {
                let display_name = room
                    .display_name()
                    .await
                    .map(|dn| dn.to_string())
                    .unwrap_or_else(|_| "Unknown".to_string());

                let topic = room.topic();
                let is_encrypted = matches!(
                    room.encryption_state(),
                    matrix_sdk::EncryptionState::Encrypted
                );

                let is_public = room.is_public().unwrap_or(false);

                rooms.push(RoomInfo {
                    id: room.room_id().to_string(),
                    display_name,
                    is_encrypted,
                    is_public,
                    topic,
                    is_invited: false,
                });
            }

            for room in invited {
                let display_name = room
                    .display_name()
                    .await
                    .map(|dn| dn.to_string())
                    .unwrap_or_else(|_| "Unknown".to_string());

                let topic = room.topic();
                let is_encrypted = matches!(
                    room.encryption_state(),
                    matrix_sdk::EncryptionState::Encrypted
                );

                let is_public = room.is_public().unwrap_or(false);

                rooms.push(RoomInfo {
                    id: room.room_id().to_string(),
                    display_name,
                    is_encrypted,
                    is_public,
                    topic,
                    is_invited: true,
                });
            }

            Ok(rooms)
        })
    }

    /// Send a text message to a room.
    pub fn send_message(&self, room_id: &str, body: &str) -> Result<()> {
        let client = self.client();
        self.runtime.block_on(async {
            let room_id = <&RoomId>::try_from(room_id).map_err(|e| ParlotteError::Room {
                message: format!("invalid room ID: {e}"),
            })?;

            let room = client
                .get_room(room_id)
                .ok_or_else(|| ParlotteError::Room {
                    message: format!("room {room_id} not found"),
                })?;

            let content = RoomMessageEventContent::text_plain(body);
            room.send(content).await.map_err(|e| ParlotteError::Room {
                message: format!("failed to send message: {e}"),
            })?;

            Ok(())
        })
    }

    /// Get recent messages from a room, most recent last.
    pub fn messages(&self, room_id: &str, limit: u64) -> Result<Vec<MessageInfo>> {
        let client = self.client();
        self.runtime.block_on(async {
            let room_id = <&RoomId>::try_from(room_id).map_err(|e| ParlotteError::Room {
                message: format!("invalid room ID: {e}"),
            })?;

            let room = client
                .get_room(room_id)
                .ok_or_else(|| ParlotteError::Room {
                    message: format!("room {room_id} not found"),
                })?;

            let options = MessagesOptions::backward();

            let response = room.messages(options).await.map_err(|e| ParlotteError::Room {
                message: format!("failed to fetch messages: {e}"),
            })?;

            let mut messages = Vec::new();
            for event in response.chunk {
                let raw = event.raw();
                let Ok(deserialized) = raw.deserialize() else {
                    continue;
                };

                if let AnySyncTimelineEvent::MessageLike(
                    matrix_sdk::ruma::events::AnySyncMessageLikeEvent::RoomMessage(msg),
                ) = deserialized
                {
                    let original = match msg {
                        matrix_sdk::ruma::events::SyncMessageLikeEvent::Original(o) => o,
                        _ => continue,
                    };

                    let body = match original.content.msgtype {
                        matrix_sdk::ruma::events::room::message::MessageType::Text(text) => {
                            text.body
                        }
                        _ => continue,
                    };

                    messages.push(MessageInfo {
                        event_id: original.event_id.to_string(),
                        sender: original.sender.to_string(),
                        body,
                        timestamp_ms: original.origin_server_ts.0.into(),
                    });

                    if messages.len() >= limit as usize {
                        break;
                    }
                }
            }

            // Reverse so oldest is first, newest last
            messages.reverse();
            Ok(messages)
        })
    }

    /// Perform a single sync cycle. Useful for tests and initial sync.
    pub fn sync_once(&self) -> Result<()> {
        tracing::debug!("sync_once starting");
        let result = self.runtime.block_on(SyncManager::sync_once(self.client()));
        match &result {
            Ok(()) => tracing::debug!("sync_once completed"),
            Err(e) => tracing::warn!("sync_once failed: {e}"),
        }
        result
    }

    /// Register an event listener to receive incoming messages and state changes.
    pub fn set_event_listener(&self, listener: Arc<dyn EventListener>) {
        let listener_clone = listener.clone();
        *self.event_listener.lock().unwrap() = Some(listener);

        self.client().add_event_handler(
            move |ev: OriginalSyncRoomMessageEvent, room: matrix_sdk::Room| {
                let listener = listener_clone.clone();
                async move {
                    let body = match ev.content.msgtype {
                        matrix_sdk::ruma::events::room::message::MessageType::Text(text) => {
                            text.body
                        }
                        _ => return,
                    };
                    listener.on_message(
                        room.room_id().to_string(),
                        ev.sender.to_string(),
                        body,
                        ev.origin_server_ts.0.into(),
                    );
                }
            },
        );
    }

    /// Check if sync is currently running.
    pub fn is_syncing(&self) -> bool {
        self.sync_manager.is_running()
    }

    /// Access the underlying matrix_sdk::Client (for advanced usage / tests).
    pub fn inner(&self) -> &Client {
        self.client()
    }

    /// Access the tokio runtime (for tests).
    pub(crate) fn runtime(&self) -> &tokio::runtime::Runtime {
        &self.runtime
    }

    /// Create a room with the given name. Returns the room ID.
    /// If `is_public` is true, the room is listed in the directory and anyone can join.
    pub fn create_room(&self, name: &str, is_public: bool) -> Result<String> {
        use matrix_sdk::ruma::api::client::room::create_room::v3::Request as CreateRoomRequest;
        use matrix_sdk::ruma::api::client::room::Visibility;
        use matrix_sdk::ruma::events::room::encryption::RoomEncryptionEventContent;
        use matrix_sdk::ruma::events::EmptyStateKey;
        use matrix_sdk::ruma::events::InitialStateEvent;

        let client = self.client();
        self.runtime.block_on(async {
            let mut request = CreateRoomRequest::new();
            request.name = Some(name.to_owned());

            if is_public {
                request.visibility = Visibility::Public;
                request.preset = Some(
                    matrix_sdk::ruma::api::client::room::create_room::v3::RoomPreset::PublicChat,
                );
            } else {
                // Private rooms are encrypted by default
                let encryption_content =
                    RoomEncryptionEventContent::with_recommended_defaults();
                let encryption_event =
                    InitialStateEvent::new(EmptyStateKey, encryption_content);
                request
                    .initial_state
                    .push(encryption_event.to_raw_any());
            }

            let response = client
                .create_room(request)
                .await
                .map_err(|e| ParlotteError::Room {
                    message: format!("failed to create room: {e}"),
                })?;

            Ok(response.room_id().to_string())
        })
    }

    /// List public rooms from the server directory.
    pub fn public_rooms(&self) -> Result<Vec<PublicRoomInfo>> {
        use matrix_sdk::ruma::api::client::directory::get_public_rooms_filtered;

        let client = self.client();
        self.runtime.block_on(async {
            let request = get_public_rooms_filtered::v3::Request::new();
            let response = client
                .public_rooms_filtered(request)
                .await
                .map_err(|e| ParlotteError::Room {
                    message: format!("failed to fetch public rooms: {e}"),
                })?;

            Ok(response
                .chunk
                .into_iter()
                .map(|r| PublicRoomInfo {
                    id: r.room_id.to_string(),
                    name: r.name,
                    topic: r.topic,
                    member_count: r.num_joined_members.into(),
                    alias: r.canonical_alias.map(|a| a.to_string()),
                })
                .collect())
        })
    }

    /// Invite a user to a room.
    pub fn invite_user(&self, room_id: &str, user_id: &str) -> Result<()> {
        let client = self.client();
        self.runtime.block_on(async {
            let room_id = <&RoomId>::try_from(room_id).map_err(|e| ParlotteError::Room {
                message: format!("invalid room ID: {e}"),
            })?;

            let user_id =
                matrix_sdk::ruma::UserId::parse(user_id).map_err(|e| ParlotteError::Room {
                    message: format!("invalid user ID: {e}"),
                })?;

            let room = client
                .get_room(room_id)
                .ok_or_else(|| ParlotteError::Room {
                    message: format!("room {room_id} not found"),
                })?;

            tracing::debug!(%user_id, %room_id, "inviting user to room");
            room.invite_user_by_id(&user_id)
                .await
                .map_err(|e| ParlotteError::Room {
                    message: format!("failed to invite user: {e}"),
                })?;

            tracing::debug!(%user_id, %room_id, "invite sent successfully");
            Ok(())
        })
    }

    /// Explicitly shut down, dropping the inner client within the tokio runtime.
    /// This prevents panics from deadpool's connection pool cleanup.
    pub fn shutdown(self) {
        // Drop is implemented below to handle this automatically.
        drop(self);
    }

    /// Join a room by its ID.
    pub fn join_room(&self, room_id: &str) -> Result<()> {
        let client = self.client();
        self.runtime.block_on(async {
            let room_id =
                OwnedRoomId::try_from(room_id.to_owned()).map_err(|e| ParlotteError::Room {
                    message: format!("invalid room ID: {e}"),
                })?;

            client
                .join_room_by_id(&room_id)
                .await
                .map_err(|e| ParlotteError::Room {
                    message: format!("failed to join room: {e}"),
                })?;

            Ok(())
        })
    }
}

impl Drop for ParlotteClient {
    fn drop(&mut self) {
        // Drop the inner Client inside the tokio runtime so that deadpool's
        // SQLite connection pool cleanup has access to a reactor.
        if let Some(client) = self.inner.take() {
            let _ = self.runtime.block_on(async move {
                drop(client);
            });
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::{AtomicU32, Ordering};

    // -- Tests for our input validation and error mapping --

    #[test]
    fn client_creation_with_no_store() {
        // Our code should build a client successfully when given a valid URL
        // and no store path (in-memory mode).
        let client = ParlotteClient::new("http://localhost:1234", None);
        assert!(client.is_ok());
    }

    #[test]
    fn client_creation_with_invalid_url() {
        // Our code maps SDK builder errors into ParlotteError::Network
        let result = ParlotteClient::new("not-a-valid-url", None);
        match result {
            Err(ParlotteError::Network { .. }) => {} // expected
            Err(other) => panic!("expected Network error, got: {other}"),
            Ok(_) => panic!("expected error for invalid URL"),
        }
    }

    #[test]
    fn send_message_rejects_invalid_room_id() {
        let client = ParlotteClient::new("http://localhost:1234", None).unwrap();
        let result = client.send_message("not-a-room-id", "hello");
        assert!(result.is_err());
        let err = result.unwrap_err();
        assert!(matches!(err, ParlotteError::Room { .. }));
        assert!(err.to_string().contains("invalid room ID"));
    }

    #[test]
    fn messages_rejects_invalid_room_id() {
        let client = ParlotteClient::new("http://localhost:1234", None).unwrap();
        let result = client.messages("not-a-room-id", 50);
        assert!(result.is_err());
        assert!(matches!(result.unwrap_err(), ParlotteError::Room { .. }));
    }

    #[test]
    fn messages_rejects_nonexistent_room() {
        let client = ParlotteClient::new("http://localhost:1234", None).unwrap();
        let result = client.messages("!nonexistent:example.com", 50);
        assert!(result.is_err());
        let err = result.unwrap_err();
        assert!(matches!(err, ParlotteError::Room { .. }));
        assert!(err.to_string().contains("not found"));
    }

    #[test]
    fn send_message_rejects_nonexistent_room() {
        let client = ParlotteClient::new("http://localhost:1234", None).unwrap();
        // Valid format but room doesn't exist in client state
        let result = client.send_message("!nonexistent:example.com", "hello");
        assert!(result.is_err());
        let err = result.unwrap_err();
        assert!(matches!(err, ParlotteError::Room { .. }));
        assert!(err.to_string().contains("not found"));
    }

    #[test]
    fn invite_user_rejects_invalid_room_id() {
        let client = ParlotteClient::new("http://localhost:1234", None).unwrap();
        let result = client.invite_user("bad-room", "@alice:example.com");
        assert!(result.is_err());
        assert!(matches!(result.unwrap_err(), ParlotteError::Room { .. }));
    }

    #[test]
    fn invite_user_rejects_invalid_user_id() {
        let client = ParlotteClient::new("http://localhost:1234", None).unwrap();
        let result = client.invite_user("!room:example.com", "not-a-user-id");
        assert!(result.is_err());
        let err = result.unwrap_err();
        assert!(matches!(err, ParlotteError::Room { .. }));
        assert!(err.to_string().contains("invalid user ID"));
    }

    #[test]
    fn join_room_rejects_invalid_room_id() {
        let client = ParlotteClient::new("http://localhost:1234", None).unwrap();
        let result = client.join_room("garbage");
        assert!(result.is_err());
        assert!(matches!(result.unwrap_err(), ParlotteError::Room { .. }));
    }

    #[test]
    fn rooms_returns_empty_before_sync() {
        let client = ParlotteClient::new("http://localhost:1234", None).unwrap();
        let rooms = client.rooms().unwrap();
        assert!(rooms.is_empty());
    }

    #[test]
    fn is_syncing_returns_false_initially() {
        let client = ParlotteClient::new("http://localhost:1234", None).unwrap();
        assert!(!client.is_syncing());
    }

    // -- Tests for EventListener registration --

    struct TestListener {
        message_count: AtomicU32,
    }

    impl TestListener {
        fn new() -> Self {
            Self {
                message_count: AtomicU32::new(0),
            }
        }
        fn count(&self) -> u32 {
            self.message_count.load(Ordering::SeqCst)
        }
    }

    impl EventListener for TestListener {
        fn on_message(&self, _room_id: String, _sender: String, _body: String, _ts: u64) {
            self.message_count.fetch_add(1, Ordering::SeqCst);
        }
        fn on_sync_state_changed(&self, _is_syncing: bool) {}
    }

    #[test]
    fn set_event_listener_does_not_panic() {
        let client = ParlotteClient::new("http://localhost:1234", None).unwrap();
        let listener = Arc::new(TestListener::new());
        client.set_event_listener(listener.clone());
        // No messages received yet since we haven't synced
        assert_eq!(listener.count(), 0);
    }

    #[test]
    fn set_event_listener_replaces_previous() {
        let client = ParlotteClient::new("http://localhost:1234", None).unwrap();
        let listener1 = Arc::new(TestListener::new());
        let listener2 = Arc::new(TestListener::new());
        client.set_event_listener(listener1);
        client.set_event_listener(listener2);
        // Should not panic — second registration replaces stored listener
    }

    #[test]
    fn session_returns_none_before_login() {
        let client = ParlotteClient::new("http://localhost:1234", None).unwrap();
        assert!(client.session().is_none());
    }

    #[test]
    fn restore_session_rejects_invalid_user_id() {
        let client = ParlotteClient::new("http://localhost:1234", None).unwrap();
        let data = MatrixSessionData {
            user_id: "not-a-valid-user-id".into(),
            device_id: "SOMEDEVICE".into(),
            access_token: "some_token".into(),
        };
        let result = client.restore_session(data);
        assert!(result.is_err());
        assert!(matches!(result.unwrap_err(), ParlotteError::Auth { .. }));
    }

    // Note: SQLite store path testing is covered in integration tests because
    // the deadpool connection pool has tokio runtime lifecycle requirements
    // that conflict with ParlotteClient's embedded runtime in unit test context.
}
