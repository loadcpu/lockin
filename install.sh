#!/bin/bash
set -e

APP="Lock In"
BOLD='\033[1m'; GREEN='\033[0;32m'; RED='\033[0;31m'; DIM='\033[2m'; RESET='\033[0m'

# ── Dev mode: run from the source repo ──────────────────────────────────────
if [ -f Package.swift ]; then
    PLIST="$HOME/Library/LaunchAgents/com.local.lockin.plist"

    echo "${BOLD}Building and installing Lock In...${RESET}"
    ./build.sh

    # Unload the agent first so launchd doesn't race-restart the old binary
    # while we're swapping the app bundle
    launchctl unload "$PLIST" 2>/dev/null || true
    pkill -x "LockIn" 2>/dev/null || true

    rm -rf "/Applications/$APP.app"
    cp -r ".build/$APP.app" /Applications/

    # Reload — launchd starts the new binary cleanly
    launchctl load -w "$PLIST" 2>/dev/null || true

    echo ""
    echo "${GREEN}  ✓ Lock In installed from source${RESET}"
    echo ""
    exit 0
fi

# ── End-user mode: download latest release zip ──────────────────────────────
REPO="loadcpu/screen-blocker"
ZIP_URL="https://github.com/$REPO/releases/latest/download/LockIn.zip"

echo ""
echo "${BOLD}Installing Lock In...${RESET}"
echo ""

if [[ "$(uname)" != "Darwin" ]]; then
  echo "${RED}Error: Lock In is macOS only.${RESET}"
  exit 1
fi

TMP=$(mktemp -d)
trap "rm -rf $TMP" EXIT

printf "  Downloading... "
curl -fsSL "$ZIP_URL" -o "$TMP/LockIn.zip"
echo "done"

printf "  Installing to /Applications... "
[ -d "/Applications/$APP.app" ] && rm -rf "/Applications/$APP.app"
unzip -q "$TMP/LockIn.zip" -d /Applications/
# Strip quarantine so Gatekeeper doesn't block the ad-hoc-signed binary
xattr -cr "/Applications/$APP.app"
echo "done"

echo ""
echo "${GREEN}  ✓ Lock In installed!${RESET}"
echo "  ${DIM}Opening Lock In...${RESET}"
open "/Applications/$APP.app"
echo ""
