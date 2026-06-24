#!/bin/bash
set -e

APP="Lock In"
BOLD='\033[1m'; GREEN='\033[0;32m'; RED='\033[0;31m'; DIM='\033[2m'; RESET='\033[0m'

require_build_tools() {
    if ! xcode-select -p >/dev/null 2>&1 || ! command -v swift >/dev/null 2>&1; then
        echo "${RED}Error: Xcode Command Line Tools are required.${RESET}"
        echo "  ${DIM}Run: xcode-select --install${RESET}"
        exit 1
    fi
}

# ── Dev mode: run from the source repo ──────────────────────────────────────
if [ -f Package.swift ]; then
    PLIST="$HOME/Library/LaunchAgents/com.local.lockin.plist"

    echo "${BOLD}Building and installing Lock In...${RESET}"
    require_build_tools
    ./build.sh

    # Unload the agent first so launchd doesn't race-restart the old binary
    # while we're swapping the app bundle. Active sessions intentionally ignore
    # SIGTERM, so an explicit reinstall must use SIGKILL after unloading launchd.
    launchctl unload "$PLIST" 2>/dev/null || true
    pkill -KILL -x "LockIn" 2>/dev/null || true

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
REPO="${LOCKIN_REPO:-loadcpu/screen-blocker}"
ZIP_URL="${LOCKIN_ZIP_URL:-https://github.com/$REPO/releases/latest/download/LockIn.zip}"

echo ""
echo "${BOLD}Installing Lock In...${RESET}"
echo ""

if [[ "$(uname)" != "Darwin" ]]; then
  echo "${RED}Error: Lock In is macOS only.${RESET}"
  exit 1
fi

TMP=$(mktemp -d)
trap "rm -rf $TMP" EXIT
ZIP_PATH="$TMP/LockIn.zip"

printf "  Downloading app... "
if ! curl --proto '=https' --tlsv1.2 -fLsS "$ZIP_URL" -o "$ZIP_PATH"; then
  echo ""
  echo "${RED}Error: failed to download release zip.${RESET}"
  echo "  ${DIM}URL: $ZIP_URL${RESET}"
  echo "  ${DIM}Publish a GitHub release with a LockIn.zip asset first.${RESET}"
  exit 1
fi
echo "done"

printf "  Installing to /Applications... "
[ -d "/Applications/$APP.app" ] && rm -rf "/Applications/$APP.app"
if ! ditto -x -k "$ZIP_PATH" /Applications/; then
  echo ""
  echo "${RED}Error: release zip did not extract cleanly.${RESET}"
  exit 1
fi
if [ ! -d "/Applications/$APP.app" ]; then
  echo ""
  echo "${RED}Error: Lock In.app was not found after install.${RESET}"
  exit 1
fi
xattr -cr "/Applications/$APP.app" 2>/dev/null || true
echo "done"

echo ""
echo "${GREEN}  ✓ Lock In installed!${RESET}"
echo "  ${DIM}Opening Lock In...${RESET}"
open "/Applications/$APP.app"
echo ""
