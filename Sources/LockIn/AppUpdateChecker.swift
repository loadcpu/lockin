import AppKit
import Foundation
import Sparkle

/// Automatic updates through Sparkle. The feed URL (SUFeedURL) and EdDSA public key
/// (SUPublicEDKey) live in Info.plist; release.sh publishes a signed appcast.xml with
/// every GitHub release.
final class AppUpdateChecker: NSObject, SPUUpdaterDelegate, SPUStandardUserDriverDelegate {
    static let shared = AppUpdateChecker()

    private var controller: SPUStandardUpdaterController!
    private var postponedRelaunchTimer: Timer?

    private override init() {
        super.init()
        controller = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: self,
            userDriverDelegate: self
        )
    }

    /// Starts Sparkle's scheduled background checks. Dev builds without a feed URL
    /// (script/build_and_run.sh) skip it so Sparkle doesn't complain.
    func start() {
        guard Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil else { return }
        controller.startUpdater()
    }

    @objc func checkForUpdates() {
        NSApp.activate(ignoringOtherApps: true)
        controller.checkForUpdates(nil)
    }

    // MARK: - SPUUpdaterDelegate

    // A relaunch can't happen mid-session (applicationShouldTerminate refuses), so hold
    // the install until the session ends instead of leaving the update stuck halfway.
    func updater(_ updater: SPUUpdater, shouldPostponeRelaunchForUpdate item: SUAppcastItem, untilInvokingBlock installHandler: @escaping () -> Void) -> Bool {
        guard BlockerService.shared.isBlocking else { return false }
        postponedRelaunchTimer?.invalidate()
        postponedRelaunchTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] timer in
            guard !BlockerService.shared.isBlocking else { return }
            timer.invalidate()
            self?.postponedRelaunchTimer = nil
            installHandler()
        }
        return true
    }

    // MARK: - SPUStandardUserDriverDelegate

    // Lock In runs without a Dock icon, so scheduled update alerts would otherwise open
    // behind other apps.
    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        NSApp.activate(ignoringOtherApps: true)
    }
}
