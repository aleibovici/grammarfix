// Generates AppIcon.icns. Run: swift make-icon.swift
import AppKit

func render(size: Int) -> Data {
    let s = CGFloat(size)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // macOS icon grid: 824pt rounded square inside a 1024pt canvas.
    let inset = s * 100 / 1024
    let rect = NSRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let shape = NSBezierPath(roundedRect: rect, xRadius: s * 185 / 1024, yRadius: s * 185 / 1024)

    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
    shadow.shadowBlurRadius = s * 0.02
    shadow.shadowOffset = NSSize(width: 0, height: -s * 0.01)
    NSGraphicsContext.saveGraphicsState()
    shadow.set()
    NSColor.black.setFill()
    shape.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGradient(colors: [
        NSColor(srgbRed: 0.20, green: 0.78, blue: 0.60, alpha: 1),
        NSColor(srgbRed: 0.05, green: 0.48, blue: 0.52, alpha: 1),
    ])!.draw(in: shape, angle: -90)

    // "Aa" above an underline that ends in a tick.
    let font = NSFont.systemFont(ofSize: s * 0.40, weight: .bold)
    let text = NSAttributedString(string: "Aa", attributes: [.font: font, .foregroundColor: NSColor.white])
    let textSize = text.size()
    text.draw(at: NSPoint(x: (s - textSize.width) / 2, y: s * 0.40))

    let tick = NSBezierPath()
    tick.move(to: NSPoint(x: s * 0.27, y: s * 0.31))
    tick.line(to: NSPoint(x: s * 0.40, y: s * 0.31))
    tick.line(to: NSPoint(x: s * 0.49, y: s * 0.23))
    tick.line(to: NSPoint(x: s * 0.73, y: s * 0.40))
    tick.lineWidth = s * 0.05
    tick.lineCapStyle = .round
    tick.lineJoinStyle = .round
    NSColor.white.setStroke()
    tick.stroke()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let iconset = URL(fileURLWithPath: "build/AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try render(size: base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try render(size: base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}

let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", "AppIcon.icns"]
try task.run()
task.waitUntilExit()
print("Wrote AppIcon.icns")
