#!/bin/bash
set -e

APP="Screen Blocker"
BOLD='\033[1m'; GREEN='\033[0;32m'; RED='\033[0;31m'; DIM='\033[2m'; RESET='\033[0m'

# ── Dev mode: run from the source repo ──────────────────────────────────────
if [ -f Package.swift ]; then
    PLIST="$HOME/Library/LaunchAgents/com.local.screenblocker.plist"

    echo "${BOLD}Building and installing Screen Blocker...${RESET}"
    ./build.sh

    # Unload the agent first so launchd doesn't race-restart the old binary
    # while we're swapping the app bundle
    launchctl unload "$PLIST" 2>/dev/null || true
    pkill -x "Screen Blocker" 2>/dev/null || true

    rm -rf "/Applications/$APP.app"
    cp -r ".build/$APP.app" /Applications/

    # Reload — launchd starts the new binary cleanly
    launchctl load -w "$PLIST" 2>/dev/null || true

    echo ""
    echo "${GREEN}  ✓ Screen Blocker installed from source${RESET}"
    echo ""
    exit 0
fi

# ── End-user mode: download latest release DMG ──────────────────────────────
REPO="loadcpu/screen-blocker"
DMG_URL="https://github.com/$REPO/releases/latest/download/ScreenBlocker.dmg"

echo ""
echo "${BOLD}Installing Screen Blocker...${RESET}"
echo ""

if [[ "$(uname)" != "Darwin" ]]; then
  echo "${RED}Error: Screen Blocker is macOS only.${RESET}"
  exit 1
fi

TMP=$(mktemp -d)
trap "rm -rf $TMP" EXIT

printf "  Downloading... "
curl -fsSL "$DMG_URL" -o "$TMP/ScreenBlocker.dmg"
echo "done"

printf "  Mounting... "
VOLUME=$(hdiutil attach "$TMP/ScreenBlocker.dmg" -nobrowse -noverify 2>/dev/null \
  | awk -F'\t' '/\/Volumes/{print $NF}')
echo "done"

printf "  Installing to /Applications... "
[ -d "/Applications/$APP.app" ] && rm -rf "/Applications/$APP.app"
cp -r "$VOLUME/$APP.app" /Applications/
echo "done"

hdiutil detach "$VOLUME" -quiet
xattr -cr "/Applications/$APP.app"

echo ""
echo "${GREEN}  ✓ Screen Blocker installed!${RESET}"
echo "  ${DIM}Open via Spotlight (⌘ Space → \"Screen Blocker\")${RESET}"
echo ""
