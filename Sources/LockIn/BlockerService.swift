import AppKit
import Foundation
import Combine
import ImageIO
import UserNotifications

final class BlockerService: ObservableObject {
    static let shared = BlockerService()
    private static let blockPageLogoURL = makeBlockPageLogoDataURL()

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
    private let websiteBlockQueue = DispatchQueue(label: "com.loadcpu.lockin.website-blocks", qos: .utility)
    private var browserWatcherListenerID: UUID?
    private var automationPermissionAlertsInFlight: Set<String> = []

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
        HelperInstaller.syncLaunchAgent(shouldExist: true)
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

    var countdownClockString: String {
        let totalSeconds = max(0, remainingSeconds)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        }

        return String(format: "%02d:%02d", minutes, seconds)
    }

    var sessionProgress: Double {
        sessionProgress(at: Date())
    }

    func sessionProgress(at date: Date) -> Double {
        guard let session else { return 0 }
        let totalDuration = session.endTime.timeIntervalSince(session.startTime)
        guard totalDuration > 0 else { return 1 }

        let elapsed = date.timeIntervalSince(session.startTime)
        return min(max(elapsed / totalDuration, 0), 1)
    }

    var sessionEndDate: Date? {
        session?.endTime
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
        HelperInstaller.syncLaunchAgent(shouldExist: false)
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
        killTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.killBlockedApps()
            self?.interruptBlockedTabsInRunningBrowsers()
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
        let websites = Array(sessionWebsites.union(limitBlockedWebsites))

        if blockedAppNames.isEmpty && websites.isEmpty {
            stopMonitoring()
        } else {
            startMonitoring()
            killBlockedApps()
        }

        websiteBlockQueue.async { [weak self] in
            if websites.isEmpty {
                HostsManager.removeBlocks()
            } else if HostsManager.applyBlocks(domains: websites), shouldReload {
                self?.interruptBlockedTabsInRunningBrowsers()
            }
        }
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
        return blockedWebsites.contains { DomainMatcher.matches(host: normalizedDomain, blockedDomain: $0) }
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

    func recordBrowserAutomationSuccess(bundleID: String) {
        DispatchQueue.main.async {
            guard self.knownBrowsers.contains(where: { $0.bundleID == bundleID }) else { return }
            guard !self.primedBrowserIDs.contains(bundleID) else { return }
            self.primedBrowserIDs.insert(bundleID)
        }
    }

    func handleBrowserAutomationPermissionDenied(bundleID: String) {
        DispatchQueue.main.async {
            guard let browser = self.knownBrowsers.first(where: { $0.bundleID == bundleID }) else { return }
            if self.primedBrowserIDs.contains(bundleID) {
                self.primedBrowserIDs.remove(bundleID)
            }
            guard !self.automationPermissionAlertsInFlight.contains(bundleID) else { return }

            self.automationPermissionAlertsInFlight.insert(bundleID)
            self.presentBrowserAutomationAlert(for: browser)
        }
    }

    func presentBrowserPermissionSetupAlert() {
        let alert = NSAlert()
        alert.messageText = "Grant Browser Permissions"
        alert.informativeText = "Open the browsers you use, then click Continue so macOS can ask for Automation access. If you already denied access, open System Settings → Privacy & Security → Automation."
        alert.addButton(withTitle: "Continue")
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")
        prepareAlertForForeground(alert)

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            primeBrowserPermissions()
        } else if response == .alertSecondButtonReturn {
            openAutomationSystemSettings()
        }
    }

    func presentBrowserPermissionDeniedAlert(bundleIDs: [String]) {
        let browserList = bundleIDs
            .map(browserName(forBundleID:))
            .joined(separator: ", ")

        let alert = NSAlert()
        alert.messageText = "Permission Not Granted"
        alert.informativeText = "\(browserList) still need Automation access for website stats and instant blocking. Open System Settings → Privacy & Security → Automation to enable Lock In."
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "OK")
        prepareAlertForForeground(alert)
        if alert.runModal() == .alertFirstButtonReturn {
            openAutomationSystemSettings()
        }
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
        primeBrowserPermissions(bundleIDs: nil, completion: completion)
    }

    func primeBrowserPermissions(bundleIDs: [String]?, completion: @escaping () -> Void = {}) {
        DispatchQueue.global(qos: .userInitiated).async {
            var primed = self.primedBrowserIDs
            for b in self.knownBrowsers {
                if let bundleIDs, !bundleIDs.contains(b.bundleID) { continue }
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

    private func presentBrowserAutomationAlert(for browser: Browser) {
        let alert = NSAlert()
        alert.messageText = "Allow \(browser.name)"
        alert.informativeText = "Allow Lock In to read tabs in \(browser.name) for website stats and blocking."
        alert.addButton(withTitle: "Try Again")
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Not Now")
        prepareAlertForForeground(alert)

        let response = alert.runModal()
        automationPermissionAlertsInFlight.remove(browser.bundleID)

        if response == .alertFirstButtonReturn {
            primeBrowserPermissions(bundleIDs: [browser.bundleID])
        } else if response == .alertSecondButtonReturn {
            openAutomationSystemSettings()
        }
    }

    private func prepareAlertForForeground(_ alert: NSAlert) {
        NSApp.activate(ignoringOtherApps: true)
        let window = alert.window
        window.level = .modalPanel
        window.collectionBehavior.insert(.moveToActiveSpace)
        window.center()
        window.orderFrontRegardless()
        window.makeKey()
    }

    private func openAutomationSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Browser enforcement

    private enum BrowserWindowQueryResult {
        case windows([(index: Int, domain: String)])
        case noWindows
        case failed
    }

    private func interruptBlockedTabsInRunningBrowsers() {
        for browser in knownBrowsers {
            guard NSRunningApplication.runningApplications(withBundleIdentifier: browser.bundleID).first != nil else { continue }

            switch currentDomainsByWindow(in: browser) {
            case .windows(let windows):
                let blockedWindows = windows.filter { matchesBlockedWebsite($0.domain) }
                guard !blockedWindows.isEmpty else { continue }
                var failedToInterrupt = false
                for window in blockedWindows {
                    if !interruptBlockedTab(in: browser, windowIndex: window.index, domain: window.domain) {
                        failedToInterrupt = true
                        break
                    }
                }
                if failedToInterrupt, isBlocking {
                    _ = forceQuitBrowsers(bundleIDs: [browser.bundleID])
                    notifyBrowserForceQuit(browser.name)
                }
            case .noWindows:
                continue
            case .failed:
                if isBlocking {
                    _ = forceQuitBrowsers(bundleIDs: [browser.bundleID])
                    notifyBrowserForceQuit(browser.name)
                }
            }
        }

        BrowserWatcher.shared.refreshNow()
    }

    private func currentDomainsByWindow(in browser: Browser) -> BrowserWindowQueryResult {
        let script: String
        if browser.isSafari {
            script = """
            if application "\(browser.name)" is running then
                tell application "\(browser.name)"
                    set output to {}
                    repeat with i from 1 to count of windows
                        set windowURL to URL of current tab of window i
                        if windowURL is not missing value then set end of output to (i as string) & "|" & windowURL
                    end repeat
                    set AppleScript's text item delimiters to linefeed
                    set joinedOutput to output as string
                    set AppleScript's text item delimiters to ""
                    return joinedOutput
                end tell
            end if
            """
        } else {
            script = """
            if application "\(browser.name)" is running then
                tell application "\(browser.name)"
                    set output to {}
                    repeat with i from 1 to count of windows
                        set windowURL to URL of active tab of window i
                        if windowURL is not missing value then set end of output to (i as string) & "|" & windowURL
                    end repeat
                    set AppleScript's text item delimiters to linefeed
                    set joinedOutput to output as string
                    set AppleScript's text item delimiters to ""
                    return joinedOutput
                end tell
            end if
            """
        }

        var err: NSDictionary?
        let result = NSAppleScript(source: script)?.executeAndReturnError(&err)
        if let err {
            NSLog("LockIn: %@ window-tab query error: %@", browser.name, err)
            return .failed
        }

        guard let output = result?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              !output.isEmpty else {
            return .noWindows
        }

        let windows = output
            .components(separatedBy: .newlines)
            .compactMap { entry -> (index: Int, domain: String)? in
                let parts = entry.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
                guard parts.count == 2,
                      let index = Int(parts[0]),
                      let host = URL(string: String(parts[1]))?.host,
                      let domain = DomainMatcher.normalizeHost(host) else {
                    return nil
                }
                return (index, domain)
            }

        return windows.isEmpty ? .noWindows : .windows(windows)
    }

    private func notifyBrowserForceQuit(_ browserName: String) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized else { return }
            let content = UNMutableNotificationContent()
            content.title = "Browser closed during session"
            content.body = "\(browserName) was closed. Click to enable Automation for Lock In."
            let request = UNNotificationRequest(identifier: "browser-force-quit-\(browserName)", content: content, trigger: nil)
            UNUserNotificationCenter.current().add(request) { error in
                if let error { NSLog("LockIn: browser-force-quit notification failed: %@", error.localizedDescription) }
            }
        }
    }

    @discardableResult
    private func interruptBlockedCurrentTab(in browser: Browser, domain: String) -> Bool {
        interruptBlockedTab(in: browser, windowIndex: nil, domain: domain)
    }

    @discardableResult
    private func interruptBlockedTab(in browser: Browser, windowIndex: Int?, domain: String) -> Bool {
        let replacementURL = blockPageURL(for: domain)
        let script: String
        let windowReference = windowIndex.map { "window \($0)" } ?? "front window"
        if browser.isSafari {
            script = """
            if application "\(browser.name)" is running then
                tell application "\(browser.name)"
                    if (count of windows) > 0 then
                        set URL of current tab of \(windowReference) to "\(replacementURL)"
                    end if
                end tell
            end if
            """
        } else {
            script = """
            if application "\(browser.name)" is running then
                tell application "\(browser.name)"
                    if (count of windows) > 0 then
                        set URL of active tab of \(windowReference) to "\(replacementURL)"
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
            logoMarkup = ""
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
}
