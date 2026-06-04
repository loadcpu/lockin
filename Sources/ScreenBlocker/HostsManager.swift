import Foundation

struct HostsManager {
    static func cleanupOnLaunch() {}

    @discardableResult
    static func applyBlocks(domains: [String]) -> Bool { true }

    static func removeBlocks() {}
}
