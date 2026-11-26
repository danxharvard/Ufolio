import SwiftUI

// Warp speed: a quick starfield streak when you switch Orbits. It lasts under half a second and
// is drawn over the window without touching it.

// MARK: - Warp speed

/// A quick starfield streak when you switch Orbits: under half a second, drawn over the window
/// without touching it, and never in the way of the switch itself.
enum WarpSpeed {
    static let notification = Notification.Name("UfolioWarpSpeed")
    static func engage(for model: BrowserModel) {
        guard Effects.on else { return }
        NotificationCenter.default.post(name: notification, object: model)
    }
}

struct WarpSpeedOverlay: View {
    let model: BrowserModel
    @State private var started: Date?
    private static let duration: TimeInterval = 0.42

    var body: some View {
        ZStack {
            if let started {
                TimelineView(.animation) { context in
                    let p = min(1, context.date.timeIntervalSince(started) / Self.duration)
                    Canvas { ctx, size in Self.draw(ctx, size: size, progress: p) }
                }
                .transition(.identity)
            }
        }
        .allowsHitTesting(false)
        .onReceive(NotificationCenter.default.publisher(for: WarpSpeed.notification)) { note in
            guard (note.object as AnyObject?) === model else { return }
            let now = Date()
            started = now
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.duration + 0.03) {
                if started == now { started = nil }
            }
        }
    }

    private static func draw(_ ctx: GraphicsContext, size: CGSize, progress p: Double) {
        let center = CGPoint(x: size.width / 2, y: size.height * 0.46)
        let reach = hypot(size.width, size.height) * 0.6
        // In and out: brightest in the middle of the jump.
        let fade = sin(.pi * p)
        var random = SeededRandom(seed: 42)
        let speed = p * p   // accelerating
        for i in 0..<90 {
            let angle = random.next() * 2 * .pi
            let start = 0.08 + random.next() * 0.5
            let length = 0.10 + random.next() * 0.25
            let r1 = (start + speed * 0.9) * reach
            let r2 = r1 + (length * (0.3 + speed * 2.2)) * reach
            let dx = cos(angle), dy = sin(angle)
            var line = Path()
            line.move(to: CGPoint(x: center.x + dx * r1, y: center.y + dy * r1))
            line.addLine(to: CGPoint(x: center.x + dx * r2, y: center.y + dy * r2))
            let tint: Color = i % 7 == 0 ? Color(red: 0.75, green: 0.66, blue: 1.0) : i % 5 == 0 ? Color(red: 0.6, green: 0.95, blue: 1.0) : .white
            ctx.stroke(line, with: .color(tint.opacity(0.75 * fade)), style: StrokeStyle(lineWidth: i % 3 == 0 ? 1.6 : 1, lineCap: .round))
        }
        // A faint flash at the centre as the jump peaks.
        let glow = Path(ellipseIn: CGRect(x: center.x - 160, y: center.y - 160, width: 320, height: 320))
        ctx.fill(glow, with: .radialGradient(Gradient(colors: [.white.opacity(0.18 * fade), .clear]),
                                             center: center, startRadius: 0, endRadius: 160))
    }
}
