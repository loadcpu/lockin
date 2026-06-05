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
        return defaultCategoryMappings[identifier] ?? .other
    }

    private static var fileURL: URL {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".screenblocker")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("config.json")
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
