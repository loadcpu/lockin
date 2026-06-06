import Foundation
import AppKit

enum HelperInstaller {
    private static let helperPath   = "/usr/local/bin/screenblocker-hosts"
    private static let sudoersPath  = "/etc/sudoers.d/screenblocker"
    private static let versionTag   = "# sb-version v5"
    private static let defaultsKey  = "helperInstalled_v5"
    private static let agentLabel   = "com.local.screenblocker"
    private static let agentVersion = "<!-- sb-agent v3 -->"

    static func ensureInstalled() {
        if UserDefaults.standard.bool(forKey: defaultsKey) {
            if FileManager.default.fileExists(atPath: helperPath) { return }
            UserDefaults.standard.removeObject(forKey: defaultsKey)
        }
        if isHelperCurrent() {
            UserDefaults.standard.set(true, forKey: defaultsKey)
            return
        }
        runInstaller()
    }

    static func ensureLaunchAgent() {
        guard Bundle.main.bundlePath == "/Applications/Screen Blocker.app" else { return }

        let home     = FileManager.default.homeDirectoryForCurrentUser
        let agentDir = home.appendingPathComponent("Library/LaunchAgents")
        let plistURL = agentDir.appendingPathComponent("\(agentLabel).plist")
        let logDir   = home.appendingPathComponent(".screenblocker")

        if let existing = try? String(contentsOf: plistURL, encoding: .utf8),
           existing.contains(agentVersion) { return }

        let execPath = Bundle.main.executablePath
            ?? "/Applications/Screen Blocker.app/Contents/MacOS/ScreenBlocker"

        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        \(agentVersion)
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(agentLabel)</string>
            <key>ProgramArguments</key>
            <array>
                <string>\(execPath)</string>
            </array>
            <key>RunAtLoad</key>
            <true/>
            <key>KeepAlive</key>
            <dict>
                <key>PathState</key>
                <dict>
                    <key>\(home.path)/.screenblocker/session.json</key>
                    <true/>
                </dict>
            </dict>
            <key>StandardOutPath</key>
            <string>\(logDir.path)/app.log</string>
            <key>StandardErrorPath</key>
            <string>\(logDir.path)/error.log</string>
        </dict>
        </plist>
        """

        DispatchQueue.global(qos: .utility).async {
            try? FileManager.default.createDirectory(at: agentDir, withIntermediateDirectories: true)
            try? FileManager.default.createDirectory(at: logDir,   withIntermediateDirectories: true)
            exec("/bin/launchctl", ["unload", plistURL.path])
            guard (try? plist.write(to: plistURL, atomically: true, encoding: .utf8)) != nil else { return }
            exec("/bin/launchctl", ["load", "-w", plistURL.path])
        }
    }

    // MARK: - Private

    private static func exec(_ path: String, _ args: [String]) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError  = FileHandle.nullDevice
        try? p.run()
        p.waitUntilExit()
    }

    private static func isHelperCurrent() -> Bool {
        guard let content = try? String(contentsOfFile: helperPath, encoding: .utf8) else { return false }
        return content.contains(versionTag)
    }

    private static func runInstaller() {
        let stagingPath = "/tmp/screenblocker-hosts-staging"
        let scriptPath  = "/tmp/screenblocker-install.sh"
        let user = NSUserName()

        let installScript = """
        #!/bin/bash
        set -e
        mkdir -p /usr/local/bin
        cp \(stagingPath) \(helperPath)
        chmod 755 \(helperPath)
        if [ ! -f \(sudoersPath) ]; then
            echo '\(user) ALL=(root) NOPASSWD: \(helperPath)' > \(sudoersPath)
            chmod 440 \(sudoersPath)
        fi
        """

        guard (try? helperScriptContent.write(toFile: stagingPath, atomically: true, encoding: .utf8)) != nil,
              (try? installScript.write(toFile: scriptPath, atomically: true, encoding: .utf8)) != nil
        else {
            showAlert()
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let src = "do shell script \"bash \(scriptPath)\" with administrator privileges"
            var err: NSDictionary?
            NSAppleScript(source: src)?.executeAndReturnError(&err)
            try? FileManager.default.removeItem(atPath: scriptPath)
            try? FileManager.default.removeItem(atPath: stagingPath)

            DispatchQueue.main.async {
                if err != nil {
                    showAlert()
                } else {
                    UserDefaults.standard.set(true, forKey: defaultsKey)
                }
            }
        }
    }

    private static func showAlert() {
        let a = NSAlert()
        a.messageText = "Website Blocking Disabled"
        a.informativeText = "Website blocking requires a one-time setup. Quit and relaunch Screen Blocker to try again, then click Allow when prompted."
        a.alertStyle = .warning
        a.runModal()
    }

    // MARK: - Embedded helper

    private static let helperScriptContent: String = #"""
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
"""#
}
