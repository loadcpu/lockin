#!/bin/bash
set -e

APP="Screen Blocker"
DMG="ScreenBlocker.dmg"
STAGING=$(mktemp -d)

echo "Building…"
./build.sh

echo "Staging DMG…"
cp -r ".build/${APP}.app" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

# Write a minimal install note alongside the app
cat > "$STAGING/Install Notes.txt" << 'TXT'
Drag Screen Blocker to Applications, then double-click to launch.

On first use, the app will ask for your password once to install a
helper that modifies /etc/hosts for website blocking. This is a
one-time step.
TXT

echo "Creating DMG…"
rm -f "$DMG"
hdiutil create \
    -volname "$APP" \
    -srcfolder "$STAGING" \
    -ov \
    -format UDZO \
    -fs HFS+ \
    -o "$DMG" \
    > /dev/null

rm -rf "$STAGING"

SIZE=$(du -sh "$DMG" | cut -f1)
echo ""
echo "✓ $DMG ready ($SIZE)"
echo "  Upload to GitHub Releases as a release asset."
