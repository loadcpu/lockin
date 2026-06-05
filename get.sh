#!/bin/bash
set -e

REPO="loadcpu/screen-blocker"
APP="Screen Blocker"
DMG_URL="https://github.com/$REPO/releases/latest/download/ScreenBlocker.dmg"

BOLD='\033[1m'; GREEN='\033[0;32m'; RED='\033[0;31m'; DIM='\033[2m'; RESET='\033[0m'

echo ""
echo "${BOLD}Installing ScreenBlocker...${RESET}"
echo ""

if [[ "$(uname)" != "Darwin" ]]; then
  echo "${RED}Error: ScreenBlocker is macOS only.${RESET}"
  exit 1
fi

TMP=$(mktemp -d)
trap "rm -rf $TMP" EXIT

printf "  Downloading... "
curl -fsSL "$DMG_URL" -o "$TMP/ScreenBlocker.dmg"
echo "done"

printf "  Mounting... "
hdiutil attach "$TMP/ScreenBlocker.dmg" -nobrowse -quiet
VOLUME="/Volumes/Screen Blocker"
echo "done"

printf "  Installing to /Applications... "
[ -d "/Applications/$APP.app" ] && rm -rf "/Applications/$APP.app"
cp -r "$VOLUME/$APP.app" /Applications/
echo "done"

hdiutil detach "$VOLUME" -quiet

xattr -cr "/Applications/$APP.app"

echo ""
echo "${GREEN}  ✓ ScreenBlocker installed!${RESET}"
echo "  ${DIM}Open via Spotlight (⌘ Space → \"Screen Blocker\")${RESET}"
echo ""
