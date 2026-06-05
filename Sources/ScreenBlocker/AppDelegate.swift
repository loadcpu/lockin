import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var mainTimer: Timer?
    private var configWC: ConfigWindowController?
    private var dashboardWC: DashboardWindowController?
    private var statsWC: StatsWindowController?
    private var blockSetupWC: BlockSetupWindowController?

    // MARK: - Launch

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        setupMainMenu()
        BlockerService.shared.loadState()
        HelperInstaller.ensureInstalled()
        ActivityTracker.shared.start()
        LimitsChecker.shared.start()
        setupStatusItem()
        startMainTimer()
        showDashboard()
        maybePromptBrowserPermissions()
    }

    private func setupMainMenu() {
        let appMenu = NSMenu()
        let quitItem = NSMenuItem(title: "Quit Screen Blocker", action: #selector(handleQuit), keyEquivalent: "q")
        quitItem.target = self
        appMenu.addItem(quitItem)
        let appMenuItem = NSMenuItem()
        appMenuItem.submenu = appMenu
        let mainMenu = NSMenu()
        mainMenu.addItem(appMenuItem)
        NSApp.mainMenu = mainMenu
    }

    private func maybePromptBrowserPermissions() {
        guard !UserDefaults.standard.bool(forKey: "hasPromptedBrowserPermissions") else { return }
        UserDefaults.standard.set(true, forKey: "hasPromptedBrowserPermissions")
        // Let the UI settle before showing the prompt
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            self.promptBrowserPermissions()
        }
    }

    private func promptBrowserPermissions() {
        let alert = NSAlert()
        alert.messageText = "Enable Instant Website Blocking"
        alert.informativeText = "Screen Blocker can reload your open browser tabs the moment a session starts, so blocked websites are cut off immediately.\n\nmacOS will ask your permission for each browser you have open. Click Allow on each prompt — it only happens once."
        alert.addButton(withTitle: "Grant Permission")
        alert.addButton(withTitle: "Not Now")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        BlockerService.shared.primeBrowserPermissions()
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
            dashboardWC = DashboardWindowController(
                onStartBlocking: { [weak self] in self?.startBlocking() },
                onConfigure:     { [weak self] in self?.openConfig() },
                onViewStats:     { [weak self] in self?.openStats() }
            )
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
            add(disabled: "✅  Ready", to: menu)
            menu.addItem(.separator())
            menu.addItem(item("Dashboard",       action: #selector(openDashboard), key: "d"))
            menu.addItem(item("Screen Time…",    action: #selector(openStats),     key: "t"))
            menu.addItem(item("Configure…",      action: #selector(openConfig),    key: ","))
            menu.addItem(item("Start Blocking…", action: #selector(startBlocking), key: "s"))
        }

        menu.addItem(.separator())
        menu.addItem(item("Quit", action: #selector(handleQuit), key: "q"))
    }

    // MARK: - Actions

    @objc private func openDashboard() { showDashboard() }

    @objc private func openConfig() {
        if configWC == nil { configWC = ConfigWindowController() }
        configWC?.showWindow(nil)
    }

    @objc private func openStats() {
        if statsWC == nil { statsWC = StatsWindowController() }
        statsWC?.showWindow(nil)
    }

    @objc private func startBlocking() {
        guard !BlockerService.shared.isBlocking else { return }
        blockSetupWC = BlockSetupWindowController { [weak self] minutes, apps, websites in
            BlockerService.shared.startSession(minutes: minutes, apps: apps, websites: websites)
            self?.blockSetupWC?.close()
            self?.blockSetupWC = nil
            self?.refreshButton()
        }
        blockSetupWC?.showWindow(nil)
    }

    @objc private func handleQuit() {
        if BlockerService.shared.isBlocking {
            let a = NSAlert()
            a.messageText = "Session Active"
            a.informativeText = "A blocking session is running. Quitting will pause the app-kill monitor, but the session timer will resume on next launch."
            a.alertStyle = .warning
            a.addButton(withTitle: "Quit Anyway")
            a.addButton(withTitle: "Cancel")
            if a.runModal() == .alertFirstButtonReturn { NSApp.terminate(nil) }
        } else {
            NSApp.terminate(nil)
        }
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
}
