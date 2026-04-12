/// Integration test helpers for parlotte-core.
/// These tests require a running Synapse server (see docker-compose.yml).
///
/// Run with: cargo test -p parlotte-integration
///
/// The tests use the Synapse registration API to create fresh users for each
/// test, so they are fully isolated and can run in parallel.
use parlotte_core::ParlotteClient;
use serde::Deserialize;
use std::sync::atomic::{AtomicU32, Ordering};

const HOMESERVER_URL: &str = "http://localhost:8008";

static USER_COUNTER: AtomicU32 = AtomicU32::new(0);

/// Generate a unique username for each test to avoid conflicts.
fn unique_username(prefix: &str) -> String {
    let id = USER_COUNTER.fetch_add(1, Ordering::SeqCst);
    let ts = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_millis();
    format!("{prefix}_{id}_{ts}")
}

#[derive(Deserialize)]
struct RegisterResponse {
    user_id: String,
}

/// Register a user via Synapse's registration API and return a logged-in ParlotteClient.
fn register_and_login(prefix: &str) -> (ParlotteClient, String) {
    let username = unique_username(prefix);
    let password = "test-password-123";

    // Register via the Matrix client API (open registration is enabled)
    let rt = tokio::runtime::Runtime::new().unwrap();
    let user_id = rt.block_on(async {
        let client = reqwest::Client::new();
        let resp = client
            .post(format!("{HOMESERVER_URL}/_matrix/client/v3/register"))
            .json(&serde_json::json!({
                "username": username,
                "password": password,
                "auth": {
                    "type": "m.login.dummy"
                }
            }))
            .send()
            .await
            .expect("failed to send registration request");

        let status = resp.status();
        let body = resp.text().await.unwrap();
        assert!(
            status.is_success(),
            "registration failed ({status}): {body}"
        );

        let reg: RegisterResponse = serde_json::from_str(&body).unwrap();
        reg.user_id
    });
    drop(rt);

    // Now create a ParlotteClient and login
    let client = ParlotteClient::new(HOMESERVER_URL, None)
        .expect("failed to create parlotte client");
    let session = client
        .login(&username, password)
        .expect("login failed after registration");

    assert_eq!(session.user_id, user_id);
    assert!(!session.device_id.is_empty());

    (client, user_id)
}

/// Check if Synapse is reachable. Skips tests if not.
fn require_synapse() {
    let rt = tokio::runtime::Runtime::new().unwrap();
    let reachable = rt.block_on(async {
        reqwest::get(format!("{HOMESERVER_URL}/health"))
            .await
            .map(|r| r.status().is_success())
            .unwrap_or(false)
    });
    drop(rt);

    if !reachable {
        panic!(
            "Synapse not reachable at {HOMESERVER_URL}. \
             Start it with: docker compose -f tests/integration/docker-compose.yml up -d"
        );
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    // -- Test: Login with valid credentials --

    #[test]
    fn login_with_valid_credentials() {
        require_synapse();
        let (client, user_id) = register_and_login("login_valid");

        // Verify session info
        assert!(user_id.starts_with('@'));
        assert!(user_id.contains(":parlotte.test"));

        // Rooms should be empty for a fresh user
        let rooms = client.rooms().unwrap();
        assert!(rooms.is_empty());
    }

    // -- Test: Login with invalid credentials --

    #[test]
    fn login_with_invalid_credentials() {
        require_synapse();

        let client = ParlotteClient::new(HOMESERVER_URL, None).unwrap();
        let result = client.login("nonexistent_user_xyz", "wrong_password");

        assert!(result.is_err());
        match result.unwrap_err() {
            parlotte_core::ParlotteError::Auth { message } => {
                assert!(!message.is_empty());
            }
            other => panic!("expected Auth error, got: {other}"),
        }
    }

    // -- Test: Create room and list rooms --

    #[test]
    fn create_room_and_list() {
        require_synapse();
        let (client, _) = register_and_login("create_room");

        // Create a room
        let room_id = client.create_room("Test Room", false).unwrap();
        assert!(room_id.starts_with('!'));
        assert!(room_id.contains(":parlotte.test"));

        // Sync to pick up the room
        client.sync_once().unwrap();

        // List rooms — should contain our new room
        let rooms = client.rooms().unwrap();
        assert_eq!(rooms.len(), 1);
        assert_eq!(rooms[0].id, room_id);
        assert_eq!(rooms[0].display_name, "Test Room");
        // Note: modern Synapse enables encryption by default for new rooms
    }

    // -- Test: Two users send and receive messages --

    #[test]
    fn two_users_messaging() {
        require_synapse();
        let (alice, _alice_id) = register_and_login("alice");
        let (bob, bob_id) = register_and_login("bob");

        // Alice creates a room and invites Bob
        let room_id = alice.create_room("Chat Room", false).unwrap();
        alice.sync_once().unwrap();
        alice.invite_user(&room_id, &bob_id).unwrap();

        // Bob syncs to see the invite
        bob.sync_once().unwrap();

        // Verify the invited room appears in Bob's room list
        let bob_rooms = bob.rooms().unwrap();
        let invited = bob_rooms.iter().find(|r| r.id == room_id);
        assert!(invited.is_some(), "Bob should see the invited room");
        assert!(invited.unwrap().is_invited, "Room should be marked as invited");

        bob.join_room(&room_id).unwrap();

        // Both sync to see Bob's join
        alice.sync_once().unwrap();
        bob.sync_once().unwrap();

        // After joining, room should no longer be marked as invited
        let bob_rooms = bob.rooms().unwrap();
        let joined = bob_rooms.iter().find(|r| r.id == room_id);
        assert!(joined.is_some(), "Bob should still see the room after joining");
        assert!(!joined.unwrap().is_invited, "Room should not be marked as invited after joining");

        // Alice sends a message
        alice.send_message(&room_id, "Hello Bob!").unwrap();

        // Both sync to receive the message
        alice.sync_once().unwrap();
        bob.sync_once().unwrap();

        // Verify both users see the room
        let alice_rooms = alice.rooms().unwrap();
        let bob_rooms = bob.rooms().unwrap();
        assert!(alice_rooms.iter().any(|r| r.id == room_id));
        assert!(bob_rooms.iter().any(|r| r.id == room_id));

        // Verify Alice's message is visible to both users
        let alice_msgs = alice.messages(&room_id, 50, None).unwrap().messages;
        let bob_msgs = bob.messages(&room_id, 50, None).unwrap().messages;

        assert!(
            alice_msgs.iter().any(|m| m.body == "Hello Bob!"),
            "Alice should see her own message"
        );
        assert!(
            bob_msgs.iter().any(|m| m.body == "Hello Bob!"),
            "Bob should see Alice's message"
        );
    }

    // -- Test: Multi-message conversation between two users --

    #[test]
    fn two_users_conversation() {
        require_synapse();
        let (alice, _alice_id) = register_and_login("conv_alice");
        let (bob, bob_id) = register_and_login("conv_bob");

        // Alice creates a room and invites Bob
        let room_id = alice.create_room("Conversation", false).unwrap();
        alice.sync_once().unwrap();
        alice.invite_user(&room_id, &bob_id).unwrap();

        bob.sync_once().unwrap();
        bob.join_room(&room_id).unwrap();

        alice.sync_once().unwrap();
        bob.sync_once().unwrap();

        // Exchange several messages
        alice.send_message(&room_id, "Hey Bob, how are you?").unwrap();
        bob.sync_once().unwrap();

        bob.send_message(&room_id, "I'm good Alice! You?").unwrap();
        alice.sync_once().unwrap();

        alice.send_message(&room_id, "Great, thanks!").unwrap();
        alice.sync_once().unwrap();
        bob.sync_once().unwrap();

        // Both should see all three messages
        let alice_msgs = alice.messages(&room_id, 50, None).unwrap().messages;
        let bob_msgs = bob.messages(&room_id, 50, None).unwrap().messages;

        let expected = ["Hey Bob, how are you?", "I'm good Alice! You?", "Great, thanks!"];
        for body in &expected {
            assert!(
                alice_msgs.iter().any(|m| m.body == *body),
                "Alice missing message: {body}"
            );
            assert!(
                bob_msgs.iter().any(|m| m.body == *body),
                "Bob missing message: {body}"
            );
        }

        // Messages should be ordered by timestamp (oldest first)
        let alice_texts: Vec<&str> = alice_msgs.iter().map(|m| m.body.as_str()).collect();
        assert_eq!(
            alice_texts.iter().position(|b| *b == expected[0]).unwrap()
                < alice_texts.iter().position(|b| *b == expected[1]).unwrap(),
            true,
            "Messages should be in chronological order"
        );
    }

    // -- Test: Room display name resolution --

    #[test]
    fn room_display_name() {
        require_synapse();
        let (client, _) = register_and_login("display_name");

        // Create rooms with different names
        let room1_id = client.create_room("Living Room", false).unwrap();
        let room2_id = client.create_room("Kitchen", false).unwrap();

        client.sync_once().unwrap();

        let rooms = client.rooms().unwrap();
        assert_eq!(rooms.len(), 2);

        let room1 = rooms.iter().find(|r| r.id == room1_id).unwrap();
        let room2 = rooms.iter().find(|r| r.id == room2_id).unwrap();

        assert_eq!(room1.display_name, "Living Room");
        assert_eq!(room2.display_name, "Kitchen");
    }

    // -- Test: Leave room --

    #[test]
    fn leave_room() {
        require_synapse();
        let (client, _) = register_and_login("leave");

        let room_id = client.create_room("Goodbye Room", false).unwrap();
        client.sync_once().unwrap();
        assert_eq!(client.rooms().unwrap().len(), 1);

        client.leave_room(&room_id).unwrap();
        client.sync_once().unwrap();
        assert_eq!(client.rooms().unwrap().len(), 0);
    }

    // -- Test: Room members --

    #[test]
    fn room_members_list() {
        require_synapse();
        let (alice, _alice_id) = register_and_login("members_alice");
        let (bob, bob_id) = register_and_login("members_bob");

        // Alice creates a room and invites Bob
        let room_id = alice.create_room("Members Test", false).unwrap();
        alice.sync_once().unwrap();
        alice.invite_user(&room_id, &bob_id).unwrap();

        bob.sync_once().unwrap();
        bob.join_room(&room_id).unwrap();
        alice.sync_once().unwrap();
        bob.sync_once().unwrap();

        // Alice should see both members
        let members = alice.room_members(&room_id).unwrap();
        assert_eq!(members.len(), 2, "Room should have 2 members");

        // Alice is the creator, should be admin
        let alice_member = members.iter().find(|m| m.user_id == _alice_id).unwrap();
        assert_eq!(alice_member.role, "admin");

        // Bob is a regular member
        let bob_member = members.iter().find(|m| m.user_id == bob_id).unwrap();
        assert_eq!(bob_member.role, "member");
    }

    // -- Test: Multiple syncs are idempotent --

    #[test]
    fn multiple_syncs_idempotent() {
        require_synapse();
        let (client, _) = register_and_login("multi_sync");

        client.create_room("Stable Room", false).unwrap();

        // Sync multiple times — room count should stay at 1
        client.sync_once().unwrap();
        client.sync_once().unwrap();
        client.sync_once().unwrap();

        let rooms = client.rooms().unwrap();
        assert_eq!(rooms.len(), 1);
    }

    // -- Test: Invite with persistent store --

    #[test]
    fn invite_visible_with_persistent_store() {
        require_synapse();

        let alice_user = unique_username("store_alice");
        let bob_user = unique_username("store_bob");
        let password = "test-password-123";

        // Register both users
        let rt = tokio::runtime::Runtime::new().unwrap();
        let (_alice_id, bob_id) = rt.block_on(async {
            let http = reqwest::Client::new();
            let a = http.post(format!("{HOMESERVER_URL}/_matrix/client/v3/register"))
                .json(&serde_json::json!({"username": alice_user, "password": password, "auth": {"type": "m.login.dummy"}}))
                .send().await.unwrap().json::<RegisterResponse>().await.unwrap();
            let b = http.post(format!("{HOMESERVER_URL}/_matrix/client/v3/register"))
                .json(&serde_json::json!({"username": bob_user, "password": password, "auth": {"type": "m.login.dummy"}}))
                .send().await.unwrap().json::<RegisterResponse>().await.unwrap();
            (a.user_id, b.user_id)
        });
        drop(rt);

        // Create clients with persistent stores (like the app does)
        let alice_store = format!("{}/alice_store", std::env::temp_dir().display());
        let bob_store = format!("{}/bob_store", std::env::temp_dir().display());
        let _ = std::fs::remove_dir_all(&alice_store);
        let _ = std::fs::remove_dir_all(&bob_store);

        let alice = ParlotteClient::new(HOMESERVER_URL, Some(&alice_store)).unwrap();
        alice.login(&alice_user, password).unwrap();
        alice.sync_once().unwrap();

        let bob = ParlotteClient::new(HOMESERVER_URL, Some(&bob_store)).unwrap();
        bob.login(&bob_user, password).unwrap();
        bob.sync_once().unwrap();

        // Bob has no rooms yet
        let bob_rooms = bob.rooms().unwrap();
        assert_eq!(bob_rooms.len(), 0, "Bob should start with no rooms");

        // Alice creates a private room and invites Bob
        let room_id = alice.create_room("StoreTest", false).unwrap();
        alice.sync_once().unwrap();
        alice.invite_user(&room_id, &bob_id).unwrap();

        // Bob syncs — should see the invite
        bob.sync_once().unwrap();
        let bob_rooms = bob.rooms().unwrap();
        let invited = bob_rooms.iter().filter(|r| r.is_invited).collect::<Vec<_>>();
        assert_eq!(invited.len(), 1, "Bob should see 1 invited room, got {}", invited.len());
        assert_eq!(invited[0].id, room_id);

        // Cleanup
        let _ = std::fs::remove_dir_all(&alice_store);
        let _ = std::fs::remove_dir_all(&bob_store);
    }

    // -- Test: Message editing --

    #[test]
    fn edit_message() {
        require_synapse();
        let (alice, _) = register_and_login("edit_alice");

        let room_id = alice.create_room("Edit Test", false).unwrap();
        alice.sync_once().unwrap();

        alice.send_message(&room_id, "Original message").unwrap();
        alice.sync_once().unwrap();

        let msgs = alice.messages(&room_id, 50, None).unwrap().messages;
        let event_id = &msgs.iter().find(|m| m.body == "Original message").unwrap().event_id;

        alice.edit_message(&room_id, event_id, "Edited message").unwrap();
        alice.sync_once().unwrap();

        let msgs = alice.messages(&room_id, 50, None).unwrap().messages;
        let edited = msgs.iter().find(|m| m.event_id == *event_id).unwrap();
        assert_eq!(edited.body, "Edited message");
        assert!(edited.is_edited, "Message should be marked as edited");
    }

    // -- Test: Message deletion (redaction) --

    #[test]
    fn redact_message() {
        require_synapse();
        let (alice, _) = register_and_login("redact_alice");

        let room_id = alice.create_room("Redact Test", false).unwrap();
        alice.sync_once().unwrap();

        alice.send_message(&room_id, "Delete me").unwrap();
        alice.sync_once().unwrap();

        let msgs = alice.messages(&room_id, 50, None).unwrap().messages;
        assert!(msgs.iter().any(|m| m.body == "Delete me"));
        let event_id = &msgs.iter().find(|m| m.body == "Delete me").unwrap().event_id;

        alice.redact_message(&room_id, event_id).unwrap();
        alice.sync_once().unwrap();

        let msgs = alice.messages(&room_id, 50, None).unwrap().messages;
        assert!(
            !msgs.iter().any(|m| m.body == "Delete me"),
            "Redacted message should not appear"
        );
    }

    // -- Test: Unread count and read receipts --

    #[test]
    fn unread_count_and_read_receipt() {
        require_synapse();
        let (alice, _alice_id) = register_and_login("unread_alice");
        let (bob, bob_id) = register_and_login("unread_bob");

        // Alice creates a room and invites Bob
        let room_id = alice.create_room("Unread Test", false).unwrap();
        alice.sync_once().unwrap();
        alice.invite_user(&room_id, &bob_id).unwrap();

        bob.sync_once().unwrap();
        bob.join_room(&room_id).unwrap();
        alice.sync_once().unwrap();
        bob.sync_once().unwrap();

        // Alice sends a message
        alice.send_message(&room_id, "Unread message").unwrap();
        bob.sync_once().unwrap();

        // Bob should have unread notifications
        let bob_rooms = bob.rooms().unwrap();
        let room = bob_rooms.iter().find(|r| r.id == room_id).unwrap();
        assert!(room.unread_count > 0, "Bob should have unread notifications");

        // Bob reads the messages and sends a read receipt
        let bob_msgs = bob.messages(&room_id, 50, None).unwrap().messages;
        let last_event_id = &bob_msgs.last().unwrap().event_id;
        bob.send_read_receipt(&room_id, last_event_id).unwrap();
        bob.sync_once().unwrap();

        // After sending the read receipt and syncing, unread count should be 0
        let bob_rooms = bob.rooms().unwrap();
        let room = bob_rooms.iter().find(|r| r.id == room_id).unwrap();
        assert_eq!(room.unread_count, 0, "Unread count should be 0 after read receipt");
    }

    // -- Test: Public room discovery and join --

    #[test]
    fn public_room_discovery_and_join() {
        require_synapse();
        let (alice, _) = register_and_login("pub_alice");
        let (bob, _) = register_and_login("pub_bob");

        // Alice creates a public room
        let room_id = alice.create_room("Public Lounge", true).unwrap();
        alice.sync_once().unwrap();
        bob.sync_once().unwrap();

        // Bob discovers it via the directory
        let public = bob.public_rooms().unwrap();
        assert!(
            public.iter().any(|r| r.id == room_id),
            "Public room should appear in directory"
        );

        let found = public.iter().find(|r| r.id == room_id).unwrap();
        assert_eq!(found.name.as_deref(), Some("Public Lounge"));

        // Bob joins the public room (no invite needed)
        bob.join_room(&room_id).unwrap();
        bob.sync_once().unwrap();

        let bob_rooms = bob.rooms().unwrap();
        assert!(bob_rooms.iter().any(|r| r.id == room_id));

        // Both can exchange messages
        alice.send_message(&room_id, "Welcome!").unwrap();
        bob.sync_once().unwrap();

        let msgs = bob.messages(&room_id, 50, None).unwrap().messages;
        assert!(msgs.iter().any(|m| m.body == "Welcome!"));
    }

    #[test]
    fn message_pagination() {
        require_synapse();
        let (alice, _) = register_and_login("page_alice");

        let room_id = alice.create_room("Pagination Test", false).unwrap();
        alice.sync_once().unwrap();

        // Send 8 messages
        for i in 1..=8 {
            alice
                .send_message(&room_id, &format!("msg-{i}"))
                .unwrap();
        }
        alice.sync_once().unwrap();

        // Fetch first batch (limit 3) — should get the 3 most recent (6, 7, 8)
        let batch1 = alice.messages(&room_id, 3, None).unwrap();
        assert_eq!(batch1.messages.len(), 3);
        // Messages should be oldest-first within the batch
        assert_eq!(batch1.messages[0].body, "msg-6");
        assert_eq!(batch1.messages[1].body, "msg-7");
        assert_eq!(batch1.messages[2].body, "msg-8");
        assert!(
            batch1.end_token.is_some(),
            "Should have a pagination token for more messages"
        );

        // Verify chronological order (timestamps non-decreasing)
        for w in batch1.messages.windows(2) {
            assert!(
                w[0].timestamp_ms <= w[1].timestamp_ms,
                "Messages should be in chronological order"
            );
        }

        // Fetch second batch using the pagination token
        let batch2 = alice
            .messages(&room_id, 3, batch1.end_token.as_deref())
            .unwrap();
        assert_eq!(batch2.messages.len(), 3);
        assert_eq!(batch2.messages[0].body, "msg-3");
        assert_eq!(batch2.messages[1].body, "msg-4");
        assert_eq!(batch2.messages[2].body, "msg-5");

        // Second batch should be older than first batch
        assert!(
            batch2.messages.last().unwrap().timestamp_ms
                <= batch1.messages.first().unwrap().timestamp_ms,
            "Second batch should be older than first batch"
        );

        // Fetch third batch
        let batch3 = alice
            .messages(&room_id, 3, batch2.end_token.as_deref())
            .unwrap();
        // Should get remaining messages (msg-1, msg-2, and possibly room creation event)
        assert!(
            batch3.messages.iter().any(|m| m.body == "msg-1"),
            "Third batch should contain msg-1"
        );
        assert!(
            batch3.messages.iter().any(|m| m.body == "msg-2"),
            "Third batch should contain msg-2"
        );
    }
}
