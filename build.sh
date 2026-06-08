#!/bin/bash
set -e

STAGING=".build/Screen Blocker.app"

echo "Building…"
swift build -c release 2>&1

echo "Generating icon…"
swift generate_icon.swift 2>&1 | grep -v "^$"

echo "Packaging…"
rm -rf "$STAGING"
mkdir -p "$STAGING/Contents/MacOS"
mkdir -p "$STAGING/Contents/Resources"

cp .build/release/ScreenBlocker "$STAGING/Contents/MacOS/ScreenBlocker"
cp AppIcon.icns "$STAGING/Contents/Resources/AppIcon.icns"

cat > "$STAGING/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>ScreenBlocker</string>
    <key>CFBundleIdentifier</key>
    <string>com.local.screenblocker</string>
    <key>CFBundleName</key>
    <string>Screen Blocker</string>
    <key>CFBundleDisplayName</key>
    <string>Screen Blocker</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>NSHumanReadableCopyright</key>
    <string>Personal use only</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>Screen Blocker reloads your browser tabs when a session starts so blocked websites take effect immediately.</string>
</dict>
</plist>
PLIST

echo "Signing…"
codesign --force --deep --sign - "$STAGING"

echo ""
echo "✓ Build ready at $STAGING"
echo "  Run: ./install.sh"
