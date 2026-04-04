uniffi::setup_scaffolding!();

use parlotte_core::{
    MessageInfo as CoreMessageInfo, ParlotteClient as CoreClient, ParlotteError as CoreError,
    RoomInfo as CoreRoomInfo, SessionInfo as CoreSessionInfo,
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
    pub topic: Option<String>,
}

impl From<CoreRoomInfo> for RoomInfo {
    fn from(r: CoreRoomInfo) -> Self {
        Self {
            id: r.id,
            display_name: r.display_name,
            is_encrypted: r.is_encrypted,
            topic: r.topic,
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

    pub fn logout(&self) -> Result<(), ParlotteError> {
        Ok(self.inner.logout()?)
    }

    pub fn rooms(&self) -> Result<Vec<RoomInfo>, ParlotteError> {
        Ok(self.inner.rooms()?.into_iter().map(Into::into).collect())
    }

    pub fn send_message(&self, room_id: String, body: String) -> Result<(), ParlotteError> {
        Ok(self.inner.send_message(&room_id, &body)?)
    }

    pub fn sync_once(&self) -> Result<(), ParlotteError> {
        Ok(self.inner.sync_once()?)
    }

    pub fn create_room(&self, name: String) -> Result<String, ParlotteError> {
        Ok(self.inner.create_room(&name)?)
    }

    pub fn invite_user(&self, room_id: String, user_id: String) -> Result<(), ParlotteError> {
        Ok(self.inner.invite_user(&room_id, &user_id)?)
    }

    pub fn join_room(&self, room_id: String) -> Result<(), ParlotteError> {
        Ok(self.inner.join_room(&room_id)?)
    }

    pub fn is_syncing(&self) -> bool {
        self.inner.is_syncing()
    }
}
