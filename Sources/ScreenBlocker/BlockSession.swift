import Foundation

struct BlockSession: Codable {
    let startTime: Date
    let endTime: Date
    let blockedApps: [String]
    let blockedWebsites: [String]

    init(minutes: Int, blockedApps: [String], blockedWebsites: [String]) {
        self.startTime = Date()
        self.endTime = Date().addingTimeInterval(TimeInterval(minutes * 60))
        self.blockedApps = blockedApps
        self.blockedWebsites = blockedWebsites
    }

    var isActive: Bool { Date() < endTime }

    var remainingSeconds: Int { max(0, Int(endTime.timeIntervalSinceNow)) }

    var remainingFormatted: String {
        let secs = remainingSeconds
        let h = secs / 3600
        let m = (secs % 3600) / 60
        let s = secs % 60
        if h > 0 { return "\(h)h \(String(format: "%02d", m))m" }
        return "\(m):\(String(format: "%02d", s))"
    }

    private static var fileURL: URL {
        FileManager.screenblockerDir.appendingPathComponent("session.json")
    }

    static func load() -> BlockSession? {
        guard let data = try? Data(contentsOf: fileURL),
              let session = try? JSONDecoder().decode(BlockSession.self, from: data) else {
            return nil
        }
        return session
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        try? data.write(to: BlockSession.fileURL)
    }

    static func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
