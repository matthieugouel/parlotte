<p align="center">
  <img src="branding/icon/parlotte-icon.svg" width="128" alt="Parlotte icon">
</p>

# Parlotte

A fast, native Matrix client for macOS.

No Electron, no web views — SwiftUI from the ground up. End-to-end encrypted by default, with cross-signing and key backup. Works with any standard Matrix homeserver.

## Status

In active development. First TestFlight build is being prepared. iOS next.

## Links

- [Landing](https://matthieugouel.github.io/parlotte/) · [Privacy](https://matthieugouel.github.io/parlotte/privacy/) · [Support](https://matthieugouel.github.io/parlotte/support/)
- [Roadmap](ROADMAP.md) · [Architecture notes](CLAUDE.md)

## Building

```bash
cargo test -p parlotte-core             # Rust unit tests
cd apple/Parlotte && swift run Parlotte # Run the app (dev mode)
./scripts/build-app.sh                  # Build a signed .app bundle
```

## License

MIT
