#![recursion_limit = "512"]

pub mod client;
pub mod error;
pub mod message;
pub mod recovery;
pub mod room;
pub mod sync;
pub mod verification;

pub use client::ParlotteClient;
pub use sync::SyncListener;
pub use error::ParlotteError;
pub use message::{LoginMethods, MatrixSessionData, MessageBatch, MessageInfo, ReactionInfo, SessionInfo, SsoProvider, UserProfile};
pub use recovery::RecoveryState;
pub use room::{PublicRoomInfo, RoomInfo, RoomMemberInfo};
pub use verification::{EmojiInfo, VerificationListener, VerificationRequestInfo, VerificationState};
