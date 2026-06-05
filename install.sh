#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
STAGING="$SCRIPT_DIR/.build/ScreenBlocker.app"
INSTALL_DIR="/Applications/ScreenBlocker.app"
AGENT_DIR="$HOME/Library/LaunchAgents"
PLIST="$AGENT_DIR/com.local.screenblocker.plist"
HELPER=/usr/local/bin/screenblocker-hosts
SUDOERS=/etc/sudoers.d/screenblocker

# Build if not already built
if [ ! -d "$STAGING" ]; then
    cd "$SCRIPT_DIR" && ./build.sh
fi

# Install privileged helper + sudoers entry (only if not already installed)
if [ ! -f "$SUDOERS" ] || [ ! -f "$HELPER" ]; then
echo "Installing privileged helper (requires sudo once)…"
sudo tee "$HELPER" > /dev/null << 'HELPER_SCRIPT'
#!/bin/bash
# screenblocker-hosts apply <tempfile> | remove
ACTION="$1"
TEMPFILE="$2"
if [ "$ACTION" = "apply" ]; then
    sed -i '' '/# ScreenBlocker BEGIN/,/# ScreenBlocker END/d' /etc/hosts
    cat "$TEMPFILE" >> /etc/hosts
elif [ "$ACTION" = "remove" ]; then
    sed -i '' '/# ScreenBlocker BEGIN/,/# ScreenBlocker END/d' /etc/hosts
fi
dscacheutil -flushcache
killall -HUP mDNSResponder 2>/dev/null
exit 0
HELPER_SCRIPT
sudo chmod 755 "$HELPER"
echo "$(whoami) ALL=(root) NOPASSWD: $HELPER" | sudo tee "$SUDOERS" > /dev/null
sudo chmod 440 "$SUDOERS"
fi

# Stop running instance before replacing the app
pkill -x ScreenBlocker 2>/dev/null || true
sleep 1

# Copy app to /Applications
echo "Installing app to /Applications…"
rm -rf "$INSTALL_DIR"
cp -r "$STAGING" "$INSTALL_DIR"

# Install LaunchAgent
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
        <string>$INSTALL_DIR/Contents/MacOS/ScreenBlocker</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>StandardOutPath</key>
    <string>$HOME/.screenblocker/app.log</string>
    <key>StandardErrorPath</key>
    <string>$HOME/.screenblocker/error.log</string>
</dict>
</plist>
EOF

mkdir -p "$HOME/.screenblocker"
launchctl unload "$PLIST" 2>/dev/null || true
launchctl load -w "$PLIST"

echo ""
echo "✓ Screen Blocker installed"
echo "  • App installed to /Applications/ScreenBlocker.app"
echo "  • Starts automatically at login"
echo "  • Look for the shield icon in your menu bar"
echo ""
echo "To uninstall: ./uninstall.sh"
