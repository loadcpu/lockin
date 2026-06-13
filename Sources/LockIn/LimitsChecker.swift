import Foundation
import UserNotifications

final class LimitsChecker {
    static let shared = LimitsChecker()
    private var checkTimer: Timer?

    private init() {}

    func start() {
        check()
        checkTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.check()
        }
    }

    func stop() {
        checkTimer?.invalidate()
        checkTimer = nil
    }

    private func check() {
        let config = BlockerService.shared.config
        guard !config.categoryLimits.isEmpty else {
            BlockerService.shared.updateLimitBlocks(apps: [], websites: [])
            return
        }

        let breakdown = ActivityStore.shared.categoryBreakdown(forDays: 1) { config.category(for: $0) }
        var blockedApps = Set<String>()
        var blockedSites = Set<String>()

        for (rawCategory, limitMinutes) in config.categoryLimits {
            guard limitMinutes > 0, let category = AppCategory(rawValue: rawCategory) else { continue }

            let used = breakdown.first { $0.category == category }?.duration ?? 0
            let threshold = TimeInterval(limitMinutes * 60)
            guard used >= threshold else { continue }

            let apps  = collectApps(for: category, config: config)
            let sites = collectSites(for: category, config: config)
            blockedApps.formUnion(apps)
            blockedSites.formUnion(sites)

            // Notifications fire once per category per day; enforcement is recomputed
            // every minute so it survives focus sessions and clears at midnight.
            let dayStamp = Int(Calendar.current.startOfDay(for: Date()).timeIntervalSinceReferenceDate)
            let notifKey = "limit_notified_\(rawCategory)_\(dayStamp)"
            guard !UserDefaults.standard.bool(forKey: notifKey) else { continue }
            UserDefaults.standard.set(true, forKey: notifKey)
            deliver(category: category, used: used, limit: limitMinutes, willBlock: !apps.isEmpty || !sites.isEmpty)
        }

        BlockerService.shared.updateLimitBlocks(
            apps: Array(blockedApps),
            websites: Array(blockedSites)
        )
    }

    // MARK: - Helpers

    private func collectApps(for category: AppCategory, config: Config) -> [String] {
        let fromActivity = ActivityStore.shared.topApps(forDays: 1, limit: 50)
            .filter { u in
                u.domain == nil &&
                config.category(for: u.bundleID.isEmpty ? u.appName : u.bundleID) == category
            }
            .map(\.appName)
        let fromConfig = config.blockedApps.filter { config.category(for: $0) == category }
        return Array(Set(fromActivity + fromConfig))
    }

    private func collectSites(for category: AppCategory, config: Config) -> [String] {
        let fromActivity = ActivityStore.shared.topApps(forDays: 1, limit: 50)
            .compactMap(\.domain)
            .filter { config.category(for: $0) == category }
        let fromConfig = config.blockedWebsites.filter { config.category(for: $0) == category }
        return Array(Set(fromActivity + fromConfig))
    }

    private func deliver(category: AppCategory, used: TimeInterval, limit: Int, willBlock: Bool) {
        let content = UNMutableNotificationContent()
        content.title = "Screen Time Limit Reached"
        content.body = willBlock
            ? "\(used.formattedDuration) on \(category.rawValue) — apps are now blocked for the rest of the day."
            : "You've spent \(used.formattedDuration) on \(category.rawValue) today — your \(limit)m limit."
        content.sound = .default
        UNUserNotificationCenter.current()
            .add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
}
