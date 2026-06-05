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
                HostsManager.applyBlocks(domains: s.blockedWebsites)
                session = s
                isBlocking = true
                remainingSeconds = s.remainingSeconds
                startMonitoring()
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

    // Applies web blocks first (shows password dialog), then starts the session
    // so the endTime is measured from after the dialog, not before.
    func startSession(minutes: Int) {
        if !config.blockedWebsites.isEmpty {
            guard HostsManager.applyBlocks(domains: config.blockedWebsites) else { return }
            reloadBrowserTabs()
        }
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

    private func reloadBrowserTabs() {
        let script = """
        repeat with browserName in {"Safari", "Google Chrome", "Firefox", "Arc", "Brave Browser", "Microsoft Edge"}
            if application browserName is running then
                if browserName is "Safari" then
                    tell application "Safari"
                        repeat with w in windows
                            repeat with t in tabs of w
                                set URL of t to URL of t
                            end repeat
                        end repeat
                    end tell
                else
                    tell application browserName
                        repeat with w in windows
                            repeat with t in tabs of w
                                reload t
                            end repeat
                        end repeat
                    end tell
                end if
            end if
        end repeat
        """
        var err: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&err)
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
