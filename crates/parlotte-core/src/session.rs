use crate::message::OidcSessionData;

/// A notification emitted by the matrix-sdk about the login session.
#[derive(Debug, Clone)]
pub enum SessionChangeEvent {
    /// The OIDC access/refresh tokens were rotated. The caller should
    /// persist `session` so the next app launch restores with the current
    /// refresh token (MAS rotates refresh tokens on each use).
    TokensRefreshed { session: OidcSessionData },
    /// The server rejected our token with `M_UNKNOWN_TOKEN`. The caller
    /// should prompt the user to sign in again. `soft_logout` is `true`
    /// when the server left the device registered (so a simple re-login
    /// restores state) and `false` when the device was fully invalidated.
    UnknownToken { soft_logout: bool },
}

/// Callback for session-level changes (token refresh, unknown-token logout).
/// Register with [`crate::ParlotteClient::set_session_change_listener`].
pub trait SessionChangeListener: Send + Sync + 'static {
    fn on_session_change(&self, event: SessionChangeEvent);
}
