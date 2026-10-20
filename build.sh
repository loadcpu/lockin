#!/bin/bash
set -e

APP_NAME="Lock In"
EXECUTABLE_NAME="LockIn"
APP_BUNDLE_ID="${LOCKIN_BUNDLE_ID:-com.loadcpu.lockin}"
STAGING=".build/$APP_NAME.app"
ICON_PATH=".build/AppIcon.icns"
APP_VERSION="${LOCKIN_VERSION:-1.0}"
APP_BUILD="${LOCKIN_BUILD:-1}"
ENTITLEMENTS_PATH="${LOCKIN_ENTITLEMENTS:-LockIn.entitlements}"
SIGNING_IDENTITY="${LOCKIN_SIGN_IDENTITY:--}"
SIGNING_MODE="${LOCKIN_SIGN_MODE:-auto}"
WORKDIR="$(pwd)"
MODULE_CACHE_ROOT="$WORKDIR/.build/module-cache"
CLANG_CACHE="$MODULE_CACHE_ROOT/clang"
SWIFTPM_CACHE="$MODULE_CACHE_ROOT/swiftpm"
SPARKLE_FEED_URL="${LOCKIN_SPARKLE_FEED_URL:-https://github.com/loadcpu/lockin/releases/latest/download/appcast.xml}"
SPARKLE_PUBLIC_KEY="${LOCKIN_SPARKLE_PUBLIC_KEY:-bv0+YriGpuRny13+5CFb90Zj4telIaNoURByucOrhRM=}"

mkdir -p "$CLANG_CACHE" "$SWIFTPM_CACHE"

run_swift_build() {
    CLANG_MODULE_CACHE_PATH="$CLANG_CACHE" \
    SWIFTPM_MODULECACHE_OVERRIDE="$SWIFTPM_CACHE" \
    swift build -c release 2>&1
}

run_swift_tool() {
    CLANG_MODULE_CACHE_PATH="$CLANG_CACHE" \
    SWIFTPM_MODULECACHE_OVERRIDE="$SWIFTPM_CACHE" \
    swift "$@"
}

echo "Building…"
if ! run_swift_build; then
    echo ""
    echo "Build failed."
    echo "If you see a Swift/SDK mismatch, reinstall or switch to a matching Apple toolchain."
    echo "Current developer dir: $(xcode-select -p 2>/dev/null || echo unavailable)"
    echo "Current Swift: $(swift --version 2>/dev/null | head -n 1 || echo unavailable)"
    exit 1
fi

echo "Generating icon…"
run_swift_tool generate_icon.swift 2>&1 | grep -v "^$"

echo "Packaging…"
rm -rf "$STAGING"
mkdir -p "$STAGING/Contents/MacOS"
mkdir -p "$STAGING/Contents/Resources"
mkdir -p "$STAGING/Contents/Frameworks"

cp ".build/release/$EXECUTABLE_NAME" "$STAGING/Contents/MacOS/$EXECUTABLE_NAME"
cp "$ICON_PATH" "$STAGING/Contents/Resources/AppIcon.icns"
ditto "$(swift build -c release --show-bin-path)/Sparkle.framework" "$STAGING/Contents/Frameworks/Sparkle.framework"

echo "Stripping packaged binary…"
strip -S -x "$STAGING/Contents/MacOS/$EXECUTABLE_NAME"

INFO_PLIST="$STAGING/Contents/Info.plist"
cat > "$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>${EXECUTABLE_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>${APP_BUNDLE_ID}</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${APP_VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${APP_BUILD}</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>NSHumanReadableCopyright</key>
    <string>Personal use only</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>Lock In reloads your browser tabs when a session starts so blocked websites take effect immediately.</string>
    <key>LSUIElement</key>
    <true/>
    <key>SUFeedURL</key>
    <string>${SPARKLE_FEED_URL}</string>
    <key>SUPublicEDKey</key>
    <string>${SPARKLE_PUBLIC_KEY}</string>
    <key>SUEnableAutomaticChecks</key>
    <true/>
    <key>SUAutomaticallyUpdate</key>
    <true/>
</dict>
</plist>
PLIST

# Sparkle's helpers are signed inside-out with their own entitlements (Downloader.xpc
# keeps its network-client entitlement), so the app itself is signed without --deep.
sign_developer_id() {
    local sparkle="$STAGING/Contents/Frameworks/Sparkle.framework/Versions/B"
    codesign --force --options runtime --sign "$SIGNING_IDENTITY" "$sparkle/XPCServices/Installer.xpc"
    codesign --force --options runtime --preserve-metadata=entitlements --sign "$SIGNING_IDENTITY" "$sparkle/XPCServices/Downloader.xpc"
    codesign --force --options runtime --sign "$SIGNING_IDENTITY" "$sparkle/Autoupdate"
    codesign --force --options runtime --sign "$SIGNING_IDENTITY" "$sparkle/Updater.app"
    codesign --force --options runtime --sign "$SIGNING_IDENTITY" "$STAGING/Contents/Frameworks/Sparkle.framework"
    codesign \
        --force \
        --options runtime \
        --entitlements "$ENTITLEMENTS_PATH" \
        --sign "$SIGNING_IDENTITY" \
        "$STAGING"
}

sign_app() {
    case "$SIGNING_MODE" in
        none)
            echo "Skipping code signing (LOCKIN_SIGN_MODE=none)…"
            ;;
        adhoc)
            echo "Signing with ad-hoc identity…"
            codesign --force --deep --sign - "$STAGING"
            ;;
        developer-id)
            echo "Signing with Developer ID identity…"
            sign_developer_id
            ;;
        auto)
            if [ "$SIGNING_IDENTITY" = "-" ]; then
                echo "Signing with ad-hoc identity…"
                codesign --force --deep --sign - "$STAGING"
            else
                echo "Signing with configured identity…"
                sign_developer_id
            fi
            ;;
        *)
            echo "Unknown LOCKIN_SIGN_MODE: $SIGNING_MODE"
            echo "Use one of: auto, adhoc, developer-id, none"
            exit 1
            ;;
    esac
}

echo "Signing…"
sign_app

echo ""
echo "✓ Build ready at $STAGING"
echo "  Open: $STAGING"
