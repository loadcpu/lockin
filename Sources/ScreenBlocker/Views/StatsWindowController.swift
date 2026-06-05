import AppKit
import SwiftUI

extension Notification.Name {
    static let statsViewShouldReload = Notification.Name("StatsViewShouldReload")
}

final class StatsWindowController: NSWindowController {
    convenience init() {
        let hosting = NSHostingView(rootView: StatsView())
        hosting.autoresizingMask = [.width, .height]

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        win.title = "Screen Blocker – Screen Time"
        win.contentView = hosting
        win.minSize = NSSize(width: 560, height: 420)
        win.center()
        win.isReleasedWhenClosed = false

        self.init(window: win)
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(sender)
        NSApp.activate(ignoringOtherApps: true)
        NotificationCenter.default.post(name: .statsViewShouldReload, object: nil)
    }
}
