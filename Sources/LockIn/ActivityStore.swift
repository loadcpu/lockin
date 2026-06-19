import Foundation
import AppKit
import Combine

final class ActivityStore: ObservableObject {
    static let shared = ActivityStore()
    private static let browserBundleIDs: Set<String> = [
        "com.apple.Safari",
        "com.google.Chrome",
        "company.thebrowser.Browser",
        "com.brave.Browser",
        "com.microsoft.edgemac",
        "org.mozilla.firefox",
    ]

    @Published var todayTotal: TimeInterval = 0

    private let queue = DispatchQueue(label: "ActivityStore", qos: .utility)
    private var screenTimeRefreshTick = 0
    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private init() {
        todayTotal = computeTodayTotal()
        pruneOldFiles()
    }

    // Called from AppDelegate's 1-second timer; refreshes Screen Time total every 30s.
    func tick() {
        screenTimeRefreshTick += 1
        guard screenTimeRefreshTick >= 30 else { return }
        screenTimeRefreshTick = 0
        guard ScreenTimeReader.shared.isAvailable else { return }
        let total = ScreenTimeReader.shared.totalDuration(for: Date())
        DispatchQueue.main.async { self.todayTotal = total }
    }

    // MARK: - Storage (fallback custom tracking)

    private var baseDir: URL {
        let dir = FileManager.lockinDir.appendingPathComponent("activity")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func fileURL(for date: Date) -> URL {
        baseDir.appendingPathComponent("\(dateFormatter.string(from: date)).jsonl")
    }

    // Only written by ActivityTracker when Screen Time DB is not available.
    func append(_ event: ActivityEvent) {
        let usesScreenTime = ScreenTimeReader.shared.isAvailable
        // When Screen Time is available, persist only domain-level browser slices.
        guard !usesScreenTime || event.domain != nil else { return }

        let url = fileURL(for: event.timestamp)
        let delta = event.duration
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
            guard !usesScreenTime else { return }
            DispatchQueue.main.async { self.todayTotal += delta }
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
            guard domain == nil, !bundleID.isEmpty, bundleID != "web" else { return nil }
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

    func totalDuration(forDays days: Int) -> TimeInterval {
        if ScreenTimeReader.shared.isAvailable {
            let calendar = Calendar.current
            let today = Date()
            return (0..<days).reduce(0.0) { total, offset in
                guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { return total }
                return total + ScreenTimeReader.shared.totalDuration(for: date)
            }
        }
        return events(forDays: days).reduce(0) { $0 + $1.duration }
    }

    func totalDuration(for date: Date) -> TimeInterval {
        if ScreenTimeReader.shared.isAvailable {
            return ScreenTimeReader.shared.totalDuration(for: date)
        }
        return events(for: date).reduce(0) { $0 + $1.duration }
    }

    func topApps(forDays days: Int, limit: Int = 10) -> [AppUsage] {
        if ScreenTimeReader.shared.isAvailable {
            return mergedTopApps(forDays: days, limit: limit)
        }
        return aggregate(events(forDays: days), limit: limit)
    }

    func topApps(for date: Date, limit: Int = 10) -> [AppUsage] {
        if ScreenTimeReader.shared.isAvailable {
            return mergedTopApps(for: date, limit: limit)
        }
        return aggregate(events(for: date), limit: limit)
    }

    func categoryBreakdown(forDays days: Int, categoryLookup: (String) -> AppCategory) -> [CategoryUsage] {
        if ScreenTimeReader.shared.isAvailable {
            return mergedCategoryBreakdown(forDays: days, lookup: categoryLookup)
        }
        return buildCategoryBreakdown(events(forDays: days), lookup: categoryLookup)
    }

    func categoryBreakdown(for date: Date, categoryLookup: (String) -> AppCategory) -> [CategoryUsage] {
        if ScreenTimeReader.shared.isAvailable {
            return mergedCategoryBreakdown(for: date, lookup: categoryLookup)
        }
        return buildCategoryBreakdown(events(for: date), lookup: categoryLookup)
    }

    // MARK: - Screen Time data paths

    private func mergedTopApps(forDays days: Int, limit: Int) -> [AppUsage] {
        mergedUsage(screenTimeSamples: screenTimeSamples(forDays: days), trackedEvents: events(forDays: days))
            .sorted { $0.duration > $1.duration }
            .prefix(limit)
            .map { $0 }
    }

    private func mergedTopApps(for date: Date, limit: Int) -> [AppUsage] {
        mergedUsage(screenTimeSamples: ScreenTimeReader.shared.samples(for: date), trackedEvents: events(for: date))
            .sorted { $0.duration > $1.duration }
            .prefix(limit)
            .map { $0 }
    }

    private func screenTimeSamples(forDays days: Int) -> [ScreenTimeReader.Sample] {
        let calendar = Calendar.current
        let today = Date()
        return (0..<days).flatMap { offset -> [ScreenTimeReader.Sample] in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { return [] }
            return ScreenTimeReader.shared.samples(for: date)
        }
    }

    private func mergedUsage(screenTimeSamples: [ScreenTimeReader.Sample], trackedEvents: [ActivityEvent]) -> [AppUsage] {
        var byKey: [String: (appName: String, bundleID: String, domain: String?, duration: TimeInterval)] = [:]

        let trackedDomainUsage = aggregate(trackedEvents.filter { $0.domain != nil }, limit: Int.max)
        let hasTrackedDomains = !trackedDomainUsage.isEmpty

        for sample in screenTimeSamples {
            if hasTrackedDomains && Self.browserBundleIDs.contains(sample.bundleID) {
                continue
            }
            let key = sample.domain ?? sample.bundleID
            let appName = resolveAppName(bundleID: sample.bundleID) ?? sample.domain ?? sample.bundleID
            if byKey[key] != nil {
                byKey[key]!.duration += sample.duration
            } else {
                byKey[key] = (appName, sample.bundleID, sample.domain, sample.duration)
            }
        }

        for usage in trackedDomainUsage {
            let key = usage.domain ?? usage.bundleID
            if byKey[key] != nil {
                byKey[key]!.duration += usage.duration
            } else {
                byKey[key] = (usage.appName, usage.bundleID, usage.domain, usage.duration)
            }
        }

        return byKey
            .map { _, v in AppUsage(appName: v.appName, bundleID: v.bundleID, domain: v.domain, duration: v.duration) }
    }

    private func mergedCategoryBreakdown(forDays days: Int, lookup: (String) -> AppCategory) -> [CategoryUsage] {
        buildCategoryBreakdown(
            mergedUsage(screenTimeSamples: screenTimeSamples(forDays: days), trackedEvents: events(forDays: days))
                .map { ActivityEvent(timestamp: .now, duration: $0.duration, appName: $0.appName, bundleID: $0.bundleID, domain: $0.domain) },
            lookup: lookup
        )
    }

    private func mergedCategoryBreakdown(for date: Date, lookup: (String) -> AppCategory) -> [CategoryUsage] {
        buildCategoryBreakdown(
            mergedUsage(screenTimeSamples: ScreenTimeReader.shared.samples(for: date), trackedEvents: events(for: date))
                .map { ActivityEvent(timestamp: .now, duration: $0.duration, appName: $0.appName, bundleID: $0.bundleID, domain: $0.domain) },
            lookup: lookup
        )
    }

    private func screenTimeCategoryBreakdown(forDays days: Int, lookup: (String) -> AppCategory) -> [CategoryUsage] {
        var byCategory: [AppCategory: TimeInterval] = [:]
        for sample in screenTimeSamples(forDays: days) {
            let key = sample.domain ?? sample.bundleID
            let cat = lookup(key)
            byCategory[cat, default: 0] += sample.duration
        }

        let noiseCategories: Set<AppCategory> = [.system, .other]
        return byCategory
            .map { CategoryUsage(category: $0.key, duration: $0.value) }
            .filter { $0.duration > 0 }
            .sorted {
                let aNoise = noiseCategories.contains($0.category)
                let bNoise = noiseCategories.contains($1.category)
                if aNoise != bNoise { return bNoise }
                return $0.duration > $1.duration
            }
    }

    private func screenTimeCategoryBreakdown(for date: Date, lookup: (String) -> AppCategory) -> [CategoryUsage] {
        var byCategory: [AppCategory: TimeInterval] = [:]

        for sample in ScreenTimeReader.shared.samples(for: date) {
            let key = sample.domain ?? sample.bundleID
            let cat = lookup(key)
            byCategory[cat, default: 0] += sample.duration
        }

        let noiseCategories: Set<AppCategory> = [.system, .other]
        return byCategory
            .map { CategoryUsage(category: $0.key, duration: $0.value) }
            .filter { $0.duration > 0 }
            .sorted {
                let aNoise = noiseCategories.contains($0.category)
                let bNoise = noiseCategories.contains($1.category)
                if aNoise != bNoise { return bNoise }
                return $0.duration > $1.duration
            }
    }

    // MARK: - Private helpers

    private func computeTodayTotal() -> TimeInterval {
        if ScreenTimeReader.shared.isAvailable {
            return ScreenTimeReader.shared.totalDuration(for: Date())
        }
        return events(for: Date()).reduce(0) { $0 + $1.duration }
    }

    private func resolveAppName(bundleID: String) -> String? {
        guard bundleID != "web" else { return nil }
        return NSWorkspace.shared.urlsForApplications(withBundleIdentifier: bundleID)
            .first.map { $0.deletingPathExtension().lastPathComponent }
    }

    private func pruneOldFiles(keepDays: Int = 90) {
        queue.async {
            let cutoff = Calendar.current.date(byAdding: .day, value: -keepDays, to: Date()) ?? Date()
            let fm = FileManager.default
            guard let files = try? fm.contentsOfDirectory(
                at: self.baseDir, includingPropertiesForKeys: nil
            ) else { return }
            for url in files where url.pathExtension == "jsonl" {
                let name = url.deletingPathExtension().lastPathComponent
                guard let date = self.dateFormatter.date(from: name),
                      date < cutoff else { continue }
                try? fm.removeItem(at: url)
            }
        }
    }

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
        let noiseCategories: Set<AppCategory> = [.system, .other]
        return byCategory
            .map { CategoryUsage(category: $0.key, duration: $0.value) }
            .filter { $0.duration > 0 }
            .sorted {
                let aNoise = noiseCategories.contains($0.category)
                let bNoise = noiseCategories.contains($1.category)
                if aNoise != bNoise { return bNoise }
                return $0.duration > $1.duration
            }
    }
}
