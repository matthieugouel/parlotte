#![recursion_limit = "512"]

pub mod client;
pub mod error;
pub mod message;
pub mod room;
pub(crate) mod sync;

pub use client::{EventListener, ParlotteClient};
pub use error::ParlotteError;
pub use message::{MatrixSessionData, MessageInfo, SessionInfo};
pub use room::{PublicRoomInfo, RoomInfo, RoomMemberInfo};
