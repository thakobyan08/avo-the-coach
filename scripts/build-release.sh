#!/usr/bin/env bash
# Builds a universal (Apple Silicon + Intel) Release of Avo and zips it to build/Avo.zip,
# ready to attach to a GitHub release. Needs Xcode.
# Usage: scripts/build-release.sh
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="Avo"
OUT_DIR="build"
DERIVED="$OUT_DIR/release"
ZIP="$OUT_DIR/${APP_NAME}.zip"

rm -rf "$DERIVED" "$ZIP"
xcodebuild \
    -project Avo.xcodeproj \
    -scheme Avo \
    -configuration Release \
    -derivedDataPath "$DERIVED" \
    -destination 'generic/platform=macOS' \
    ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO \
    build -quiet

app="$DERIVED/Build/Products/Release/${APP_NAME}.app"
lipo -info "$app/Contents/MacOS/$APP_NAME"
codesign --verify --strict "$app"

ditto -c -k --keepParent "$app" "$ZIP"
shasum -a 256 "$ZIP"
echo "Wrote $ZIP"
