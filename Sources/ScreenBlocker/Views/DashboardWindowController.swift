import AppKit
import SwiftUI

final class DashboardWindowController: NSWindowController {
    convenience init(onStartBlocking: @escaping () -> Void, onConfigure: @escaping () -> Void) {
        let view = DashboardView(onStartBlocking: onStartBlocking, onConfigure: onConfigure)
        let hosting = NSHostingView(rootView: view)

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 300),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        win.title = "Screen Blocker"
        win.contentView = hosting
        win.setContentSize(hosting.fittingSize)
        win.center()
        win.isReleasedWhenClosed = false
        win.titlebarAppearsTransparent = true
        win.isMovableByWindowBackground = true

        self.init(window: win)
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(sender)
        NSApp.activate(ignoringOtherApps: true)
    }
}
