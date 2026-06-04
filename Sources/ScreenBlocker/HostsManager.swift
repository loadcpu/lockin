import Foundation
import AppKit

final class HostsManager {
    static let shared = HostsManager()

    private let marker    = "# --- SCREENBLOCKER START ---"
    private let markerEnd = "# --- SCREENBLOCKER END ---"
    private let hostsPath = "/etc/hosts"

    private init() {}

    @discardableResult
    func applyBlocks(websites: [String]) -> Bool {
        guard !websites.isEmpty else { return true }

        var current = (try? String(contentsOfFile: hostsPath, encoding: .utf8)) ?? ""
        current = stripped(current)

        var lines = [marker]
        for site in websites {
            let s = site.trimmingCharacters(in: .whitespaces).lowercased()
            guard !s.isEmpty else { continue }
            lines.append("127.0.0.1\t\(s)")
            if !s.hasPrefix("www.") { lines.append("127.0.0.1\twww.\(s)") }
        }
        lines.append(markerEnd)

        let newContent = current.trimmingCharacters(in: .newlines) + "\n\n" + lines.joined(separator: "\n") + "\n"
        return writePrivileged(newContent)
    }

    @discardableResult
    func removeBlocks() -> Bool {
        guard let current = try? String(contentsOfFile: hostsPath, encoding: .utf8) else { return true }
        guard current.contains(marker) else { return true }
        return writePrivileged(stripped(current))
    }

    func blocksAreApplied() -> Bool {
        (try? String(contentsOfFile: hostsPath, encoding: .utf8))?.contains(marker) == true
    }

    // MARK: - Private

    private func stripped(_ content: String) -> String {
        var result: [String] = []
        var inside = false
        for line in content.components(separatedBy: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t == marker    { inside = true;  continue }
            if t == markerEnd { inside = false; continue }
            if !inside { result.append(line) }
        }
        return result.joined(separator: "\n")
    }

    private func writePrivileged(_ content: String) -> Bool {
        let tmp = NSTemporaryDirectory() + "screenblocker_hosts"
        guard let data = content.data(using: .utf8) else { return false }
        do { try data.write(to: URL(fileURLWithPath: tmp)) }
        catch { return false }

        // Escape single quotes in path (shouldn't be any, but be safe)
        let safe = tmp.replacingOccurrences(of: "'", with: "'\\''")
        let cmd  = "cp '\(safe)' /etc/hosts && dscacheutil -flushcache && killall -HUP mDNSResponder 2>/dev/null; true"
        let script = "do shell script \"\(cmd.replacingOccurrences(of: "\"", with: "\\\""))\" with administrator privileges"

        var err: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&err)
        return err == nil
    }
}
