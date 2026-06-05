#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
STAGING="$SCRIPT_DIR/.build/Screen Blocker.app"
INSTALL_DIR="/Applications/Screen Blocker.app"
AGENT_DIR="$HOME/Library/LaunchAgents"
PLIST="$AGENT_DIR/com.local.screenblocker.plist"
HELPER=/usr/local/bin/screenblocker-hosts
SUDOERS=/etc/sudoers.d/screenblocker

# Build if not already built
if [ ! -d "$STAGING" ]; then
    cd "$SCRIPT_DIR" && ./build.sh
fi

# Install/update helper when version changes
HELPER_VER="v5"
NEED_HELPER=false
[ ! -f "$SUDOERS" ] && NEED_HELPER=true
[ ! -f "$HELPER" ] && NEED_HELPER=true
grep -q "# sb-version $HELPER_VER" "$HELPER" 2>/dev/null || NEED_HELPER=true

if $NEED_HELPER; then
echo "Installing privileged helper (requires sudo once)…"
sudo tee "$HELPER" > /dev/null << 'HELPER_SCRIPT'
#!/bin/bash
# sb-version v5
ACTION="$1"
TEMPFILE="$2"
ANCHOR="com.apple/screenblocker"

if [ "$ACTION" = "apply" ]; then
    DOMAINS=$(awk '/^127\.0\.0\.1/ && $2 !~ /^www\./{print $2}' "$TEMPFILE")
    TMPIPS=$(mktemp)

    if [ -n "$DOMAINS" ]; then
        # Source 1: local DNS cache BEFORE flushing — this matches what Safari is
        # actually connected to, which can differ from what 8.8.8.8 returns.
        for domain in $DOMAINS; do
            dscacheutil -q host -a name         "$domain" 2>/dev/null | awk '/ip_address:/{print $2}'     >> "$TMPIPS"
            dscacheutil -q host -a name     "www.$domain" 2>/dev/null | awk '/ip_address:/{print $2}'     >> "$TMPIPS"
            dscacheutil -q host -a name         "$domain" 2>/dev/null | awk '/ipv6_address:/{print $2}'   >> "$TMPIPS"
            dscacheutil -q host -a name     "www.$domain" 2>/dev/null | awk '/ipv6_address:/{print $2}'   >> "$TMPIPS"
        done

        # Source 2: lsof — exact IPs browsers have live connections to right now
        lsof -i tcp:443 -i tcp:80 -n -P 2>/dev/null | \
            awk '/ESTABLISHED/ && ($1 ~ /Safari|Chrome|Arc|Brave|firefox|msedge|Edge/) {
                split($9, a, "->")
                split(a[2], b, ":")
                ip = b[1]; gsub(/[\[\]]/, "", ip)
                if (ip != "" && ip !~ /^127\./) print ip
            }' >> "$TMPIPS"
    fi

    # Update /etc/hosts
    sed -i '' '/# ScreenBlocker BEGIN/,/# ScreenBlocker END/d' /etc/hosts
    cat "$TEMPFILE" >> /etc/hosts

    # Flush DNS cache AFTER collecting cached IPs above
    dscacheutil -flushcache
    killall -HUP mDNSResponder 2>/dev/null

    # Source 3: fresh DNS via 8.8.8.8 (runs in parallel, catches any cache misses)
    if [ -n "$DOMAINS" ]; then
        for domain in $DOMAINS; do
            host -t A    "$domain" 8.8.8.8 2>/dev/null | awk '/has address/{print $4}'      >> "$TMPIPS" &
            host -t AAAA "$domain" 8.8.8.8 2>/dev/null | awk '/has IPv6 address/{print $5}' >> "$TMPIPS" &
        done
        wait
    fi

    IPS=$(grep -vE '^$|^127\.|^::1$' "$TMPIPS" | sort -u | tr '\n' ' ')
    rm -f "$TMPIPS"

    if [ -n "$(echo "$IPS" | tr -d ' ')" ]; then
        pfctl -E 2>/dev/null || true
        cat << EOF | pfctl -a "$ANCHOR" -f - 2>/dev/null
table <blocked> { $IPS}
block return quick proto tcp from any to <blocked> port { 80 443 }
block return quick proto udp from any to <blocked> port 443
EOF
    fi

elif [ "$ACTION" = "remove" ]; then
    sed -i '' '/# ScreenBlocker BEGIN/,/# ScreenBlocker END/d' /etc/hosts
    dscacheutil -flushcache
    killall -HUP mDNSResponder 2>/dev/null
    echo "" | pfctl -a "$ANCHOR" -f - 2>/dev/null || true
    pfctl -X 2>/dev/null || true
fi
exit 0
HELPER_SCRIPT
sudo chmod 755 "$HELPER"
if [ ! -f "$SUDOERS" ]; then
    echo "$(whoami) ALL=(root) NOPASSWD: $HELPER" | sudo tee "$SUDOERS" > /dev/null
    sudo chmod 440 "$SUDOERS"
fi
fi

# Stop running instance before replacing the app
pkill -x ScreenBlocker 2>/dev/null || true
pkill -x "Screen Blocker" 2>/dev/null || true
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
launchctl unload "$PLIST" 2>/dev/null || true
launchctl load -w "$PLIST"

echo ""
echo "✓ Screen Blocker installed"
echo "  • App installed to /Applications/Screen Blocker.app"
echo "  • Starts automatically at login"
echo "  • Look for the shield icon in your menu bar"
echo ""
echo "To uninstall: ./uninstall.sh"
