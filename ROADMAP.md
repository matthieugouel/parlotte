# Parlotte Roadmap (macOS app)

Items tagged **[v1]** are targeted for the first App Store release. See the
[Release](#release-app-store-v1) section for branding and store-submission
work that doesn't belong in any other category.

## Core
- [x] Login / logout with session persistence
- [x] Apple build pipeline (Rust -> XCFramework -> Swift bindings)
- [x] Integration tests against real Synapse server
- [x] Multi-profile support (`--profile` flag for testing)
- [x] Debug logging (`--debug` flag)
- [x] Background sync (persistent connection instead of 5s polling)
- [ ] **[v1]** Push notifications (APNs entitlement, Sygnal/pusher config, tap-to-open-room)
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
- [x] Room settings (name, topic)
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
- [x] Reactions (emoji)
- [x] Rich text rendering (HTML formatted messages)
- [x] Non-text message indicators (image, file, video, audio, location)
- [x] Media messages (display images, download files)
- [x] Media upload (send images, files)

## UX
- [x] Unread indicators / notification badges
- [x] Read receipts (mark rooms as read)
- [x] User profile (display name, avatar)
- [x] Light & dark mode
- [x] Design system (spacing tokens, semantic colors, typography scale)
- [x] Message grouping (consecutive same-sender messages collapse)
- [x] Room avatars in sidebar and headers
- [x] Redesigned room list (two-line rows with avatar, name, subtitle)
- [x] Redesigned room header (avatar, consolidated overflow menu)
- [x] Redesigned message composer (rounded surface with border)
- [x] Sidebar header with user avatar and sync status
- [x] Empty conversation state
- [ ] Search (messages, rooms)

## Security
- [x] Legacy SSO login (browser-based, works with most Synapse servers)
- [ ] Native OIDC login (MAS / OpenID Connect)
- [ ] **[v1]** Device verification (cross-signing)
- [x] **[v1]** Key backup and recovery (reinstall must not lose encrypted history)
  - [x] Core + FFI: enable/disable/recover + `RecoveryState`
  - [x] Settings UI: status, enable, recovery-key display, key entry
  - [x] Post-login prompt when `RecoveryState::Incomplete` (new device)
  - [x] `is_last_device` warning before logout

## Testing
- [x] Unit tests for input validation and error paths (parlotte-core)
- [x] Integration tests against real Synapse (Docker)
- [x] FFI round-trip tests (type conversions, error mapping)
- [x] Swift state management tests (optimistic updates, failure revert, dedup)
- [x] AppState edge-case coverage (pagination guards, invite/create error paths, delete revert)
- [x] Debug IPC server (`--debug-ipc-port`) for AI-driven UI testing
- [x] DebugServer test suite (state snapshots, command dispatch, error paths)
- [x] `ax-inspect` accessibility driver (real keystroke typing, button clicks, field input, wait-for)
- [ ] CI pipeline (GitHub Actions: build, test, clippy, fmt)
- [ ] Persistent sync loop integration test (start sync, receive callback, stop)
- [ ] **[v1]** Crash reporting (Sentry or MetricKit) for post-launch triage

## Release (App Store v1)

Feature work tagged **[v1]** lives in the sections above. This section covers
only branding and store-submission artifacts.

### Branding
- [ ] App icon (1024×1024 master + full macOS icon set)
- [ ] App name and bundle identifier finalized
- [ ] Launch screen / first-run experience
- [ ] Marketing screenshots for the App Store listing
- [ ] App Store description, keywords, category, support URL

### Submission
- [ ] Privacy manifest (`PrivacyInfo.xcprivacy`) declaring data collection and required-reason APIs
- [ ] Privacy policy + terms of service URLs
- [ ] Mac App Store distribution profile and code signing
- [ ] Notarization and hardened runtime
- [ ] Sandbox entitlements audit (network, keychain, user-selected files)
