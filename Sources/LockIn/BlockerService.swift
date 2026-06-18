import AppKit
import Foundation
import Combine
import ImageIO
import UserNotifications

final class BlockerService: ObservableObject {
    static let shared = BlockerService()
    private static let blockPageLogoURL = makeBlockPageLogoDataURL()
    private static let relatedWebsiteDomains: [String: Set<String>] = [
        "instagram.com": [
            "instagram.com",
            "www.instagram.com",
            "i.instagram.com",
            "api.instagram.com",
            "graph.instagram.com",
            "help.instagram.com",
            "cdninstagram.com",
            "scontent.cdninstagram.com",
            "fbcdn.net",
            "instagram.fiev1-1.fna.fbcdn.net",
        ],
    ]

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
    private var lastWebsiteRefreshAt: Date = .distantPast
    private var cachedExpandedBlockedHosts: Set<String> = []
    private var browserWatcherListenerID: UUID?

    private init() {
        browserWatcherListenerID = BrowserWatcher.shared.addListener { [weak self] domain, bundleID in
            self?.handleBrowserDomainChange(domain: domain, bundleID: bundleID)
        }
    }

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
        refreshWebsiteBlocksIfNeeded()
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
        let newWebsites = Set(websites.compactMap(DomainMatcher.normalizeHost))
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
        let sessionWebsites = Set((session?.blockedWebsites ?? []).compactMap(DomainMatcher.normalizeHost))
        blockedAppNames = sessionApps.union(limitBlockedApps)

        if blockedAppNames.isEmpty {
            stopMonitoring()
        } else {
            startMonitoring()
            killBlockedApps()
        }

        let websites = Array(sessionWebsites.union(limitBlockedWebsites))
        let currentDomain = BrowserWatcher.shared.currentDomain
        lastWebsiteRefreshAt = Date()
        websiteBlockQueue.async { [weak self] in
            guard let self else { return }
            let expanded = Set(self.expandedBlockedWebsiteHosts(from: websites, currentDomain: currentDomain))
            self.cachedExpandedBlockedHosts = expanded

            let sortedHosts = expanded.sorted()
            if websites.isEmpty {
                HostsManager.removeBlocks()
            } else if HostsManager.applyBlocks(domains: sortedHosts), shouldReload {
                self.reloadBrowserTabs(blockedHosts: sortedHosts)
            }
        }
    }

    private func refreshWebsiteBlocksIfNeeded() {
        guard Date().timeIntervalSince(lastWebsiteRefreshAt) >= 30 else { return }
        refreshEffectiveBlocks(reloadBrowserTabs: false)
    }

    private func handleBrowserDomainChange(domain: String?, bundleID: String?) {
        guard let domain, let bundleID else { return }
        guard isBlocking || hasLimitRestrictions else { return }
        guard let browser = knownBrowsers.first(where: { $0.bundleID == bundleID }) else { return }
        guard matchesBlockedWebsite(domain) else { return }
        _ = interruptBlockedCurrentTab(in: browser, domain: domain)
    }

    private func matchesBlockedWebsite(_ domain: String) -> Bool {
        guard let normalizedDomain = DomainMatcher.normalizeHost(domain) else { return false }

        let blockedWebsites = Set((session?.blockedWebsites ?? []).compactMap(DomainMatcher.normalizeHost))
            .union(limitBlockedWebsites)
        guard !blockedWebsites.isEmpty else { return false }

        let expanded = websiteBlockQueue.sync { cachedExpandedBlockedHosts }
        if expanded.isEmpty {
            return blockedWebsites.contains { DomainMatcher.matches(host: normalizedDomain, blockedDomain: $0) }
        }
        return expanded.contains { DomainMatcher.matches(host: normalizedDomain, blockedDomain: $0) }
    }

    private func expandedBlockedWebsiteHosts(from websites: [String], currentDomain: String?) -> [String] {
        var hosts = Set(websites.compactMap(DomainMatcher.normalizeHost))
        guard !hosts.isEmpty else { return [] }

        for domain in Array(hosts) {
            let related = Self.relatedWebsiteDomains[domain] ?? []
            hosts.formUnion(related.compactMap(DomainMatcher.normalizeHost))
        }

        var observedHosts = Set(
            ActivityStore.shared
                .topApps(forDays: 7, limit: 500)
                .compactMap(\.domain)
                .compactMap(DomainMatcher.normalizeHost)
        )
        if let currentDomain = currentDomain.flatMap(DomainMatcher.normalizeHost) {
            observedHosts.insert(currentDomain)
        }

        for host in observedHosts {
            if hosts.contains(where: { DomainMatcher.matches(host: host, blockedDomain: $0) }) {
                hosts.insert(host)
            }
        }

        return hosts.sorted()
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

    // MARK: - Tab replacement (session start)

    private func reloadBrowserTabs(blockedHosts: [String]) {
        guard !blockedHosts.isEmpty else { return }

        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.25) {
            for b in self.knownBrowsers {
                guard NSRunningApplication.runningApplications(withBundleIdentifier: b.bundleID).first != nil else { continue }
                let replacedCount = self.replaceBlockedTabs(in: b, blockedHosts: blockedHosts)
                if replacedCount > 0 {
                    NSLog("LockIn: %@ replaced %d blocked tabs", b.name, replacedCount)
                }
            }
        }
    }

    @discardableResult
    private func interruptBlockedCurrentTab(in browser: Browser, domain: String) -> Bool {
        let replacementURL = blockPageURL(for: domain)
        let script: String
        if browser.isSafari {
            script = """
            if application "\(browser.name)" is running then
                tell application "\(browser.name)"
                    if (count of windows) > 0 then
                        set URL of current tab of front window to "\(replacementURL)"
                    end if
                end tell
            end if
            """
        } else {
            script = """
            if application "\(browser.name)" is running then
                tell application "\(browser.name)"
                    if (count of windows) > 0 then
                        set URL of active tab of front window to "\(replacementURL)"
                    end if
                end tell
            end if
            """
        }

        var err: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&err)
        if let err {
            NSLog("LockIn: %@ blocked-site interrupt error for %@: %@", browser.name, domain, err)
        }
        return err == nil
    }

    @discardableResult
    private func replaceBlockedTabs(in browser: Browser, blockedHosts: [String]) -> Int {
        let targets = browserTabTargets(in: browser, blockedHosts: blockedHosts)
        guard !targets.isEmpty else { return 0 }

        let groupedTargets = Dictionary(grouping: targets, by: \.windowIndex)
        let replacementURL = blockPageURL(for: nil)
        var commands: [String] = []
        for windowIndex in groupedTargets.keys.sorted() {
            for target in groupedTargets[windowIndex, default: []].sorted(by: { $0.tabIndex < $1.tabIndex }) {
                commands.append("""
                        try
                            set URL of tab \(target.tabIndex) of window \(windowIndex) to "\(replacementURL)"
                        end try
                """)
            }
        }

        let script = """
        if application "\(browser.name)" is running then
            tell application "\(browser.name)"
        \(commands.joined(separator: "\n"))
            end tell
        end if
        """
        var err: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&err)
        if let err {
            NSLog("LockIn: %@ blocked-tab replacement error: %@", browser.name, err)
            return 0
        }
        return targets.count
    }

    private func browserTabTargets(in browser: Browser, blockedHosts: [String]) -> [BrowserTabTarget] {
        let script = """
        set outputLines to {}
        if application "\(browser.name)" is running then
            tell application "\(browser.name)"
                repeat with wIndex from 1 to (count of windows)
                    repeat with tIndex from 1 to (count of tabs of window wIndex)
                        try
                            set end of outputLines to (wIndex as text) & tab & (tIndex as text) & tab & (URL of tab tIndex of window wIndex)
                        end try
                    end repeat
                end repeat
            end tell
        end if
        set AppleScript's text item delimiters to linefeed
        return outputLines as text
        """

        var err: NSDictionary?
        let result = NSAppleScript(source: script)?.executeAndReturnError(&err)
        if let err {
            NSLog("LockIn: %@ tab query error: %@", browser.name, err)
            return []
        }

        let lines = result?.stringValue?
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init) ?? []

        return lines.compactMap { line in
            let parts = line.components(separatedBy: "\t")
            guard parts.count >= 3,
                  let windowIndex = Int(parts[0]),
                  let tabIndex = Int(parts[1]),
                  let host = URL(string: parts[2])?.host,
                  blockedHosts.contains(where: { DomainMatcher.matches(host: host, blockedDomain: $0) }) else {
                return nil
            }
            return BrowserTabTarget(windowIndex: windowIndex, tabIndex: tabIndex)
        }
    }

    private func blockPageURL(for domain: String?) -> String {
        let html = blockPageHTML(for: domain)
        let base64HTML = Data(html.utf8).base64EncodedString()
        return "data:text/html;charset=utf-8;base64,\(base64HTML)"
    }

    private func blockPageHTML(for domain: String?) -> String {
        let message: String
        if let domain {
            message = "\(htmlEscaped(domain)) is blocked right now."
        } else {
            message = "This website is blocked right now."
        }
        let logoMarkup: String
        if let logoURL = Self.blockPageLogoURL {
            logoMarkup = #"<img class="brand-logo" src="\#(logoURL)" alt="Lock In logo">"#
        } else {
            logoMarkup = """
            <span class="brand-mark" aria-hidden="true">
                <svg viewBox="0 0 24 24">
                    <path d="M13.8 2 6.7 13.1h4.5L10.2 22l7.1-11.1h-4.5z"/>
                </svg>
            </span>
            """
        }

        return """
        <!doctype html>
        <html lang="en">
        <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <title>Lock In</title>
            <style>
                :root { color-scheme: light; }
                * { box-sizing: border-box; }
                body {
                    margin: 0;
                    min-height: 100vh;
                    display: grid;
                    place-items: center;
                    padding: 32px;
                    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
                    background: #ffffff;
                    color: #1d1d1f;
                }
                main {
                    width: min(760px, 100%);
                    padding: 36px 40px;
                    border-radius: 24px;
                    background: #f7f7f9;
                    border: 1px solid #ececf1;
                    box-shadow: 0 12px 30px rgba(17, 24, 39, 0.08);
                }
                .brand {
                    display: inline-flex;
                    align-items: center;
                    gap: 12px;
                    margin-bottom: 28px;
                    color: #000000;
                    font-size: 15px;
                    font-weight: 700;
                    letter-spacing: 0.08em;
                    text-transform: uppercase;
                }
                .brand-mark {
                    width: 34px;
                    height: 34px;
                    border-radius: 10px;
                    background: linear-gradient(180deg, #f6dec0 0%, #efcfaa 100%);
                    display: grid;
                    place-items: center;
                    box-shadow: inset 0 1px 0 rgba(255,255,255,0.55);
                }
                .brand-mark svg {
                    width: 18px;
                    height: 18px;
                    fill: #7a4d26;
                }
                .brand-logo {
                    width: 34px;
                    height: 34px;
                    border-radius: 10px;
                    display: block;
                }
                h1 {
                    margin: 0 0 16px;
                    font-size: clamp(30px, 5vw, 42px);
                    line-height: 1.05;
                }
                p {
                    margin: 0;
                    font-size: 17px;
                    line-height: 1.55;
                    color: #4f4438;
                }
            </style>
        </head>
        <body>
            <main>
                <div class="brand">
                    \(logoMarkup)
                    <span>Lock In</span>
                </div>
                <h1>Stay on task.</h1>
                <p>\(message)</p>
            </main>
        </body>
        </html>
        """
    }

    private func htmlEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    private static func makeBlockPageLogoDataURL() -> String? {
        guard let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
              let imageSource = CGImageSourceCreateWithURL(iconURL as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(imageSource, 0, nil),
              let destinationData = CFDataCreateMutable(nil, 0),
              let destination = CGImageDestinationCreateWithData(destinationData, "public.png" as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        let pngData = destinationData as Data
        return "data:image/png;base64,\(pngData.base64EncodedString())"
    }

    private struct BrowserTabTarget {
        let windowIndex: Int
        let tabIndex: Int
    }
}
