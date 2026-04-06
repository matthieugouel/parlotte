# Parlotte Roadmap (macOS app)

## Core
- [x] Login / logout with session persistence
- [x] Apple build pipeline (Rust -> XCFramework -> Swift bindings)
- [x] Integration tests against real Synapse server
- [x] Multi-profile support (`--profile` flag for testing)
- [x] Debug logging (`--debug` flag)
- [ ] Background sync (persistent connection instead of 5s polling)
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
- [ ] Message editing
- [ ] Message deletion
- [ ] Reply to messages
- [ ] Typing indicators
- [ ] Media messages (images, files)
- [ ] Markdown / rich text rendering

## UX
- [x] Unread indicators / notification badges
- [x] Read receipts (mark rooms as read)
- [ ] Room ordering by recent activity
- [ ] User profile (display name, avatar)
- [ ] Search (messages, rooms)

## Security
- [ ] OAuth / SSO login
- [ ] Device verification (cross-signing)
- [ ] Key backup and recovery
