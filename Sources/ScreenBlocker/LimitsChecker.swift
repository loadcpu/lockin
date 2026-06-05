import Foundation
import UserNotifications

final class LimitsChecker {
    static let shared = LimitsChecker()
    private var checkTimer: Timer?

    private init() {}

    func start() {
        // Request notification permission once; silently ignored on subsequent launches
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound]) { _, _ in }

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
        guard !config.categoryLimits.isEmpty else { return }

        let events = ActivityStore.shared.events(for: Date())

        for (rawCategory, limitMinutes) in config.categoryLimits {
            guard limitMinutes > 0, let category = AppCategory(rawValue: rawCategory) else { continue }

            let used = events
                .filter { config.category(for: ActivityStore.eventKey($0)) == category }
                .reduce(0) { $0 + $1.duration }

            let threshold = TimeInterval(limitMinutes * 60)
            guard used >= threshold else { continue }

            // One notification per category per day
            let dayStamp = Int(Calendar.current.startOfDay(for: Date()).timeIntervalSinceReferenceDate)
            let notifKey = "limit_notified_\(rawCategory)_\(dayStamp)"
            guard !UserDefaults.standard.bool(forKey: notifKey) else { continue }
            UserDefaults.standard.set(true, forKey: notifKey)

            deliver(category: category, used: used, limit: limitMinutes)
        }
    }

    private func deliver(category: AppCategory, used: TimeInterval, limit: Int) {
        let content = UNMutableNotificationContent()
        content.title = "Screen Time Alert"
        content.body = "You've spent \(used.formattedDuration) on \(category.rawValue) today — your \(limit)m limit."
        content.sound = .default
        UNUserNotificationCenter.current()
            .add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
}
