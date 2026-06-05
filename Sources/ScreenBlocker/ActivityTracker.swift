import AppKit
import CoreGraphics
import Foundation

final class ActivityTracker {
    static let shared = ActivityTracker()

    private var currentAppName: String?
    private var currentBundleID: String?
    private var currentDomain: String?
    private var currentStartTime: Date?
    private var heartbeatTimer: Timer?

    private let idleThreshold: TimeInterval = 180  // 3 minutes

    private init() {}

    func start() {
        if let app = NSWorkspace.shared.frontmostApplication {
            beginTracking(app: app)
        }

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(appActivated(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )

        BrowserWatcher.shared.onDomainChanged = { [weak self] domain in
            self?.handleDomainChange(to: domain)
        }
        BrowserWatcher.shared.start()

        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.heartbeat()
        }
    }

    func stop() {
        flushCurrent()
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        BrowserWatcher.shared.stop()
        NSWorkspace.shared.notificationCenter.removeObserver(
            self,
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
    }

    // MARK: - App activation

    @objc private func appActivated(_ note: Notification) {
        flushCurrent()
        if let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
            beginTracking(app: app)
        }
    }

    private func beginTracking(app: NSRunningApplication) {
        guard app.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
        currentAppName = app.localizedName ?? app.bundleIdentifier ?? "Unknown"
        currentBundleID = app.bundleIdentifier ?? ""
        currentDomain = nil
        currentStartTime = Date()
    }

    // MARK: - Domain change (browser tab navigated)

    func handleDomainChange(to newDomain: String?) {
        guard let bundleID = currentBundleID, BrowserWatcher.isBrowser(bundleID) else { return }
        flushAndRestart(newDomain: newDomain)
    }

    // MARK: - Heartbeat (every 30s)

    private func heartbeat() {
        // Stop accumulating time if the user has been idle
        let idleSeconds = CGEventSource.secondsSinceLastEventType(
            .hidSystemState,
            eventType: CGEventType(rawValue: UInt32.max)!
        )
        guard idleSeconds <= idleThreshold else {
            flushTrimmedToIdle(idleSeconds: idleSeconds)
            return
        }

        guard let name = currentAppName,
              let bundleID = currentBundleID,
              let start = currentStartTime else { return }
        let now = Date()
        let duration = now.timeIntervalSince(start)
        guard duration >= 2 else { return }
        ActivityStore.shared.append(ActivityEvent(
            timestamp: start, duration: duration,
            appName: name, bundleID: bundleID, domain: currentDomain
        ))
        currentStartTime = now
    }

    // MARK: - Flush helpers

    // Writes only the active portion of the current window, ending when input stopped.
    private func flushTrimmedToIdle(idleSeconds: TimeInterval) {
        guard let name = currentAppName,
              let bundleID = currentBundleID,
              let start = currentStartTime else { return }
        let lastActive = Date().addingTimeInterval(-idleSeconds)
        let duration = lastActive.timeIntervalSince(start)
        let domain = currentDomain
        currentAppName = nil; currentBundleID = nil; currentDomain = nil; currentStartTime = nil
        guard duration >= 2 else { return }
        ActivityStore.shared.append(ActivityEvent(
            timestamp: start, duration: duration,
            appName: name, bundleID: bundleID, domain: domain
        ))
    }

    private func flushCurrent() {
        guard let name = currentAppName,
              let bundleID = currentBundleID,
              let start = currentStartTime else { return }
        let duration = Date().timeIntervalSince(start)
        let domain = currentDomain
        currentAppName = nil; currentBundleID = nil; currentDomain = nil; currentStartTime = nil
        guard duration >= 2 else { return }
        ActivityStore.shared.append(ActivityEvent(
            timestamp: start, duration: duration,
            appName: name, bundleID: bundleID, domain: domain
        ))
    }

    // Saves the current slice and restarts tracking the same app with a new domain.
    private func flushAndRestart(newDomain: String?) {
        guard let name = currentAppName,
              let bundleID = currentBundleID,
              let start = currentStartTime else { return }
        let now = Date()
        let duration = now.timeIntervalSince(start)
        if duration >= 2 {
            ActivityStore.shared.append(ActivityEvent(
                timestamp: start, duration: duration,
                appName: name, bundleID: bundleID, domain: currentDomain
            ))
        }
        currentStartTime = now
        currentDomain = newDomain
    }
}
