import AppKit
import Foundation

final class BrowserWatcher {
    static let shared = BrowserWatcher()
    private let pollInterval: TimeInterval = 1.0

    private var pollTimer: Timer?
    private(set) var currentDomain: String?
    private(set) var currentBrowserBundleID: String?
    private var lastDomain: String?
    private var lastBrowserBundleID: String?
    private var scriptCache: [String: NSAppleScript] = [:]
    private var listeners: [UUID: (String?, String?) -> Void] = [:]
    private let pollLock = NSLock()
    private var isPolling = false

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
        guard pollTimer == nil else { return }
        refreshNow()
        pollTimer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            self?.refreshNow()
        }
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    func refreshNow() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.poll()
        }
    }

    @discardableResult
    func addListener(_ listener: @escaping (String?, String?) -> Void) -> UUID {
        let id = UUID()
        listeners[id] = listener
        return id
    }

    func removeListener(_ id: UUID) {
        listeners.removeValue(forKey: id)
    }

    // MARK: - Polling

    private func poll() {
        pollLock.lock()
        if isPolling {
            pollLock.unlock()
            return
        }
        isPolling = true
        pollLock.unlock()
        defer {
            pollLock.lock()
            isPolling = false
            pollLock.unlock()
        }

        guard let front = NSWorkspace.shared.frontmostApplication,
              let bundleID = front.bundleIdentifier,
              Self.isBrowser(bundleID)
        else {
            maybeFireCallback(domain: nil, bundleID: nil)
            return
        }
        let appName = front.localizedName ?? ""
        let urlString = bundleID == "com.apple.Safari" ? querySafari() : queryChromium(appName)
        let domain = urlString.flatMap { extractDomain($0) }
        maybeFireCallback(domain: domain, bundleID: bundleID)
    }

    private func maybeFireCallback(domain: String?, bundleID: String?) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard domain != self.lastDomain || bundleID != self.lastBrowserBundleID else { return }
            self.lastDomain = domain
            self.lastBrowserBundleID = bundleID
            self.currentDomain = domain
            self.currentBrowserBundleID = bundleID
            for listener in self.listeners.values {
                listener(domain, bundleID)
            }
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
        return DomainMatcher.normalizeHost(host)
    }
}
