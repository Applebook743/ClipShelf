import AppKit
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let assets = root.appendingPathComponent("Assets", isDirectory: true)
try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)

let sizes: [(String, CGFloat)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

enum IconVariant: Int, CaseIterable {
    case clipboardTextClock = 1
    case clipboardLinesClock = 2
    case stackedWindowsClock = 3

    var iconsetName: String {
        "AppIcon\(rawValue).iconset"
    }
}

func iconImage(size: CGFloat, variant: IconVariant) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()

    let rect = NSRect(x: 0, y: 0, width: size, height: size)
    NSColor.clear.setFill()
    rect.fill()

    drawTile(in: rect, size: size)

    switch variant {
    case .clipboardTextClock:
        drawClipboard(in: rect, size: size, lineStyle: .greenShort)
    case .clipboardLinesClock:
        drawClipboard(in: rect, size: size, lineStyle: .grayLines)
    case .stackedWindowsClock:
        drawStackedWindows(in: rect, size: size)
    }

    drawClock(in: rect, size: size)

    image.unlockFocus()
    return image
}

func drawTile(in rect: NSRect, size: CGFloat) {
    let inset = size * 0.055
    let tileRect = rect.insetBy(dx: inset, dy: inset)
    let radius = size * 0.16
    let tile = NSBezierPath(roundedRect: tileRect, xRadius: radius, yRadius: radius)

    NSColor(calibratedWhite: 1, alpha: 1).setFill()
    tile.fill()

    NSColor(calibratedWhite: 0.82, alpha: 0.62).setStroke()
    tile.lineWidth = max(1, size * 0.008)
    tile.stroke()

    let highlight = NSBezierPath(roundedRect: tileRect.insetBy(dx: size * 0.018, dy: size * 0.018), xRadius: radius * 0.88, yRadius: radius * 0.88)
    NSColor.white.withAlphaComponent(0.86).setStroke()
    highlight.lineWidth = max(0.7, size * 0.005)
    highlight.stroke()
}

enum ClipboardLineStyle {
    case greenShort
    case grayLines
}

func drawClipboard(in rect: NSRect, size: CGFloat, lineStyle: ClipboardLineStyle) {
    let stroke = NSColor(calibratedRed: 0.16, green: 0.20, blue: 0.24, alpha: 1)
    let boardRect = NSRect(x: size * 0.29, y: size * 0.23, width: size * 0.34, height: size * 0.47)
    let board = NSBezierPath(roundedRect: boardRect, xRadius: size * 0.035, yRadius: size * 0.035)

    NSColor.clear.setFill()
    board.fill()
    stroke.setStroke()
    board.lineWidth = max(2.4, size * 0.035)
    board.lineJoinStyle = .round
    board.stroke()

    let clipRect = NSRect(x: size * 0.39, y: size * 0.66, width: size * 0.17, height: size * 0.08)
    let clip = NSBezierPath(roundedRect: clipRect, xRadius: size * 0.022, yRadius: size * 0.022)
    NSColor(calibratedWhite: 1, alpha: 1).setFill()
    clip.fill()
    stroke.setStroke()
    clip.lineWidth = max(2.1, size * 0.030)
    clip.stroke()

    switch lineStyle {
    case .greenShort:
        drawLine(x1: 0.40, x2: 0.57, y: 0.52, size: size, color: tealColor, width: 0.030)
        drawLine(x1: 0.40, x2: 0.51, y: 0.43, size: size, color: tealColor, width: 0.026)
    case .grayLines:
        let gray = NSColor(calibratedRed: 0.46, green: 0.48, blue: 0.50, alpha: 0.78)
        drawLine(x1: 0.38, x2: 0.58, y: 0.55, size: size, color: gray, width: 0.024)
        drawLine(x1: 0.38, x2: 0.54, y: 0.45, size: size, color: gray, width: 0.024)
        drawLine(x1: 0.38, x2: 0.49, y: 0.36, size: size, color: gray, width: 0.024)
    }
}

func drawStackedWindows(in rect: NSRect, size: CGFloat) {
    let stroke = NSColor(calibratedRed: 0.16, green: 0.20, blue: 0.24, alpha: 1)

    let backRect = NSRect(x: size * 0.30, y: size * 0.34, width: size * 0.30, height: size * 0.38)
    let frontRect = NSRect(x: size * 0.40, y: size * 0.24, width: size * 0.34, height: size * 0.38)

    for windowRect in [backRect, frontRect] {
        let path = openWindowPath(rect: windowRect, size: size)
        stroke.setStroke()
        path.lineWidth = max(2.5, size * 0.036)
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.stroke()
    }
}

func openWindowPath(rect: NSRect, size: CGFloat) -> NSBezierPath {
    let path = NSBezierPath()
    let radius = size * 0.035
    path.move(to: NSPoint(x: rect.minX + radius, y: rect.maxY))
    path.line(to: NSPoint(x: rect.maxX - radius, y: rect.maxY))
    path.curve(
        to: NSPoint(x: rect.maxX, y: rect.maxY - radius),
        controlPoint1: NSPoint(x: rect.maxX - radius * 0.45, y: rect.maxY),
        controlPoint2: NSPoint(x: rect.maxX, y: rect.maxY - radius * 0.45)
    )
    path.line(to: NSPoint(x: rect.maxX, y: rect.minY + radius))
    path.curve(
        to: NSPoint(x: rect.maxX - radius, y: rect.minY),
        controlPoint1: NSPoint(x: rect.maxX, y: rect.minY + radius * 0.45),
        controlPoint2: NSPoint(x: rect.maxX - radius * 0.45, y: rect.minY)
    )
    path.line(to: NSPoint(x: rect.minX + radius, y: rect.minY))
    path.curve(
        to: NSPoint(x: rect.minX, y: rect.minY + radius),
        controlPoint1: NSPoint(x: rect.minX + radius * 0.45, y: rect.minY),
        controlPoint2: NSPoint(x: rect.minX, y: rect.minY + radius * 0.45)
    )
    path.line(to: NSPoint(x: rect.minX, y: rect.maxY - radius))
    return path
}

func drawClock(in rect: NSRect, size: CGFloat) {
    let clockRect = NSRect(x: size * 0.55, y: size * 0.22, width: size * 0.26, height: size * 0.26)
    let circle = NSBezierPath(ovalIn: clockRect)
    NSColor.white.setFill()
    circle.fill()
    tealColor.setStroke()
    circle.lineWidth = max(2.4, size * 0.034)
    circle.stroke()

    let center = NSPoint(x: clockRect.midX, y: clockRect.midY)
    tealColor.setStroke()
    let hour = NSBezierPath()
    hour.lineWidth = max(2, size * 0.024)
    hour.lineCapStyle = .round
    hour.move(to: center)
    hour.line(to: NSPoint(x: center.x, y: center.y + size * 0.065))
    hour.stroke()

    let minute = NSBezierPath()
    minute.lineWidth = max(2, size * 0.024)
    minute.lineCapStyle = .round
    minute.move(to: center)
    minute.line(to: NSPoint(x: center.x + size * 0.055, y: center.y - size * 0.045))
    minute.stroke()
}

func drawLine(x1: CGFloat, x2: CGFloat, y: CGFloat, size: CGFloat, color: NSColor, width: CGFloat) {
    let path = NSBezierPath()
    path.lineWidth = max(1.5, size * width)
    path.lineCapStyle = .round
    path.move(to: NSPoint(x: size * x1, y: size * y))
    path.line(to: NSPoint(x: size * x2, y: size * y))
    color.setStroke()
    path.stroke()
}

let tealColor = NSColor(calibratedRed: 0.10, green: 0.72, blue: 0.62, alpha: 1)

for variant in IconVariant.allCases {
    let iconset = assets.appendingPathComponent(variant.iconsetName, isDirectory: true)
    if FileManager.default.fileExists(atPath: iconset.path) {
        try FileManager.default.removeItem(at: iconset)
    }
    try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

    for (name, size) in sizes {
        let image = iconImage(size: size, variant: variant)
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            continue
        }

        try png.write(to: iconset.appendingPathComponent(name))
    }
}
