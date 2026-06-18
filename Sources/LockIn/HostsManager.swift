import Foundation

struct HostsManager {
    private static let tempPath   = "/tmp/lockin_hosts"
    private static let helperPath = "/usr/local/bin/lockin-hosts"
    private static let beginMark  = "# Lock In BEGIN"
    private static let endMark    = "# Lock In END"

    @discardableResult
    static func applyBlocks(domains: [String]) -> Bool {
        let normalizedDomains = Array(Set(domains.compactMap(DomainMatcher.normalizeHost))).sorted()
        guard !normalizedDomains.isEmpty else { return true }
        guard HelperInstaller.ensureInstalled() else { return false }

        var lines = [beginMark]
        for bare in normalizedDomains {
            lines.append("127.0.0.1 \(bare)")
            lines.append("127.0.0.1 www.\(bare)")
            lines.append("::1 \(bare)")
            lines.append("::1 www.\(bare)")
        }
        lines.append(endMark)
        let content = lines.joined(separator: "\n") + "\n"

        guard (try? content.write(toFile: tempPath, atomically: true, encoding: .utf8)) != nil else {
            return false
        }

        return runHelper("apply", tempPath)
    }

    static func removeBlocks() {
        _ = runHelper("remove", nil)
    }

    // MARK: - Private

    @discardableResult
    private static func runHelper(_ action: String, _ arg: String?) -> Bool {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        var args = ["-n", helperPath, action]
        if let arg { args.append(arg) }
        proc.arguments = args
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError  = FileHandle.nullDevice
        guard (try? proc.run()) != nil else { return false }
        proc.waitUntilExit()
        return proc.terminationStatus == 0
    }
}
