import Foundation

enum DomainMatcher {
    static func normalizeHost(_ raw: String) -> String? {
        let trimmed = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
        guard !trimmed.isEmpty else { return nil }

        let host: String
        if trimmed.contains("://"), let url = URL(string: trimmed), let candidate = url.host {
            host = candidate
        } else {
            host = trimmed.components(separatedBy: "/").first ?? trimmed
        }

        guard !host.isEmpty else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    static func matches(host: String, blockedDomain: String) -> Bool {
        guard let normalizedHost = normalizeHost(host),
              let normalizedBlocked = normalizeHost(blockedDomain) else { return false }
        return normalizedHost == normalizedBlocked || normalizedHost.hasSuffix(".\(normalizedBlocked)")
    }
}
