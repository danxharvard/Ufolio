import SwiftUI

/// The Hush mark ("Eclipse"): a crescent moon quietly swallowing a tracker.
/// Drawn in code, so it's sharp at every size and can animate.
///
/// - `eclipse` 0…1 animates the tracker dot from beside the moon (0) to tucked
///   inside its curve and faded (1), the resting state.
struct HushMark: View {
    var color: Color = .white
    var eclipse: CGFloat = 1
    var showStars = true
    /// Draws the moon dimmed (used when Hush Guard is off).
    var outlined = false

    var body: some View {
        GeometryReader { geo in
            let d = min(geo.size.width, geo.size.height)
            ZStack {
                // The tracker: slides into the moon's curve and fades away.
                Circle()
                    .fill(color.opacity(0.85 - 0.6 * eclipse))
                    .frame(width: d * (0.17 - 0.03 * eclipse), height: d * (0.17 - 0.03 * eclipse))
                    .offset(x: d * (0.32 - 0.14 * eclipse), y: d * (-0.08 - 0.03 * eclipse))

                // The crescent, drawn as one clean shape.
                CrescentShape()
                    .fill(outlined ? color.opacity(0.4) : color)
                    .frame(width: d * 0.62, height: d * 0.62)
                .offset(x: -d * 0.06, y: d * 0.03)

                if showStars {
                    Circle().fill(color.opacity(0.85)).frame(width: d * 0.055, height: d * 0.055)
                        .offset(x: d * 0.31, y: -d * 0.32)
                    Circle().fill(color.opacity(0.65)).frame(width: d * 0.035, height: d * 0.035)
                        .offset(x: d * 0.40, y: -d * 0.19)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityLabel("Hush")
    }
}

/// The Hush mark on its twilight tile, as in the app icon.
struct HushLogoTile: View {
    var size: CGFloat
    var eclipse: CGFloat = 1

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.62, green: 0.49, blue: 0.96),
                                              Color(red: 0.36, green: 0.27, blue: 0.75),
                                              Color(red: 0.16, green: 0.13, blue: 0.38)],
                                     startPoint: .topTrailing, endPoint: .bottomLeading))
            HushMark(eclipse: eclipse)
                .padding(size * 0.12)
        }
        .frame(width: size, height: size)
        .shadow(color: Color(red: 0.3, green: 0.2, blue: 0.7).opacity(0.35), radius: size * 0.12, y: size * 0.05)
    }
}

/// The logo playing its eclipse once: the tracker drifts behind the moon and fades.
struct AnimatedHushLogo: View {
    var size: CGFloat
    @State private var eclipse: CGFloat = 0
    @AppStorage(Prefs.reduceMotion) private var reduceMotion = false

    var body: some View {
        HushLogoTile(size: size, eclipse: eclipse)
            .onAppear {
                guard !reduceMotion else { eclipse = 1; return }
                withAnimation(.easeInOut(duration: 1.4).delay(0.35)) { eclipse = 1 }
            }
    }
}

/// The Hush crescent as a free-standing, gradient-lit object (for illustrations):
/// lit from the top right, with a soft highlight along its outer edge.
struct HushMoon: View {
    var colors: [Color]

    var body: some View {
        ZStack {
            CrescentShape()
                .fill(LinearGradient(colors: colors, startPoint: .topTrailing, endPoint: .bottomLeading))
            // A soft sheen from the lit side, clipped to the crescent.
            RadialGradient(colors: [.white.opacity(0.45), .clear], center: .init(x: 0.25, y: 0.8),
                           startRadius: 0, endRadius: 60)
                .clipShape(CrescentShape())
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

/// The Hush crescent as one clean outline: the moon's circle minus the "bite" circle,
/// computed from where the two circles meet, so it fills as a single shape with no seams.
struct CrescentShape: Shape {
    /// Bite centre offset and size as fractions of the moon's diameter (y is downwards).
    var biteOffset = CGPoint(x: 0.21, y: -0.14)
    var biteScale: CGFloat = 0.84

    func path(in rect: CGRect) -> Path {
        let d = min(rect.width, rect.height)
        let c1 = CGPoint(x: rect.midX, y: rect.midY), r1 = d / 2
        let c2 = CGPoint(x: c1.x + biteOffset.x * d, y: c1.y + biteOffset.y * d), r2 = r1 * biteScale
        let dx = c2.x - c1.x, dy = c2.y - c1.y
        let dist = sqrt(dx * dx + dy * dy)
        guard dist > 0, dist < r1 + r2, dist > abs(r1 - r2) else { return Path(ellipseIn: rect) }
        let a = (r1 * r1 - r2 * r2 + dist * dist) / (2 * dist)
        let h = sqrt(max(0, r1 * r1 - a * a))
        let mid = CGPoint(x: c1.x + a * dx / dist, y: c1.y + a * dy / dist)
        let p1 = CGPoint(x: mid.x + h * (-dy) / dist, y: mid.y + h * dx / dist)
        let p2 = CGPoint(x: mid.x - h * (-dy) / dist, y: mid.y - h * dx / dist)

        func angle(_ p: CGPoint, from c: CGPoint) -> CGFloat { atan2(p.y - c.y, p.x - c.x) }
        func span(from start: CGFloat, to end: CGFloat, through want: CGFloat, avoid: Bool) -> (CGFloat, CGFloat) {
            var delta = end - start
            while delta <= 0 { delta += 2 * .pi }
            var midAngle = start + delta / 2
            midAngle = atan2(sin(midAngle), cos(midAngle))
            let diff = abs(atan2(sin(midAngle - want), cos(midAngle - want)))
            let passes = diff < .pi / 2
            return passes == avoid ? (start, delta - 2 * .pi) : (start, delta)
        }

        var path = Path()
        // Outer edge: around the moon, the long way (away from the bite).
        let (o0, oSweep) = span(from: angle(p1, from: c1), to: angle(p2, from: c1), through: angle(c2, from: c1), avoid: true)
        let steps = 72
        for i in 0...steps {
            let t = o0 + oSweep * CGFloat(i) / CGFloat(steps)
            let pt = CGPoint(x: c1.x + r1 * cos(t), y: c1.y + r1 * sin(t))
            if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
        }
        // Inner edge: back along the bite's curve, on the side facing the moon's centre.
        let (i0, iSweep) = span(from: angle(p2, from: c2), to: angle(p1, from: c2), through: angle(c1, from: c2), avoid: false)
        for i in 0...steps {
            let t = i0 + iSweep * CGFloat(i) / CGFloat(steps)
            path.addLine(to: CGPoint(x: c2.x + r2 * cos(t), y: c2.y + r2 * sin(t)))
        }
        path.closeSubpath()
        return path
    }
}
