import AppKit
import SwiftUI
import UserNotifications

private final class HostingWindowController: NSWindowController {
    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(sender)
        NSApp.activate(ignoringOtherApps: true)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, UNUserNotificationCenterDelegate {
    private var statusItem: NSStatusItem!
    private var mainTimer: Timer?
    private var configWC: HostingWindowController?
    private var dashboardWC: HostingWindowController?
    private var statsWC: HostingWindowController?
    private var blockSetupWC: HostingWindowController?
    private var sigTermSource: DispatchSourceSignal?

    // MARK: - Launch

    func applicationDidFinishLaunching(_ notification: Notification) {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.local.lockin"
        if NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).count > 1 {
            NSApp.terminate(nil)
            return
        }

        NSApp.setActivationPolicy(.regular)
        UNUserNotificationCenter.current().delegate = self
        setupMainMenu()
        installSigTermHandler()
        BlockerService.shared.loadState()
        HelperInstaller.ensureInstalled()
        HelperInstaller.ensureLaunchAgent()
        ActivityTracker.shared.start()
        LimitsChecker.shared.start()
        setupStatusItem()
        startMainTimer()
        showDashboard()
    }

    private func setupMainMenu() {
        let appMenu = NSMenu()
        let quitItem = NSMenuItem(title: "Quit Lock In", action: #selector(handleQuit), keyEquivalent: "q")
        quitItem.target = self
        appMenu.addItem(quitItem)
        let appMenuItem = NSMenuItem()
        appMenuItem.submenu = appMenu
        let mainMenu = NSMenu()
        mainMenu.addItem(appMenuItem)
        NSApp.mainMenu = mainMenu
    }

    private func installSigTermHandler() {
        // Tell the OS not to default-handle SIGTERM (which would kill the process).
        // We take ownership of it via DispatchSource so we can gate on isBlocking.
        signal(SIGTERM, SIG_IGN)
        let src = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        src.setEventHandler { [weak self] in
            guard !BlockerService.shared.isBlocking else { return }
            NSApp.terminate(self)
        }
        src.resume()
        sigTermSource = src
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        BlockerService.shared.isBlocking ? .terminateCancel : .terminateNow
    }

    func applicationWillTerminate(_ notification: Notification) {
        ActivityTracker.shared.stop()
        LimitsChecker.shared.stop()
    }

    // Re-open dashboard when user clicks the Dock icon
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        showDashboard()
        return true
    }

    // MARK: - Dashboard

    private func showDashboard() {
        if dashboardWC == nil {
            dashboardWC = makeHostingWindow(
                rootView: DashboardView(
                    onStartBlocking: { [weak self] in self?.startBlocking() },
                    onConfigure:     { [weak self] in self?.openConfig() },
                    onViewStats:     { [weak self] in self?.openStats() }
                ),
                title: "Lock In",
                size: NSSize(width: 300, height: 300),
                style: [.titled, .closable, .fullSizeContentView]
            ) { win, hosting in
                win.setContentSize(hosting.fittingSize)
                win.titlebarAppearsTransparent = true
                win.isMovableByWindowBackground = true
            }
        }
        dashboardWC?.showWindow(nil)
    }

    // MARK: - Status bar

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        statusItem.button?.image = makeMenuBarIcon()
        statusItem.button?.imagePosition = .imageLeft

        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        refreshButton()
    }

    private func refreshButton() {
        let svc = BlockerService.shared
        statusItem.button?.title = svc.isBlocking ? "  \(svc.remainingTimeString)" : ""
    }

    // MARK: - Main tick timer

    private func startMainTimer() {
        mainTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            BlockerService.shared.tick()
            ActivityStore.shared.tick()
            self?.refreshButton()
        }
    }

    // MARK: - NSMenuDelegate (rebuild on open)

    func menuWillOpen(_ menu: NSMenu) {
        menu.removeAllItems()
        let svc = BlockerService.shared

        if svc.isBlocking {
            add(disabled: "🔴  Blocking Active", to: menu)
            add(disabled: "     ⏱ \(svc.remainingTimeString) remaining", to: menu)
            menu.addItem(.separator())
            add(disabled: "🔒  Session locked – cannot stop early", to: menu)
        } else {
            add(disabled: svc.hasLimitRestrictions ? "🔒  Category limits active" : "✅  Ready", to: menu)
            menu.addItem(.separator())
            menu.addItem(item("Dashboard",       action: #selector(openDashboard), key: "d"))
            menu.addItem(item("Screen Time…",    action: #selector(openStats),     key: "t"))
            menu.addItem(item("Configure…",      action: #selector(openConfig),    key: ","))
            menu.addItem(item("Start Blocking", action: #selector(startBlocking), key: "s"))
        }

        menu.addItem(.separator())
        menu.addItem(item("Quit", action: #selector(handleQuit), key: "q"))
    }

    // MARK: - Actions

    @objc private func openDashboard() { showDashboard() }

    @objc private func openConfig() {
        if configWC == nil {
            configWC = makeHostingWindow(
                rootView: ConfigView(),
                title: "Lock In – Configure",
                size: NSSize(width: 520, height: 520),
                style: [.titled, .closable, .miniaturizable]
            ) { win, hosting in
                hosting.autoresizingMask = [.width, .height]
                win.setContentSize(hosting.fittingSize)
            }
        }
        configWC?.showWindow(nil)
    }

    @objc private func openStats() {
        // Closing an NSWindow only orders it out, so discard its hosting view before
        // reopening to reset the selected range and ScrollView position.
        if statsWC?.window?.isVisible == false {
            statsWC = nil
        }

        if statsWC == nil {
            statsWC = makeHostingWindow(
                rootView: StatsView(),
                title: "Lock In – Screen Time",
                size: NSSize(width: 600, height: 560),
                style: [.titled, .closable, .miniaturizable, .resizable]
            ) { win, hosting in
                hosting.autoresizingMask = [.width, .height]
                win.minSize = NSSize(width: 560, height: 420)
            }
        }
        statsWC?.showWindow(nil)
        NotificationCenter.default.post(name: .statsViewShouldReload, object: nil)
    }

    @objc private func startBlocking() {
        guard !BlockerService.shared.isBlocking else { return }
        blockSetupWC = makeHostingWindow(
            rootView: BlockSetupView(
                onStart: { [weak self] minutes, apps, websites in
                    BlockerService.shared.startSession(minutes: minutes, apps: apps, websites: websites)
                    self?.blockSetupWC?.close()
                    self?.blockSetupWC = nil
                    self?.refreshButton()
                },
                onCancel: { [weak self] in
                    self?.blockSetupWC?.close()
                    self?.blockSetupWC = nil
                }
            ),
            title: "Start Focus Session",
            size: NSSize(width: 560, height: 660),
            style: [.titled, .closable]
        ) { _, hosting in
            hosting.autoresizingMask = [.width, .height]
        }
        blockSetupWC?.showWindow(nil)
    }

    @objc private func handleQuit() {
        guard !BlockerService.shared.isBlocking else {
            let a = NSAlert()
            a.messageText = "Session Locked"
            a.informativeText = "You cannot quit while a blocking session is active. Wait for the timer to expire."
            a.alertStyle = .informational
            a.addButton(withTitle: "OK")
            a.runModal()
            return
        }
        NSApp.terminate(nil)
    }

    // MARK: - Icon

    private func makeMenuBarIcon() -> NSImage {
        let size: CGFloat = 18
        let img = NSImage(size: NSSize(width: size, height: size))
        img.lockFocus()
        defer { img.unlockFocus() }

        let rect = NSRect(origin: .zero, size: NSSize(width: size, height: size))
        NSBezierPath(roundedRect: rect, xRadius: size * 0.22, yRadius: size * 0.22).setClip()
        NSGradient(colors: [
            NSColor(calibratedRed: 0.10, green: 0.22, blue: 0.82, alpha: 1),
            NSColor(calibratedRed: 0.04, green: 0.10, blue: 0.48, alpha: 1),
        ])!.draw(in: rect, angle: 255)

        let cfg = NSImage.SymbolConfiguration(pointSize: size * 0.60, weight: .medium)
            .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
        if let sym = NSImage(systemSymbolName: "lock.shield.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(cfg) {
            sym.draw(
                at: NSPoint(x: (size - sym.size.width) / 2, y: (size - sym.size.height) / 2),
                from: .zero, operation: .sourceOver, fraction: 1
            )
        }
        return img
    }

    // MARK: - Helpers

    private func item(_ title: String, action: Selector, key: String) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
        i.target = self
        return i
    }

    private func add(disabled title: String, to menu: NSMenu) {
        let i = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        i.isEnabled = false
        menu.addItem(i)
    }

    private func makeHostingWindow<V: View>(
        rootView: V,
        title: String,
        size: NSSize,
        style: NSWindow.StyleMask,
        configure: ((NSWindow, NSHostingView<V>) -> Void)? = nil
    ) -> HostingWindowController {
        let hosting = NSHostingView(rootView: rootView)
        let win = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: style,
            backing: .buffered,
            defer: false
        )
        win.title = title
        win.contentView = hosting
        win.isReleasedWhenClosed = false
        configure?(win, hosting)
        win.center()
        return HostingWindowController(window: win)
    }

    // MARK: - UNUserNotificationCenterDelegate

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
