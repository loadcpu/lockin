import AppKit
import Foundation
import Combine
import UserNotifications

final class BlockerService: ObservableObject {
    static let shared = BlockerService()

    @Published var isBlocking = false
    @Published var remainingSeconds = 0
    @Published var config: Config = .load()
    @Published private(set) var hasLimitRestrictions = false

    @Published private(set) var primedBrowserIDs: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "primedBrowserIDs") ?? []) {
        didSet { UserDefaults.standard.set(Array(primedBrowserIDs), forKey: "primedBrowserIDs") }
    }

    private var session: BlockSession?
    private var killTimer: Timer?
    private var isMonitoring = false
    private var blockedAppNames: Set<String> = []
    private var limitBlockedApps: Set<String> = []
    private var limitBlockedWebsites: Set<String> = []
    private let websiteBlockQueue = DispatchQueue(label: "com.local.lockin.website-blocks", qos: .utility)

    private init() {}

    // Called once at launch
    func loadState() {
        config = Config.load()
        if let s = BlockSession.load() {
            if s.isActive {
                session = s
                isBlocking = true
                remainingSeconds = s.remainingSeconds
                refreshEffectiveBlocks(reloadBrowserTabs: true)
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
        refreshEffectiveBlocks(reloadBrowserTabs: true)
        // Schedule the end notification now, while the app is stable.
        // The system daemon holds it and fires it even after this process exits,
        // avoiding the BlockSession.clear() → launchd SIGTERM → app-exit race.
        scheduleSessionEndNotification(minutes: minutes)
    }

    func updateLimitBlocks(apps: [String], websites: [String]) {
        let newApps = Set(apps.map { $0.lowercased() })
        let newWebsites = Set(websites)
        guard newApps != limitBlockedApps || newWebsites != limitBlockedWebsites else { return }

        limitBlockedApps = newApps
        limitBlockedWebsites = newWebsites
        hasLimitRestrictions = !newApps.isEmpty || !newWebsites.isEmpty
        refreshEffectiveBlocks(reloadBrowserTabs: hasLimitRestrictions)
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
        BlockSession.clear()
        refreshEffectiveBlocks(reloadBrowserTabs: false)
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
                    NSLog("LockIn: notification schedule failed: %@", error.localizedDescription)
                } else {
                    NSLog("LockIn: session-end notification scheduled for %dm", minutes)
                }
            }
        }
    }

    private func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true
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
        guard isMonitoring else { return }
        isMonitoring = false
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        killTimer?.invalidate()
        killTimer = nil
    }

    private func refreshEffectiveBlocks(reloadBrowserTabs shouldReload: Bool) {
        let sessionApps = Set(session?.blockedApps.map { $0.lowercased() } ?? [])
        let sessionWebsites = Set(session?.blockedWebsites ?? [])
        blockedAppNames = sessionApps.union(limitBlockedApps)

        if blockedAppNames.isEmpty {
            stopMonitoring()
        } else {
            startMonitoring()
            killBlockedApps()
        }

        let websites = Array(sessionWebsites.union(limitBlockedWebsites))
        websiteBlockQueue.async { [weak self] in
            if websites.isEmpty {
                HostsManager.removeBlocks()
            } else if HostsManager.applyBlocks(domains: websites), shouldReload {
                self?.reloadBrowserTabs()
            }
        }
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

    func browserName(forBundleID bundleID: String) -> String {
        knownBrowsers.first(where: { $0.bundleID == bundleID })?.name ?? bundleID
    }

    @discardableResult
    func forceQuitBrowsers(bundleIDs: [String]) -> [String] {
        var closed: [String] = []
        for bundleID in bundleIDs {
            guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else { continue }
            app.forceTerminate()
            closed.append(browserName(forBundleID: bundleID))
        }
        return closed
    }

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
                guard NSRunningApplication.runningApplications(withBundleIdentifier: b.bundleID).first != nil else { continue }
                if !self.reloadTabs(in: b) {
                    // During an active locked session, browsers that can bypass
                    // website blocking must be closed if Automation is denied.
                    _ = self.forceQuitBrowsers(bundleIDs: [b.bundleID])
                    self.notifyBrowserForceQuit(b.name)
                }
            }
        }
    }

    private func notifyBrowserForceQuit(_ browserName: String) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized else { return }
            let content = UNMutableNotificationContent()
            content.title = "Browser closed during session"
            content.body = "\(browserName) was closed because Automation access was denied and already-open tabs could bypass website blocking. Enable Lock In in System Settings → Privacy & Security → Automation."
            let request = UNNotificationRequest(identifier: "browser-force-quit-\(browserName)", content: content, trigger: nil)
            UNUserNotificationCenter.current().add(request) { error in
                if let error { NSLog("LockIn: browser-force-quit notification failed: %@", error.localizedDescription) }
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
        if let err { NSLog("LockIn: %@ reload error: %@", browser.name, err) }
        return err == nil
    }
}
