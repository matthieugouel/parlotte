/// A single message from a room timeline.
#[derive(Debug, Clone)]
pub struct MessageInfo {
    /// The Matrix event ID.
    pub event_id: String,
    /// The sender's Matrix user ID.
    pub sender: String,
    /// The text body of the message (plain text fallback).
    pub body: String,
    /// HTML-formatted body, if the sender provided one.
    pub formatted_body: Option<String>,
    /// The message type (e.g. "text", "image", "file", "video", "audio", "notice", "emote").
    pub message_type: String,
    /// Unix timestamp in milliseconds when the message was sent (origin server ts).
    pub timestamp_ms: u64,
    /// Whether this message has been edited.
    pub is_edited: bool,
    /// The event ID this message is replying to, if any.
    pub replied_to_event_id: Option<String>,
    /// The mxc:// URI for media messages (image, file, video, audio).
    pub media_source: Option<String>,
    /// MIME type for media messages.
    pub media_mime_type: Option<String>,
    /// Width in pixels for image/video messages.
    pub media_width: Option<u32>,
    /// Height in pixels for image/video messages.
    pub media_height: Option<u32>,
    /// Size in bytes of the media file.
    pub media_size: Option<u64>,
}

/// A batch of messages with a pagination token for loading more.
#[derive(Debug, Clone)]
pub struct MessageBatch {
    /// The messages in this batch (oldest first).
    pub messages: Vec<MessageInfo>,
    /// Opaque token to fetch the next (older) batch. None if no more history.
    pub end_token: Option<String>,
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
            formatted_body: Some("<b>Hello!</b>".into()),
            message_type: "text".into(),
            timestamp_ms: 1700000000000,
            is_edited: false,
            replied_to_event_id: Some("$parent:example.com".into()),
            media_source: None,
            media_mime_type: None,
            media_width: None,
            media_height: None,
            media_size: None,
        };
        assert_eq!(msg.event_id, "$event1:example.com");
        assert_eq!(msg.sender, "@alice:example.com");
        assert_eq!(msg.body, "Hello!");
        assert_eq!(msg.formatted_body.as_deref(), Some("<b>Hello!</b>"));
        assert_eq!(msg.message_type, "text");
        assert_eq!(msg.timestamp_ms, 1700000000000);
        assert_eq!(msg.replied_to_event_id.as_deref(), Some("$parent:example.com"));
    }

    #[test]
    fn message_info_clone() {
        let msg = MessageInfo {
            event_id: "$e:x.com".into(),
            sender: "@a:x.com".into(),
            body: "hi".into(),
            formatted_body: None,
            message_type: "text".into(),
            timestamp_ms: 0,
            is_edited: false,
            replied_to_event_id: None,
            media_source: None,
            media_mime_type: None,
            media_width: None,
            media_height: None,
            media_size: None,
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
