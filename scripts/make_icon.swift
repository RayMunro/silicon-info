// Draws the Silicon Info app icon (three power arcs, CPU / GPU / Neural Engine) into an .iconset folder.
// Usage: swift make_icon.swift <out.iconset>
import AppKit

func draw(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let k = CGFloat(px) / 1024
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.scaleBy(x: k, y: k)

    // macOS icon grid: 824pt rounded square centred on the 1024 canvas
    let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
    let path = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: NSColor.black.withAlphaComponent(0.35).cgColor)
    NSColor.black.setFill(); path.fill()
    ctx.restoreGState()
    path.addClip()
    NSGradient(colors: [NSColor(red: 0.13, green: 0.14, blue: 0.22, alpha: 1), NSColor(red: 0.03, green: 0.03, blue: 0.07, alpha: 1)])!
        .draw(in: tile, angle: -90)

    let c = NSPoint(x: 512, y: 512)
    func arc(_ r: CGFloat, _ from: CGFloat, _ to: CGFloat, _ color: NSColor, _ w: CGFloat) {
        let a = NSBezierPath()
        a.appendArc(withCenter: c, radius: r, startAngle: from, endAngle: to, clockwise: false)
        a.lineWidth = w; a.lineCapStyle = .round
        color.withAlphaComponent(0.16).setStroke()
        let track = NSBezierPath(ovalIn: NSRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
        track.lineWidth = w; track.stroke()
        color.setStroke(); a.stroke()
    }
    let blue = NSColor(red: 0.30, green: 0.60, blue: 1.00, alpha: 1)
    let orange = NSColor(red: 1.00, green: 0.55, blue: 0.25, alpha: 1)
    let purple = NSColor(red: 0.75, green: 0.45, blue: 1.00, alpha: 1)
    arc(300, 90, -200, blue, 62)     // CPU, outer ring
    arc(200, 90, -120, orange, 62)   // GPU
    arc(100, 90, 10, purple, 62)     // Neural Engine, inner ring

    // pulse dot in the middle
    NSColor.white.setFill()
    NSBezierPath(ovalIn: NSRect(x: 512 - 30, y: 512 - 30, width: 60, height: 60)).fill()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let out = CommandLine.arguments[1]
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
for (name, px) in [("16", 16), ("16@2x", 32), ("32", 32), ("32@2x", 64), ("128", 128), ("128@2x", 256),
                   ("256", 256), ("256@2x", 512), ("512", 512), ("512@2x", 1024)] {
    try! draw(px).write(to: URL(fileURLWithPath: "\(out)/icon_\(name.replacingOccurrences(of: "@2x", with: ""))x\(name.replacingOccurrences(of: "@2x", with: ""))\(name.hasSuffix("@2x") ? "@2x" : "").png"))
}
