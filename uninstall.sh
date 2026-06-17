#!/bin/bash

PLIST="$HOME/Library/LaunchAgents/com.local.lockin.plist"
INSTALL_DIR="/Applications/Lock In.app"
HELPER=/usr/local/bin/lockin-hosts
SUDOERS=/etc/sudoers.d/lockin

# Stop and remove LaunchAgent
launchctl unload "$PLIST" 2>/dev/null || true
rm -f "$PLIST"

# Kill any running instance
pkill -9 LockIn 2>/dev/null || true

# Remove website blocks from /etc/hosts if any remain
if grep -q "# ScreenBlocker BEGIN" /etc/hosts 2>/dev/null; then
    echo "Removing website blocks from /etc/hosts…"
    sudo "$HELPER" remove 2>/dev/null || true
fi

# Remove privileged helper and sudoers entry
sudo rm -f "$HELPER" "$SUDOERS"

# Remove app from /Applications
rm -rf "$INSTALL_DIR"

# Remove temp files
rm -f /tmp/screenblocker_hosts

echo "✓ Lock In uninstalled"
echo "  Config and logs remain in ~/.lockin/ - delete manually if desired."
