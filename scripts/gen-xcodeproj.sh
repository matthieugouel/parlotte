#!/usr/bin/env bash
set -euo pipefail

# Generates apple/Parlotte/Parlotte.xcodeproj from the xcodegen config. The
# .xcodeproj is gitignored — regenerate after pulling, or after editing
# project.yml.

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT/apple/Parlotte"

if ! command -v xcodegen >/dev/null 2>&1; then
    echo "xcodegen not found. Install with: brew install xcodegen" >&2
    exit 1
fi

xcodegen generate --spec project.yml
echo "Generated: apple/Parlotte/Parlotte.xcodeproj"
