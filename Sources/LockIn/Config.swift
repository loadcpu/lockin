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

let defaultTimerPresets: [Int] = [25, 60, 90]

struct Config: Codable {
    var blockedApps: [String] = []
    var blockedWebsites: [String] = defaultWebsites
    var timerPresets: [Int] = defaultTimerPresets
    var appCategoryOverrides: [String: String] = [:]
    var categoryLimits: [String: Int] = [:]  // AppCategory.rawValue → minutes (0 = off)

    private enum CodingKeys: String, CodingKey {
        case blockedApps
        case blockedWebsites
        case timerPresets
        case appCategoryOverrides
        case categoryLimits
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        blockedApps = try container.decodeIfPresent([String].self, forKey: .blockedApps) ?? []
        blockedWebsites = try container.decodeIfPresent([String].self, forKey: .blockedWebsites) ?? defaultWebsites
        timerPresets = try container.decodeIfPresent([Int].self, forKey: .timerPresets) ?? defaultTimerPresets
        appCategoryOverrides = try container.decodeIfPresent([String: String].self, forKey: .appCategoryOverrides) ?? [:]
        categoryLimits = try container.decodeIfPresent([String: Int].self, forKey: .categoryLimits) ?? [:]
    }

    func category(for identifier: String) -> AppCategory {
        if let raw = appCategoryOverrides[identifier], let cat = AppCategory(rawValue: raw) { return cat }
        if let cat = defaultCategoryMappings[identifier] { return cat }
        return bundleIDPrefixCategory(identifier) ?? .other
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
