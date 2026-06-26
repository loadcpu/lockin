import AppKit

func envInt(_ key: String, default defaultValue: Int) -> Int {
    guard let value = ProcessInfo.processInfo.environment[key], let parsed = Int(value) else {
        return defaultValue
    }
    return parsed
}

let width = envInt("LOCKIN_DMG_WIDTH", default: 620)
let height = envInt("LOCKIN_DMG_HEIGHT", default: 300)
let appX = envInt("LOCKIN_DMG_APP_X", default: 170)
let appsX = envInt("LOCKIN_DMG_APPS_X", default: 450)
let iconY = envInt("LOCKIN_DMG_ICON_Y", default: 132)
let iconSize = envInt("LOCKIN_DMG_ICON_SIZE", default: 104)
let outputURL = URL(fileURLWithPath: ".build/dmg-background.png")

let image = NSImage(size: NSSize(width: width, height: height))
image.lockFocus()

NSColor(calibratedWhite: 0.98, alpha: 1).setFill()
NSBezierPath(rect: NSRect(x: 0, y: 0, width: width, height: height)).fill()

let lineColor = NSColor(calibratedWhite: 0.55, alpha: 1)
let arrowInset = max(34, (iconSize / 2) + 16)
let arrowY = iconY + (iconSize / 2)
let arrowStartX = appX + arrowInset
let arrowEndX = appsX - arrowInset
let line = NSBezierPath()
line.lineWidth = 1.5
line.move(to: NSPoint(x: arrowStartX, y: arrowY))
line.line(to: NSPoint(x: arrowEndX, y: arrowY))
lineColor.setStroke()
line.stroke()

let arrow = NSBezierPath()
arrow.lineWidth = 1.5
arrow.move(to: NSPoint(x: arrowEndX - 11, y: arrowY + 8))
arrow.line(to: NSPoint(x: arrowEndX, y: arrowY))
arrow.line(to: NSPoint(x: arrowEndX - 11, y: arrowY - 8))
lineColor.setStroke()
arrow.stroke()

image.unlockFocus()

guard
    let tiffData = image.tiffRepresentation,
    let bitmap = NSBitmapImageRep(data: tiffData),
    let pngData = bitmap.representation(using: .png, properties: [:])
else {
    fputs("Failed to render DMG background\n", stderr)
    exit(1)
}

try FileManager.default.createDirectory(
    at: outputURL.deletingLastPathComponent(),
    withIntermediateDirectories: true
)
try pngData.write(to: outputURL)
