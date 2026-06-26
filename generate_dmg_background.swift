import AppKit

let width = 720
let height = 360
let outputURL = URL(fileURLWithPath: ".build/dmg-background.png")

let image = NSImage(size: NSSize(width: width, height: height))
image.lockFocus()

NSColor(calibratedWhite: 0.98, alpha: 1).setFill()
NSBezierPath(rect: NSRect(x: 0, y: 0, width: width, height: height)).fill()

let lineColor = NSColor(calibratedWhite: 0.55, alpha: 1)
let line = NSBezierPath()
line.lineWidth = 1.5
line.move(to: NSPoint(x: 275, y: 182))
line.line(to: NSPoint(x: 445, y: 182))
lineColor.setStroke()
line.stroke()

let arrow = NSBezierPath()
arrow.lineWidth = 1.5
arrow.move(to: NSPoint(x: 434, y: 190))
arrow.line(to: NSPoint(x: 445, y: 182))
arrow.line(to: NSPoint(x: 434, y: 174))
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
