#!/bin/bash
set -e

STAGING=".build/Lock In.app"
APP_VERSION="${LOCKIN_VERSION:-1.0}"
APP_BUILD="${LOCKIN_BUILD:-1}"
WORKDIR="$(pwd)"
MODULE_CACHE_ROOT="$WORKDIR/.build/module-cache"
CLANG_CACHE="$MODULE_CACHE_ROOT/clang"
SWIFTPM_CACHE="$MODULE_CACHE_ROOT/swiftpm"

mkdir -p "$CLANG_CACHE" "$SWIFTPM_CACHE"

run_swift_build() {
    CLANG_MODULE_CACHE_PATH="$CLANG_CACHE" \
    SWIFTPM_MODULECACHE_OVERRIDE="$SWIFTPM_CACHE" \
    swift build -c release 2>&1
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
swift generate_icon.swift 2>&1 | grep -v "^$"

echo "Packaging…"
rm -rf "$STAGING"
mkdir -p "$STAGING/Contents/MacOS"
mkdir -p "$STAGING/Contents/Resources"

cp .build/release/LockIn "$STAGING/Contents/MacOS/LockIn"
cp AppIcon.icns "$STAGING/Contents/Resources/AppIcon.icns"

cat > "$STAGING/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>LockIn</string>
    <key>CFBundleIdentifier</key>
    <string>com.local.lockin</string>
    <key>CFBundleName</key>
    <string>Lock In</string>
    <key>CFBundleDisplayName</key>
    <string>Lock In</string>
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
</dict>
</plist>
PLIST

echo "Signing…"
codesign --force --deep --sign - "$STAGING"

echo ""
echo "✓ Build ready at $STAGING"
echo "  Run: ./install.sh"
