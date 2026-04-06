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
    MatrixSessionData as CoreMatrixSessionData, MessageInfo as CoreMessageInfo,
    ParlotteClient as CoreClient, ParlotteError as CoreError,
    PublicRoomInfo as CorePublicRoomInfo, RoomInfo as CoreRoomInfo,
    SessionInfo as CoreSessionInfo,
};
use std::fmt;

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
        }
    }
}

#[derive(uniffi::Record)]
pub struct MessageInfo {
    pub event_id: String,
    pub sender: String,
    pub body: String,
    pub timestamp_ms: u64,
}

impl From<CoreMessageInfo> for MessageInfo {
    fn from(m: CoreMessageInfo) -> Self {
        Self {
            event_id: m.event_id,
            sender: m.sender,
            body: m.body,
            timestamp_ms: m.timestamp_ms,
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

// -- Callback interface --

#[uniffi::export(callback_interface)]
pub trait ParlotteEventListener: Send + Sync {
    fn on_message(&self, room_id: String, sender: String, body: String, timestamp_ms: u64);
    fn on_sync_state_changed(&self, is_syncing: bool);
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

    pub fn messages(&self, room_id: String, limit: u64) -> Result<Vec<MessageInfo>, ParlotteError> {
        Ok(self.inner.messages(&room_id, limit)?.into_iter().map(Into::into).collect())
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

    pub fn is_syncing(&self) -> bool {
        self.inner.is_syncing()
    }
}
