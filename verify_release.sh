#!/bin/bash
set -e

REQUIRE_STAPLE=0
if [ "${1:-}" = "--require-staple" ]; then
    REQUIRE_STAPLE=1
    shift
fi

APP_PATH="${1:-.build/Lock In.app}"
DMG_PATH="${2:-}"
ENTITLEMENTS_PATH="${LOCKIN_ENTITLEMENTS:-LockIn.entitlements}"
BOLD='\033[1m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RESET='\033[0m'

if [ ! -d "$APP_PATH" ]; then
    echo "Error: app bundle not found at $APP_PATH"
    echo "Build it first with ./build.sh or ./release.sh"
    exit 1
fi

echo "${BOLD}Validating app bundle…${RESET}"
plutil -lint "$APP_PATH/Contents/Info.plist"

if [ -f "$ENTITLEMENTS_PATH" ]; then
    plutil -lint "$ENTITLEMENTS_PATH"
fi

echo "${BOLD}Checking code signature…${RESET}"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
codesign --display --entitlements :- "$APP_PATH" >/dev/null

echo "${BOLD}Assessing Gatekeeper launch policy…${RESET}"
spctl --assess --type execute --verbose=2 "$APP_PATH" || true

if [ -n "$DMG_PATH" ]; then
    if [ ! -f "$DMG_PATH" ]; then
        echo "Error: DMG not found at $DMG_PATH"
        exit 1
    fi

    echo "${BOLD}Validating disk image…${RESET}"
    codesign --verify --verbose=2 "$DMG_PATH"
    spctl --assess --type open --verbose=2 "$DMG_PATH" || true

    if xcrun stapler validate "$DMG_PATH" >/dev/null 2>&1; then
        echo "${GREEN}✓ Stapled DMG ticket is valid${RESET}"
    else
        if [ "$REQUIRE_STAPLE" = "1" ]; then
            echo "Error: DMG stapler validation did not pass"
            exit 1
        fi
        echo "${YELLOW}! DMG stapler validation did not pass${RESET}"
    fi
fi

if xcrun stapler validate "$APP_PATH" >/dev/null 2>&1; then
    echo "${GREEN}✓ Stapled app ticket is valid${RESET}"
else
    if [ "$REQUIRE_STAPLE" = "1" ]; then
        echo "Error: app stapler validation did not pass"
        exit 1
    fi
    echo "${YELLOW}! App stapler validation did not pass${RESET}"
fi

echo ""
echo "${GREEN}✓ Release verification checks completed${RESET}"
