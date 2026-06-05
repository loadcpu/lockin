import AppKit
import Foundation

final class BrowserWatcher {
    static let shared = BrowserWatcher()

    var onDomainChanged: ((String?) -> Void)?

    private var pollTimer: Timer?
    private(set) var currentDomain: String?
    private var lastDomain: String?
    private var scriptCache: [String: NSAppleScript] = [:]

    static let bundleIDs: Set<String> = [
        "com.apple.Safari",
        "com.google.Chrome",
        "company.thebrowser.Browser",   // Arc
        "com.brave.Browser",
        "com.microsoft.edgemac",
        "org.mozilla.firefox",
    ]

    static func isBrowser(_ bundleID: String) -> Bool {
        bundleIDs.contains(bundleID)
    }

    private init() {}

    func start() {
        pollTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            DispatchQueue.global(qos: .utility).async { self?.poll() }
        }
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    // MARK: - Polling

    private func poll() {
        guard let front = NSWorkspace.shared.frontmostApplication,
              let bundleID = front.bundleIdentifier,
              Self.isBrowser(bundleID),
              BlockerService.shared.primedBrowserIDs.contains(bundleID)
        else {
            maybeFireCallback(nil)
            return
        }
        let appName = front.localizedName ?? ""
        let urlString = bundleID == "com.apple.Safari" ? querySafari() : queryChromium(appName)
        let domain = urlString.flatMap { extractDomain($0) }
        maybeFireCallback(domain)
    }

    private func maybeFireCallback(_ domain: String?) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard domain != self.lastDomain else { return }
            self.lastDomain = domain
            self.currentDomain = domain
            self.onDomainChanged?(domain)
        }
    }

    // MARK: - AppleScript helpers

    private func script(for key: String, source: () -> String) -> NSAppleScript? {
        if let cached = scriptCache[key] { return cached }
        guard let s = NSAppleScript(source: source()) else { return nil }
        scriptCache[key] = s
        return s
    }

    private func querySafari() -> String? {
        let s = script(for: "Safari") {
            """
            tell application "Safari"
                if (count of windows) > 0 then
                    return URL of current tab of front window
                end if
            end tell
            """
        }
        var err: NSDictionary?
        let result = s?.executeAndReturnError(&err)
        guard err == nil else { return nil }
        return result?.stringValue
    }

    private func queryChromium(_ appName: String) -> String? {
        let s = script(for: appName) {
            """
            tell application "\(appName)"
                if (count of windows) > 0 then
                    return URL of active tab of front window
                end if
            end tell
            """
        }
        var err: NSDictionary?
        let result = s?.executeAndReturnError(&err)
        guard err == nil else { return nil }
        return result?.stringValue
    }

    // MARK: - Domain extraction

    private func extractDomain(_ urlString: String) -> String? {
        guard let url = URL(string: urlString), let host = url.host else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}
