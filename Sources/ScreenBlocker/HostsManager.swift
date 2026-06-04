import Foundation
import AppKit
import Darwin

// Manages website blocking via a privileged DNS sinkhole (ScreenBlockerDNS helper).
// The helper binds 127.0.0.1:53 as root; system DNS is redirected to 127.0.0.1
// via networksetup. On stop, DNS is restored and the helper is killed.
final class HostsManager {
    static let shared = HostsManager()

    private let pidFile     = "/tmp/screenblocker_dns.pid"
    private let domainsFile = "/tmp/screenblocker_blocked.txt"
    private let stateFile   = "/tmp/screenblocker_dns_state.txt"

    private init() {}

    @discardableResult
    func applyBlocks(websites: [String]) -> Bool {
        guard !websites.isEmpty else { return true }

        // Expand each entry to include www. variant
        let domains = websites.flatMap { site -> [String] in
            let s = site.trimmingCharacters(in: .whitespaces).lowercased()
            guard !s.isEmpty else { return [] }
            return s.hasPrefix("www.") ? [s] : [s, "www.\(s)"]
        }

        // Write domains for the helper to read
        guard (try? domains.joined(separator: "\n")
            .write(toFile: domainsFile, atomically: true, encoding: .utf8)) != nil
        else { return false }

        guard let helperPath = helperBinaryPath() else { return false }

        // Save original DNS so we can restore it later
        let services = activeNetworkServices()
        saveDNSState(for: services)

        let safePid     = singleQuoted(pidFile)
        let safeDomains = singleQuoted(domainsFile)
        let safeHelper  = singleQuoted(helperPath)

        // Launch helper as root (needs port 53), then set system DNS
        let launchCmd = "nohup \(safeHelper) \(safeDomains) > /dev/null 2>&1 & echo $! > \(safePid)"
        let dnsSetCmds = services.map {
            "networksetup -setdnsservers \(singleQuoted($0)) 127.0.0.1"
        }.joined(separator: "; ")

        let fullCmd = dnsSetCmds.isEmpty ? launchCmd : "\(launchCmd); \(dnsSetCmds)"
        return runPrivileged(fullCmd)
    }

    @discardableResult
    func removeBlocks() -> Bool {
        let state = loadDNSState()
        let safePid = singleQuoted(pidFile)

        let killCmd = "kill $(cat \(safePid)) 2>/dev/null; rm -f \(safePid); true"
        let dnsRestoreCmds = state.map { svc, dns -> String in
            let servers = dns.isEmpty ? "Empty" : dns.joined(separator: " ")
            return "networksetup -setdnsservers \(singleQuoted(svc)) \(servers)"
        }.joined(separator: "; ")

        let fullCmd = dnsRestoreCmds.isEmpty ? killCmd : "\(killCmd); \(dnsRestoreCmds)"
        let ok = runPrivileged(fullCmd)

        try? FileManager.default.removeItem(atPath: domainsFile)
        try? FileManager.default.removeItem(atPath: stateFile)
        return ok
    }

    func blocksAreApplied() -> Bool {
        guard let content = try? String(contentsOfFile: pidFile, encoding: .utf8),
              let pid = Int32(content.trimmingCharacters(in: .whitespacesAndNewlines))
        else { return false }
        // kill signal 0 checks existence; EPERM means exists but not our process (running as root)
        return kill(pid, 0) == 0 || errno == EPERM
    }

    // MARK: - Private

    private func helperBinaryPath() -> String? {
        guard let exe = Bundle.main.executableURL else { return nil }
        let path = exe.deletingLastPathComponent()
            .appendingPathComponent("ScreenBlockerDNS").path
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        return path
    }

    private func activeNetworkServices() -> [String] {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
        proc.arguments = ["-listallnetworkservices"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        try? proc.run()
        proc.waitUntilExit()
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return out.components(separatedBy: "\n")
            .dropFirst() // skip "An asterisk (*) denotes..." header
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("*") }
    }

    private func currentDNS(for service: String) -> [String] {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
        proc.arguments = ["-getdnsservers", service]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        try? proc.run()
        proc.waitUntilExit()
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let lines = out.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if lines.first?.hasPrefix("There aren't any") == true { return [] }
        return lines
    }

    private func saveDNSState(for services: [String]) {
        let lines = services.map { "\($0)|\(currentDNS(for: $0).joined(separator: " "))" }
        try? lines.joined(separator: "\n").write(toFile: stateFile, atomically: true, encoding: .utf8)
    }

    private func loadDNSState() -> [(String, [String])] {
        guard let content = try? String(contentsOfFile: stateFile, encoding: .utf8) else {
            return activeNetworkServices().map { ($0, []) }
        }
        return content.components(separatedBy: "\n")
            .filter { !$0.isEmpty }
            .compactMap { line -> (String, [String])? in
                let parts = line.components(separatedBy: "|")
                guard !parts[0].isEmpty else { return nil }
                let dns = parts.count > 1
                    ? parts[1].components(separatedBy: " ").filter { !$0.isEmpty }
                    : []
                return (parts[0], dns)
            }
    }

    // Wraps a string in single quotes, escaping any embedded single quotes.
    private func singleQuoted(_ s: String) -> String {
        "'\(s.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    private func runPrivileged(_ cmd: String) -> Bool {
        let escaped = cmd
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let script = "do shell script \"\(escaped)\" with administrator privileges"
        var err: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&err)
        return err == nil
    }
}
