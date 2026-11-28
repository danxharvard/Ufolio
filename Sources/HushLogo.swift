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
struct Alien: View {
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
    @AppStorage(Prefs.theme) private var theme = "classic"

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
                .fill(LinearGradient(colors: AlienTheme.isActive(theme) ? AlienTheme.tile
                                        : [Color(red: 0.42, green: 0.25, blue: 0.80),
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

/// The logo with its eclipse complete (it used to play the eclipse as it appeared).
struct AnimatedHushLogo: View {
    var size: CGFloat

    var body: some View {
        HushLogoTile(size: size, eclipse: 1)
    }
}

/// The saucer flying about and zapping ads with its beams (the setup guide's welcome).
/// Drawn from the clock at 30 frames a second; still when Reduce Motion is on.
struct UFOZapperScene: View {
    @AppStorage(Prefs.reduceMotion) private var reduceMotion = false
    /// Paused while its window isn't the one you're using (Settings left open behind the browser
    /// kept drawing 30 frames a second for nobody). Only the window you're typing in is "key":
    /// one behind the browser in Ufolio itself is "active", not "inactive", and kept drawing.
    @Environment(\.controlActiveState) private var activeState

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion || activeState != .key)) { context in
            let t = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
            GeometryReader { geo in
                let w = geo.size.width, h = geo.size.height
                // A lazy figure-of-eight across the sky.
                let saucerX = w * 0.5 + CGFloat(sin(t * 0.55)) * w * 0.28
                let saucerY = h * 0.30 + CGFloat(sin(t * 1.1)) * h * 0.08
                let saucerW = min(w, h) * 0.42
                ZStack {
                    ZapperCanvas(t: t, size: geo.size, muzzle: CGPoint(x: saucerX, y: saucerY + saucerW * 0.12))
                    SaucerArt(beam: 0)
                        .frame(width: saucerW, height: saucerW)
                        .rotationEffect(.degrees(cos(t * 0.55) * 7))   // banks as it turns
                        .position(x: saucerX, y: saucerY)
                }
            }
        }
    }
}

/// Ads drifting up from below; the saucer's bolt hits each one and it bursts apart.
private struct ZapperCanvas: View {
    let t: Double
    let size: CGSize
    let muzzle: CGPoint
    private static let laser = Color(red: 0.55, green: 1.0, blue: 0.55)
    private static let adColors = [Color(red: 1.0, green: 0.42, blue: 0.36), Color(red: 1.0, green: 0.62, blue: 0.25),
                                   Color(red: 0.95, green: 0.35, blue: 0.6), Color(red: 0.4, green: 0.6, blue: 1.0)]

    var body: some View {
        Canvas { ctx, _ in
            let lanes: [CGFloat] = [0.14, 0.38, 0.62, 0.86]
            for (i, lane) in lanes.enumerated() {
                let phase = ((t / 2.6) + Double(i) / 4).truncatingRemainder(dividingBy: 1)
                let x = size.width * lane + CGFloat(sin(t + Double(i) * 1.7)) * 8
                let y = size.height * 0.82 + CGFloat(sin(t * 1.4 + Double(i))) * 4
                let color = Self.adColors[i % Self.adColors.count]
                let ad = CGRect(x: x - 20, y: y - 12, width: 40, height: 24)
                switch phase {
                case ..<0.45:
                    draw(ctx, ad.offsetBy(dx: 0, dy: CGFloat((0.45 - phase) * 30)), color.opacity(min(1, phase * 4)))
                case ..<0.56:
                    draw(ctx, ad, color)
                    let p = (phase - 0.45) / 0.11
                    let head = CGPoint(x: muzzle.x + (x - muzzle.x) * p, y: muzzle.y + (y - muzzle.y) * p)
                    var bolt = Path(); bolt.move(to: muzzle); bolt.addLine(to: head)
                    ctx.stroke(bolt, with: .color(Self.laser.opacity(0.35)), style: StrokeStyle(lineWidth: 9, lineCap: .round))
                    ctx.stroke(bolt, with: .color(.white.opacity(0.95)), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                case ..<0.82:
                    let k = (phase - 0.56) / 0.26
                    let flash = 12 + 40 * k
                    ctx.fill(Path(ellipseIn: CGRect(x: x - flash / 2, y: y - flash / 2, width: flash, height: flash)), with: .color(Self.laser.opacity(0.5 * (1 - k))))
                    for f in 0..<8 {
                        let a = Double(f) / 8 * 2 * .pi + Double(i)
                        let r = 8 + 34 * k
                        let s = 6 * (1 - k * 0.6)
                        ctx.fill(Path(roundedRect: CGRect(x: x + CGFloat(cos(a) * r) - s / 2, y: y + CGFloat(sin(a) * r) + CGFloat(k * k * 14) - s / 2, width: s, height: s), cornerRadius: 1.5),
                                 with: .color(color.opacity(1 - k)))
                    }
                default: break
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func draw(_ ctx: GraphicsContext, _ r: CGRect, _ color: Color) {
        ctx.fill(Path(roundedRect: r, cornerRadius: 6), with: .color(color))
        ctx.stroke(Path(roundedRect: r, cornerRadius: 6), with: .color(.white.opacity(0.35)), lineWidth: 1)
        ctx.draw(Text("AD").font(.system(size: 12, weight: .heavy, design: .rounded)).foregroundStyle(.white), at: CGPoint(x: r.midX, y: r.midY))
    }
}

/// "Ufolio" in goofy alien lettering: chunky rounded letters in alien green, each tilted and
/// bobbing at its own angle, with a soft glow.
struct AlienTitle: View {
    var text = "Ufolio"
    var size: CGFloat = 50

    var body: some View {
        HStack(spacing: size * 0.02) {
            ForEach(Array(text.enumerated()), id: \.offset) { i, letter in
                Text(String(letter))
                    .font(.system(size: size, weight: .black, design: .rounded))
                    .foregroundStyle(LinearGradient(colors: [Color(red: 0.70, green: 1.0, blue: 0.45), Color(red: 0.25, green: 0.80, blue: 0.45)],
                                                    startPoint: .top, endPoint: .bottom))
                    .rotationEffect(.degrees([-8.0, 6, -5, 9, -7, 5][i % 6]))
                    .offset(y: CGFloat([2.0, -4, 3, -2, 4, -3][i % 6]) * size / 50)
                    .scaleEffect([1.0, 0.92, 1.06, 0.95, 1.04, 0.97][i % 6])
            }
        }
        .shadow(color: Color(red: 0.4, green: 1.0, blue: 0.5).opacity(0.45), radius: size * 0.14)
        .accessibilityLabel(text)
    }
}


