import Foundation
import AppKit
import Combine

final class ActivityStore: ObservableObject {
    static let shared = ActivityStore()

    @Published var todayTotal: TimeInterval = 0

    private let queue = DispatchQueue(label: "ActivityStore", qos: .utility)
    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private init() {
        todayTotal = totalDuration(for: Date())
    }

    // MARK: - Storage

    private var baseDir: URL {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".screenblocker/activity")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func fileURL(for date: Date) -> URL {
        baseDir.appendingPathComponent("\(dateFormatter.string(from: date)).jsonl")
    }

    func append(_ event: ActivityEvent) {
        let url = fileURL(for: event.timestamp)
        queue.async { [weak self] in
            guard let self,
                  let data = try? JSONEncoder().encode(event),
                  let line = String(data: data, encoding: .utf8) else { return }
            let entry = line + "\n"
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(Data(entry.utf8))
                try? handle.close()
            } else {
                try? entry.write(to: url, atomically: false, encoding: .utf8)
            }
            let newTotal = self.totalDuration(for: Date())
            DispatchQueue.main.async { self.todayTotal = newTotal }
        }
    }

    // MARK: - Reading

    func events(for date: Date) -> [ActivityEvent] {
        let url = fileURL(for: date)
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        let decoder = JSONDecoder()
        return content.split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { line -> ActivityEvent? in
                guard let data = String(line).data(using: .utf8) else { return nil }
                return try? decoder.decode(ActivityEvent.self, from: data)
            }
    }

    func events(forDays days: Int) -> [ActivityEvent] {
        let calendar = Calendar.current
        let today = Date()
        return (0..<days).flatMap { offset -> [ActivityEvent] in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { return [] }
            return events(for: date)
        }
    }

    // MARK: - Stats

    struct AppUsage: Identifiable {
        let id = UUID()
        let appName: String
        let bundleID: String
        let domain: String?
        let duration: TimeInterval

        var displayName: String { domain ?? appName }

        var icon: NSImage? {
            guard domain == nil, !bundleID.isEmpty else { return nil }
            let urls = NSWorkspace.shared.urlsForApplications(withBundleIdentifier: bundleID)
            guard let url = urls.first else { return nil }
            return NSWorkspace.shared.icon(forFile: url.path)
        }
    }

    struct CategoryUsage: Identifiable {
        let id = UUID()
        let category: AppCategory
        let duration: TimeInterval
    }

    func totalDuration(for date: Date) -> TimeInterval {
        events(for: date).reduce(0) { $0 + $1.duration }
    }

    func totalDuration(forDays days: Int) -> TimeInterval {
        events(forDays: days).reduce(0) { $0 + $1.duration }
    }

    func topApps(for date: Date, limit: Int = 10) -> [AppUsage] {
        aggregate(events(for: date), limit: limit)
    }

    func topApps(forDays days: Int, limit: Int = 10) -> [AppUsage] {
        aggregate(events(forDays: days), limit: limit)
    }

    func categoryBreakdown(for date: Date, categoryLookup: (String) -> AppCategory) -> [CategoryUsage] {
        buildCategoryBreakdown(events(for: date), lookup: categoryLookup)
    }

    func categoryBreakdown(forDays days: Int, categoryLookup: (String) -> AppCategory) -> [CategoryUsage] {
        buildCategoryBreakdown(events(forDays: days), lookup: categoryLookup)
    }

    // MARK: - Private helpers

    // Stable event identifier: domain > bundleID > appName
    static func eventKey(_ e: ActivityEvent) -> String {
        e.domain ?? (e.bundleID.isEmpty ? e.appName : e.bundleID)
    }

    private func aggregate(_ events: [ActivityEvent], limit: Int) -> [AppUsage] {
        var byKey: [String: (appName: String, bundleID: String, domain: String?, duration: TimeInterval)] = [:]
        for e in events {
            let key = ActivityStore.eventKey(e)
            if byKey[key] != nil {
                byKey[key]!.duration += e.duration
            } else {
                byKey[key] = (e.appName, e.bundleID, e.domain, e.duration)
            }
        }
        return byKey
            .map { _, v in AppUsage(appName: v.appName, bundleID: v.bundleID, domain: v.domain, duration: v.duration) }
            .sorted { $0.duration > $1.duration }
            .prefix(limit)
            .map { $0 }
    }

    private func buildCategoryBreakdown(_ events: [ActivityEvent], lookup: (String) -> AppCategory) -> [CategoryUsage] {
        var byCategory: [AppCategory: TimeInterval] = [:]
        for e in events {
            let cat = lookup(ActivityStore.eventKey(e))
            byCategory[cat, default: 0] += e.duration
        }
        return byCategory
            .map { CategoryUsage(category: $0.key, duration: $0.value) }
            .filter { $0.duration > 0 }
            .sorted { $0.duration > $1.duration }
    }
}
