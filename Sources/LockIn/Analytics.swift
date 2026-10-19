import Foundation
import os

/// Anonymous usage events, sent to PostHog's capture API (no SDK). Each event carries a random
/// install ID made on first launch and tied to nothing else, the app and macOS versions, and
/// the event's own properties. Nothing the user writes, records or browses is ever sent.
///
/// Builds run from `.build/`, `dist/` or DerivedData send nothing, and setting the `shareUsageCounts`
/// default to false turns it off for good. `LOCKIN_ANALYTICS_HOST=http://127.0.0.1:PORT` sends
/// from any build to that host instead, to check events without touching the real project.
enum Analytics {
    static let enabledKey = "shareUsageCounts"
    /// `defaults write -g loadcpuNoAnalytics -bool true` keeps a whole Mac out of the stats, for
    /// every loadcpu app and build at once (the developer's own machines).
    private static let machineOptOutKey = "loadcpuNoAnalytics"
    /// The same key and host in every loadcpu app, so one PostHog project sees all of them;
    /// the `app` property tells them apart.
    private static let apiKey = "phc_puj7kPBWnDaxRUv3dvcySXpPbqA93QWjoXBZU5wCRmi8"
    private static let host = ProcessInfo.processInfo.environment["LOCKIN_ANALYTICS_HOST"]
        ?? "https://eu.i.posthog.com"
    private static let app = "lockin"
    private static let installIDKey = "analyticsInstallID"
    private static let lastVersionKey = "analyticsLastVersion"
    /// Settings that copies from before analytics already wrote, so a first event from one of
    /// them is an update rather than a new install.
    private static let earlierInstallKeys = ["appUpdateLastCheck", "helperInstalled_v8", "helperInstalled_v9", "primedBrowserIDs"]
    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "lockin", category: "analytics")

    static var isAvailable: Bool {
        guard !apiKey.contains("REPLACE") else { return false }
        if ProcessInfo.processInfo.environment["LOCKIN_ANALYTICS_HOST"] != nil { return true }
        guard !UserDefaults.standard.bool(forKey: machineOptOutKey) else { return false }
        let path = Bundle.main.bundlePath
        return path.hasSuffix(".app")
            && !["/.build/", "/dist/", "/DerivedData/"].contains { path.contains($0) }
    }

    /// `app_installed` on the very first launch, `app_updated` when the version differs from
    /// the last launch, then `app_launched` every time. Call it before anything else at launch
    /// writes to UserDefaults, so a fresh install still looks fresh.
    static func appDidLaunch() {
        guard isAvailable else { return }
        let defaults = UserDefaults.standard
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        let previous = defaults.string(forKey: lastVersionKey)
        if defaults.string(forKey: installIDKey) == nil {
            if earlierInstallKeys.contains(where: { defaults.object(forKey: $0) != nil }) {
                capture("app_updated", ["from_version": "unknown"])
            } else {
                capture("app_installed")
            }
        } else if let previous, previous != version {
            capture("app_updated", ["from_version": previous])
        }
        defaults.set(version, forKey: lastVersionKey)
        capture("app_launched")
    }

    static func capture(_ event: String, _ properties: [String: Any] = [:]) {
        // bool(forKey:) also reads "NO" and 0, e.g. from `defaults write … shareUsageCounts NO`.
        let defaults = UserDefaults.standard
        guard isAvailable, defaults.object(forKey: enabledKey) == nil || defaults.bool(forKey: enabledKey),
              let url = URL(string: "\(host)/i/v0/e/")
        else { return }
        let info = Bundle.main.infoDictionary ?? [:]
        let os = ProcessInfo.processInfo.operatingSystemVersion
        var props: [String: Any] = [
            "app": app,
            "app_version": info["CFBundleShortVersionString"] as? String ?? "",
            "app_build": info["CFBundleVersion"] as? String ?? "",
            "$os": "macOS",
            "$os_version": "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)",
            "$lib": "loadcpu-swift",
        ]
        props.merge(properties) { _, new in new }
        let body: [String: Any] = [
            "api_key": apiKey,
            "event": event,
            "distinct_id": installID,
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "properties": props,
        ]
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        URLSession.shared.dataTask(with: request) { _, response, error in
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if error != nil || status != 200 {
                log.notice("Analytics \(event, privacy: .public) not sent: status \(status) \(error?.localizedDescription ?? "", privacy: .public)")
            }
        }.resume()
    }

    private static var installID: String {
        let defaults = UserDefaults.standard
        if let id = defaults.string(forKey: installIDKey) { return id }
        let id = UUID().uuidString
        defaults.set(id, forKey: installIDKey)
        return id
    }
}
