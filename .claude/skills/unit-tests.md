---
description: Run parlotte-core unit tests (no Docker required)
match:
  - unit test
  - run tests
  - cargo test
  - test core
---

# Running Unit Tests

Unit tests are embedded in each source file under `#[cfg(test)]` modules.

```bash
cargo test -p parlotte-core
```

This runs all 24+ tests across the core modules:
- `client::tests` — Client creation, input validation, error mapping, event listener registration
- `error::tests` — Error display messages, Debug impl, Result alias
- `room::tests` — RoomInfo construction and Clone
- `message::tests` — MessageInfo/SessionInfo construction and Clone
- `sync::tests` — SyncManager state machine

## Philosophy

We test **our code**, not the Matrix SDK. Tests cover:
- Input validation (invalid room IDs, user IDs, URLs)
- Error type conversions (`From<matrix_sdk::Error> for ParlotteError`)
- Type construction and trait implementations
- State management (sync manager running state)
- Event listener registration (no panics, replacement works)

We do NOT mock HTTP endpoints to test SDK behavior — that's the SDK's job.

## Running a Single Test

```bash
cargo test -p parlotte-core client::tests::send_message_rejects_invalid_room_id
```

## Known Constraints

- `ParlotteClient` owns a `tokio::Runtime`, so it cannot be created/dropped inside an async test context. Tests that need a client use synchronous `#[test]`, not `#[tokio::test]`.
- SQLite store path testing is covered in integration tests because `deadpool` requires a tokio reactor during both init and drop.
