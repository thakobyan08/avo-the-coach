#!/usr/bin/env bash
# Builds Avo from source and installs it to /Applications.
# Usage: ./install.sh
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="Avo"
BUNDLE_ID="com.thakobyan08.avo"
DEST="/Applications/${APP_NAME}.app"
LOG="${TMPDIR:-/tmp}/avo-install.log"
BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/avo-build.XXXXXX")"
trap 'rm -rf "$BUILD_DIR"' EXIT

step() { printf '\033[1m==>\033[0m %s\n' "$1"; }
fail() { printf '\033[31mError:\033[0m %s\n' "$1" >&2; exit 1; }

# 1. macOS 14 or newer
macos_major="$(sw_vers -productVersion | cut -d. -f1)"
if [ "$macos_major" -lt 14 ]; then
    fail "Avo needs macOS 14 (Sonoma) or newer. This Mac runs $(sw_vers -productVersion)."
fi

# 2. Full Xcode, not only the Command Line Tools
developer_dir="$(xcode-select -p 2>/dev/null || true)"
if [ -z "$developer_dir" ] || [[ "$developer_dir" == *CommandLineTools* ]]; then
    if [ -d "/Applications/Xcode.app" ]; then
        fail "Xcode is installed but not selected. Run this, then try again:
    sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
    else
        fail "Avo is built with Xcode. Install Xcode from the App Store, open it once, then try again."
    fi
fi
if ! xcodebuild -version >/dev/null 2>&1; then
    fail "Xcode is not ready yet. Open Xcode once and accept the license (or run: sudo xcodebuild -license accept), then try again."
fi

# 3. Build
step "Building ${APP_NAME} (this takes a minute)…"
if ! xcodebuild \
        -project Avo.xcodeproj \
        -scheme Avo \
        -configuration Release \
        -derivedDataPath "$BUILD_DIR" \
        build >"$LOG" 2>&1; then
    fail "The build failed. Details are in: $LOG"
fi
built_app="$BUILD_DIR/Build/Products/Release/${APP_NAME}.app"
[ -d "$built_app" ] || fail "The build finished but ${APP_NAME}.app was not found. Details are in: $LOG"

# 4. Quit the running copy, if any
if pgrep -x "$APP_NAME" >/dev/null; then
    step "Quitting the running ${APP_NAME}…"
    osascript -e "tell application id \"${BUNDLE_ID}\" to quit" >/dev/null 2>&1 || true
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        pgrep -x "$APP_NAME" >/dev/null || break
        sleep 0.5
    done
    pkill -x "$APP_NAME" 2>/dev/null || true
fi

# 5. Install
step "Installing to ${DEST}…"
if [ -w "/Applications" ] && { [ ! -e "$DEST" ] || [ -w "$DEST" ]; }; then
    rm -rf "$DEST"
    ditto "$built_app" "$DEST"
else
    echo "    Your password is needed to write to /Applications."
    sudo rm -rf "$DEST"
    sudo ditto "$built_app" "$DEST"
fi

# 6. Launch
step "Opening ${APP_NAME}…"
open "$DEST"

printf '\n\033[32mDone!\033[0m Look for the avocado in your menu bar (top right of the screen).\n'
rm -f "$LOG"
