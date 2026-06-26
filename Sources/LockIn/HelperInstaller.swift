import Foundation
import AppKit

enum HelperInstaller {
    private static let helperPath   = "/usr/local/bin/lockin-hosts"
    private static let sudoersPath  = "/etc/sudoers.d/lockin"
    private static let versionTag   = "# sb-version v8"
    private static let defaultsKey  = "helperInstalled_v8"
    private static let agentVersion = "<!-- sb-agent v3 -->"

    @discardableResult
    static func ensureInstalled() -> Bool {
        if UserDefaults.standard.bool(forKey: defaultsKey) {
            if FileManager.default.fileExists(atPath: helperPath) { return true }
            UserDefaults.standard.removeObject(forKey: defaultsKey)
        }
        if isHelperCurrent() {
            UserDefaults.standard.set(true, forKey: defaultsKey)
            return true
        }
        return runInstaller()
    }

    static func syncLaunchAgent(shouldExist: Bool) {
        guard Bundle.main.bundlePath == "/Applications/Lock In.app" else { return }

        let home = FileManager.default.homeDirectoryForCurrentUser
        let agentLabel = Bundle.main.bundleIdentifier ?? "com.loadcpu.lockin"
        let plistURL = home
            .appendingPathComponent("Library/LaunchAgents")
            .appendingPathComponent("\(agentLabel).plist")

        let removeLaunchAgent = {
            exec("/bin/launchctl", ["unload", plistURL.path])
            try? FileManager.default.removeItem(at: plistURL)
        }

        if !shouldExist {
            DispatchQueue.global(qos: .utility).async {
                removeLaunchAgent()
            }
            return
        }

        DispatchQueue.global(qos: .utility).async {
            // A LaunchAgent that points at the full app binary can still be auto-discovered
            // by per-user launchd as soon as the plist lands in ~/Library/LaunchAgents.
            // That creates a second GUI-app launch attempt during an active session, which
            // immediately exits via the single-instance guard but still flashes in the Dock.
            // Until Lock In has a dedicated background helper, keep the recovery agent absent.
            if let existing = try? String(contentsOf: plistURL, encoding: .utf8),
               existing.contains(agentVersion) {
                removeLaunchAgent()
            }
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

    @discardableResult
    private static func runInstaller() -> Bool {
        let stagingPath = "/tmp/lockin-hosts-staging"
        let scriptPath  = "/tmp/lockin-install.sh"
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
            return false
        }

        var installOK = false
        let runInstall = {
            let src = "do shell script \"bash \(scriptPath)\" with administrator privileges"
            var err: NSDictionary?
            NSAppleScript(source: src)?.executeAndReturnError(&err)
            try? FileManager.default.removeItem(atPath: scriptPath)
            try? FileManager.default.removeItem(atPath: stagingPath)

            if err != nil {
                showAlert()
            } else {
                UserDefaults.standard.set(true, forKey: defaultsKey)
                installOK = true
            }
        }
        if Thread.isMainThread {
            runInstall()
        } else {
            DispatchQueue.main.sync(execute: runInstall)
        }
        return installOK
    }

    private static func showAlert() {
        let a = NSAlert()
        a.messageText = "Website Blocking Disabled"
        a.informativeText = "Website blocking requires a one-time setup. Quit and relaunch Lock In to try again, then click Allow when prompted."
        a.alertStyle = .warning
        a.runModal()
    }

    // MARK: - Embedded helper

    private static let helperScriptContent: String = #"""
#!/bin/bash
# sb-version v8
ACTION="$1"
TEMPFILE="$2"
ANCHOR="com.apple/lockin"

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
            awk '/ESTABLISHED/ && ($1 ~ /Safari|Google|Chrome|Arc|Brave|firefox|msedge|Edge|Opera/) {
                split($9, a, "->")
                addr = a[2]
                if (addr ~ /^\[/) {
                    gsub(/^\[/, "", addr); sub(/\]:[0-9]*$/, "", addr); ip = addr
                } else {
                    split(addr, b, ":"); ip = b[1]
                }
                if (ip != "" && ip !~ /^127\./ && ip != "::1") print ip
            }' >> "$TMPIPS"
    fi

    # Update /etc/hosts
    sed -i '' '/# Lock In BEGIN/,/# Lock In END/d' /etc/hosts
    cat "$TEMPFILE" >> /etc/hosts

    # Flush DNS cache AFTER collecting cached IPs above
    dscacheutil -flushcache
    killall -HUP mDNSResponder 2>/dev/null

    # Source 3: fresh DNS via 8.8.8.8 (runs in parallel, catches any cache misses)
    if [ -n "$DOMAINS" ]; then
        for domain in $DOMAINS; do
            host -t A    "$domain" 8.8.8.8 2>/dev/null | awk '/has address/{print $4}'      >> "$TMPIPS" &
            host -t A    "$domain" 1.1.1.1 2>/dev/null | awk '/has address/{print $4}'      >> "$TMPIPS" &
            host -t AAAA "$domain" 8.8.8.8 2>/dev/null | awk '/has IPv6 address/{print $5}' >> "$TMPIPS" &
        done
        wait
    fi

    IPS=$(grep -vE '^$|^127\.|^::1$' "$TMPIPS" | sort -u | tr '\n' ' ')
    rm -f "$TMPIPS"

    echo "$(date '+%Y-%m-%d %H:%M:%S') DOMAINS=[$DOMAINS] IPS=[$IPS]" >> /tmp/lockin_ips.log

    if [ -n "$(echo "$IPS" | tr -d ' ')" ]; then
        pfctl -E 2>/dev/null || true
        cat << EOF | pfctl -a "$ANCHOR" -f - 2>/dev/null
table <blocked> { $IPS}
block return quick proto tcp from any to <blocked> port { 80 443 }
block return quick proto udp from any to <blocked> port 443
EOF
    fi

elif [ "$ACTION" = "remove" ]; then
    sed -i '' '/# Lock In BEGIN/,/# Lock In END/d' /etc/hosts
    sed -i '' '/# LockIn BEGIN/,/# LockIn END/d' /etc/hosts
    dscacheutil -flushcache
    killall -HUP mDNSResponder 2>/dev/null
    echo "" | pfctl -a "$ANCHOR" -f - 2>/dev/null || true
    pfctl -X 2>/dev/null || true
fi
exit 0
"""#
}
