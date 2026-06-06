import Foundation
import AppKit

struct AppInfo: Identifiable, Hashable {
    let id: String       // bundle path
    let name: String
    let bundlePath: String

    var icon: NSImage { NSWorkspace.shared.icon(forFile: bundlePath) }
}

final class AppScanner {
    static let shared = AppScanner()
    private var cache: [AppInfo]?
    private init() {}

    func installedApps() -> [AppInfo] {
        if let c = cache { return c }
        var apps: [AppInfo] = []
        let dirs = [
            "/Applications",
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path,
        ]
        for dir in dirs {
            let url = URL(fileURLWithPath: dir)
            guard let items = try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) else { continue }
            for item in items where item.pathExtension == "app" {
                let name = item.deletingPathExtension().lastPathComponent
                guard name != "Screen Blocker" else { continue }
                apps.append(AppInfo(id: item.path, name: name, bundlePath: item.path))
            }
        }
        let sorted = apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        cache = sorted
        return sorted
    }
}
