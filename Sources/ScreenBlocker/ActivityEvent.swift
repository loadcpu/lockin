import Foundation

struct ActivityEvent: Codable {
    let id: UUID
    let timestamp: Date
    let duration: TimeInterval
    let appName: String
    let bundleID: String
    var domain: String?  // non-nil only for browser tab events

    init(timestamp: Date, duration: TimeInterval, appName: String, bundleID: String, domain: String? = nil) {
        self.id = UUID()
        self.timestamp = timestamp
        self.duration = duration
        self.appName = appName
        self.bundleID = bundleID
        self.domain = domain
    }
}

extension TimeInterval {
    var formattedDuration: String {
        let total = Int(self)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        if minutes > 0 { return "\(minutes)m" }
        if total > 0  { return "< 1m" }
        return "0m"
    }
}
