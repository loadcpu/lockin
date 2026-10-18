import Foundation

/// Anonymous usage events, sent to PostHog's capture API (no SDK). Each event carries a random
/// install ID made on first launch and tied to nothing else, the app and macOS versions, and
/// the event's own properties. Nothing the user writes, records or browses is ever sent.
///
/// Builds run from `.build/` or DerivedData send nothing, and setting the `shareUsageCounts`
/// default to false turns it off for good.
enum Analytics {
    static let enabledKey = "shareUsageCounts"
    /// The same key and host in every loadcpu app, so one PostHog project sees all of them;
    /// the `app` property tells them apart.
    private static let apiKey = "phc_puj7kPBWnDaxRUv3dvcySXpPbqA93QWjoXBZU5wCRmi8"
    private static let host = "https://eu.i.posthog.com"
    private static let app = "lockin"
    private static let installIDKey = "analyticsInstallID"

    static var isAvailable: Bool {
        guard !apiKey.contains("REPLACE") else { return false }
        let path = Bundle.main.bundlePath
        return path.hasSuffix(".app") && !path.contains("/.build/") && !path.contains("/DerivedData/")
    }

    static func capture(_ event: String, _ properties: [String: Any] = [:]) {
        guard isAvailable, UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true,
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
        URLSession.shared.dataTask(with: request).resume()
    }

    private static var installID: String {
        let defaults = UserDefaults.standard
        if let id = defaults.string(forKey: installIDKey) { return id }
        let id = UUID().uuidString
        defaults.set(id, forKey: installIDKey)
        return id
    }
}
