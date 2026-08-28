#!/bin/bash
# Build DexUI and assemble it into a double-clickable .app bundle.
#
# Usage: Scripts/bundle.sh [--version 1.2.3] [--universal] [--output dist]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

VERSION="0.0.0-dev"
OUTPUT="dist"
ARCH_FLAGS=()
APP_NAME="Tasks"
# The SwiftPM product is still called DexUI; the shipped executable is not.
EXECUTABLE_NAME="Tasks"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) VERSION="$2"; shift 2 ;;
    --output)  OUTPUT="$2";  shift 2 ;;
    --universal) ARCH_FLAGS=(--arch arm64 --arch x86_64); shift ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

# A leading "v" is fine in a git tag but not in CFBundleVersion.
VERSION="${VERSION#v}"

echo "==> Building DexUI ${VERSION}"
swift build -c release --product DexUI ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}

BINARY="$(swift build -c release --product DexUI ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"} --show-bin-path)/DexUI"
[[ -f "$BINARY" ]] || { echo "No binary at $BINARY" >&2; exit 1; }

APP="$OUTPUT/$APP_NAME.app"
echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BINARY" "$APP/Contents/MacOS/$EXECUTABLE_NAME"
sed -e "s/__VERSION__/$VERSION/g" -e "s/__EXECUTABLE__/$EXECUTABLE_NAME/g" \
  Resources/Info.plist > "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

if "$ROOT/Scripts/make-icon.sh" "$APP/Contents/Resources/AppIcon.icns"; then
  echo "==> Icon generated"
else
  echo "==> Skipping icon (generation failed)" >&2
fi

# Ad-hoc signature. Without it macOS refuses to launch an arm64 binary that has
# been moved or unzipped, which is exactly what a release download is.
codesign --force --deep --sign - "$APP" 2>/dev/null || echo "==> codesign unavailable, continuing" >&2

echo "==> Built $APP"
