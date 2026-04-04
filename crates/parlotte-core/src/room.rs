/// Summary information about a joined room.
#[derive(Debug, Clone)]
pub struct RoomInfo {
    /// The Matrix room ID (e.g., `!abc123:example.com`).
    pub id: String,
    /// Human-readable display name for the room.
    pub display_name: String,
    /// Whether the room has encryption enabled.
    pub is_encrypted: bool,
    /// The topic of the room, if set.
    pub topic: Option<String>,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn room_info_construction() {
        let room = RoomInfo {
            id: "!abc:example.com".into(),
            display_name: "Test Room".into(),
            is_encrypted: true,
            topic: Some("A topic".into()),
        };
        assert_eq!(room.id, "!abc:example.com");
        assert_eq!(room.display_name, "Test Room");
        assert!(room.is_encrypted);
        assert_eq!(room.topic.as_deref(), Some("A topic"));
    }

    #[test]
    fn room_info_without_topic() {
        let room = RoomInfo {
            id: "!xyz:example.com".into(),
            display_name: "No Topic".into(),
            is_encrypted: false,
            topic: None,
        };
        assert!(!room.is_encrypted);
        assert!(room.topic.is_none());
    }

    #[test]
    fn room_info_clone() {
        let room = RoomInfo {
            id: "!abc:example.com".into(),
            display_name: "Cloned".into(),
            is_encrypted: false,
            topic: None,
        };
        let cloned = room.clone();
        assert_eq!(room.id, cloned.id);
        assert_eq!(room.display_name, cloned.display_name);
    }
}
