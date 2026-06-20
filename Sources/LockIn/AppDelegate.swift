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
        HelperInstaller.ensureLaunchAgent()
        ActivityTracker.shared.start()
        LimitsChecker.shared.start()
        setupStatusItem()
        startMainTimer()
        showDashboard()
    }

    private func setupMainMenu() {
        let mainMenu = NSMenu()
        let appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Lock In"

        mainMenu.addItem(makeAppMenuItem(appName: appName))
        mainMenu.addItem(makeFileMenuItem())
        mainMenu.addItem(makeEditMenuItem())
        mainMenu.addItem(makeWindowMenuItem())

        NSApp.mainMenu = mainMenu
    }

    private func makeAppMenuItem(appName: String) -> NSMenuItem {
        let appMenu = NSMenu(title: appName)

        let aboutItem = NSMenuItem(title: "About \(appName)", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        aboutItem.target = NSApp
        appMenu.addItem(aboutItem)
        appMenu.addItem(.separator())

        let hideItem = NSMenuItem(title: "Hide \(appName)", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        hideItem.target = NSApp
        appMenu.addItem(hideItem)

        let hideOthersItem = NSMenuItem(title: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthersItem.target = NSApp
        hideOthersItem.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(hideOthersItem)

        let showAllItem = NSMenuItem(title: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        showAllItem.target = NSApp
        appMenu.addItem(showAllItem)
        appMenu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit \(appName)", action: #selector(handleQuit), keyEquivalent: "q")
        quitItem.target = self
        appMenu.addItem(quitItem)

        let appMenuItem = NSMenuItem()
        appMenuItem.submenu = appMenu
        return appMenuItem
    }

    private func makeFileMenuItem() -> NSMenuItem {
        let fileMenu = NSMenu(title: "File")

        let closeItem = NSMenuItem(title: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        closeItem.target = nil
        fileMenu.addItem(closeItem)

        let fileMenuItem = NSMenuItem()
        fileMenuItem.submenu = fileMenu
        return fileMenuItem
    }

    private func makeEditMenuItem() -> NSMenuItem {
        let editMenu = NSMenu(title: "Edit")

        let undoItem = NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        undoItem.target = nil
        editMenu.addItem(undoItem)

        let redoItem = NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        redoItem.target = nil
        editMenu.addItem(redoItem)

        editMenu.addItem(.separator())

        let cutItem = NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        cutItem.target = nil
        editMenu.addItem(cutItem)

        let copyItem = NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        copyItem.target = nil
        editMenu.addItem(copyItem)

        let pasteItem = NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        pasteItem.target = nil
        editMenu.addItem(pasteItem)

        let deleteItem = NSMenuItem(title: "Delete", action: #selector(NSText.delete(_:)), keyEquivalent: "")
        deleteItem.target = nil
        editMenu.addItem(deleteItem)

        let selectAllItem = NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        selectAllItem.target = nil
        editMenu.addItem(selectAllItem)

        let editMenuItem = NSMenuItem()
        editMenuItem.submenu = editMenu
        return editMenuItem
    }

    private func makeWindowMenuItem() -> NSMenuItem {
        let windowMenu = NSMenu(title: "Window")

        let minimizeItem = NSMenuItem(title: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        minimizeItem.target = nil
        windowMenu.addItem(minimizeItem)

        let zoomItem = NSMenuItem(title: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        zoomItem.target = nil
        windowMenu.addItem(zoomItem)

        windowMenu.addItem(.separator())

        let bringAllToFrontItem = NSMenuItem(title: "Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")
        bringAllToFrontItem.target = NSApp
        windowMenu.addItem(bringAllToFrontItem)

        NSApp.windowsMenu = windowMenu

        let windowMenuItem = NSMenuItem()
        windowMenuItem.submenu = windowMenu
        return windowMenuItem
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
                    onViewStats:     { [weak self] in self?.openStats() }
                ),
                title: "Lock In",
                size: NSSize(width: 300, height: 300),
                style: [.titled, .closable, .miniaturizable]
            ) { win, hosting in
                win.setContentSize(hosting.fittingSize)
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
            menu.addItem(item("Start Blocking", action: #selector(startBlocking), key: "s"))
        }

        menu.addItem(.separator())
        menu.addItem(item("Quit", action: #selector(handleQuit), key: "q"))
    }

    // MARK: - Actions

    @objc private func openDashboard() { showDashboard() }

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
            style: [.titled, .closable, .fullSizeContentView]
        ) { win, hosting in
            hosting.autoresizingMask = [.width, .height]
            win.titlebarAppearsTransparent = true
            win.isMovableByWindowBackground = true
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
        configure: ((NSWindow, NSHostingView<AnyView>) -> Void)? = nil
    ) -> HostingWindowController {
        var windowStyle = style
        windowStyle.insert(.fullSizeContentView)

        let hosting = NSHostingView(rootView: AnyView(
            ZStack {
                AppTheme.background.ignoresSafeArea()
                rootView
            }
        ))
        let win = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: windowStyle,
            backing: .buffered,
            defer: false
        )
        win.title = title
        win.titleVisibility = .hidden
        win.titlebarAppearsTransparent = true
        win.backgroundColor = AppTheme.backgroundNSColor
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

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        defer { completionHandler() }

        guard response.notification.request.identifier.hasPrefix("browser-force-quit-"),
              let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") else {
            return
        }

        NSWorkspace.shared.open(url)
    }
}
