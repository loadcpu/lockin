import AppKit
import SwiftUI

final class BlockSetupWindowController: NSWindowController {
    convenience init(onStart: @escaping (Int, [String], [String]) -> Void) {
        let view = BlockSetupView(
            onStart: onStart,
            onCancel: { NSApp.keyWindow?.performClose(nil) }
        )
        let hosting = NSHostingView(rootView: view)
        hosting.autoresizingMask = [.width, .height]

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 440),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        win.title = "Start Focus Session"
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
