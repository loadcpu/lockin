#!/bin/bash

PLIST="$HOME/Library/LaunchAgents/com.local.screenblocker.plist"

launchctl unload "$PLIST" 2>/dev/null || true
rm -f "$PLIST"

# Remove website blocks from /etc/hosts if any remain
if grep -q "SCREENBLOCKER" /etc/hosts 2>/dev/null; then
    echo "Removing leftover website blocks from /etc/hosts…"
    osascript -e 'do shell script "sed -i \"\" \"/# --- SCREENBLOCKER/,/# --- SCREENBLOCKER END/d\" /etc/hosts && dscacheutil -flushcache && killall -HUP mDNSResponder 2>/dev/null; true" with administrator privileges'
fi

echo "✓ Screen Blocker uninstalled"
echo "  Config and logs remain in ~/.screenblocker/ – delete manually if desired."
