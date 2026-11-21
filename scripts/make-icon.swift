// Draws the Hush app icon and writes Resources/AppIcon.icns.
// Run: swift scripts/make-icon.swift   (build-app.sh does this when the icon is missing)
import AppKit

func render(size: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = size / 1024

    // macOS icon grid: 824pt rounded square centred on a 1024 canvas, with a soft shadow.
    let rect = NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    let shape = NSBezierPath(roundedRect: rect, xRadius: 185 * s, yRadius: 185 * s)
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
    shadow.shadowBlurRadius = 24 * s
    shadow.shadowOffset = NSSize(width: 0, height: -10 * s)
    NSGraphicsContext.saveGraphicsState()
    shadow.set()
    NSColor.black.setFill()
    shape.fill()
    NSGraphicsContext.restoreGraphicsState()

    // Twilight gradient.
    NSGradient(colors: [
        NSColor(red: 0.16, green: 0.13, blue: 0.38, alpha: 1),
        NSColor(red: 0.36, green: 0.27, blue: 0.75, alpha: 1),
        NSColor(red: 0.62, green: 0.49, blue: 0.96, alpha: 1),
    ])!.draw(in: shape, angle: 65)

    // Soft glow behind the moon.
    NSGraphicsContext.saveGraphicsState()
    shape.addClip()
    let glowRect = NSRect(x: 230 * s, y: 250 * s, width: 560 * s, height: 560 * s)
    NSGradient(colors: [NSColor.white.withAlphaComponent(0.22), NSColor.white.withAlphaComponent(0)])!
        .draw(in: NSBezierPath(ovalIn: glowRect), relativeCenterPosition: .zero)
    NSGraphicsContext.restoreGraphicsState()

    // Crescent moon: a circle with a smaller offset circle cut out.
    let moon = NSBezierPath(ovalIn: NSRect(x: 300 * s, y: 290 * s, width: 430 * s, height: 430 * s))
    let bite = NSBezierPath(ovalIn: NSRect(x: 420 * s, y: 390 * s, width: 380 * s, height: 380 * s))
    NSGraphicsContext.saveGraphicsState()
    let clip = NSBezierPath(rect: NSRect(x: 0, y: 0, width: size, height: size))
    clip.append(bite.reversed)
    clip.addClip()
    NSColor(white: 1, alpha: 0.96).setFill()
    moon.fill()
    NSGraphicsContext.restoreGraphicsState()

    // A few small stars.
    for (x, y, r) in [(690.0, 640.0, 16.0), (760.0, 540.0, 10.0), (640.0, 740.0, 8.0)] {
        NSColor(white: 1, alpha: 0.9).setFill()
        NSBezierPath(ovalIn: NSRect(x: (x - r) * s, y: (y - r) * s, width: 2 * r * s, height: 2 * r * s)).fill()
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
let iconset = root.appendingPathComponent("build/AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let px = CGFloat(base * scale)
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        let png = render(size: px).representation(using: .png, properties: [:])!
        try! png.write(to: iconset.appendingPathComponent(name))
    }
}
print("Wrote \(iconset.path)")
