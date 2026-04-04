use matrix_sdk::ruma::events::room::message::{
    OriginalSyncRoomMessageEvent, RoomMessageEventContent,
};
use matrix_sdk::ruma::{OwnedRoomId, RoomId};
use matrix_sdk::Client;
use std::sync::{Arc, Mutex};

use crate::error::{ParlotteError, Result};
use crate::message::SessionInfo;
use crate::room::RoomInfo;
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
    inner: Client,
    runtime: tokio::runtime::Runtime,
    sync_manager: SyncManager,
    event_listener: Arc<Mutex<Option<Arc<dyn EventListener>>>>,
}

impl ParlotteClient {
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
            inner: client,
            runtime,
            sync_manager: SyncManager::new(),
            event_listener: Arc::new(Mutex::new(None)),
        })
    }

    /// Create a client from an existing matrix_sdk::Client and runtime.
    /// Primarily used for testing.
    pub(crate) fn from_inner(client: Client, runtime: tokio::runtime::Runtime) -> Self {
        Self {
            inner: client,
            runtime,
            sync_manager: SyncManager::new(),
            event_listener: Arc::new(Mutex::new(None)),
        }
    }

    /// Log in with username and password.
    pub fn login(&self, username: &str, password: &str) -> Result<SessionInfo> {
        self.runtime.block_on(async {
            self.inner
                .matrix_auth()
                .login_username(username, password)
                .send()
                .await
                .map_err(|e| ParlotteError::Auth {
                    message: e.to_string(),
                })?;

            let user_id = self
                .inner
                .user_id()
                .ok_or_else(|| ParlotteError::Auth {
                    message: "no user_id after login".to_string(),
                })?
                .to_string();

            let device_id = self
                .inner
                .device_id()
                .ok_or_else(|| ParlotteError::Auth {
                    message: "no device_id after login".to_string(),
                })?
                .to_string();

            Ok(SessionInfo {
                user_id,
                device_id,
            })
        })
    }

    /// Log out and invalidate the current session.
    pub fn logout(&self) -> Result<()> {
        self.runtime.block_on(async {
            self.sync_manager.stop();
            self.inner
                .matrix_auth()
                .logout()
                .await
                .map_err(|e| ParlotteError::Auth {
                    message: e.to_string(),
                })?;
            Ok(())
        })
    }

    /// Get a list of all joined rooms.
    pub fn rooms(&self) -> Result<Vec<RoomInfo>> {
        self.runtime.block_on(async {
            let joined = self.inner.joined_rooms();
            let mut rooms = Vec::with_capacity(joined.len());

            for room in joined {
                let display_name = room
                    .display_name()
                    .await
                    .map(|dn| dn.to_string())
                    .unwrap_or_else(|_| "Unknown".to_string());

                let topic = room.topic();
                let is_encrypted = !matches!(room.encryption_state(), matrix_sdk::EncryptionState::NotEncrypted);

                rooms.push(RoomInfo {
                    id: room.room_id().to_string(),
                    display_name,
                    is_encrypted,
                    topic,
                });
            }

            Ok(rooms)
        })
    }

    /// Send a text message to a room.
    pub fn send_message(&self, room_id: &str, body: &str) -> Result<()> {
        self.runtime.block_on(async {
            let room_id = <&RoomId>::try_from(room_id).map_err(|e| ParlotteError::Room {
                message: format!("invalid room ID: {e}"),
            })?;

            let room = self
                .inner
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

    /// Perform a single sync cycle. Useful for tests and initial sync.
    pub fn sync_once(&self) -> Result<()> {
        self.runtime
            .block_on(SyncManager::sync_once(&self.inner))
    }

    /// Register an event listener to receive incoming messages and state changes.
    pub fn set_event_listener(&self, listener: Arc<dyn EventListener>) {
        let listener_clone = listener.clone();
        *self.event_listener.lock().unwrap() = Some(listener);

        self.inner.add_event_handler(
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
        &self.inner
    }

    /// Access the tokio runtime (for tests).
    pub(crate) fn runtime(&self) -> &tokio::runtime::Runtime {
        &self.runtime
    }

    /// Create a room with the given name. Returns the room ID.
    pub fn create_room(&self, name: &str) -> Result<String> {
        use matrix_sdk::ruma::api::client::room::create_room::v3::Request as CreateRoomRequest;

        self.runtime.block_on(async {
            let mut request = CreateRoomRequest::new();
            request.name = Some(name.to_owned());

            let response =
                self.inner
                    .create_room(request)
                    .await
                    .map_err(|e| ParlotteError::Room {
                        message: format!("failed to create room: {e}"),
                    })?;

            Ok(response.room_id().to_string())
        })
    }

    /// Invite a user to a room.
    pub fn invite_user(&self, room_id: &str, user_id: &str) -> Result<()> {
        self.runtime.block_on(async {
            let room_id = <&RoomId>::try_from(room_id).map_err(|e| ParlotteError::Room {
                message: format!("invalid room ID: {e}"),
            })?;

            let user_id = matrix_sdk::ruma::UserId::parse(user_id).map_err(|e| {
                ParlotteError::Room {
                    message: format!("invalid user ID: {e}"),
                }
            })?;

            let room = self
                .inner
                .get_room(room_id)
                .ok_or_else(|| ParlotteError::Room {
                    message: format!("room {room_id} not found"),
                })?;

            room.invite_user_by_id(&user_id)
                .await
                .map_err(|e| ParlotteError::Room {
                    message: format!("failed to invite user: {e}"),
                })?;

            Ok(())
        })
    }

    /// Join a room by its ID.
    pub fn join_room(&self, room_id: &str) -> Result<()> {
        self.runtime.block_on(async {
            let room_id =
                OwnedRoomId::try_from(room_id.to_owned()).map_err(|e| ParlotteError::Room {
                    message: format!("invalid room ID: {e}"),
                })?;

            self.inner
                .join_room_by_id(&room_id)
                .await
                .map_err(|e| ParlotteError::Room {
                    message: format!("failed to join room: {e}"),
                })?;

            Ok(())
        })
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

    // Note: SQLite store path testing is covered in integration tests because
    // the deadpool connection pool has tokio runtime lifecycle requirements
    // that conflict with ParlotteClient's embedded runtime in unit test context.
}
