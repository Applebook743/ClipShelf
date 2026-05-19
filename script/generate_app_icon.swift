import AppKit
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let assets = root.appendingPathComponent("Assets", isDirectory: true)
try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)

let appIconSizes: [(String, CGFloat)] = [
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
    case clipboardHistory = 1
    case historyList = 2
    case stackedHistory = 3
    case compactClipboard = 4

    var iconsetName: String {
        "AppIcon\(rawValue).iconset"
    }

    var sourceName: String {
        "AppIconSource\(rawValue).png"
    }
}

func pngData(from image: NSImage) -> Data? {
    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff) else {
        return nil
    }

    return bitmap.representation(using: .png, properties: [:])
}

func appIconPNG(from source: NSImage, size: CGFloat) -> Data? {
    let rect = NSRect(x: 0, y: 0, width: size, height: size)
    let image = NSImage(size: rect.size)
    let tileInset = size * 0.075
    let tileRect = rect.insetBy(dx: tileInset, dy: tileInset)

    image.lockFocus()
    NSGraphicsContext.current?.imageInterpolation = .high
    NSColor.clear.setFill()
    rect.fill()

    let cornerRadius = tileRect.width * 0.22
    let path = NSBezierPath(roundedRect: tileRect, xRadius: cornerRadius, yRadius: cornerRadius)
    path.addClip()
    source.draw(in: tileRect, from: .zero, operation: .sourceOver, fraction: 1)
    image.unlockFocus()

    return pngData(from: image)
}

func strokePath(_ path: NSBezierPath, width: CGFloat = 4.2) {
    NSColor.black.setStroke()
    path.lineWidth = width
    path.lineCapStyle = .round
    path.lineJoinStyle = .round
    path.stroke()
}

func strokeRoundedRect(_ rect: NSRect, radius: CGFloat, width: CGFloat = 4.2) {
    strokePath(NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius), width: width)
}

func strokeLine(from start: NSPoint, to end: NSPoint, width: CGFloat = 4.2) {
    let path = NSBezierPath()
    path.move(to: start)
    path.line(to: end)
    strokePath(path, width: width)
}

func drawClipboardOutline(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) {
    let path = NSBezierPath()
    path.move(to: NSPoint(x: x + width * 0.15, y: y))
    path.line(to: NSPoint(x: x, y: y))
    path.line(to: NSPoint(x: x, y: y + height * 0.86))
    path.line(to: NSPoint(x: x + width * 0.30, y: y + height * 0.86))
    path.move(to: NSPoint(x: x + width * 0.70, y: y + height * 0.86))
    path.line(to: NSPoint(x: x + width, y: y + height * 0.86))
    path.line(to: NSPoint(x: x + width, y: y + height * 0.30))
    strokePath(path)

    strokeRoundedRect(
        NSRect(x: x + width * 0.30, y: y + height * 0.78, width: width * 0.40, height: height * 0.20),
        radius: 4,
        width: 4.2
    )
    strokeRoundedRect(
        NSRect(x: x + width * 0.43, y: y + height * 0.91, width: width * 0.14, height: height * 0.10),
        radius: 4,
        width: 3.6
    )
}

func drawClock(center: NSPoint, radius: CGFloat) {
    let circle = NSBezierPath()
    circle.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 300)
    strokePath(circle)
    strokeLine(from: NSPoint(x: center.x, y: center.y), to: NSPoint(x: center.x, y: center.y + radius * 0.48), width: 4)
    strokeLine(from: NSPoint(x: center.x, y: center.y), to: NSPoint(x: center.x + radius * 0.43, y: center.y - radius * 0.36), width: 4)
}

func drawHistoryDots(center: NSPoint, radius: CGFloat) {
    let path = NSBezierPath()
    path.appendArc(withCenter: center, radius: radius, startAngle: 40, endAngle: 305)
    strokePath(path)

    for offset in [-8, 0, 8] {
        NSColor.black.setFill()
        NSBezierPath(ovalIn: NSRect(x: center.x + CGFloat(offset) - 2.3, y: center.y - 2.3, width: 4.6, height: 4.6)).fill()
    }
}

func drawStatusIcon() -> NSImage {
    let size: CGFloat = 72
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: size, height: size).fill()

    let clipboard = NSBezierPath()
    clipboard.move(to: NSPoint(x: 38, y: 10))
    clipboard.line(to: NSPoint(x: 18, y: 10))
    clipboard.curve(
        to: NSPoint(x: 13, y: 15),
        controlPoint1: NSPoint(x: 15, y: 10),
        controlPoint2: NSPoint(x: 13, y: 12)
    )
    clipboard.line(to: NSPoint(x: 13, y: 45))
    clipboard.curve(
        to: NSPoint(x: 19, y: 51),
        controlPoint1: NSPoint(x: 13, y: 49),
        controlPoint2: NSPoint(x: 16, y: 51)
    )
    clipboard.line(to: NSPoint(x: 26, y: 51))
    clipboard.move(to: NSPoint(x: 46, y: 51))
    clipboard.line(to: NSPoint(x: 53, y: 51))
    clipboard.curve(
        to: NSPoint(x: 59, y: 45),
        controlPoint1: NSPoint(x: 57, y: 51),
        controlPoint2: NSPoint(x: 59, y: 49)
    )
    clipboard.line(to: NSPoint(x: 59, y: 35))
    strokePath(clipboard, width: 4.8)

    strokeRoundedRect(NSRect(x: 25, y: 49, width: 22, height: 14), radius: 5, width: 4.8)
    strokeLine(from: NSPoint(x: 27, y: 40), to: NSPoint(x: 45, y: 40), width: 4.1)
    strokeLine(from: NSPoint(x: 27, y: 31), to: NSPoint(x: 40, y: 31), width: 4.1)
    strokeLine(from: NSPoint(x: 27, y: 23), to: NSPoint(x: 35, y: 23), width: 4.1)

    let clockCenter = NSPoint(x: 50, y: 22)
    let clockRadius: CGFloat = 18
    let clock = NSBezierPath(ovalIn: NSRect(
        x: clockCenter.x - clockRadius,
        y: clockCenter.y - clockRadius,
        width: clockRadius * 2,
        height: clockRadius * 2
    ))
    strokePath(clock, width: 5)
    strokeLine(from: clockCenter, to: NSPoint(x: clockCenter.x, y: clockCenter.y + 13), width: 5)
    strokeLine(from: clockCenter, to: NSPoint(x: clockCenter.x + 10, y: clockCenter.y - 8), width: 5)

    image.unlockFocus()
    return image
}

func statusIconPNG() -> Data? {
    pngData(from: drawStatusIcon())
}

for variant in IconVariant.allCases {
    let sourceURL = assets.appendingPathComponent(variant.sourceName)
    guard let source = NSImage(contentsOf: sourceURL) else {
        fputs("Missing icon source: \(sourceURL.path)\n", stderr)
        exit(1)
    }

    let iconset = assets.appendingPathComponent(variant.iconsetName, isDirectory: true)
    if FileManager.default.fileExists(atPath: iconset.path) {
        try FileManager.default.removeItem(at: iconset)
    }
    try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

    for (name, size) in appIconSizes {
        guard let png = appIconPNG(from: source, size: size) else {
            continue
        }

        try png.write(to: iconset.appendingPathComponent(name))
    }
}

if let png = statusIconPNG() {
    try png.write(to: assets.appendingPathComponent("AppStatusIcon.png"))
}
