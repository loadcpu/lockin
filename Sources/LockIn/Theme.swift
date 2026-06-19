import AppKit
import SwiftUI

enum AppTheme {
    static let background = Color(
        red: 30.0 / 255.0,
        green: 30.0 / 255.0,
        blue: 30.0 / 255.0
    )

    static let backgroundNSColor = NSColor(
        calibratedRed: 30.0 / 255.0,
        green: 30.0 / 255.0,
        blue: 30.0 / 255.0,
        alpha: 1
    )

    static let accentBlue = Color(
        red: 26.0 / 255.0,
        green: 56.0 / 255.0,
        blue: 209.0 / 255.0
    )

    static let linkBlue = Color(
        red: 57.0 / 255.0,
        green: 123.0 / 255.0,
        blue: 247.0 / 255.0
    )

    static let windowSurface = Color(NSColor.windowBackgroundColor)
    static let controlSurface = Color(NSColor.controlBackgroundColor)
    static let separator = Color(NSColor.separatorColor)
}

extension View {
    func appWindowSurface() -> some View {
        background(AppTheme.windowSurface)
    }

    func appControlSurface() -> some View {
        background(AppTheme.controlSurface)
    }

    func appCard(cornerRadius: CGFloat) -> some View {
        background(AppTheme.controlSurface)
            .cornerRadius(cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(AppTheme.separator, lineWidth: 1)
            )
    }
}
