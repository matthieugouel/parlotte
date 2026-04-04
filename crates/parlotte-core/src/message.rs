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
}

/// Information about the current session.
#[derive(Debug, Clone)]
pub struct SessionInfo {
    /// The authenticated user's Matrix ID.
    pub user_id: String,
    /// The device ID for this session.
    pub device_id: String,
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
}
