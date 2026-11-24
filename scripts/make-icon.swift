// Draws the Ufolio app icon (a flying saucer with little green men) and writes Resources/AppIcon.icns.
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

    func oval(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSBezierPath {
        NSBezierPath(ovalIn: NSRect(x: x * s, y: y * s, width: w * s, height: h * s))
    }

    // Deep space: navy into violet.
    NSGradient(colors: [
        NSColor(red: 0.05, green: 0.06, blue: 0.20, alpha: 1),
        NSColor(red: 0.20, green: 0.12, blue: 0.45, alpha: 1),
        NSColor(red: 0.42, green: 0.25, blue: 0.80, alpha: 1),
    ])!.draw(in: shape, angle: 70)

    NSGraphicsContext.saveGraphicsState()
    shape.addClip()

    // Stars.
    for (x, y, r, a) in [(210.0, 820.0, 7.0, 0.9), (330.0, 760.0, 4.0, 0.7), (790.0, 830.0, 8.0, 0.95), (850.0, 700.0, 5.0, 0.7),
                         (180.0, 610.0, 5.0, 0.6), (700.0, 880.0, 4.0, 0.6), (880.0, 520.0, 4.0, 0.5), (260.0, 420.0, 3.5, 0.5)] {
        NSColor(white: 1, alpha: a).setFill()
        oval(x - r, y - r, 2 * r, 2 * r).fill()
    }

    // Tractor beam: a soft green cone below the saucer.
    let beam = NSBezierPath()
    beam.move(to: NSPoint(x: 400 * s, y: 430 * s))
    beam.line(to: NSPoint(x: 624 * s, y: 430 * s))
    beam.line(to: NSPoint(x: 760 * s, y: 110 * s))
    beam.line(to: NSPoint(x: 264 * s, y: 110 * s))
    beam.close()
    NSGradient(colors: [NSColor(red: 0.55, green: 1.0, blue: 0.55, alpha: 0.55), NSColor(red: 0.55, green: 1.0, blue: 0.55, alpha: 0.0)])!
        .draw(in: beam, angle: -90)

    // Glass dome, with two little green men inside.
    let dome = oval(372, 470, 280, 290)
    NSGradient(colors: [NSColor(red: 0.75, green: 0.95, blue: 1.0, alpha: 0.55), NSColor(red: 0.35, green: 0.70, blue: 0.95, alpha: 0.35)])!
        .draw(in: dome, angle: -90)
    NSGraphicsContext.saveGraphicsState()
    dome.addClip()
    for (cx, cy, scale) in [(462.0, 560.0, 1.0), (566.0, 548.0, 0.88)] {
        let green = NSColor(red: 0.42, green: 0.86, blue: 0.36, alpha: 1)
        // Antennae.
        green.setStroke()
        for dx in [-22.0, 22.0] {
            let a = NSBezierPath()
            a.lineWidth = 7 * s * scale
            a.move(to: NSPoint(x: (cx + dx * 0.6) * s, y: (cy + 70 * scale) * s))
            a.line(to: NSPoint(x: (cx + dx * 1.3) * s, y: (cy + 118 * scale) * s))
            a.stroke()
            green.setFill()
            oval(cx + dx * 1.3 - 9 * scale, cy + 112 * scale, 18 * scale, 18 * scale).fill()
        }
        // Head.
        green.setFill()
        oval(cx - 52 * scale, cy - 10 * scale, 104 * scale, 112 * scale).fill()
        // Big black eyes.
        NSColor(white: 0.05, alpha: 1).setFill()
        for dx in [-22.0, 22.0] {
            let eye = oval(cx + dx * scale - 16 * scale, cy + 32 * scale, 32 * scale, 40 * scale)
            eye.fill()
            NSColor(white: 1, alpha: 0.85).setFill()
            oval(cx + dx * scale - 4 * scale, cy + 56 * scale, 9 * scale, 9 * scale).fill()
            NSColor(white: 0.05, alpha: 1).setFill()
        }
    }
    NSGraphicsContext.restoreGraphicsState()
    // Dome highlight.
    NSColor(white: 1, alpha: 0.45).setFill()
    oval(420, 660, 70, 46).fill()

    // The saucer: a wide silver disc with a darker rim.
    let disc = oval(170, 380, 684, 180)
    NSGradient(colors: [NSColor(white: 0.97, alpha: 1), NSColor(white: 0.72, alpha: 1), NSColor(white: 0.50, alpha: 1)])!
        .draw(in: disc, angle: -90)
    let rim = oval(230, 372, 564, 96)
    NSGradient(colors: [NSColor(white: 0.55, alpha: 1), NSColor(white: 0.32, alpha: 1)])!.draw(in: rim, angle: -90)
    // Rim lights.
    let lights = [NSColor(red: 1.0, green: 0.85, blue: 0.3, alpha: 1), NSColor(red: 0.55, green: 1.0, blue: 0.55, alpha: 1),
                  NSColor(red: 0.45, green: 0.85, blue: 1.0, alpha: 1)]
    for (i, x) in [292.0, 382.0, 472.0, 552.0, 642.0, 732.0].enumerated() {
        let y = 418.0 - abs(x - 512.0) * 0.06
        lights[i % lights.count].setFill()
        oval(x - 14, y - 14, 28, 28).fill()
    }
    // A sheen across the top of the disc.
    NSColor(white: 1, alpha: 0.35).setFill()
    oval(300, 505, 300, 34).fill()

    NSGraphicsContext.restoreGraphicsState()

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
