#!/bin/bash
set -e

APP="Lock In"
REPO="${LOCKIN_REPO:-loadcpu/lockin}"
DIST_DIR=".build/dist"
STABLE_ZIP="$DIST_DIR/LockIn.zip"
STABLE_DMG="$DIST_DIR/LockIn.dmg"
RW_DMG="$DIST_DIR/LockIn-rw.dmg"
BKG_PNG=".build/dmg-background.png"
DMG_MOUNT_DIR=".build/dmg-mount"
DMG_BACKGROUND_DIR=".background"
DMG_WINDOW_WIDTH=620
DMG_WINDOW_HEIGHT=300
DMG_ICON_SIZE=104
DMG_TEXT_SIZE=14
DMG_APP_X=170
DMG_APPS_X=450
DMG_ICON_Y=132
BOLD='\033[1m'; GREEN='\033[0;32m'; RESET='\033[0m'
BUNDLE_ID="${LOCKIN_BUNDLE_ID:-com.loadcpu.lockin}"
SIGNING_IDENTITY="${LOCKIN_SIGN_IDENTITY:-}"
NOTARY_PROFILE="${LOCKIN_NOTARY_PROFILE:-}"
INCLUDE_ZIP="${LOCKIN_INCLUDE_ZIP:-0}"
PUBLISH_RELEASE="${LOCKIN_PUBLISH_RELEASE:-1}"
WORKDIR="$(pwd)"
MODULE_CACHE_ROOT="$WORKDIR/.build/module-cache"
CLANG_CACHE="$MODULE_CACHE_ROOT/clang"
SWIFTPM_CACHE="$MODULE_CACHE_ROOT/swiftpm"

VERSION="${1:-}"
if [ -z "$VERSION" ]; then
    echo "Usage: ./release.sh <version>   e.g. ./release.sh 1"
    exit 1
fi
BUILD_NUMBER="${2:-${VERSION}}"
RELEASE_TAG="v${VERSION}"
APP_PATH=".build/${APP}.app"
VERSIONED_ZIP="$DIST_DIR/LockIn-macOS-$RELEASE_TAG.zip"
VERSIONED_DMG="$DIST_DIR/LockIn-macOS-$RELEASE_TAG.dmg"
DMG_STAGE_DIR=".build/dmg-stage"

if [ -z "$SIGNING_IDENTITY" ]; then
    echo "Error: LOCKIN_SIGN_IDENTITY is required for release builds."
    echo "Example: export LOCKIN_SIGN_IDENTITY='Developer ID Application: Your Name (TEAMID)'"
    exit 1
fi

mkdir -p "$CLANG_CACHE" "$SWIFTPM_CACHE"

package_zip() {
    local output="$1"
    rm -f "$output"
    ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$output"
}

run_swift_tool() {
    CLANG_MODULE_CACHE_PATH="$CLANG_CACHE" \
    SWIFTPM_MODULECACHE_OVERRIDE="$SWIFTPM_CACHE" \
    swift "$@"
}

detach_image_mounts() {
    local image="$1"
    local abs_image

    abs_image="$(cd "$(dirname "$image")" && pwd)/$(basename "$image")"
    hdiutil info | awk -v image="$abs_image" '
        $1 == "image-path" {
            current = substr($0, index($0, ":") + 2)
            next
        }
        current == image && /^\/dev\/disk[0-9]+/ && root == "" {
            root = $1
        }
        current != image && root != "" {
            print root
            root = ""
        }
        END {
            if (root != "") print root
        }
    ' | while read -r dev; do
        hdiutil detach "$dev" >/dev/null 2>&1 || hdiutil detach -force "$dev" >/dev/null 2>&1 || true
    done
}

package_dmg() {
    local output="$1"
    local abs_mount_point="$PWD/$DMG_MOUNT_DIR"
    local attach_output
    local device
    local window_left=160
    local window_top=160
    local window_right=$((window_left + DMG_WINDOW_WIDTH))
    local window_bottom=$((window_top + DMG_WINDOW_HEIGHT))
    local background_dir="$abs_mount_point/$DMG_BACKGROUND_DIR"
    rm -rf "$DMG_STAGE_DIR"
    mkdir -p "$DMG_STAGE_DIR"
    cp -R "$APP_PATH" "$DMG_STAGE_DIR/"
    ln -s /Applications "$DMG_STAGE_DIR/Applications"
    LOCKIN_DMG_WIDTH="$DMG_WINDOW_WIDTH" \
    LOCKIN_DMG_HEIGHT="$DMG_WINDOW_HEIGHT" \
    LOCKIN_DMG_APP_X="$DMG_APP_X" \
    LOCKIN_DMG_APPS_X="$DMG_APPS_X" \
    LOCKIN_DMG_ICON_Y="$DMG_ICON_Y" \
    LOCKIN_DMG_ICON_SIZE="$DMG_ICON_SIZE" \
    run_swift_tool generate_dmg_background.swift >/dev/null
    rm -f "$RW_DMG"
    rm -f "$output"
    detach_image_mounts "$RW_DMG"

    hdiutil create \
        -volname "$APP" \
        -srcfolder "$DMG_STAGE_DIR" \
        -ov \
        -format UDRW \
        "$RW_DMG"

    rm -rf "$DMG_MOUNT_DIR"
    mkdir -p "$DMG_MOUNT_DIR"
    attach_output="$(hdiutil attach -readwrite -noverify -noautoopen -mountpoint "$abs_mount_point" "$RW_DMG")"
    device="$(printf '%s\n' "$attach_output" | awk '/^\/dev\// { print $1; exit }')"
    mkdir -p "$background_dir"
    cp "$BKG_PNG" "$background_dir/background.png"

    osascript <<APPLESCRIPT >/dev/null
set dmgAlias to POSIX file "$abs_mount_point" as alias
set bgFile to POSIX file "$background_dir/background.png" as alias
tell application "Finder"
    open dmgAlias
    set current view of container window of dmgAlias to icon view
    set toolbar visible of container window of dmgAlias to false
    set statusbar visible of container window of dmgAlias to false
    set bounds of container window of dmgAlias to {$window_left, $window_top, $window_right, $window_bottom}
    set viewOptions to the icon view options of container window of dmgAlias
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to $DMG_ICON_SIZE
    set text size of viewOptions to $DMG_TEXT_SIZE
    set background picture of viewOptions to bgFile
    set position of item "$APP.app" of container window of dmgAlias to {$DMG_APP_X, $DMG_ICON_Y}
    set position of item "Applications" of container window of dmgAlias to {$DMG_APPS_X, $DMG_ICON_Y}
    close container window of dmgAlias
    open dmgAlias
    update dmgAlias without registering applications
end tell
APPLESCRIPT

    SetFile -a V "$background_dir"
    SetFile -a V "$background_dir/background.png"
    hdiutil detach "$device"
    hdiutil convert "$RW_DMG" -format UDZO -o "$output" >/dev/null
    rm -f "$RW_DMG"
    rm -rf "$DMG_MOUNT_DIR"

    codesign --force --sign "$SIGNING_IDENTITY" "$output"
}

print_size() {
    du -sh "$1" | cut -f1
}

echo "${BOLD}Building…${RESET}"
LOCKIN_VERSION="$VERSION" \
LOCKIN_BUILD="$BUILD_NUMBER" \
LOCKIN_SIGN_MODE="developer-id" \
LOCKIN_SIGN_IDENTITY="$SIGNING_IDENTITY" \
LOCKIN_BUNDLE_ID="$BUNDLE_ID" \
./build.sh

echo "${BOLD}Verifying signature…${RESET}"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
spctl --assess --type execute --verbose=2 "$APP_PATH" || true
./verify_release.sh "$APP_PATH"

echo "${BOLD}Packaging archives…${RESET}"
mkdir -p "$DIST_DIR"
rm -f "$STABLE_ZIP" "$VERSIONED_ZIP" "$STABLE_DMG" "$VERSIONED_DMG"
package_zip "$STABLE_ZIP"
package_dmg "$STABLE_DMG"

echo "  $(basename "$STABLE_ZIP") ready for notarization ($(print_size "$STABLE_ZIP"))"
echo "  $(basename "$STABLE_DMG") ready ($(print_size "$STABLE_DMG"))"

if [ -n "$NOTARY_PROFILE" ]; then
    echo "${BOLD}Submitting zip for notarization…${RESET}"
    xcrun notarytool submit "$STABLE_ZIP" --keychain-profile "$NOTARY_PROFILE" --wait

    echo "${BOLD}Stapling notarization ticket…${RESET}"
    xcrun stapler staple "$APP_PATH"

    echo "${BOLD}Repackaging stapled app…${RESET}"
    package_zip "$STABLE_ZIP"
    package_dmg "$STABLE_DMG"

    echo "${BOLD}Submitting DMG for notarization…${RESET}"
    xcrun notarytool submit "$STABLE_DMG" --keychain-profile "$NOTARY_PROFILE" --wait

    echo "${BOLD}Stapling DMG notarization ticket…${RESET}"
    xcrun stapler staple "$STABLE_DMG"

    echo "${BOLD}Validating stapled artifacts…${RESET}"
    ./verify_release.sh --require-staple "$APP_PATH" "$STABLE_DMG"
fi

cp "$STABLE_DMG" "$VERSIONED_DMG"
echo "  $(basename "$VERSIONED_DMG") ready"

RELEASE_ASSETS=("$STABLE_DMG" "$VERSIONED_DMG")
if [ "$INCLUDE_ZIP" = "1" ]; then
    cp "$STABLE_ZIP" "$VERSIONED_ZIP"
    RELEASE_ASSETS+=("$STABLE_ZIP" "$VERSIONED_ZIP")
    echo "  $(basename "$VERSIONED_ZIP") ready"
fi

if [ "$PUBLISH_RELEASE" != "1" ]; then
    echo "${BOLD}Skipping GitHub publish…${RESET}"
    echo "  Release assets were built locally only (LOCKIN_PUBLISH_RELEASE=$PUBLISH_RELEASE)."
    exit 0
fi

if [ -z "$NOTARY_PROFILE" ]; then
    echo "${BOLD}Skipping GitHub publish…${RESET}"
    echo "  LOCKIN_NOTARY_PROFILE is not set, so these artifacts were not notarized for distribution."
    echo "  Set LOCKIN_NOTARY_PROFILE and rerun ./release.sh before publishing."
    exit 0
fi

echo "${BOLD}Publishing GitHub release ${RELEASE_TAG}…${RESET}"
if gh release view "$RELEASE_TAG" >/dev/null 2>&1; then
    gh release upload "$RELEASE_TAG" \
        "${RELEASE_ASSETS[@]}" \
        --clobber
else
    gh release create "$RELEASE_TAG" \
        "${RELEASE_ASSETS[@]}" \
        --title "$RELEASE_TAG" \
        --notes "Download \`LockIn.dmg\` and drag \`Lock In.app\` into Applications."
fi

echo ""
echo "${GREEN}✓ ${RELEASE_TAG} published.${RESET}"
echo "  Primary download: LockIn.dmg"
