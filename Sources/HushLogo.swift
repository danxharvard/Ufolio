import SwiftUI

/// The Ufolio mark: a flying saucer, drawn in code so it's sharp at every size and can animate.
///
/// - `eclipse` 0…1 animates the saucer's tractor beam fading in (1 is the resting state).
struct HushMark: View {
    var color: Color = .white
    var eclipse: CGFloat = 1
    var showStars = true
    /// Draws the saucer dimmed (used when Force Field is off).
    var outlined = false

    var body: some View {
        GeometryReader { geo in
            let d = min(geo.size.width, geo.size.height)
            ZStack {
                // The tractor beam.
                BeamShape()
                    .fill(LinearGradient(colors: [color.opacity(outlined ? 0.15 : 0.5 * eclipse), color.opacity(0)],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: d * 0.62, height: d * 0.36)
                    .offset(y: d * 0.26)
                // The saucer, as one clean silhouette.
                SaucerShape()
                    .fill(outlined ? color.opacity(0.4) : color)
                    .frame(width: d * 0.92, height: d * 0.5)
                    .offset(y: -d * 0.04)
                if showStars {
                    Circle().fill(color.opacity(0.85)).frame(width: d * 0.055, height: d * 0.055)
                        .offset(x: d * 0.34, y: -d * 0.36)
                    Circle().fill(color.opacity(0.65)).frame(width: d * 0.035, height: d * 0.035)
                        .offset(x: -d * 0.38, y: -d * 0.30)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityLabel("Ufolio")
    }
}

/// A saucer silhouette: a glass dome on a wide disc, with a little skirt underneath.
struct SaucerShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        // Dome.
        p.addEllipse(in: CGRect(x: r.minX + r.width * 0.30, y: r.minY, width: r.width * 0.40, height: r.height * 0.78))
        // Disc.
        p.addEllipse(in: CGRect(x: r.minX, y: r.minY + r.height * 0.42, width: r.width, height: r.height * 0.40))
        // Skirt.
        p.addEllipse(in: CGRect(x: r.minX + r.width * 0.18, y: r.minY + r.height * 0.66, width: r.width * 0.64, height: r.height * 0.30))
        return p
    }
}

/// The tractor beam: a cone widening downwards.
struct BeamShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX + r.width * 0.3, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - r.width * 0.3, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

/// The full-colour saucer: silver disc, glass dome with two little green men, rim lights and a
/// green beam, as in the app icon.
struct SaucerArt: View {
    var beam: CGFloat = 1
    var discColors: [Color] = [Color(white: 0.98), Color(white: 0.72), Color(white: 0.50)]

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                BeamShape()
                    .fill(LinearGradient(colors: [Color(red: 0.55, green: 1.0, blue: 0.55).opacity(0.55 * beam), .clear],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: w * 0.62, height: h * 0.34)
                    .offset(y: h * 0.30)
                // Dome with its crew.
                ZStack {
                    Ellipse().fill(LinearGradient(colors: [Color(red: 0.75, green: 0.95, blue: 1.0).opacity(0.6),
                                                           Color(red: 0.35, green: 0.70, blue: 0.95).opacity(0.4)],
                                                  startPoint: .top, endPoint: .bottom))
                    HStack(spacing: w * 0.01) {
                        Alien().frame(width: w * 0.12, height: h * 0.16)
                        Alien().frame(width: w * 0.105, height: h * 0.14).offset(y: h * 0.012)
                    }
                    .offset(y: h * 0.05)
                    Ellipse().fill(Color.white.opacity(0.45)).frame(width: w * 0.07, height: h * 0.045).offset(x: -w * 0.07, y: -h * 0.09)
                }
                .clipShape(Ellipse())
                .frame(width: w * 0.30, height: h * 0.32)
                .offset(y: -h * 0.10)
                // Disc, rim and lights.
                Ellipse().fill(LinearGradient(colors: discColors, startPoint: .top, endPoint: .bottom))
                    .frame(width: w * 0.70, height: h * 0.19).offset(y: h * 0.06)
                Ellipse().fill(LinearGradient(colors: [Color(white: 0.55), Color(white: 0.32)], startPoint: .top, endPoint: .bottom))
                    .frame(width: w * 0.56, height: h * 0.10).offset(y: h * 0.10)
                HStack(spacing: w * 0.055) {
                    ForEach(0..<5, id: \.self) { i in
                        Circle().fill([Color.yellow, Color.green, Color.cyan][i % 3]).frame(width: w * 0.032, height: w * 0.032)
                    }
                }
                .offset(y: h * 0.10)
            }
            .frame(width: w, height: h)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

/// One little green man: a head, two antennae and big black eyes.
private struct Alien: View {
    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            let green = Color(red: 0.42, green: 0.86, blue: 0.36)
            ZStack {
                ForEach([-1.0, 1.0], id: \.self) { side in
                    Capsule().fill(green).frame(width: w * 0.08, height: h * 0.32)
                        .rotationEffect(.degrees(side * 22)).offset(x: side * w * 0.2, y: -h * 0.36)
                    Circle().fill(green).frame(width: w * 0.16).offset(x: side * w * 0.27, y: -h * 0.5)
                }
                Ellipse().fill(green).frame(width: w * 0.9, height: h * 0.72).offset(y: h * 0.06)
                ForEach([-1.0, 1.0], id: \.self) { side in
                    Ellipse().fill(Color(white: 0.05)).frame(width: w * 0.26, height: h * 0.28).offset(x: side * w * 0.2, y: h * 0.02)
                }
            }
            .frame(width: w, height: h)
        }
    }
}

/// The Ufolio logo on its deep-space tile, as in the app icon.
struct HushLogoTile: View {
    var size: CGFloat
    var eclipse: CGFloat = 1

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.42, green: 0.25, blue: 0.80),
                                              Color(red: 0.20, green: 0.12, blue: 0.45),
                                              Color(red: 0.05, green: 0.06, blue: 0.20)],
                                     startPoint: .topTrailing, endPoint: .bottomLeading))
            if size >= 30 {
                Circle().fill(.white.opacity(0.9)).frame(width: size * 0.035).offset(x: size * 0.30, y: -size * 0.32)
                Circle().fill(.white.opacity(0.6)).frame(width: size * 0.025).offset(x: -size * 0.32, y: -size * 0.22)
                SaucerArt(beam: eclipse).padding(size * 0.02)
            } else {
                HushMark(eclipse: eclipse, showStars: false).padding(size * 0.14)   // tiny: the simple silhouette
            }
        }
        .frame(width: size, height: size)
        .shadow(color: Color(red: 0.2, green: 0.1, blue: 0.5).opacity(0.35), radius: size * 0.12, y: size * 0.05)
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

/// The saucer as a free-standing, gradient-lit object (for illustrations such as the Force
/// Field panel), in the given colours.
struct HushMoon: View {
    var colors: [Color]

    var body: some View {
        ZStack {
            SaucerShape()
                .fill(LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom))
                .frame(maxWidth: .infinity)
                .aspectRatio(1.85, contentMode: .fit)
            // A sheen across the dome and disc.
            SaucerShape()
                .fill(LinearGradient(colors: [.white.opacity(0.45), .clear], startPoint: .top, endPoint: .center))
                .aspectRatio(1.85, contentMode: .fit)
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
