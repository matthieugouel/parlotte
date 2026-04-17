#!/usr/bin/env bash
set -euo pipefail

# Builds Parlotte.app as a real bundle for local testing — unlike `swift run`,
# this produces a signed .app with a valid Info.plist so features that require
# a bundle (notifications, keychain groups, URL schemes) work correctly.
#
# Output: apple/Parlotte/build/Build/Products/Debug/Parlotte.app
#
# Usage:
#   ./scripts/build-app.sh            # debug build
#   ./scripts/build-app.sh release    # release config

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_MODE="${1:-debug}"

case "$BUILD_MODE" in
    debug)   CONFIG="Debug"   ;;
    release) CONFIG="Release" ;;
    *) echo "Usage: $0 [debug|release]" >&2; exit 1 ;;
esac

# Ensure the Rust XCFramework and Swift bindings are up to date.
"$REPO_ROOT/scripts/build-apple.sh" "$BUILD_MODE"

# Regenerate the Xcode project from project.yml.
"$REPO_ROOT/scripts/gen-xcodeproj.sh"

cd "$REPO_ROOT/apple/Parlotte"
xcodebuild \
    -project Parlotte.xcodeproj \
    -scheme Parlotte \
    -configuration "$CONFIG" \
    -derivedDataPath build \
    -destination 'platform=macOS' \
    build

APP_PATH="$REPO_ROOT/apple/Parlotte/build/Build/Products/$CONFIG/Parlotte.app"
if [ ! -d "$APP_PATH" ]; then
    echo "Build succeeded but Parlotte.app not found at $APP_PATH" >&2
    exit 1
fi

echo ""
echo "Built: $APP_PATH"
echo "Run with: open '$APP_PATH'"
