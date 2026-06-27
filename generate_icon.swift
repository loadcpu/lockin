#!/usr/bin/env swift
// Run: swift generate_icon.swift
import AppKit

_ = NSApplication.shared // init AppKit rendering

func makeIconPNG(px: Int) -> Data? {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: px,
        pixelsHigh: px,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        return nil
    }

    let s = CGFloat(px)
    let rect = NSRect(origin: .zero, size: NSSize(width: s, height: s))
    guard let context = NSGraphicsContext(bitmapImageRep: rep) else {
        return nil
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    defer { NSGraphicsContext.restoreGraphicsState() }

    // Rounded-rect background clip
    NSBezierPath(roundedRect: rect, xRadius: s * 0.22, yRadius: s * 0.22).setClip()

    // Deep-blue gradient
    NSGradient(colors: [
        NSColor(calibratedRed: 0.10, green: 0.22, blue: 0.82, alpha: 1),
        NSColor(calibratedRed: 0.04, green: 0.10, blue: 0.48, alpha: 1),
    ])!.draw(in: rect, angle: 255)

    // White lock.shield.fill SF Symbol
    let cfg = NSImage.SymbolConfiguration(pointSize: s * 0.60, weight: .medium)
        .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
    if let sym = NSImage(systemSymbolName: "lock.shield.fill", accessibilityDescription: nil)?
        .withSymbolConfiguration(cfg) {
        sym.draw(
            at: NSPoint(x: (s - sym.size.width) / 2, y: (s - sym.size.height) / 2),
            from: .zero, operation: .sourceOver, fraction: 1
        )
    }

    return rep.representation(using: .png, properties: [:])
}

let fileManager = FileManager.default
let buildDir = ".build"
let dir = "\(buildDir)/AppIcon.iconset"
let iconPath = "\(buildDir)/AppIcon.icns"
try? fileManager.createDirectory(atPath: buildDir, withIntermediateDirectories: true)
try? FileManager.default.removeItem(atPath: dir)
try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

let specs: [(String, Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
]

for (name, size) in specs {
    if let png = makeIconPNG(px: size) {
        try? png.write(to: URL(fileURLWithPath: "\(dir)/\(name)"))
        print("  \(name)")
    }
}

let task = Process()
task.launchPath = "/usr/bin/iconutil"
task.arguments = ["-c", "icns", dir, "-o", iconPath]
task.launch()
task.waitUntilExit()
guard task.terminationStatus == 0 else { print("iconutil failed"); exit(1) }
print("\(iconPath) ready")
