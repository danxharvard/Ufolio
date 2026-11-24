// Draws the background of the installer window (the "drag Hush into Applications" box).
// Usage: swift scripts/make-dmg-background.swift <output-folder>
// Writes background.png (640×420) and background@2x.png; build-app.sh combines them.
import AppKit

let width: CGFloat = 640
let height: CGFloat = 420
// Icon centres, measured from the top-left like Finder does (must match scripts/dmg-settings.py).
let appCenter = CGPoint(x: 170, y: 220)
let applicationsCenter = CGPoint(x: 470, y: 220)

func render(scale: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width * scale), pixelsHigh: Int(height * scale),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: width, height: height) // points, so @2x is treated as Retina
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    let canvas = NSRect(x: 0, y: 0, width: width, height: height)

    // Soft twilight gradient, light enough for Finder's dark icon labels.
    NSGradient(colors: [
        NSColor(red: 0.975, green: 0.968, blue: 1.0, alpha: 1),
        NSColor(red: 0.925, green: 0.910, blue: 0.985, alpha: 1),
    ])!.draw(in: canvas, angle: -90)

    // Two gentle glows in Hush's colours.
    // A smooth radial fade from the colour to fully transparent, with no visible edge.
    func glow(_ color: NSColor, center: CGPoint, radius: CGFloat) {
        guard let cg = NSGraphicsContext.current?.cgContext,
              let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                        colors: [color.cgColor, color.withAlphaComponent(color.alphaComponent * 0.45).cgColor,
                                                 color.withAlphaComponent(0).cgColor] as CFArray,
                                        locations: [0, 0.45, 1]) else { return }
        cg.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [])
    }
    glow(NSColor(red: 0.55, green: 0.42, blue: 0.98, alpha: 0.20), center: CGPoint(x: 90, y: height - 60), radius: 260)
    glow(NSColor(red: 0.30, green: 0.62, blue: 1.0, alpha: 0.14), center: CGPoint(x: width - 60, y: 40), radius: 280)

    func text(_ string: String, size: CGFloat, weight: NSFont.Weight, color: NSColor, y: CGFloat) {
        let font = NSFont.systemFont(ofSize: size, weight: weight)
        let rounded = font.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: size) } ?? font
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        let attributed = NSAttributedString(string: string, attributes: [
            .font: rounded, .foregroundColor: color, .paragraphStyle: style, .kern: size > 20 ? 0.3 : 0,
        ])
        let h = attributed.size().height
        attributed.draw(in: NSRect(x: 0, y: height - y - h / 2, width: width, height: h))
    }

    text("Ufolio Browser", size: 26, weight: .semibold, color: NSColor(red: 0.13, green: 0.11, blue: 0.24, alpha: 1), y: 58)
    text("Drag Ufolio into your Applications folder to install it.", size: 13.5, weight: .regular,
         color: NSColor(red: 0.36, green: 0.34, blue: 0.46, alpha: 1), y: 90)

    // The arrow, from Hush towards Applications, with a gentle arc.
    let startX = appCenter.x + 86, endX = applicationsCenter.x - 86
    let y = height - appCenter.y
    let arrow = NSBezierPath()
    arrow.move(to: CGPoint(x: startX, y: y))
    arrow.curve(to: CGPoint(x: endX, y: y), controlPoint1: CGPoint(x: startX + 40, y: y + 22),
                controlPoint2: CGPoint(x: endX - 40, y: y + 22))
    arrow.lineWidth = 3.5
    arrow.lineCapStyle = .round
    let dash: [CGFloat] = [0.01, 9]
    arrow.setLineDash(dash, count: 2, phase: 0)
    NSColor(red: 0.47, green: 0.36, blue: 0.93, alpha: 0.85).setStroke()
    arrow.stroke()

    // Arrowhead.
    let head = NSBezierPath()
    head.move(to: CGPoint(x: endX - 13, y: y + 10))
    head.line(to: CGPoint(x: endX + 1, y: y))
    head.line(to: CGPoint(x: endX - 13, y: y - 10))
    head.lineWidth = 3.5
    head.lineCapStyle = .round
    head.lineJoinStyle = .round
    head.stroke()

    text("github.com/danxharvard/Ufolio", size: 10.5, weight: .regular,
         color: NSColor(red: 0.50, green: 0.48, blue: 0.60, alpha: 1), y: height - 26)

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
try! FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
try! render(scale: 1).representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent("background.png"))
try! render(scale: 2).representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent("background@2x.png"))
print("Wrote installer background to \(out.path)")
