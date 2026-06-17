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
if [ -x "$HELPER" ] || grep -Eq "# (Lock In|LockIn) BEGIN" /etc/hosts 2>/dev/null; then
    echo "Removing website blocks from /etc/hosts…"
    if [ -x "$HELPER" ]; then
        sudo "$HELPER" remove 2>/dev/null || true
    else
        sudo sh -c "sed -i '' '/# Lock In BEGIN/,/# Lock In END/d' /etc/hosts; sed -i '' '/# LockIn BEGIN/,/# LockIn END/d' /etc/hosts; dscacheutil -flushcache; killall -HUP mDNSResponder 2>/dev/null || true"
    fi
fi

# Remove privileged helper, sudoers entry, and helper temp/log files
sudo rm -f "$HELPER" "$SUDOERS" /tmp/lockin_ips.log

# Remove app from /Applications
rm -rf "$INSTALL_DIR"

# Remove temp files
rm -f /tmp/lockin_hosts /tmp/lockin-hosts-staging /tmp/lockin-install.sh

echo "✓ Lock In uninstalled"
echo "  Config and logs remain in ~/.lockin/ - delete manually if desired."
