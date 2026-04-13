use matrix_sdk::authentication::matrix::MatrixSession;
use matrix_sdk::room::MessagesOptions;
use matrix_sdk::ruma::events::room::message::RoomMessageEventContent;
use matrix_sdk::ruma::events::AnySyncTimelineEvent;
use matrix_sdk::ruma::{OwnedRoomId, RoomId};
use matrix_sdk::store::RoomLoadSettings;
use matrix_sdk::{Client, SessionMeta, SessionTokens};
use std::sync::Arc;

use crate::error::{ParlotteError, Result};
use crate::message::{LoginMethods, MatrixSessionData, MessageBatch, MessageInfo, ReactionInfo, SessionInfo, SsoProvider};
use crate::room::{PublicRoomInfo, RoomInfo, RoomMemberInfo};
use crate::sync::{SyncListener, SyncManager};

/// The main Parlotte client wrapping the Matrix SDK.
pub struct ParlotteClient {
    /// Wrapped in Option so Drop can take ownership and drop it inside the runtime.
    inner: Option<Client>,
    runtime: tokio::runtime::Runtime,
    sync_manager: SyncManager,
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
        })
    }

    /// Query the homeserver for supported login methods.
    pub fn login_methods(&self) -> Result<LoginMethods> {
        use matrix_sdk::ruma::api::client::session::get_login_types::v3::LoginType;

        let client = self.client();
        self.runtime.block_on(async {
            let response = client
                .matrix_auth()
                .get_login_types()
                .await
                .map_err(|e| ParlotteError::Auth {
                    message: format!("failed to get login types: {e}"),
                })?;

            let mut supports_password = false;
            let mut supports_sso = false;
            let mut sso_providers = Vec::new();

            for flow in &response.flows {
                match flow {
                    LoginType::Password(_) => supports_password = true,
                    LoginType::Sso(sso) => {
                        supports_sso = true;
                        for idp in &sso.identity_providers {
                            sso_providers.push(SsoProvider {
                                id: idp.id.clone(),
                                name: idp.name.clone(),
                            });
                        }
                    }
                    _ => {}
                }
            }

            Ok(LoginMethods {
                supports_password,
                supports_sso,
                sso_providers,
            })
        })
    }

    /// Get the URL to redirect the user to for SSO login.
    /// After authentication, the homeserver redirects to `redirect_url` with a `loginToken` parameter.
    pub fn sso_login_url(&self, redirect_url: &str, idp_id: Option<&str>) -> Result<String> {
        let client = self.client();
        self.runtime.block_on(async {
            client
                .matrix_auth()
                .get_sso_login_url(redirect_url, idp_id)
                .await
                .map_err(|e| ParlotteError::Auth {
                    message: format!("failed to get SSO login URL: {e}"),
                })
        })
    }

    /// Complete SSO login using the callback URL containing the loginToken.
    pub fn login_sso_callback(&self, callback_url: &str) -> Result<SessionInfo> {
        let client = self.client();
        self.runtime.block_on(async {
            let url = url::Url::parse(callback_url)
                .map_err(|e| ParlotteError::Auth {
                    message: format!("invalid callback URL: {e}"),
                })?;

            client
                .matrix_auth()
                .login_with_sso_callback(url)
                .map_err(|e| ParlotteError::Auth {
                    message: format!("SSO callback failed: {e}"),
                })?
                .initial_device_display_name("Parlotte")
                .await
                .map_err(|e| ParlotteError::Auth {
                    message: format!("SSO login failed: {e}"),
                })?;

            let user_id = client
                .user_id()
                .ok_or_else(|| ParlotteError::Auth {
                    message: "no user_id after SSO login".to_string(),
                })?
                .to_string();

            let device_id = client
                .device_id()
                .ok_or_else(|| ParlotteError::Auth {
                    message: "no device_id after SSO login".to_string(),
                })?
                .to_string();

            Ok(SessionInfo { user_id, device_id })
        })
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

                let counts = room.unread_notification_counts();
                let unread_count = if counts.notification_count > 0 {
                    counts.notification_count
                } else {
                    room.num_unread_messages()
                };

                rooms.push(RoomInfo {
                    id: room.room_id().to_string(),
                    display_name,
                    is_encrypted,
                    is_public,
                    topic,
                    is_invited: false,
                    unread_count,
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
                    unread_count: 0,
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

    /// Send a reply to a specific message in a room.
    pub fn send_reply(&self, room_id: &str, event_id: &str, body: &str) -> Result<()> {
        use matrix_sdk::room::reply::{EnforceThread, Reply};
        use matrix_sdk::ruma::events::room::message::RoomMessageEventContentWithoutRelation;
        use matrix_sdk::ruma::EventId;

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

            let event_id = <&EventId>::try_from(event_id).map_err(|e| ParlotteError::Room {
                message: format!("invalid event ID: {e}"),
            })?;

            let content = RoomMessageEventContentWithoutRelation::text_plain(body);
            let reply_content = room
                .make_reply_event(
                    content,
                    Reply {
                        event_id: event_id.to_owned(),
                        enforce_thread: EnforceThread::Unthreaded,
                    },
                )
                .await
                .map_err(|e| ParlotteError::Room {
                    message: format!("failed to create reply: {e}"),
                })?;

            room.send(reply_content)
                .await
                .map_err(|e| ParlotteError::Room {
                    message: format!("failed to send reply: {e}"),
                })?;

            Ok(())
        })
    }

    /// Get recent messages from a room, most recent last.
    /// Pass `from` as `None` to fetch the latest messages, or provide a pagination
    /// token from a previous `MessageBatch::end_token` to load older history.
    pub fn messages(&self, room_id: &str, limit: u64, from: Option<&str>) -> Result<MessageBatch> {
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

            let mut options = MessagesOptions::backward();
            options.limit = matrix_sdk::ruma::UInt::new(limit).unwrap_or(matrix_sdk::ruma::UInt::MAX);
            if let Some(token) = from {
                options.from = Some(token.to_owned());
            }

            let response = room.messages(options).await.map_err(|e| ParlotteError::Room {
                message: format!("failed to fetch messages: {e}"),
            })?;

            use matrix_sdk::ruma::events::room::message::Relation;
            use std::collections::HashMap;

            let mut messages = Vec::new();
            // Track edits: original_event_id -> (new body, new formatted_body)
            let mut edits: HashMap<String, (String, Option<String>)> = HashMap::new();
            // Track reactions: target_event_id -> Vec<ReactionInfo>
            let mut reactions_map: HashMap<String, Vec<ReactionInfo>> = HashMap::new();

            for event in response.chunk {
                let raw = event.raw();
                let Ok(deserialized) = raw.deserialize() else {
                    continue;
                };

                // Collect m.reaction events
                if let AnySyncTimelineEvent::MessageLike(
                    matrix_sdk::ruma::events::AnySyncMessageLikeEvent::Reaction(reaction_event),
                ) = &deserialized
                {
                    if let matrix_sdk::ruma::events::SyncMessageLikeEvent::Original(original) = reaction_event {
                        let annotation = &original.content.relates_to;
                        reactions_map
                            .entry(annotation.event_id.to_string())
                            .or_default()
                            .push(ReactionInfo {
                                event_id: original.event_id.to_string(),
                                key: annotation.key.clone(),
                                sender: original.sender.to_string(),
                            });
                    }
                }

                if let AnySyncTimelineEvent::MessageLike(
                    matrix_sdk::ruma::events::AnySyncMessageLikeEvent::RoomMessage(msg),
                ) = deserialized
                {
                    let original = match msg {
                        matrix_sdk::ruma::events::SyncMessageLikeEvent::Original(o) => o,
                        // Redacted events are skipped
                        _ => continue,
                    };

                    // Check if this is an edit (replacement) event
                    if let Some(Relation::Replacement(replacement)) = &original.content.relates_to {
                        let (body, formatted) = extract_body_and_formatted(&replacement.new_content.msgtype);
                        edits.insert(
                            replacement.event_id.to_string(),
                            (body, formatted),
                        );
                        continue;
                    }

                    let replied_to_event_id = match &original.content.relates_to {
                        Some(Relation::Reply { in_reply_to }) => {
                            Some(in_reply_to.event_id.to_string())
                        }
                        _ => None,
                    };

                    let (body, formatted_body) = extract_body_and_formatted(&original.content.msgtype);
                    let message_type = message_type_str(&original.content.msgtype).to_owned();
                    let (media_source, media_mime_type, media_width, media_height, media_size) =
                        extract_media_info(&original.content.msgtype);

                    messages.push(MessageInfo {
                        event_id: original.event_id.to_string(),
                        sender: original.sender.to_string(),
                        body,
                        formatted_body,
                        message_type,
                        timestamp_ms: original.origin_server_ts.0.into(),
                        is_edited: false,
                        replied_to_event_id,
                        media_source,
                        media_mime_type,
                        media_width,
                        media_height,
                        media_size,
                        reactions: vec![],
                    });
                }
            }

            // Apply edits to original messages
            for msg in &mut messages {
                if let Some((new_body, new_formatted)) = edits.remove(&msg.event_id) {
                    msg.body = new_body;
                    msg.formatted_body = new_formatted;
                    msg.is_edited = true;
                }
            }

            // Attach reactions to their target messages
            for msg in &mut messages {
                if let Some(rxns) = reactions_map.remove(&msg.event_id) {
                    msg.reactions = rxns;
                }
            }

            // Reverse so oldest is first, newest last
            messages.reverse();
            Ok(MessageBatch {
                messages,
                end_token: response.end,
            })
        })
    }

    /// Edit an existing message. Only the sender can edit their own messages.
    pub fn edit_message(&self, room_id: &str, event_id: &str, new_body: &str) -> Result<()> {
        use matrix_sdk::room::edit::EditedContent;
        use matrix_sdk::ruma::events::room::message::RoomMessageEventContentWithoutRelation;
        use matrix_sdk::ruma::EventId;

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

            let event_id = <&EventId>::try_from(event_id).map_err(|e| ParlotteError::Room {
                message: format!("invalid event ID: {e}"),
            })?;

            let new_content = RoomMessageEventContentWithoutRelation::text_plain(new_body);
            let edit_content = room
                .make_edit_event(event_id, EditedContent::RoomMessage(new_content))
                .await
                .map_err(|e| ParlotteError::Room {
                    message: format!("failed to create edit: {e}"),
                })?;

            room.send(edit_content)
                .await
                .map_err(|e| ParlotteError::Room {
                    message: format!("failed to send edit: {e}"),
                })?;

            Ok(())
        })
    }

    /// Redact (delete) a message. Users can redact their own messages, and
    /// moderators/admins can redact anyone's messages.
    pub fn redact_message(&self, room_id: &str, event_id: &str) -> Result<()> {
        use matrix_sdk::ruma::EventId;

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

            let event_id = <&EventId>::try_from(event_id).map_err(|e| ParlotteError::Room {
                message: format!("invalid event ID: {e}"),
            })?;

            room.redact(event_id, None, None)
                .await
                .map_err(|e| ParlotteError::Room {
                    message: format!("failed to redact message: {e}"),
                })?;

            Ok(())
        })
    }

    /// Send a reaction (emoji) on a message. Returns the reaction event ID.
    pub fn send_reaction(&self, room_id: &str, event_id: &str, key: &str) -> Result<String> {
        use matrix_sdk::ruma::events::reaction::ReactionEventContent;
        use matrix_sdk::ruma::events::relation::Annotation;
        use matrix_sdk::ruma::EventId;

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

            let event_id = <&EventId>::try_from(event_id).map_err(|e| ParlotteError::Room {
                message: format!("invalid event ID: {e}"),
            })?;

            let content = ReactionEventContent::new(
                Annotation::new(event_id.to_owned(), key.to_owned()),
            );
            let response = room.send(content).await.map_err(|e| ParlotteError::Room {
                message: format!("failed to send reaction: {e}"),
            })?;

            Ok(response.event_id.to_string())
        })
    }

    /// Redact (remove) a reaction event. The caller must pass the event ID
    /// of the m.reaction event, not the target message.
    pub fn redact_reaction(&self, room_id: &str, reaction_event_id: &str) -> Result<()> {
        use matrix_sdk::ruma::EventId;

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

            let event_id = <&EventId>::try_from(reaction_event_id).map_err(|e| ParlotteError::Room {
                message: format!("invalid event ID: {e}"),
            })?;

            room.redact(event_id, None, None)
                .await
                .map_err(|e| ParlotteError::Room {
                    message: format!("failed to redact reaction: {e}"),
                })?;

            Ok(())
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

    /// Start a persistent sync loop in the background.
    /// The listener is called after each successful sync response.
    /// Uses long-polling (30s timeout) instead of periodic polling.
    pub fn start_sync(&self, listener: Arc<dyn SyncListener>) -> Result<()> {
        self.sync_manager.start_persistent_sync(
            self.client().clone(),
            &self.runtime,
            listener,
        )
    }

    /// Stop the persistent sync loop.
    pub fn stop_sync(&self) {
        self.sync_manager.stop();
    }

    /// Check if sync is currently running.
    pub fn is_syncing(&self) -> bool {
        self.sync_manager.is_running()
    }

    /// Access the underlying matrix_sdk::Client (for advanced usage / tests).
    pub fn inner(&self) -> &Client {
        self.client()
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

    /// Leave a room by its ID.
    pub fn leave_room(&self, room_id: &str) -> Result<()> {
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

            room.leave()
                .await
                .map_err(|e| ParlotteError::Room {
                    message: format!("failed to leave room: {e}"),
                })?;

            Ok(())
        })
    }

    /// Send a read receipt for the given event in a room.
    pub fn send_read_receipt(&self, room_id: &str, event_id: &str) -> Result<()> {
        use matrix_sdk::ruma::events::receipt::ReceiptThread;
        use matrix_sdk::ruma::OwnedEventId;

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

            let event_id: OwnedEventId =
                event_id.try_into().map_err(|e: matrix_sdk::ruma::IdParseError| ParlotteError::Room {
                    message: format!("invalid event ID: {e}"),
                })?;

            room.send_single_receipt(
                matrix_sdk::ruma::api::client::receipt::create_receipt::v3::ReceiptType::Read,
                ReceiptThread::Unthreaded,
                event_id,
            )
            .await
            .map_err(|e| ParlotteError::Room {
                message: format!("failed to send read receipt: {e}"),
            })?;

            Ok(())
        })
    }

    /// Send a typing notice for the given room.
    /// The SDK internally debounces repeated calls with `is_typing: true`.
    pub fn send_typing_notice(&self, room_id: &str, is_typing: bool) -> Result<()> {
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

            room.typing_notice(is_typing)
                .await
                .map_err(|e| ParlotteError::Room {
                    message: format!("failed to send typing notice: {e}"),
                })?;

            Ok(())
        })
    }

    /// Upload an attachment and post it as a message to the given room.
    ///
    /// `mime_type` must be a valid media type string (e.g. `"image/png"`). When
    /// the mime's top-level type is `image`, the attachment is sent as
    /// `m.image` with the provided dimensions; otherwise it is sent as
    /// `m.file`.
    pub fn send_attachment(
        &self,
        room_id: &str,
        filename: &str,
        mime_type: &str,
        data: Vec<u8>,
        width: Option<u32>,
        height: Option<u32>,
    ) -> Result<()> {
        use matrix_sdk::attachment::{
            AttachmentConfig, AttachmentInfo, BaseFileInfo, BaseImageInfo,
        };
        use matrix_sdk::ruma::UInt;

        let mime: mime::Mime = mime_type.parse().map_err(|e: mime::FromStrError| ParlotteError::Room {
            message: format!("invalid MIME type {mime_type:?}: {e}"),
        })?;

        let size_uint = UInt::new(data.len() as u64);
        let info = if mime.type_() == mime::IMAGE {
            AttachmentInfo::Image(BaseImageInfo {
                width: width.map(|w| UInt::from(w)),
                height: height.map(|h| UInt::from(h)),
                size: size_uint,
                blurhash: None,
                is_animated: None,
            })
        } else {
            AttachmentInfo::File(BaseFileInfo { size: size_uint })
        };

        let client = self.client();
        self.runtime.block_on(async {
            let room_id = <&RoomId>::try_from(room_id).map_err(|e| ParlotteError::Room {
                message: format!("invalid room ID: {e}"),
            })?;

            let room = client.get_room(room_id).ok_or_else(|| ParlotteError::Room {
                message: format!("room {room_id} not found"),
            })?;

            let config = AttachmentConfig::new().info(info);
            room.send_attachment(filename.to_owned(), &mime, data, config)
                .await
                .map_err(|e| ParlotteError::Room {
                    message: format!("failed to send attachment: {e}"),
                })?;

            Ok(())
        })
    }

    /// Download the raw bytes of a media item.
    ///
    /// `media_source` is the serialised `MediaSource` JSON produced by
    /// `extract_media_info`. It may represent either a plain mxc:// URI or an
    /// encrypted file (with decryption keys), so encrypted-room media is
    /// handled transparently.
    ///
    /// For backwards-compatibility a bare `mxc://` URI string is also accepted.
    pub fn download_media(&self, media_source: &str) -> Result<Vec<u8>> {
        use matrix_sdk::media::{MediaFormat, MediaRequestParameters};
        use matrix_sdk::ruma::events::room::MediaSource;
        use matrix_sdk::ruma::OwnedMxcUri;

        // Try deserialising as full MediaSource JSON first; fall back to treating
        // the string as a plain mxc URI for callers that pass one directly.
        let source: MediaSource = serde_json::from_str(media_source).unwrap_or_else(|_| {
            MediaSource::Plain(OwnedMxcUri::from(media_source))
        });

        // Validate that whichever variant we ended up with has a valid mxc URI.
        let uri_str = match &source {
            MediaSource::Plain(uri) => uri.as_str(),
            MediaSource::Encrypted(file) => file.url.as_str(),
        };
        if !uri_str.starts_with("mxc://") {
            return Err(ParlotteError::Room {
                message: format!("invalid mxc URI: {uri_str}"),
            });
        }

        let client = self.client();
        self.runtime.block_on(async {
            let request = MediaRequestParameters {
                source,
                format: MediaFormat::File,
            };
            client
                .media()
                .get_media_content(&request, true)
                .await
                .map_err(|e| ParlotteError::Room {
                    message: format!("failed to download media: {e}"),
                })
        })
    }

    /// Get the list of members in a room.
    pub fn room_members(&self, room_id: &str) -> Result<Vec<RoomMemberInfo>> {
        use matrix_sdk::RoomMemberships;

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

            let members = room
                .members(RoomMemberships::JOIN)
                .await
                .map_err(|e| ParlotteError::Room {
                    message: format!("failed to fetch members: {e}"),
                })?;

            Ok(members
                .into_iter()
                .map(|m| RoomMemberInfo {
                    user_id: m.user_id().to_string(),
                    display_name: m.display_name().map(|s| s.to_owned()),
                    power_level: match m.power_level() {
                        matrix_sdk::ruma::events::room::power_levels::UserPowerLevel::Int(n) => n.into(),
                        _ => 100,
                    },
                    role: match m.suggested_role_for_power_level() {
                        matrix_sdk::room::RoomMemberRole::Administrator => "admin".to_owned(),
                        matrix_sdk::room::RoomMemberRole::Moderator => "moderator".to_owned(),
                        _ => "member".to_owned(),
                    },
                })
                .collect())
        })
    }
}

/// Extract the plain-text body and optional HTML formatted body from a message type.
fn extract_body_and_formatted(
    msgtype: &matrix_sdk::ruma::events::room::message::MessageType,
) -> (String, Option<String>) {
    use matrix_sdk::ruma::events::room::message::MessageType;

    match msgtype {
        MessageType::Text(text) => {
            let formatted = text
                .formatted
                .as_ref()
                .filter(|f| f.format == matrix_sdk::ruma::events::room::message::MessageFormat::Html)
                .map(|f| f.body.clone());
            (text.body.clone(), formatted)
        }
        MessageType::Notice(notice) => {
            let formatted = notice
                .formatted
                .as_ref()
                .filter(|f| f.format == matrix_sdk::ruma::events::room::message::MessageFormat::Html)
                .map(|f| f.body.clone());
            (notice.body.clone(), formatted)
        }
        MessageType::Emote(emote) => {
            let formatted = emote
                .formatted
                .as_ref()
                .filter(|f| f.format == matrix_sdk::ruma::events::room::message::MessageFormat::Html)
                .map(|f| f.body.clone());
            (emote.body.clone(), formatted)
        }
        MessageType::Image(img) => (img.body.clone(), None),
        MessageType::File(file) => (file.body.clone(), None),
        MessageType::Video(video) => (video.body.clone(), None),
        MessageType::Audio(audio) => (audio.body.clone(), None),
        MessageType::Location(loc) => (loc.body.clone(), None),
        _ => ("[unsupported message]".to_owned(), None),
    }
}

/// Media metadata extracted from a message content.
///
/// Returns (source mxc URI, mime type, width, height, size). All fields are
/// `None` for non-media message types (text, notice, emote, location).
type MediaFields = (Option<String>, Option<String>, Option<u32>, Option<u32>, Option<u64>);

fn extract_media_info(
    msgtype: &matrix_sdk::ruma::events::room::message::MessageType,
) -> MediaFields {
    use matrix_sdk::ruma::events::room::message::MessageType;
    use matrix_sdk::ruma::events::room::MediaSource;

    // Serialize the full MediaSource (including encryption keys for E2EE rooms)
    // so that download_media can reconstruct the correct variant for decryption.
    let serialize_source = |source: &MediaSource| -> String {
        serde_json::to_string(source).unwrap_or_else(|_| match source {
            MediaSource::Plain(uri) => uri.to_string(),
            MediaSource::Encrypted(file) => file.url.to_string(),
        })
    };

    match msgtype {
        MessageType::Image(img) => {
            let source = Some(serialize_source(&img.source));
            let (mime, w, h, size) = img
                .info
                .as_ref()
                .map(|i| {
                    (
                        i.mimetype.clone(),
                        i.width.map(|v| u64::from(v) as u32),
                        i.height.map(|v| u64::from(v) as u32),
                        i.size.map(|v| u64::from(v)),
                    )
                })
                .unwrap_or((None, None, None, None));
            (source, mime, w, h, size)
        }
        MessageType::File(file) => {
            let source = Some(serialize_source(&file.source));
            let (mime, size) = file
                .info
                .as_ref()
                .map(|i| (i.mimetype.clone(), i.size.map(|v| u64::from(v))))
                .unwrap_or((None, None));
            (source, mime, None, None, size)
        }
        MessageType::Video(video) => {
            let source = Some(serialize_source(&video.source));
            let (mime, w, h, size) = video
                .info
                .as_ref()
                .map(|i| {
                    (
                        i.mimetype.clone(),
                        i.width.map(|v| u64::from(v) as u32),
                        i.height.map(|v| u64::from(v) as u32),
                        i.size.map(|v| u64::from(v)),
                    )
                })
                .unwrap_or((None, None, None, None));
            (source, mime, w, h, size)
        }
        MessageType::Audio(audio) => {
            let source = Some(serialize_source(&audio.source));
            let (mime, size) = audio
                .info
                .as_ref()
                .map(|i| (i.mimetype.clone(), i.size.map(|v| u64::from(v))))
                .unwrap_or((None, None));
            (source, mime, None, None, size)
        }
        _ => (None, None, None, None, None),
    }
}

/// Return a short string label for the message type.
fn message_type_str(msgtype: &matrix_sdk::ruma::events::room::message::MessageType) -> &'static str {
    use matrix_sdk::ruma::events::room::message::MessageType;

    match msgtype {
        MessageType::Text(_) => "text",
        MessageType::Notice(_) => "notice",
        MessageType::Emote(_) => "emote",
        MessageType::Image(_) => "image",
        MessageType::File(_) => "file",
        MessageType::Video(_) => "video",
        MessageType::Audio(_) => "audio",
        MessageType::Location(_) => "location",
        _ => "unknown",
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
        let result = client.messages("not-a-room-id", 50, None);
        assert!(result.is_err());
        assert!(matches!(result.unwrap_err(), ParlotteError::Room { .. }));
    }

    #[test]
    fn messages_rejects_nonexistent_room() {
        let client = ParlotteClient::new("http://localhost:1234", None).unwrap();
        let result = client.messages("!nonexistent:example.com", 50, None);
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
    fn send_reply_rejects_invalid_room_id() {
        let client = ParlotteClient::new("http://localhost:1234", None).unwrap();
        let result = client.send_reply("not-a-room-id", "$event:example.com", "reply");
        assert!(result.is_err());
        let err = result.unwrap_err();
        assert!(matches!(err, ParlotteError::Room { .. }));
        assert!(err.to_string().contains("invalid room ID"));
    }

    #[test]
    fn send_reply_rejects_nonexistent_room() {
        let client = ParlotteClient::new("http://localhost:1234", None).unwrap();
        let result = client.send_reply("!nonexistent:example.com", "$event:example.com", "reply");
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
    fn leave_room_rejects_invalid_room_id() {
        let client = ParlotteClient::new("http://localhost:1234", None).unwrap();
        let result = client.leave_room("garbage");
        assert!(result.is_err());
        assert!(matches!(result.unwrap_err(), ParlotteError::Room { .. }));
    }

    #[test]
    fn leave_room_rejects_nonexistent_room() {
        let client = ParlotteClient::new("http://localhost:1234", None).unwrap();
        let result = client.leave_room("!nonexistent:example.com");
        assert!(result.is_err());
        let err = result.unwrap_err();
        assert!(matches!(err, ParlotteError::Room { .. }));
        assert!(err.to_string().contains("not found"));
    }

    #[test]
    fn room_members_rejects_invalid_room_id() {
        let client = ParlotteClient::new("http://localhost:1234", None).unwrap();
        let result = client.room_members("garbage");
        assert!(result.is_err());
        assert!(matches!(result.unwrap_err(), ParlotteError::Room { .. }));
    }

    #[test]
    fn room_members_rejects_nonexistent_room() {
        let client = ParlotteClient::new("http://localhost:1234", None).unwrap();
        let result = client.room_members("!nonexistent:example.com");
        assert!(result.is_err());
        let err = result.unwrap_err();
        assert!(matches!(err, ParlotteError::Room { .. }));
        assert!(err.to_string().contains("not found"));
    }

    #[test]
    fn send_read_receipt_rejects_invalid_room_id() {
        let client = ParlotteClient::new("http://localhost:1234", None).unwrap();
        let result = client.send_read_receipt("garbage", "$event:example.com");
        assert!(result.is_err());
        assert!(matches!(result.unwrap_err(), ParlotteError::Room { .. }));
    }

    #[test]
    fn send_read_receipt_rejects_nonexistent_room() {
        let client = ParlotteClient::new("http://localhost:1234", None).unwrap();
        let result = client.send_read_receipt("!room:example.com", "$event:example.com");
        assert!(result.is_err());
        let err = result.unwrap_err();
        assert!(matches!(err, ParlotteError::Room { .. }));
        assert!(err.to_string().contains("not found"));
    }

    #[test]
    fn send_typing_notice_rejects_invalid_room_id() {
        let client = ParlotteClient::new("http://localhost:1234", None).unwrap();
        let result = client.send_typing_notice("not-a-room-id", true);
        assert!(result.is_err());
        assert!(matches!(result.unwrap_err(), ParlotteError::Room { .. }));
    }

    #[test]
    fn send_typing_notice_rejects_nonexistent_room() {
        let client = ParlotteClient::new("http://localhost:1234", None).unwrap();
        let result = client.send_typing_notice("!nonexistent:example.com", true);
        assert!(result.is_err());
        let err = result.unwrap_err();
        assert!(matches!(err, ParlotteError::Room { .. }));
        assert!(err.to_string().contains("not found"));
    }

    #[test]
    fn send_attachment_rejects_invalid_room_id() {
        let client = ParlotteClient::new("http://localhost:1234", None).unwrap();
        let result = client.send_attachment("garbage", "file.png", "image/png", vec![1, 2, 3], Some(10), Some(10));
        assert!(result.is_err());
        assert!(matches!(result.unwrap_err(), ParlotteError::Room { .. }));
    }

    #[test]
    fn send_attachment_rejects_nonexistent_room() {
        let client = ParlotteClient::new("http://localhost:1234", None).unwrap();
        let result = client.send_attachment(
            "!nonexistent:example.com",
            "file.png",
            "image/png",
            vec![1, 2, 3],
            None,
            None,
        );
        assert!(result.is_err());
        let err = result.unwrap_err();
        assert!(matches!(err, ParlotteError::Room { .. }));
        assert!(err.to_string().contains("not found"));
    }

    #[test]
    fn send_attachment_rejects_invalid_mime() {
        let client = ParlotteClient::new("http://localhost:1234", None).unwrap();
        let result = client.send_attachment(
            "!room:example.com",
            "file.png",
            "not a valid mime type",
            vec![1, 2, 3],
            None,
            None,
        );
        assert!(result.is_err());
        assert!(result.unwrap_err().to_string().contains("invalid MIME type"));
    }

    #[test]
    fn download_media_rejects_invalid_mxc_uri() {
        let client = ParlotteClient::new("http://localhost:1234", None).unwrap();
        let result = client.download_media("not-a-valid-mxc-uri");
        assert!(result.is_err());
        assert!(matches!(result.unwrap_err(), ParlotteError::Room { .. }));
    }

    #[test]
    fn edit_message_rejects_invalid_room_id() {
        let client = ParlotteClient::new("http://localhost:1234", None).unwrap();
        let result = client.edit_message("garbage", "$event:example.com", "new body");
        assert!(result.is_err());
        assert!(matches!(result.unwrap_err(), ParlotteError::Room { .. }));
    }

    #[test]
    fn edit_message_rejects_nonexistent_room() {
        let client = ParlotteClient::new("http://localhost:1234", None).unwrap();
        let result = client.edit_message("!room:example.com", "$event:example.com", "new body");
        assert!(result.is_err());
        assert!(result.unwrap_err().to_string().contains("not found"));
    }

    #[test]
    fn redact_message_rejects_invalid_room_id() {
        let client = ParlotteClient::new("http://localhost:1234", None).unwrap();
        let result = client.redact_message("garbage", "$event:example.com");
        assert!(result.is_err());
        assert!(matches!(result.unwrap_err(), ParlotteError::Room { .. }));
    }

    #[test]
    fn redact_message_rejects_nonexistent_room() {
        let client = ParlotteClient::new("http://localhost:1234", None).unwrap();
        let result = client.redact_message("!room:example.com", "$event:example.com");
        assert!(result.is_err());
        assert!(result.unwrap_err().to_string().contains("not found"));
    }

    #[test]
    fn sso_login_url_rejects_invalid_redirect() {
        let client = ParlotteClient::new("http://localhost:1234", None).unwrap();
        // This will fail because the server isn't reachable, not because of validation
        let result = client.sso_login_url("http://localhost:9999/callback", None);
        assert!(result.is_err());
    }

    #[test]
    fn login_sso_callback_rejects_invalid_url() {
        let client = ParlotteClient::new("http://localhost:1234", None).unwrap();
        let result = client.login_sso_callback("not-a-url");
        assert!(result.is_err());
        assert!(matches!(result.unwrap_err(), ParlotteError::Auth { .. }));
    }

    #[test]
    fn login_sso_callback_rejects_missing_token() {
        let client = ParlotteClient::new("http://localhost:1234", None).unwrap();
        let result = client.login_sso_callback("http://localhost:9999/callback?notoken=here");
        assert!(result.is_err());
        assert!(matches!(result.unwrap_err(), ParlotteError::Auth { .. }));
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

    #[test]
    fn send_reaction_rejects_invalid_room_id() {
        let client = ParlotteClient::new("http://localhost:1234", None).unwrap();
        let result = client.send_reaction("bad-room", "$event:example.com", "👍");
        assert!(result.is_err());
        assert!(matches!(result.unwrap_err(), ParlotteError::Room { .. }));
    }

    #[test]
    fn send_reaction_rejects_nonexistent_room() {
        let client = ParlotteClient::new("http://localhost:1234", None).unwrap();
        let result = client.send_reaction("!room:example.com", "$event:example.com", "👍");
        assert!(result.is_err());
        assert!(result.unwrap_err().to_string().contains("not found"));
    }

    #[test]
    fn send_reaction_rejects_invalid_event_id() {
        let client = ParlotteClient::new("http://localhost:1234", None).unwrap();
        let result = client.send_reaction("!room:example.com", "bad-event", "👍");
        assert!(result.is_err());
        let err_msg = result.unwrap_err().to_string();
        assert!(err_msg.contains("invalid event ID") || err_msg.contains("not found"));
    }

    #[test]
    fn redact_reaction_rejects_invalid_room_id() {
        let client = ParlotteClient::new("http://localhost:1234", None).unwrap();
        let result = client.redact_reaction("bad-room", "$reaction:example.com");
        assert!(result.is_err());
        assert!(matches!(result.unwrap_err(), ParlotteError::Room { .. }));
    }

    #[test]
    fn redact_reaction_rejects_nonexistent_room() {
        let client = ParlotteClient::new("http://localhost:1234", None).unwrap();
        let result = client.redact_reaction("!room:example.com", "$reaction:example.com");
        assert!(result.is_err());
        assert!(result.unwrap_err().to_string().contains("not found"));
    }

    // Note: SQLite store path testing is covered in integration tests because
    // the deadpool connection pool has tokio runtime lifecycle requirements
    // that conflict with ParlotteClient's embedded runtime in unit test context.
}
