#!/usr/bin/env bash
# Downloads the latest Avo release and installs it to /Applications.
# Usage: curl -fsSL https://raw.githubusercontent.com/thakobyan08/avo-the-coach/main/install.sh | bash
# To install a zip you built yourself: AVO_ZIP=build/Avo.zip ./install.sh
set -euo pipefail

APP_NAME="Avo"
BUNDLE_ID="com.thakobyan08.avo"
DEST="/Applications/${APP_NAME}.app"
DOWNLOAD_URL="https://github.com/thakobyan08/avo-the-coach/releases/latest/download/${APP_NAME}.zip"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/avo-install.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT

step() { printf '\033[1m==>\033[0m %s\n' "$1"; }
fail() { printf '\033[31mError:\033[0m %s\n' "$1" >&2; exit 1; }

# 1. macOS 14 or newer
macos_major="$(sw_vers -productVersion | cut -d. -f1)"
if [ "$macos_major" -lt 14 ]; then
    fail "Avo needs macOS 14 (Sonoma) or newer. This Mac runs $(sw_vers -productVersion)."
fi

# 2. Get the app
zip="$WORK_DIR/${APP_NAME}.zip"
if [ -n "${AVO_ZIP:-}" ]; then
    [ -f "$AVO_ZIP" ] || fail "No file at $AVO_ZIP"
    cp "$AVO_ZIP" "$zip"
else
    step "Downloading ${APP_NAME}…"
    curl -fsSL --retry 2 -o "$zip" "$DOWNLOAD_URL" \
        || fail "The download failed. Check your internet connection and try again."
fi
ditto -x -k "$zip" "$WORK_DIR" || fail "The download looks damaged. Please try again."
new_app="$WORK_DIR/${APP_NAME}.app"
[ -d "$new_app" ] || fail "${APP_NAME}.app was not found in the download."
codesign --verify --strict "$new_app" 2>/dev/null || fail "${APP_NAME}.app did not pass the signature check."

# 3. Quit the running copy, if any
if pgrep -x "$APP_NAME" >/dev/null; then
    step "Quitting the running ${APP_NAME}…"
    osascript -e "tell application id \"${BUNDLE_ID}\" to quit" >/dev/null 2>&1 || true
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        pgrep -x "$APP_NAME" >/dev/null || break
        sleep 0.5
    done
    pkill -x "$APP_NAME" 2>/dev/null || true
fi

# 4. Install
step "Installing to ${DEST}…"
if [ -w "/Applications" ] && { [ ! -e "$DEST" ] || [ -w "$DEST" ]; }; then
    rm -rf "$DEST"
    ditto "$new_app" "$DEST"
else
    echo "    Your password is needed to write to /Applications."
    sudo rm -rf "$DEST"
    sudo ditto "$new_app" "$DEST"
fi

# 5. Launch
step "Opening ${APP_NAME}…"
open "$DEST"

printf '\n\033[32mDone!\033[0m Look for the avocado in your menu bar (top right of the screen).\n'
