/// A single message from a room timeline.
#[derive(Debug, Clone)]
pub struct MessageInfo {
    /// The Matrix event ID.
    pub event_id: String,
    /// The sender's Matrix user ID.
    pub sender: String,
    /// The text body of the message.
    pub body: String,
    /// Unix timestamp in milliseconds when the message was sent (origin server ts).
    pub timestamp_ms: u64,
    /// Whether this message has been edited.
    pub is_edited: bool,
}

/// An SSO identity provider offered by the homeserver.
#[derive(Debug, Clone)]
pub struct SsoProvider {
    /// The provider's unique ID.
    pub id: String,
    /// Human-readable name for the provider.
    pub name: String,
}

/// Login methods supported by the homeserver.
#[derive(Debug, Clone)]
pub struct LoginMethods {
    /// Whether username/password login is supported.
    pub supports_password: bool,
    /// Whether SSO login is supported.
    pub supports_sso: bool,
    /// Available SSO identity providers (empty if SSO is not supported).
    pub sso_providers: Vec<SsoProvider>,
}

/// Information about the current session.
#[derive(Debug, Clone)]
pub struct SessionInfo {
    /// The authenticated user's Matrix ID.
    pub user_id: String,
    /// The device ID for this session.
    pub device_id: String,
}

/// Full session data needed to restore a previous login.
#[derive(Debug, Clone)]
pub struct MatrixSessionData {
    /// The authenticated user's Matrix ID.
    pub user_id: String,
    /// The device ID for this session.
    pub device_id: String,
    /// The access token for this session.
    pub access_token: String,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn message_info_construction() {
        let msg = MessageInfo {
            event_id: "$event1:example.com".into(),
            sender: "@alice:example.com".into(),
            body: "Hello!".into(),
            timestamp_ms: 1700000000000,
            is_edited: false,
        };
        assert_eq!(msg.event_id, "$event1:example.com");
        assert_eq!(msg.sender, "@alice:example.com");
        assert_eq!(msg.body, "Hello!");
        assert_eq!(msg.timestamp_ms, 1700000000000);
    }

    #[test]
    fn message_info_clone() {
        let msg = MessageInfo {
            event_id: "$e:x.com".into(),
            sender: "@a:x.com".into(),
            body: "hi".into(),
            timestamp_ms: 0,
            is_edited: false,
        };
        let cloned = msg.clone();
        assert_eq!(msg.body, cloned.body);
        assert_eq!(msg.timestamp_ms, cloned.timestamp_ms);
    }

    #[test]
    fn session_info_construction() {
        let session = SessionInfo {
            user_id: "@alice:example.com".into(),
            device_id: "DEVICEABC".into(),
        };
        assert_eq!(session.user_id, "@alice:example.com");
        assert_eq!(session.device_id, "DEVICEABC");
    }

    #[test]
    fn session_info_clone() {
        let session = SessionInfo {
            user_id: "@bob:example.com".into(),
            device_id: "DEV123".into(),
        };
        let cloned = session.clone();
        assert_eq!(session.user_id, cloned.user_id);
        assert_eq!(session.device_id, cloned.device_id);
    }

    #[test]
    fn matrix_session_data_construction() {
        let data = MatrixSessionData {
            user_id: "@alice:example.com".into(),
            device_id: "DEVICEABC".into(),
            access_token: "syt_token_123".into(),
        };
        assert_eq!(data.user_id, "@alice:example.com");
        assert_eq!(data.device_id, "DEVICEABC");
        assert_eq!(data.access_token, "syt_token_123");
    }

    #[test]
    fn matrix_session_data_clone() {
        let data = MatrixSessionData {
            user_id: "@bob:example.com".into(),
            device_id: "DEV456".into(),
            access_token: "tok".into(),
        };
        let cloned = data.clone();
        assert_eq!(data.user_id, cloned.user_id);
        assert_eq!(data.device_id, cloned.device_id);
        assert_eq!(data.access_token, cloned.access_token);
    }
}
