# Parlotte Roadmap (macOS app)

## Core
- [x] Login / logout with session persistence
- [x] Apple build pipeline (Rust -> XCFramework -> Swift bindings)
- [x] Integration tests against real Synapse server
- [x] Multi-profile support (`--profile` flag for testing)
- [x] Debug logging (`--debug` flag)
- [x] Background sync (persistent connection instead of 5s polling)
- [ ] Push notifications
- [ ] Sliding Sync (performance at scale)

## Rooms
- [x] Room list with public/private/encrypted indicators
- [x] Create rooms (public or private)
- [x] Private rooms encrypted by default (Megolm E2EE)
- [x] Public room directory (explore and join)
- [x] Invite users to rooms
- [x] Accept invites
- [x] Leave room
- [x] Room member list
- [ ] Room settings (name, topic)
- [ ] Room avatars
- [ ] Admin actions (kick, ban, change power levels)
- [ ] Delete / tombstone rooms

## Messaging
- [x] Send and receive text messages
- [x] Message history
- [x] Message pagination (load older messages on scroll)
- [x] Message editing
- [x] Message deletion
- [x] Reply to messages
- [x] Typing indicators
- [ ] Reactions (emoji)
- [x] Rich text rendering (HTML formatted messages)
- [x] Non-text message indicators (image, file, video, audio, location)
- [ ] Media messages (display images, download files)
- [ ] Media upload (send images, files)

## UX
- [x] Unread indicators / notification badges
- [x] Read receipts (mark rooms as read)
- [ ] User profile (display name, avatar)
- [ ] Search (messages, rooms)

## Security
- [x] Legacy SSO login (browser-based, works with most Synapse servers)
- [ ] Native OIDC login (MAS / OpenID Connect)
- [ ] Device verification (cross-signing)
- [ ] Key backup and recovery

## Testing
- [x] Unit tests for input validation and error paths (parlotte-core)
- [x] Integration tests against real Synapse (Docker)
- [x] FFI round-trip tests (type conversions, error mapping)
- [x] Swift state management tests (optimistic updates, failure revert, dedup)
- [ ] CI pipeline (GitHub Actions: build, test, clippy, fmt)
- [ ] Persistent sync loop integration test (start sync, receive callback, stop)
- [ ] Automated UI smoke test (XCUITest: launch, login, send message)
