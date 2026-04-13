#![recursion_limit = "512"]

pub mod client;
pub mod error;
pub mod message;
pub mod room;
pub mod sync;

pub use client::ParlotteClient;
pub use sync::SyncListener;
pub use error::ParlotteError;
pub use message::{LoginMethods, MatrixSessionData, MessageBatch, MessageInfo, ReactionInfo, SessionInfo, SsoProvider, UserProfile};
pub use room::{PublicRoomInfo, RoomInfo, RoomMemberInfo};
