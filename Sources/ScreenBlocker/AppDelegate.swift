import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var mainTimer: Timer?
    private var configWC: ConfigWindowController?

    // MARK: - Launch

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        BlockerService.shared.loadState()
        setupStatusItem()
        startMainTimer()
    }

    // MARK: - Status bar

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        refreshButton()
    }

    private func refreshButton() {
        let svc = BlockerService.shared
        if svc.isBlocking {
            statusItem.button?.title = "🛡 \(svc.remainingTimeString)"
        } else {
            statusItem.button?.title = "🛡"
        }
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
            menu.addItem(item("Configure…",      action: #selector(openConfig),    key: ","))
            menu.addItem(item("Start Blocking…", action: #selector(startBlocking), key: "s"))
        }

        menu.addItem(.separator())
        menu.addItem(item("Quit", action: #selector(handleQuit), key: "q"))
    }

    // MARK: - Actions

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
            a.informativeText = "A blocking session is running. Website blocks in /etc/hosts will persist until the timer expires. Quitting will stop the app-kill monitor."
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
        let labels   = ["15 minutes", "30 minutes", "45 minutes", "1 hour", "2 hours", "3 hours", "4 hours", "8 hours"]
        let minutes  = [15, 30, 45, 60, 120, 180, 240, 480]

        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 230, height: 26))
        popup.addItems(withTitles: labels)
        popup.selectItem(at: 3)

        let picker = NSAlert()
        picker.messageText = "Choose Block Duration"
        picker.informativeText = "You cannot stop the session early. Apps will be killed on launch; websites will be blocked system-wide."
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
        if !svc.config.blockedWebsites.isEmpty {
            let shown = svc.config.blockedWebsites.prefix(5).joined(separator: ", ")
            let extra = svc.config.blockedWebsites.count > 5 ? " (+\(svc.config.blockedWebsites.count - 5) more)" : ""
            parts.append("Sites: \(shown)\(extra)")
        }
        return parts.joined(separator: "\n\n") + "\n\nThis cannot be undone until the timer expires."
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
