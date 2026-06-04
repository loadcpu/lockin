import AppKit
import SwiftUI

final class ConfigWindowController: NSWindowController {
    convenience init() {
        let view = ConfigView()
        let hosting = NSHostingView(rootView: view)
        hosting.autoresizingMask = [.width, .height]

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 520),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        win.title = "Screen Blocker – Configure"
        win.contentView = hosting
        win.setContentSize(hosting.fittingSize)
        win.center()
        win.isReleasedWhenClosed = false

        self.init(window: win)
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(sender)
        NSApp.activate(ignoringOtherApps: true)
    }
}
