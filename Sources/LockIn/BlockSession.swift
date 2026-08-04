import Foundation

struct BlockSession: Codable {
    let startTime: Date
    var endTime: Date
    let blockedApps: [String]
    let blockedWebsites: [String]

    /// When set, the session is on a break: enforcement is paused and the countdown is frozen.
    var pauseStartedAt: Date?
    /// Length in minutes of the break currently (or most recently) in progress. 0...10.
    var breakMinutes: Int
    /// Total real time spent on completed breaks, subtracted when computing how many
    /// hours of *active* work have elapsed (used to gate how many breaks are earned).
    var totalPausedSeconds: TimeInterval
    /// Number of breaks started so far this session.
    var breaksTaken: Int

    init(minutes: Int, blockedApps: [String], blockedWebsites: [String]) {
        self.startTime = Date()
        self.endTime = Date().addingTimeInterval(TimeInterval(minutes * 60))
        self.blockedApps = blockedApps
        self.blockedWebsites = blockedWebsites
        self.pauseStartedAt = nil
        self.breakMinutes = 0
        self.totalPausedSeconds = 0
        self.breaksTaken = 0
    }

    private enum CodingKeys: String, CodingKey {
        case startTime, endTime, blockedApps, blockedWebsites
        case pauseStartedAt, breakMinutes, totalPausedSeconds, breaksTaken
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        startTime = try c.decode(Date.self, forKey: .startTime)
        endTime = try c.decode(Date.self, forKey: .endTime)
        blockedApps = try c.decode([String].self, forKey: .blockedApps)
        blockedWebsites = try c.decode([String].self, forKey: .blockedWebsites)
        pauseStartedAt = try c.decodeIfPresent(Date.self, forKey: .pauseStartedAt)
        breakMinutes = try c.decodeIfPresent(Int.self, forKey: .breakMinutes) ?? 0
        totalPausedSeconds = try c.decodeIfPresent(TimeInterval.self, forKey: .totalPausedSeconds) ?? 0
        breaksTaken = try c.decodeIfPresent(Int.self, forKey: .breaksTaken) ?? 0
    }

    var isPaused: Bool { pauseStartedAt != nil }

    /// The current wall-clock instant for countdown purposes: frozen at the moment a break
    /// started, so the timer doesn't drain while paused.
    private var effectiveNow: Date { pauseStartedAt ?? Date() }

    var isActive: Bool {
        if isPaused { return true }
        return Date() < endTime
    }

    var remainingSeconds: Int { max(0, Int(endTime.timeIntervalSince(effectiveNow))) }

    /// Active (non-paused) work time elapsed so far, used to gate break eligibility.
    var activeElapsedSeconds: TimeInterval {
        max(0, effectiveNow.timeIntervalSince(startTime) - totalPausedSeconds)
    }

    private static let breakEarnIntervalSeconds: TimeInterval = 3600

    /// One 10-minute break is earned per full hour of active work. Breaks already taken
    /// are subtracted from the number earned so far.
    var breaksAvailable: Int {
        max(0, Int(activeElapsedSeconds / Self.breakEarnIntervalSeconds) - breaksTaken)
    }

    /// Seconds left in the break currently in progress (0 once the break's time is up).
    var breakRemainingSeconds: Int {
        guard let pauseStartedAt else { return 0 }
        let breakEnd = pauseStartedAt.addingTimeInterval(TimeInterval(breakMinutes * 60))
        return max(0, Int(breakEnd.timeIntervalSinceNow))
    }

    func progress(at date: Date) -> Double {
        let totalDuration = endTime.timeIntervalSince(startTime)
        guard totalDuration > 0 else { return 1 }
        let now = isPaused ? (pauseStartedAt ?? date) : date
        let elapsed = now.timeIntervalSince(startTime)
        return min(max(elapsed / totalDuration, 0), 1)
    }

    var remainingFormatted: String {
        let secs = remainingSeconds
        let h = secs / 3600
        let m = (secs % 3600) / 60
        let s = secs % 60
        if h > 0 { return "\(h)h \(String(format: "%02d", m))m" }
        return "\(m):\(String(format: "%02d", s))"
    }

    private static var fileURL: URL {
        FileManager.lockinDir.appendingPathComponent("session.json")
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
