import AppKit
import Foundation
import Combine
import UserNotifications

final class BlockerService: ObservableObject {
    static let shared = BlockerService()

    @Published var isBlocking = false
    @Published var remainingSeconds = 0
    @Published var config: Config = .load()

    @Published private(set) var primedBrowserIDs: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "primedBrowserIDs") ?? []) {
        didSet { UserDefaults.standard.set(Array(primedBrowserIDs), forKey: "primedBrowserIDs") }
    }

    private var session: BlockSession?
    private var killTimer: Timer?
    private var blockedAppNames: Set<String> = []

    private init() {}

    // Called once at launch
    func loadState() {
        config = Config.load()
        if let s = BlockSession.load() {
            if s.isActive {
                session = s
                isBlocking = true
                remainingSeconds = s.remainingSeconds
                blockedAppNames = Set(s.blockedApps.map { $0.lowercased() })
                startMonitoring()
                // applyBlocks resolves IPs + pfctl (takes 2-4s) — run off main thread.
                // On success, reload browser tabs so existing connections to blocked
                // sites are cut off (mirrors the startSession path).
                let websites = s.blockedWebsites
                if !websites.isEmpty {
                    DispatchQueue.global(qos: .utility).async { [weak self] in
                        if HostsManager.applyBlocks(domains: websites) {
                            self?.reloadBrowserTabs()
                        }
                    }
                }
            } else {
                HostsManager.removeBlocks()
                BlockSession.clear()
            }
        } else {
            HostsManager.removeBlocks()
        }
    }

    // Called every second by AppDelegate's timer
    func tick() {
        guard isBlocking, let s = session else { return }
        if !s.isActive {
            endSession()
            return
        }
        remainingSeconds = s.remainingSeconds
        killBlockedApps()
    }

    func startSession(minutes: Int, apps: [String]? = nil, websites: [String]? = nil) {
        let s = BlockSession(
            minutes: minutes,
            blockedApps: apps ?? config.blockedApps,
            blockedWebsites: websites ?? config.blockedWebsites
        )
        s.save()
        session = s
        isBlocking = true
        remainingSeconds = s.remainingSeconds
        blockedAppNames = Set(s.blockedApps.map { $0.lowercased() })
        // Schedule the end notification now, while the app is stable.
        // The system daemon holds it and fires it even after this process exits,
        // avoiding the BlockSession.clear() → launchd SIGTERM → app-exit race.
        scheduleSessionEndNotification(minutes: minutes)
        startMonitoring()

        let websitesToBlock = s.blockedWebsites
        guard !websitesToBlock.isEmpty else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            // applyBlocks resolves IPs + applies pfctl rules (~2-4s).
            // reloadBrowserTabs fires 1s after that, so pfctl is already in place
            // when tabs reload — killing existing connections on the spot.
            if HostsManager.applyBlocks(domains: websitesToBlock) {
                self?.reloadBrowserTabs()
            }
        }
    }

    func saveConfig() {
        config.save()
    }

    var remainingTimeString: String {
        session?.remainingFormatted ?? "0:00"
    }

    // MARK: - Private

    private func endSession() {
        if let s = session {
            FocusStore.shared.record(duration: s.endTime.timeIntervalSince(s.startTime))
        }
        // The session-end notification was pre-scheduled at startSession() and is
        // held by the system daemon — no XPC call needed here during the SIGTERM race.
        isBlocking = false
        remainingSeconds = 0
        session = nil
        blockedAppNames = []
        BlockSession.clear()
        stopMonitoring()
        HostsManager.removeBlocks()
    }

    private func scheduleSessionEndNotification(minutes: Int) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["session-complete"])
            let content = UNMutableNotificationContent()
            content.title = "Focus session complete"
            content.body = "\(minutes)m focused."
            content.sound = .default
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: Double(minutes * 60), repeats: false)
            let request = UNNotificationRequest(identifier: "session-complete", content: content, trigger: trigger)
            UNUserNotificationCenter.current().add(request) { error in
                if let error {
                    NSLog("ScreenBlocker: notification schedule failed: %@", error.localizedDescription)
                } else {
                    NSLog("ScreenBlocker: session-end notification scheduled for %dm", minutes)
                }
            }
        }
    }

    private func startMonitoring() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(appLaunched(_:)),
            name: NSWorkspace.didLaunchApplicationNotification,
            object: nil
        )
        killTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.killBlockedApps()
        }
    }

    private func stopMonitoring() {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        killTimer?.invalidate()
        killTimer = nil
    }

    @objc private func appLaunched(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        checkAndKill(app)
    }

    private func killBlockedApps() {
        for app in NSWorkspace.shared.runningApplications { checkAndKill(app) }
    }

    private func checkAndKill(_ app: NSRunningApplication) {
        guard app.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
        guard !blockedAppNames.isEmpty else { return }
        if blockedAppNames.contains((app.localizedName ?? "").lowercased()) {
            app.forceTerminate()
        }
    }

    // MARK: - Browser permission priming

    private struct Browser {
        let name: String
        let bundleID: String
        let isSafari: Bool
    }

    var knownBrowserBundleIDs: [String] { knownBrowsers.map(\.bundleID) }

    private let knownBrowsers: [Browser] = [
        Browser(name: "Safari",         bundleID: "com.apple.Safari",              isSafari: true),
        Browser(name: "Google Chrome",  bundleID: "com.google.Chrome",             isSafari: false),
        Browser(name: "Arc",            bundleID: "company.thebrowser.Browser",    isSafari: false),
        Browser(name: "Brave Browser",  bundleID: "com.brave.Browser",             isSafari: false),
        Browser(name: "Microsoft Edge", bundleID: "com.microsoft.edgemac",         isSafari: false),
        Browser(name: "Firefox",        bundleID: "org.mozilla.firefox",           isSafari: false),
    ]

    // Triggers the one-time macOS Automation permission dialog for each running browser.
    // Safe to call anytime; intended to be called during onboarding or from Config UI.
    func primeBrowserPermissions(completion: @escaping () -> Void = {}) {
        DispatchQueue.global(qos: .userInitiated).async {
            var primed = self.primedBrowserIDs
            for b in self.knownBrowsers {
                guard NSRunningApplication
                    .runningApplications(withBundleIdentifier: b.bundleID).first != nil
                else { continue }
                // "count windows" is harmless — it just triggers the TCC dialog once.
                let script = """
                if application "\(b.name)" is running then
                    tell application "\(b.name)" to count windows
                end if
                """
                var err: NSDictionary?
                NSAppleScript(source: script)?.executeAndReturnError(&err)
                if err == nil { primed.insert(b.bundleID) }
            }
            DispatchQueue.main.async {
                self.primedBrowserIDs = primed
                completion()
            }
        }
    }

    // MARK: - Tab reload (session start)

    private func reloadBrowserTabs() {
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 1.0) {
            for b in self.knownBrowsers {
                guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: b.bundleID).first else { continue }
                if !self.reloadTabs(in: b) {
                    // Permission denied — kill the browser so open tabs can't be used to bypass blocking.
                    app.forceTerminate()
                }
            }
        }
    }

    @discardableResult
    private func reloadTabs(in browser: Browser) -> Bool {
        let action = browser.isSafari ? "set URL of t to URL of t" : "reload t"
        let script = """
        if application "\(browser.name)" is running then
            tell application "\(browser.name)"
                repeat with w in windows
                    repeat with t in tabs of w
                        try
                            \(action)
                        end try
                    end repeat
                end repeat
            end tell
        end if
        """
        var err: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&err)
        if let err { NSLog("ScreenBlocker: %@ reload error — force quitting: %@", browser.name, err) }
        return err == nil
    }
}
