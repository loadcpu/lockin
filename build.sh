#!/bin/bash
set -e

APP="ScreenBlocker.app"
BUNDLE_ID="com.local.screenblocker"

echo "Building…"
swift build -c release 2>&1

echo "Generating icon…"
swift generate_icon.swift 2>&1 | grep -v "^$"

echo "Packaging…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"

cp .build/release/ScreenBlocker    "$APP/Contents/MacOS/ScreenBlocker"
cp .build/release/ScreenBlockerDNS "$APP/Contents/MacOS/ScreenBlockerDNS"
cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" << 'PLIST'
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
</dict>
</plist>
PLIST

echo ""
echo "✓ Built $APP"
echo ""
echo "Run:     open $APP"
echo "Install: ./install.sh"
