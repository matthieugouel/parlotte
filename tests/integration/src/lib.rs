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
        let room_id = client.create_room("Test Room").unwrap();
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
        let room_id = alice.create_room("Chat Room").unwrap();
        alice.sync_once().unwrap();
        alice.invite_user(&room_id, &bob_id).unwrap();

        // Bob syncs to see the invite, then joins
        bob.sync_once().unwrap();
        bob.join_room(&room_id).unwrap();

        // Both sync to see Bob's join
        alice.sync_once().unwrap();
        bob.sync_once().unwrap();

        // Alice sends a message
        alice.send_message(&room_id, "Hello Bob!").unwrap();

        // Bob syncs to receive the message
        bob.sync_once().unwrap();

        // Verify both users see the room
        let alice_rooms = alice.rooms().unwrap();
        let bob_rooms = bob.rooms().unwrap();
        assert!(alice_rooms.iter().any(|r| r.id == room_id));
        assert!(bob_rooms.iter().any(|r| r.id == room_id));
    }

    // -- Test: Room display name resolution --

    #[test]
    fn room_display_name() {
        require_synapse();
        let (client, _) = register_and_login("display_name");

        // Create rooms with different names
        let room1_id = client.create_room("Living Room").unwrap();
        let room2_id = client.create_room("Kitchen").unwrap();

        client.sync_once().unwrap();

        let rooms = client.rooms().unwrap();
        assert_eq!(rooms.len(), 2);

        let room1 = rooms.iter().find(|r| r.id == room1_id).unwrap();
        let room2 = rooms.iter().find(|r| r.id == room2_id).unwrap();

        assert_eq!(room1.display_name, "Living Room");
        assert_eq!(room2.display_name, "Kitchen");
    }

    // -- Test: Multiple syncs are idempotent --

    #[test]
    fn multiple_syncs_idempotent() {
        require_synapse();
        let (client, _) = register_and_login("multi_sync");

        client.create_room("Stable Room").unwrap();

        // Sync multiple times — room count should stay at 1
        client.sync_once().unwrap();
        client.sync_once().unwrap();
        client.sync_once().unwrap();

        let rooms = client.rooms().unwrap();
        assert_eq!(rooms.len(), 1);
    }
}
