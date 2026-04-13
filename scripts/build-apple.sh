#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TARGET_TRIPLE="aarch64-apple-darwin"
FFI_LIB_NAME="parlotte_ffi"
BUILD_MODE="${1:-release}"

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'
log() { echo -e "${GREEN}[build-apple]${NC} $*"; }
err() { echo -e "${RED}[build-apple]${NC} $*" >&2; }

cd "$REPO_ROOT"

# Match the deployment target to the Swift package's minimum (macOS 14).
# Without this, the Rust lib inherits the host SDK version, causing
# "built for newer macOS" linker warnings when linking into the app.
export MACOSX_DEPLOYMENT_TARGET="14.0"

# Step 1: Build Rust static library
log "Building Rust static library ($BUILD_MODE, $TARGET_TRIPLE)..."
if [ "$BUILD_MODE" = "debug" ]; then
    cargo build -p parlotte-ffi --target "$TARGET_TRIPLE"
    LIB_DIR="$REPO_ROOT/target/$TARGET_TRIPLE/debug"
else
    cargo build -p parlotte-ffi --release --target "$TARGET_TRIPLE"
    LIB_DIR="$REPO_ROOT/target/$TARGET_TRIPLE/release"
fi

LIB_PATH="$LIB_DIR/lib${FFI_LIB_NAME}.a"
if [ ! -f "$LIB_PATH" ]; then
    err "Static library not found at $LIB_PATH"
    exit 1
fi
log "Static library: $LIB_PATH"

# Step 2: Generate Swift bindings
log "Generating Swift bindings..."
STAGING="$REPO_ROOT/target/uniffi-staging"
rm -rf "$STAGING"
mkdir -p "$STAGING"

cargo run -p parlotte-ffi --bin uniffi-bindgen generate \
    --library "$LIB_PATH" \
    --language swift \
    --out-dir "$STAGING"

for f in "${FFI_LIB_NAME}.swift" "${FFI_LIB_NAME}FFI.h" "${FFI_LIB_NAME}FFI.modulemap"; do
    if [ ! -f "$STAGING/$f" ]; then
        err "Expected generated file not found: $STAGING/$f"
        exit 1
    fi
done
log "Generated: $(ls "$STAGING" | tr '\n' ' ')"

# Step 3: Copy generated Swift bindings to ParlotteSDK
log "Copying generated files to ParlotteSDK..."
FFI_SOURCES="$REPO_ROOT/apple/ParlotteSDK/Sources/ParlotteFFI"
mkdir -p "$FFI_SOURCES"
cp "$STAGING/${FFI_LIB_NAME}.swift" "$FFI_SOURCES/"

# Step 4: Set up the C headers for the FFI module
HEADERS_DIR="$REPO_ROOT/apple/ParlotteSDK/Sources/ParlotteFFIHeaders"
rm -rf "$HEADERS_DIR"
mkdir -p "$HEADERS_DIR"
cp "$STAGING/${FFI_LIB_NAME}FFI.h" "$HEADERS_DIR/"
cp "$STAGING/${FFI_LIB_NAME}FFI.modulemap" "$HEADERS_DIR/module.modulemap"

# Step 5: Copy static library to a known location for SPM
LIB_OUT="$REPO_ROOT/apple/ParlotteSDK/RustFramework"
mkdir -p "$LIB_OUT"
cp "$LIB_PATH" "$LIB_OUT/"

log "Done! Build pipeline complete."
log ""
log "Static lib:  apple/ParlotteSDK/RustFramework/lib${FFI_LIB_NAME}.a"
log "Swift code:  apple/ParlotteSDK/Sources/ParlotteFFI/${FFI_LIB_NAME}.swift"
log "C headers:   apple/ParlotteSDK/Sources/ParlotteFFIHeaders/include/"
