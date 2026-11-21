// Draws three Hush logo directions side by side: build/logo-concepts.png
import AppKit

let tile: CGFloat = 420, gap: CGFloat = 60, labelH: CGFloat = 70
let W = tile * 3 + gap * 4, H = tile + gap * 2 + labelH
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W), pixelsHigh: Int(H), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
NSColor(red: 0.96, green: 0.95, blue: 0.99, alpha: 1).setFill()
NSRect(x: 0, y: 0, width: W, height: H).fill()

let twilight = NSGradient(colors: [NSColor(red: 0.16, green: 0.13, blue: 0.38, alpha: 1),
                                   NSColor(red: 0.36, green: 0.27, blue: 0.75, alpha: 1),
                                   NSColor(red: 0.62, green: 0.49, blue: 0.96, alpha: 1)])!

func crescent(center c: CGPoint, r: CGFloat, biteOffset: CGPoint, biteScale: CGFloat) -> (NSBezierPath, NSBezierPath) {
    let moon = NSBezierPath(ovalIn: NSRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
    let br = r * biteScale
    let bc = CGPoint(x: c.x + biteOffset.x * r, y: c.y + biteOffset.y * r)
    let bite = NSBezierPath(ovalIn: NSRect(x: bc.x - br, y: bc.y - br, width: 2 * br, height: 2 * br))
    return (moon, bite)
}

func drawCrescent(_ moon: NSBezierPath, _ bite: NSBezierPath, color: NSColor, in rect: NSRect) {
    NSGraphicsContext.saveGraphicsState()
    let clip = NSBezierPath(rect: rect)
    clip.append(bite.reversed)
    clip.addClip()
    color.setFill()
    moon.fill()
    NSGraphicsContext.restoreGraphicsState()
}

func shadowed(_ draw: () -> Void) {
    NSGraphicsContext.saveGraphicsState()
    let s = NSShadow(); s.shadowColor = NSColor.black.withAlphaComponent(0.28); s.shadowBlurRadius = 22; s.shadowOffset = NSSize(width: 0, height: -10)
    s.set(); draw()
    NSGraphicsContext.restoreGraphicsState()
}

func label(_ text: String, _ sub: String, x: CGFloat) {
    let p = NSMutableParagraphStyle(); p.alignment = .center
    NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 26, weight: .semibold), .foregroundColor: NSColor(white: 0.12, alpha: 1), .paragraphStyle: p])
        .draw(in: NSRect(x: x, y: 38, width: tile, height: 34))
    NSAttributedString(string: sub, attributes: [.font: NSFont.systemFont(ofSize: 17), .foregroundColor: NSColor(white: 0.4, alpha: 1), .paragraphStyle: p])
        .draw(in: NSRect(x: x, y: 12, width: tile, height: 26))
}

let y0 = labelH + gap

// A — Guard Moon: a soft shield with the crescent cut out.
do {
    let x = gap, r = NSRect(x: x, y: y0, width: tile, height: tile)
    let s = NSBezierPath()
    let top = r.maxY - 30, mid = r.midX
    s.move(to: CGPoint(x: mid, y: top))
    s.curve(to: CGPoint(x: r.maxX - 40, y: top - 60), controlPoint1: CGPoint(x: mid + 90, y: top), controlPoint2: CGPoint(x: r.maxX - 40, y: top - 20))
    s.curve(to: CGPoint(x: mid, y: r.minY + 20), controlPoint1: CGPoint(x: r.maxX - 40, y: r.minY + 170), controlPoint2: CGPoint(x: mid + 110, y: r.minY + 60))
    s.curve(to: CGPoint(x: r.minX + 40, y: top - 60), controlPoint1: CGPoint(x: mid - 110, y: r.minY + 60), controlPoint2: CGPoint(x: r.minX + 40, y: r.minY + 170))
    s.curve(to: CGPoint(x: mid, y: top), controlPoint1: CGPoint(x: r.minX + 40, y: top - 20), controlPoint2: CGPoint(x: mid - 90, y: top))
    s.close()
    shadowed { NSColor.black.setFill(); s.fill() }
    twilight.draw(in: s, angle: 70)
    let (moon, bite) = crescent(center: CGPoint(x: mid - 6, y: r.midY + 18), r: 96, biteOffset: CGPoint(x: 0.42, y: 0.30), biteScale: 0.86)
    drawCrescent(moon, bite, color: .white, in: r)
    label("A · Guard Moon", "Shield + moon: Hush Guard is the brand", x: x)
}

// B — Hushed Signal: crescent with tracking waves fading out.
do {
    let x = gap * 2 + tile, r = NSRect(x: x, y: y0, width: tile, height: tile)
    let sq = NSBezierPath(roundedRect: r.insetBy(dx: 20, dy: 20), xRadius: 86, yRadius: 86)
    shadowed { NSColor.black.setFill(); sq.fill() }
    twilight.draw(in: sq, angle: 65)
    let c = CGPoint(x: r.midX - 46, y: r.midY)
    let (moon, bite) = crescent(center: c, r: 98, biteOffset: CGPoint(x: 0.45, y: 0.28), biteScale: 0.84)
    drawCrescent(moon, bite, color: .white, in: r)
    for (i, radius) in [CGFloat(70), 105, 140].enumerated() {
        let arc = NSBezierPath()
        arc.appendArc(withCenter: CGPoint(x: c.x + 64, y: c.y), radius: radius, startAngle: -32, endAngle: 32)
        arc.lineWidth = 14; arc.lineCapStyle = .round
        NSColor.white.withAlphaComponent(0.55 - CGFloat(i) * 0.2).setStroke(); arc.stroke()
    }
    label("B · Hushed Signal", "Tracking waves fading into silence", x: x)
}

// C — Eclipse: the moon eclipses a tracker dot.
do {
    let x = gap * 3 + tile * 2, r = NSRect(x: x, y: y0, width: tile, height: tile)
    let sq = NSBezierPath(roundedRect: r.insetBy(dx: 20, dy: 20), xRadius: 86, yRadius: 86)
    shadowed { NSColor.black.setFill(); sq.fill() }
    twilight.draw(in: sq, angle: 65)
    let c = CGPoint(x: r.midX - 12, y: r.midY - 4)
    let (moon, bite) = crescent(center: c, r: 118, biteOffset: CGPoint(x: 0.40, y: 0.26), biteScale: 0.84)
    drawCrescent(moon, bite, color: .white, in: r)
    // The tracker: a small dot half-hidden inside the moon's curve, fading.
    let dc = CGPoint(x: c.x + 62, y: c.y + 38)
    NSGradient(colors: [NSColor.white.withAlphaComponent(0.9), NSColor.white.withAlphaComponent(0.15)])!
        .draw(in: NSBezierPath(ovalIn: NSRect(x: dc.x - 22, y: dc.y - 22, width: 44, height: 44)), angle: 210)
    for (dx, dy, rr) in [(CGFloat(120), CGFloat(120), CGFloat(9)), (150, 70, 6)] {
        NSColor.white.withAlphaComponent(0.8).setFill()
        NSBezierPath(ovalIn: NSRect(x: c.x + dx - rr, y: c.y + dy - rr, width: rr * 2, height: rr * 2)).fill()
    }
    label("C · Eclipse", "The moon quietly swallows a tracker", x: x)
}

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
print("ok")
