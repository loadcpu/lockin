#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP="$SCRIPT_DIR/ScreenBlocker.app"
AGENT_DIR="$HOME/Library/LaunchAgents"
PLIST="$AGENT_DIR/com.local.screenblocker.plist"

# Build first if app doesn't exist
if [ ! -d "$APP" ]; then
    echo "App not built yet – building now…"
    cd "$SCRIPT_DIR" && ./build.sh
fi

mkdir -p "$AGENT_DIR"

cat > "$PLIST" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.local.screenblocker</string>
    <key>ProgramArguments</key>
    <array>
        <string>$APP/Contents/MacOS/ScreenBlocker</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>$HOME/.screenblocker/app.log</string>
    <key>StandardErrorPath</key>
    <string>$HOME/.screenblocker/error.log</string>
</dict>
</plist>
EOF

mkdir -p "$HOME/.screenblocker"

# Unload if already running
launchctl unload "$PLIST" 2>/dev/null || true
launchctl load -w "$PLIST"

echo ""
echo "✓ Screen Blocker installed and running"
echo "  • Starts automatically at login"
echo "  • Restarts automatically if closed during a session"
echo "  • Look for the 🛡 icon in your menu bar"
echo ""
echo "To uninstall: ./uninstall.sh"
