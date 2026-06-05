import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var mainTimer: Timer?
    private var configWC: ConfigWindowController?
    private var dashboardWC: DashboardWindowController?

    // MARK: - Launch

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        setupMainMenu()
        BlockerService.shared.loadState()
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
                onConfigure:     { [weak self] in self?.openConfig() }
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

    @objc private func startBlocking() {
        let svc = BlockerService.shared
        if svc.config.blockedApps.isEmpty && svc.config.blockedWebsites.isEmpty {
            let a = NSAlert()
            a.messageText = "Nothing to Block"
            a.informativeText = "Open Configure and select at least one app or website to block."
            a.addButton(withTitle: "Open Configure")
            a.addButton(withTitle: "Cancel")
            if a.runModal() == .alertFirstButtonReturn { openConfig() }
            return
        }
        showDurationPicker()
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

    // MARK: - Duration picker

    private func showDurationPicker() {
        let labels  = ["1 minute", "5 minutes", "15 minutes", "30 minutes", "45 minutes", "1 hour", "2 hours", "3 hours", "4 hours", "8 hours"]
        let minutes = [1, 5, 15, 30, 45, 60, 120, 180, 240, 480]

        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 230, height: 26))
        popup.addItems(withTitles: labels)
        popup.selectItem(at: 5)

        let picker = NSAlert()
        picker.messageText = "Choose Block Duration"
        picker.informativeText = "You cannot stop the session early. Apps will be killed on launch."
        picker.accessoryView = popup
        picker.addButton(withTitle: "Next")
        picker.addButton(withTitle: "Cancel")
        guard picker.runModal() == .alertFirstButtonReturn else { return }

        let chosen = minutes[popup.indexOfSelectedItem]
        let label  = labels[popup.indexOfSelectedItem]

        let confirm = NSAlert()
        confirm.messageText = "Start \(label) Block?"
        confirm.informativeText = buildSummary(minutes: chosen)
        confirm.alertStyle = .warning
        confirm.addButton(withTitle: "Start Blocking")
        confirm.addButton(withTitle: "Cancel")
        guard confirm.runModal() == .alertFirstButtonReturn else { return }

        BlockerService.shared.startSession(minutes: chosen)
        refreshButton()
    }

    private func buildSummary(minutes: Int) -> String {
        let svc = BlockerService.shared
        var parts: [String] = []
        if !svc.config.blockedApps.isEmpty {
            parts.append("Apps: \(svc.config.blockedApps.joined(separator: ", "))")
        }
        return (parts.isEmpty ? "No apps selected yet." : parts.joined(separator: "\n\n"))
            + "\n\nThis cannot be undone until the timer expires."
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
