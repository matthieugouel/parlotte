uniffi::setup_scaffolding!();

/// Initialize logging with the given level filter (e.g. "debug", "info", "warn").
/// Only the first call has effect; subsequent calls are ignored.
#[uniffi::export]
pub fn init_logging(level: String) {
    use tracing_subscriber::EnvFilter;

    let filter = EnvFilter::try_new(format!("parlotte_core={level}"))
        .unwrap_or_else(|_| EnvFilter::new("parlotte_core=info"));

    let _ = tracing_subscriber::fmt()
        .with_env_filter(filter)
        .with_target(false)
        .try_init();
}

use parlotte_core::{
    LoginMethods as CoreLoginMethods, MatrixSessionData as CoreMatrixSessionData,
    MessageBatch as CoreMessageBatch, MessageInfo as CoreMessageInfo,
    ParlotteClient as CoreClient, ParlotteError as CoreError,
    PublicRoomInfo as CorePublicRoomInfo, RoomInfo as CoreRoomInfo,
    RoomMemberInfo as CoreRoomMemberInfo, SessionInfo as CoreSessionInfo,
    SsoProvider as CoreSsoProvider,
};
use std::fmt;
use std::sync::Arc;

// -- Error type exposed via UniFFI --

#[derive(Debug, uniffi::Error)]
pub enum ParlotteError {
    Auth { message: String },
    Network { message: String },
    Room { message: String },
    Store { message: String },
    Sync { message: String },
    Unknown { message: String },
}

impl fmt::Display for ParlotteError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Auth { message } => write!(f, "authentication failed: {message}"),
            Self::Network { message } => write!(f, "network error: {message}"),
            Self::Room { message } => write!(f, "room error: {message}"),
            Self::Store { message } => write!(f, "store error: {message}"),
            Self::Sync { message } => write!(f, "sync error: {message}"),
            Self::Unknown { message } => write!(f, "unknown error: {message}"),
        }
    }
}

impl From<CoreError> for ParlotteError {
    fn from(err: CoreError) -> Self {
        match err {
            CoreError::Auth { message } => ParlotteError::Auth { message },
            CoreError::Network { message } => ParlotteError::Network { message },
            CoreError::Room { message } => ParlotteError::Room { message },
            CoreError::Store { message } => ParlotteError::Store { message },
            CoreError::Sync { message } => ParlotteError::Sync { message },
            CoreError::Unknown { message } => ParlotteError::Unknown { message },
        }
    }
}

// -- Record types --

#[derive(uniffi::Record)]
pub struct RoomInfo {
    pub id: String,
    pub display_name: String,
    pub is_encrypted: bool,
    pub is_public: bool,
    pub topic: Option<String>,
    pub is_invited: bool,
    pub unread_count: u64,
}

impl From<CoreRoomInfo> for RoomInfo {
    fn from(r: CoreRoomInfo) -> Self {
        Self {
            id: r.id,
            display_name: r.display_name,
            is_encrypted: r.is_encrypted,
            is_public: r.is_public,
            topic: r.topic,
            is_invited: r.is_invited,
            unread_count: r.unread_count,
        }
    }
}

#[derive(uniffi::Record)]
pub struct MessageInfo {
    pub event_id: String,
    pub sender: String,
    pub body: String,
    pub formatted_body: Option<String>,
    pub message_type: String,
    pub timestamp_ms: u64,
    pub is_edited: bool,
}

impl From<CoreMessageInfo> for MessageInfo {
    fn from(m: CoreMessageInfo) -> Self {
        Self {
            event_id: m.event_id,
            sender: m.sender,
            body: m.body,
            formatted_body: m.formatted_body,
            message_type: m.message_type,
            timestamp_ms: m.timestamp_ms,
            is_edited: m.is_edited,
        }
    }
}

#[derive(uniffi::Record)]
pub struct MessageBatch {
    pub messages: Vec<MessageInfo>,
    pub end_token: Option<String>,
}

impl From<CoreMessageBatch> for MessageBatch {
    fn from(b: CoreMessageBatch) -> Self {
        Self {
            messages: b.messages.into_iter().map(Into::into).collect(),
            end_token: b.end_token,
        }
    }
}

#[derive(uniffi::Record)]
pub struct SessionInfo {
    pub user_id: String,
    pub device_id: String,
}

impl From<CoreSessionInfo> for SessionInfo {
    fn from(s: CoreSessionInfo) -> Self {
        Self {
            user_id: s.user_id,
            device_id: s.device_id,
        }
    }
}

#[derive(uniffi::Record)]
pub struct MatrixSessionData {
    pub user_id: String,
    pub device_id: String,
    pub access_token: String,
}

impl From<CoreMatrixSessionData> for MatrixSessionData {
    fn from(s: CoreMatrixSessionData) -> Self {
        Self {
            user_id: s.user_id,
            device_id: s.device_id,
            access_token: s.access_token,
        }
    }
}

impl From<MatrixSessionData> for CoreMatrixSessionData {
    fn from(s: MatrixSessionData) -> Self {
        Self {
            user_id: s.user_id,
            device_id: s.device_id,
            access_token: s.access_token,
        }
    }
}

#[derive(uniffi::Record)]
pub struct PublicRoomInfo {
    pub id: String,
    pub name: Option<String>,
    pub topic: Option<String>,
    pub member_count: u64,
    pub alias: Option<String>,
}

impl From<CorePublicRoomInfo> for PublicRoomInfo {
    fn from(r: CorePublicRoomInfo) -> Self {
        Self {
            id: r.id,
            name: r.name,
            topic: r.topic,
            member_count: r.member_count,
            alias: r.alias,
        }
    }
}

#[derive(uniffi::Record)]
pub struct RoomMemberInfo {
    pub user_id: String,
    pub display_name: Option<String>,
    pub power_level: i64,
    pub role: String,
}

impl From<CoreRoomMemberInfo> for RoomMemberInfo {
    fn from(m: CoreRoomMemberInfo) -> Self {
        Self {
            user_id: m.user_id,
            display_name: m.display_name,
            power_level: m.power_level,
            role: m.role,
        }
    }
}

#[derive(uniffi::Record)]
pub struct SsoProvider {
    pub id: String,
    pub name: String,
}

impl From<CoreSsoProvider> for SsoProvider {
    fn from(p: CoreSsoProvider) -> Self {
        Self {
            id: p.id,
            name: p.name,
        }
    }
}

#[derive(uniffi::Record)]
pub struct LoginMethods {
    pub supports_password: bool,
    pub supports_sso: bool,
    pub sso_providers: Vec<SsoProvider>,
}

impl From<CoreLoginMethods> for LoginMethods {
    fn from(m: CoreLoginMethods) -> Self {
        Self {
            supports_password: m.supports_password,
            supports_sso: m.supports_sso,
            sso_providers: m.sso_providers.into_iter().map(Into::into).collect(),
        }
    }
}

// -- Callback interfaces --

/// Callback for persistent sync updates.
/// Called after each successful sync response.
#[uniffi::export(callback_interface)]
pub trait ParlotteSyncListener: Send + Sync {
    fn on_sync_update(&self);
}

/// Bridge from the FFI callback to the core SyncListener trait.
struct SyncListenerBridge {
    inner: Box<dyn ParlotteSyncListener>,
}

// Safety: ParlotteSyncListener requires Send + Sync
unsafe impl Send for SyncListenerBridge {}
unsafe impl Sync for SyncListenerBridge {}

impl parlotte_core::SyncListener for SyncListenerBridge {
    fn on_sync_update(&self) {
        self.inner.on_sync_update();
    }
}

// -- Main client object --

#[derive(uniffi::Object)]
pub struct ParlotteClientFFI {
    inner: CoreClient,
}

#[uniffi::export]
impl ParlotteClientFFI {
    #[uniffi::constructor]
    pub fn new(homeserver_url: String, store_path: Option<String>) -> Result<Self, ParlotteError> {
        let client = CoreClient::new(&homeserver_url, store_path.as_deref())?;
        Ok(Self { inner: client })
    }

    pub fn login(&self, username: String, password: String) -> Result<SessionInfo, ParlotteError> {
        Ok(self.inner.login(&username, &password)?.into())
    }

    pub fn session(&self) -> Option<MatrixSessionData> {
        self.inner.session().map(Into::into)
    }

    pub fn restore_session(&self, session_data: MatrixSessionData) -> Result<(), ParlotteError> {
        Ok(self.inner.restore_session(session_data.into())?)
    }

    pub fn logout(&self) -> Result<(), ParlotteError> {
        Ok(self.inner.logout()?)
    }

    pub fn rooms(&self) -> Result<Vec<RoomInfo>, ParlotteError> {
        Ok(self.inner.rooms()?.into_iter().map(Into::into).collect())
    }

    pub fn send_message(&self, room_id: String, body: String) -> Result<(), ParlotteError> {
        Ok(self.inner.send_message(&room_id, &body)?)
    }

    pub fn messages(&self, room_id: String, limit: u64, from: Option<String>) -> Result<MessageBatch, ParlotteError> {
        Ok(self.inner.messages(&room_id, limit, from.as_deref())?.into())
    }

    pub fn sync_once(&self) -> Result<(), ParlotteError> {
        Ok(self.inner.sync_once()?)
    }

    pub fn create_room(&self, name: String, is_public: bool) -> Result<String, ParlotteError> {
        Ok(self.inner.create_room(&name, is_public)?)
    }

    pub fn public_rooms(&self) -> Result<Vec<PublicRoomInfo>, ParlotteError> {
        Ok(self.inner.public_rooms()?.into_iter().map(Into::into).collect())
    }

    pub fn invite_user(&self, room_id: String, user_id: String) -> Result<(), ParlotteError> {
        Ok(self.inner.invite_user(&room_id, &user_id)?)
    }

    pub fn join_room(&self, room_id: String) -> Result<(), ParlotteError> {
        Ok(self.inner.join_room(&room_id)?)
    }

    pub fn leave_room(&self, room_id: String) -> Result<(), ParlotteError> {
        Ok(self.inner.leave_room(&room_id)?)
    }

    pub fn room_members(&self, room_id: String) -> Result<Vec<RoomMemberInfo>, ParlotteError> {
        Ok(self.inner.room_members(&room_id)?.into_iter().map(Into::into).collect())
    }

    pub fn send_read_receipt(&self, room_id: String, event_id: String) -> Result<(), ParlotteError> {
        Ok(self.inner.send_read_receipt(&room_id, &event_id)?)
    }

    pub fn edit_message(&self, room_id: String, event_id: String, new_body: String) -> Result<(), ParlotteError> {
        Ok(self.inner.edit_message(&room_id, &event_id, &new_body)?)
    }

    pub fn redact_message(&self, room_id: String, event_id: String) -> Result<(), ParlotteError> {
        Ok(self.inner.redact_message(&room_id, &event_id)?)
    }

    pub fn login_methods(&self) -> Result<LoginMethods, ParlotteError> {
        Ok(self.inner.login_methods()?.into())
    }

    pub fn sso_login_url(&self, redirect_url: String, idp_id: Option<String>) -> Result<String, ParlotteError> {
        Ok(self.inner.sso_login_url(&redirect_url, idp_id.as_deref())?)
    }

    pub fn login_sso_callback(&self, callback_url: String) -> Result<SessionInfo, ParlotteError> {
        Ok(self.inner.login_sso_callback(&callback_url)?.into())
    }

    pub fn start_sync(&self, listener: Box<dyn ParlotteSyncListener>) -> Result<(), ParlotteError> {
        let bridge = Arc::new(SyncListenerBridge { inner: listener });
        Ok(self.inner.start_sync(bridge)?)
    }

    pub fn stop_sync(&self) {
        self.inner.stop_sync();
    }

    pub fn is_syncing(&self) -> bool {
        self.inner.is_syncing()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    // -- RoomInfo round-trip --

    #[test]
    fn room_info_converts_all_fields() {
        let core = CoreRoomInfo {
            id: "!room:example.com".into(),
            display_name: "General".into(),
            is_encrypted: true,
            is_public: false,
            topic: Some("Welcome".into()),
            is_invited: false,
            unread_count: 42,
        };
        let ffi: RoomInfo = core.into();
        assert_eq!(ffi.id, "!room:example.com");
        assert_eq!(ffi.display_name, "General");
        assert!(ffi.is_encrypted);
        assert!(!ffi.is_public);
        assert_eq!(ffi.topic.as_deref(), Some("Welcome"));
        assert!(!ffi.is_invited);
        assert_eq!(ffi.unread_count, 42);
    }

    #[test]
    fn room_info_converts_none_topic() {
        let core = CoreRoomInfo {
            id: "!r:x.com".into(),
            display_name: "No Topic".into(),
            is_encrypted: false,
            is_public: true,
            topic: None,
            is_invited: true,
            unread_count: 0,
        };
        let ffi: RoomInfo = core.into();
        assert!(ffi.topic.is_none());
        assert!(ffi.is_public);
        assert!(ffi.is_invited);
    }

    // -- MessageInfo round-trip --

    #[test]
    fn message_info_converts_all_fields() {
        let core = CoreMessageInfo {
            event_id: "$evt:example.com".into(),
            sender: "@alice:example.com".into(),
            body: "Hello".into(),
            formatted_body: Some("<b>Hello</b>".into()),
            message_type: "text".into(),
            timestamp_ms: 1700000000000,
            is_edited: true,
        };
        let ffi: MessageInfo = core.into();
        assert_eq!(ffi.event_id, "$evt:example.com");
        assert_eq!(ffi.sender, "@alice:example.com");
        assert_eq!(ffi.body, "Hello");
        assert_eq!(ffi.formatted_body.as_deref(), Some("<b>Hello</b>"));
        assert_eq!(ffi.message_type, "text");
        assert_eq!(ffi.timestamp_ms, 1700000000000);
        assert!(ffi.is_edited);
    }

    #[test]
    fn message_info_converts_none_formatted_body() {
        let core = CoreMessageInfo {
            event_id: "$e:x.com".into(),
            sender: "@b:x.com".into(),
            body: "plain".into(),
            formatted_body: None,
            message_type: "notice".into(),
            timestamp_ms: 0,
            is_edited: false,
        };
        let ffi: MessageInfo = core.into();
        assert!(ffi.formatted_body.is_none());
        assert_eq!(ffi.message_type, "notice");
        assert!(!ffi.is_edited);
    }

    // -- MessageBatch round-trip --

    #[test]
    fn message_batch_converts_with_token() {
        let core = CoreMessageBatch {
            messages: vec![CoreMessageInfo {
                event_id: "$1:x.com".into(),
                sender: "@a:x.com".into(),
                body: "msg".into(),
                formatted_body: None,
                message_type: "text".into(),
                timestamp_ms: 100,
                is_edited: false,
            }],
            end_token: Some("t47_42_0_1".into()),
        };
        let ffi: MessageBatch = core.into();
        assert_eq!(ffi.messages.len(), 1);
        assert_eq!(ffi.messages[0].body, "msg");
        assert_eq!(ffi.end_token.as_deref(), Some("t47_42_0_1"));
    }

    #[test]
    fn message_batch_converts_without_token() {
        let core = CoreMessageBatch {
            messages: vec![],
            end_token: None,
        };
        let ffi: MessageBatch = core.into();
        assert!(ffi.messages.is_empty());
        assert!(ffi.end_token.is_none());
    }

    // -- SessionInfo round-trip --

    #[test]
    fn session_info_converts() {
        let core = CoreSessionInfo {
            user_id: "@alice:example.com".into(),
            device_id: "ABCDEF".into(),
        };
        let ffi: SessionInfo = core.into();
        assert_eq!(ffi.user_id, "@alice:example.com");
        assert_eq!(ffi.device_id, "ABCDEF");
    }

    // -- MatrixSessionData round-trip (bidirectional) --

    #[test]
    fn matrix_session_data_core_to_ffi() {
        let core = CoreMatrixSessionData {
            user_id: "@bob:matrix.org".into(),
            device_id: "DEV999".into(),
            access_token: "syt_secret".into(),
        };
        let ffi: MatrixSessionData = core.into();
        assert_eq!(ffi.user_id, "@bob:matrix.org");
        assert_eq!(ffi.device_id, "DEV999");
        assert_eq!(ffi.access_token, "syt_secret");
    }

    #[test]
    fn matrix_session_data_ffi_to_core() {
        let ffi = MatrixSessionData {
            user_id: "@carol:example.com".into(),
            device_id: "PHONE1".into(),
            access_token: "tok_abc".into(),
        };
        let core: CoreMatrixSessionData = ffi.into();
        assert_eq!(core.user_id, "@carol:example.com");
        assert_eq!(core.device_id, "PHONE1");
        assert_eq!(core.access_token, "tok_abc");
    }

    // -- PublicRoomInfo round-trip --

    #[test]
    fn public_room_info_converts_all_fields() {
        let core = CorePublicRoomInfo {
            id: "!pub:example.com".into(),
            name: Some("Lobby".into()),
            topic: Some("Welcome all".into()),
            member_count: 150,
            alias: Some("#lobby:example.com".into()),
        };
        let ffi: PublicRoomInfo = core.into();
        assert_eq!(ffi.id, "!pub:example.com");
        assert_eq!(ffi.name.as_deref(), Some("Lobby"));
        assert_eq!(ffi.topic.as_deref(), Some("Welcome all"));
        assert_eq!(ffi.member_count, 150);
        assert_eq!(ffi.alias.as_deref(), Some("#lobby:example.com"));
    }

    #[test]
    fn public_room_info_converts_none_optionals() {
        let core = CorePublicRoomInfo {
            id: "!empty:x.com".into(),
            name: None,
            topic: None,
            member_count: 0,
            alias: None,
        };
        let ffi: PublicRoomInfo = core.into();
        assert!(ffi.name.is_none());
        assert!(ffi.topic.is_none());
        assert!(ffi.alias.is_none());
    }

    // -- RoomMemberInfo round-trip --

    #[test]
    fn room_member_info_converts() {
        let core = CoreRoomMemberInfo {
            user_id: "@mod:example.com".into(),
            display_name: Some("Moderator".into()),
            power_level: 50,
            role: "moderator".into(),
        };
        let ffi: RoomMemberInfo = core.into();
        assert_eq!(ffi.user_id, "@mod:example.com");
        assert_eq!(ffi.display_name.as_deref(), Some("Moderator"));
        assert_eq!(ffi.power_level, 50);
        assert_eq!(ffi.role, "moderator");
    }

    // -- SsoProvider round-trip --

    #[test]
    fn sso_provider_converts() {
        let core = CoreSsoProvider {
            id: "oidc-github".into(),
            name: "GitHub".into(),
        };
        let ffi: SsoProvider = core.into();
        assert_eq!(ffi.id, "oidc-github");
        assert_eq!(ffi.name, "GitHub");
    }

    // -- LoginMethods round-trip --

    #[test]
    fn login_methods_converts_with_providers() {
        let core = CoreLoginMethods {
            supports_password: true,
            supports_sso: true,
            sso_providers: vec![
                CoreSsoProvider { id: "google".into(), name: "Google".into() },
                CoreSsoProvider { id: "github".into(), name: "GitHub".into() },
            ],
        };
        let ffi: LoginMethods = core.into();
        assert!(ffi.supports_password);
        assert!(ffi.supports_sso);
        assert_eq!(ffi.sso_providers.len(), 2);
        assert_eq!(ffi.sso_providers[0].id, "google");
        assert_eq!(ffi.sso_providers[1].name, "GitHub");
    }

    #[test]
    fn login_methods_converts_empty_providers() {
        let core = CoreLoginMethods {
            supports_password: true,
            supports_sso: false,
            sso_providers: vec![],
        };
        let ffi: LoginMethods = core.into();
        assert!(ffi.supports_password);
        assert!(!ffi.supports_sso);
        assert!(ffi.sso_providers.is_empty());
    }

    // -- Error conversion --

    #[test]
    fn error_converts_all_variants() {
        let cases = vec![
            (CoreError::Auth { message: "bad".into() }, "Auth"),
            (CoreError::Network { message: "timeout".into() }, "Network"),
            (CoreError::Room { message: "gone".into() }, "Room"),
            (CoreError::Store { message: "corrupt".into() }, "Store"),
            (CoreError::Sync { message: "failed".into() }, "Sync"),
            (CoreError::Unknown { message: "wat".into() }, "Unknown"),
        ];

        for (core_err, expected_variant) in cases {
            let msg = match &core_err {
                CoreError::Auth { message } => message.clone(),
                CoreError::Network { message } => message.clone(),
                CoreError::Room { message } => message.clone(),
                CoreError::Store { message } => message.clone(),
                CoreError::Sync { message } => message.clone(),
                CoreError::Unknown { message } => message.clone(),
            };
            let ffi_err: ParlotteError = core_err.into();
            let debug = format!("{:?}", ffi_err);
            assert!(debug.contains(expected_variant), "expected {expected_variant} in {debug}");
            assert!(debug.contains(&msg), "expected message '{msg}' in {debug}");
        }
    }

    #[test]
    fn error_preserves_message_content() {
        let core = CoreError::Auth { message: "invalid credentials for @user:matrix.org".into() };
        let ffi: ParlotteError = core.into();
        assert_eq!(
            ffi.to_string(),
            "authentication failed: invalid credentials for @user:matrix.org"
        );
    }
}
