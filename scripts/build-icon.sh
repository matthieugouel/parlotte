#!/usr/bin/env bash
set -euo pipefail

# Regenerates the macOS AppIcon.appiconset from the SVG master at
# branding/icon/parlotte-icon.svg. Run this whenever the icon changes.

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC_SVG="$REPO_ROOT/branding/icon/parlotte-icon.svg"
ICONSET="$REPO_ROOT/apple/Parlotte/Resources/Assets.xcassets/AppIcon.appiconset"

if [ ! -f "$SRC_SVG" ]; then
    echo "error: $SRC_SVG not found" >&2
    exit 1
fi

mkdir -p "$ICONSET"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Render the SVG once at 1024 via QuickLook, then downscale with sips.
# qlmanage output lands next to the input with a .png suffix.
cp "$SRC_SVG" "$TMP/src.svg"
qlmanage -t -s 1024 -o "$TMP" "$TMP/src.svg" >/dev/null 2>&1
MASTER="$TMP/src.svg.png"

if [ ! -f "$MASTER" ]; then
    echo "error: QuickLook failed to render $SRC_SVG" >&2
    exit 1
fi

# macOS AppIcon requires these sizes (idiom, size, scale → pixel dim).
declare -a SIZES=(
    "16:1:16"
    "16:2:32"
    "32:1:32"
    "32:2:64"
    "128:1:128"
    "128:2:256"
    "256:1:256"
    "256:2:512"
    "512:1:512"
    "512:2:1024"
)

CONTENTS="$ICONSET/Contents.json"
echo '{' > "$CONTENTS"
echo '  "images" : [' >> "$CONTENTS"

first=1
for entry in "${SIZES[@]}"; do
    IFS=':' read -r size scale pixels <<< "$entry"
    filename="icon_${pixels}.png"
    sips -z "$pixels" "$pixels" "$MASTER" --out "$ICONSET/$filename" >/dev/null

    [ $first -eq 0 ] && echo ',' >> "$CONTENTS"
    first=0
    cat >> "$CONTENTS" <<EOF
    {
      "filename" : "$filename",
      "idiom" : "mac",
      "scale" : "${scale}x",
      "size" : "${size}x${size}"
    }
EOF
done

cat >> "$CONTENTS" <<'EOF'

  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
EOF

# Assets.xcassets needs a top-level Contents.json too.
ASSETS_ROOT="$REPO_ROOT/apple/Parlotte/Resources/Assets.xcassets/Contents.json"
cat > "$ASSETS_ROOT" <<'EOF'
{
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
EOF

echo "Generated icon set at $ICONSET"
ls "$ICONSET"
