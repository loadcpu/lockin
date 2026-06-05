import AppKit
import Foundation
import Combine

final class BlockerService: ObservableObject {
    static let shared = BlockerService()

    @Published var isBlocking = false
    @Published var remainingSeconds = 0
    @Published var config: Config = .load()

    private var session: BlockSession?
    private var killTimer: Timer?

    private init() {}

    // Called once at launch
    func loadState() {
        config = Config.load()
        if let s = BlockSession.load() {
            if s.isActive {
                session = s
                isBlocking = true
                remainingSeconds = s.remainingSeconds
                startMonitoring()
                // applyBlocks now resolves IPs + pfctl (takes 2-4s) — run off main thread
                let websites = s.blockedWebsites
                if !websites.isEmpty {
                    DispatchQueue.global(qos: .utility).async {
                        HostsManager.applyBlocks(domains: websites)
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
        killBlockedApps(s)
    }

    func startSession(minutes: Int) {
        // Start timer and UI immediately — don't block main thread waiting for pfctl
        let s = BlockSession(
            minutes: minutes,
            blockedApps: config.blockedApps,
            blockedWebsites: config.blockedWebsites
        )
        s.save()
        session = s
        isBlocking = true
        remainingSeconds = s.remainingSeconds
        startMonitoring()

        let websites = config.blockedWebsites
        guard !websites.isEmpty else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            // applyBlocks resolves IPs + applies pfctl rules (~2-4s).
            // reloadBrowserTabs fires 1s after that, so pfctl is already in place
            // when tabs reload — killing existing connections on the spot.
            if HostsManager.applyBlocks(domains: websites) {
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
        isBlocking = false
        remainingSeconds = 0
        session = nil
        BlockSession.clear()
        stopMonitoring()
        HostsManager.removeBlocks()
    }

    private func startMonitoring() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(appLaunched(_:)),
            name: NSWorkspace.didLaunchApplicationNotification,
            object: nil
        )
        killTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            guard let self, let s = self.session else { return }
            self.killBlockedApps(s)
        }
    }

    private func stopMonitoring() {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        killTimer?.invalidate()
        killTimer = nil
    }

    @objc private func appLaunched(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              let s = session else { return }
        checkAndKill(app, session: s)
    }

    private func killBlockedApps(_ s: BlockSession) {
        for app in NSWorkspace.shared.runningApplications {
            checkAndKill(app, session: s)
        }
    }

    // MARK: - Browser permission priming

    private struct Browser {
        let name: String
        let bundleID: String
        let isSafari: Bool
    }

    private let knownBrowsers: [Browser] = [
        Browser(name: "Safari",         bundleID: "com.apple.Safari",              isSafari: true),
        Browser(name: "Google Chrome",  bundleID: "com.google.Chrome",             isSafari: false),
        Browser(name: "Arc",            bundleID: "company.thebrowser.Browser",    isSafari: false),
        Browser(name: "Brave Browser",  bundleID: "com.brave.Browser",             isSafari: false),
        Browser(name: "Microsoft Edge", bundleID: "com.microsoft.edgemac",         isSafari: false),
        Browser(name: "Firefox",        bundleID: "org.mozilla.firefox",           isSafari: false),
    ]

    private var primedBrowserIDs: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: "primedBrowserIDs") ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: "primedBrowserIDs") }
    }

    @Published var primedBrowserCount: Int = UserDefaults.standard
        .stringArray(forKey: "primedBrowserIDs").map(\.count) ?? 0

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
            self.primedBrowserIDs = primed
            DispatchQueue.main.async {
                self.primedBrowserCount = primed.count
                completion()
            }
        }
    }

    // MARK: - Tab reload (session start)

    private func reloadBrowserTabs() {
        let primed = primedBrowserIDs
        // Skip entirely if no browsers have been primed — avoids any surprise TCC dialogs
        // appearing mid-session. Users prime browsers once via onboarding or Config.
        guard !primed.isEmpty else { return }

        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 1.0) {
            for b in self.knownBrowsers where primed.contains(b.bundleID) {
                if b.isSafari { self.runSafariReload() }
                else          { self.runChromiumReload(b.name) }
            }
        }
    }

    private func runSafariReload() {
        let script = """
        if application "Safari" is running then
            tell application "Safari"
                repeat with w in windows
                    repeat with t in tabs of w
                        try
                            set URL of t to URL of t
                        end try
                    end repeat
                end repeat
            end tell
        end if
        """
        var err: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&err)
        if let err { NSLog("ScreenBlocker: Safari reload error: %@", err) }
    }

    private func runChromiumReload(_ browser: String) {
        let script = """
        if application "\(browser)" is running then
            tell application "\(browser)"
                repeat with w in windows
                    repeat with t in tabs of w
                        try
                            reload t
                        end try
                    end repeat
                end repeat
            end tell
        end if
        """
        var err: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&err)
        if let err { NSLog("ScreenBlocker: %@ reload error: %@", browser, err) }
    }

    private func checkAndKill(_ app: NSRunningApplication, session s: BlockSession) {
        let blocked = Set(s.blockedApps.map { $0.lowercased() })
        guard !blocked.isEmpty else { return }
        let name = (app.localizedName ?? "").lowercased()
        if blocked.contains(name) {
            app.forceTerminate()
        }
    }
}
