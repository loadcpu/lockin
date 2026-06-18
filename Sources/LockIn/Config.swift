import Foundation

let defaultWebsites: [String] = [
    "youtube.com",
    "twitter.com",
    "x.com",
    "reddit.com",
    "instagram.com",
    "facebook.com",
    "tiktok.com",
    "twitch.tv",
    "discord.com",
    "linkedin.com",
    "news.ycombinator.com",
    "netflix.com",
    "hulu.com",
    "distractify.com",
    "buzzfeed.com",
]

struct Config: Codable {
    var blockedApps: [String] = []
    var blockedWebsites: [String] = defaultWebsites
    var appCategoryOverrides: [String: String] = [:]
    var categoryLimits: [String: Int] = [:]  // AppCategory.rawValue → minutes (0 = off)

    func category(for identifier: String) -> AppCategory {
        if let raw = appCategoryOverrides[identifier], let cat = AppCategory(rawValue: raw) { return cat }
        if let cat = defaultCategoryMappings[identifier] { return cat }
        if let cat = matchingDomainCategory(for: identifier) { return cat }
        return bundleIDPrefixCategory(identifier) ?? .other
    }

    private func matchingDomainCategory(for identifier: String) -> AppCategory? {
        guard let host = DomainMatcher.normalizeHost(identifier) else { return nil }
        return defaultCategoryMappings
            .compactMap { key, category -> (String, AppCategory)? in
                DomainMatcher.matches(host: host, blockedDomain: key) ? (key, category) : nil
            }
            .max { lhs, rhs in lhs.0.count < rhs.0.count }?
            .1
    }

    private func bundleIDPrefixCategory(_ id: String) -> AppCategory? {
        // Only match reversed-domain bundle IDs (e.g. com.apple.Foo), not web domains
        let reversedTLDs = ["com.", "org.", "net.", "io.", "dev.", "co.", "app."]
        guard reversedTLDs.contains(where: { id.hasPrefix($0) }) else { return nil }
        if id.hasPrefix("com.apple.")      { return .system }
        if id.hasPrefix("com.adobe.")      { return .creative }
        if id.hasPrefix("com.microsoft.")  { return .work }
        if id.hasPrefix("com.jetbrains.")  { return .development }
        if id.hasPrefix("com.google.")     { return .work }
        return nil
    }

    private static var fileURL: URL {
        FileManager.lockinDir.appendingPathComponent("config.json")
    }

    static func load() -> Config {
        guard let data = try? Data(contentsOf: fileURL),
              let config = try? JSONDecoder().decode(Config.self, from: data) else {
            return Config()
        }
        return config
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        try? data.write(to: Config.fileURL)
    }
}

extension FileManager {
    static var lockinDir: URL {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".lockin")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
