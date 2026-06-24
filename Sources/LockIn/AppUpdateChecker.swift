import AppKit
import Combine
import Foundation

final class AppUpdateChecker: ObservableObject {
    static let shared = AppUpdateChecker()

    @Published private(set) var latestVersion: String?
    @Published private(set) var downloadURL: URL?
    @Published private(set) var isChecking = false

    private let session: URLSession
    private let latestReleaseAPI = URL(string: "https://api.github.com/repos/loadcpu/lockin/releases/latest")!
    private let latestReleasePage = URL(string: "https://github.com/loadcpu/lockin/releases/latest")!
    private let lastCheckKey = "appUpdateLastCheck"
    private let checkInterval: TimeInterval = 60 * 60 * 12

    private init(session: URLSession = .shared) {
        self.session = session
    }

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    var isUpdateAvailable: Bool {
        guard let latestVersion else { return false }
        return Self.compareVersions(latestVersion, currentVersion) == .orderedDescending
    }

    var updateButtonTitle: String {
        isUpdateAvailable ? "Download Update" : "Check for Updates…"
    }

    func checkForUpdatesIfNeeded() {
        let lastCheck = UserDefaults.standard.object(forKey: lastCheckKey) as? Date
        if let lastCheck, Date().timeIntervalSince(lastCheck) < checkInterval {
            return
        }

        checkForUpdates(userInitiated: false)
    }

    func checkForUpdates(userInitiated: Bool) {
        guard !isChecking else { return }

        isChecking = true
        let request = URLRequest(url: latestReleaseAPI, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)

        session.dataTask(with: request) { [weak self] data, _, error in
            guard let self else { return }

            if let error {
                DispatchQueue.main.async {
                    self.isChecking = false
                    if userInitiated {
                        self.presentAlert(
                            title: "Update Check Failed",
                            message: "Lock In could not reach GitHub right now.\n\n\(error.localizedDescription)"
                        )
                    }
                }
                return
            }

            guard let data else {
                DispatchQueue.main.async {
                    self.isChecking = false
                    if userInitiated {
                        self.presentAlert(
                            title: "Update Check Failed",
                            message: "GitHub returned an empty response."
                        )
                    }
                }
                return
            }

            do {
                let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
                let version = Self.normalizeVersion(release.tagName)
                let zipURL = release.assets.first(where: Self.isPreferredZipAsset)?.browserDownloadURL

                DispatchQueue.main.async {
                    self.latestVersion = version
                    self.downloadURL = zipURL ?? release.htmlURL
                    self.isChecking = false
                    UserDefaults.standard.set(Date(), forKey: self.lastCheckKey)

                    guard userInitiated else { return }

                    if self.isUpdateAvailable {
                        let alert = NSAlert()
                        alert.messageText = "Update Available"
                        alert.informativeText = "Lock In \(version) is available. You’re currently on \(self.currentVersion)."
                        alert.addButton(withTitle: "Download Update")
                        alert.addButton(withTitle: "Later")
                        self.prepareAlertForForeground(alert)
                        if alert.runModal() == .alertFirstButtonReturn {
                            self.openDownloadPage()
                        }
                    } else {
                        self.presentAlert(
                            title: "You’re Up to Date",
                            message: "Lock In \(self.currentVersion) is the latest available version."
                        )
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.isChecking = false
                    if userInitiated {
                        self.presentAlert(
                            title: "Update Check Failed",
                            message: "Lock In could not read the latest release information from GitHub."
                        )
                    }
                }
            }
        }.resume()
    }

    func openDownloadPage() {
        NSWorkspace.shared.open(downloadURL ?? latestReleasePage)
    }

    private func presentAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        prepareAlertForForeground(alert)
        alert.runModal()
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

    private static func normalizeVersion(_ tag: String) -> String {
        tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
    }

    private static func compareVersions(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let left = lhs.split(separator: ".").map { Int($0) ?? 0 }
        let right = rhs.split(separator: ".").map { Int($0) ?? 0 }
        let count = max(left.count, right.count)

        for index in 0..<count {
            let l = index < left.count ? left[index] : 0
            let r = index < right.count ? right[index] : 0
            if l < r { return .orderedAscending }
            if l > r { return .orderedDescending }
        }

        return .orderedSame
    }

    private static func isPreferredZipAsset(_ asset: GitHubAsset) -> Bool {
        asset.name == "LockIn.zip" ||
        (asset.name.hasPrefix("LockIn-macOS-") && asset.name.hasSuffix(".zip"))
    }
}

private struct GitHubRelease: Decodable {
    let tagName: String
    let htmlURL: URL
    let assets: [GitHubAsset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case assets
    }
}

private struct GitHubAsset: Decodable {
    let name: String
    let browserDownloadURL: URL

    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadURL = "browser_download_url"
    }
}
