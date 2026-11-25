import SwiftUI
import AppKit
import QuartzCore

// The second fun batch: a saucer pet, warp speed between Orbits, galaxy ranks and a planet of
// the week. Like everything in Fun.swift, nothing here animates non-stop through SwiftUI: the
// pet makes one small move now and then and rests in between, warp speed lasts under half a
// second, and the planet turns on the render server (Core Animation), so the page itself is
// never redrawn for it.

// MARK: - Galaxy rank

/// A rank earned slowly, by the number of different days you've used Ufolio. No pop-ups:
/// it's shown quietly on the weekly report card and in Settings.
struct GalaxyRank: Identifiable, Equatable {
    let index: Int
    let title: String
    /// Days of use needed.
    let days: Int
    var id: Int { index }

    static let all: [GalaxyRank] = [
        GalaxyRank(index: 0, title: "Cadet", days: 0),
        GalaxyRank(index: 1, title: "Space Ranger", days: 3),
        GalaxyRank(index: 2, title: "Star Pilot", days: 7),
        GalaxyRank(index: 3, title: "Moon Walker", days: 14),
        GalaxyRank(index: 4, title: "Comet Chaser", days: 30),
        GalaxyRank(index: 5, title: "Nebula Navigator", days: 60),
        GalaxyRank(index: 6, title: "Starship Captain", days: 100),
        GalaxyRank(index: 7, title: "Galactic Admiral", days: 180),
    ]

    /// Different days Ufolio has been used (only a count and the last day are kept).
    static var daysUsed: Int { UserDefaults.standard.integer(forKey: "galaxyDayCount") }

    static var current: GalaxyRank { rank(forDays: daysUsed) }
    static func rank(forDays days: Int) -> GalaxyRank { all.last { days >= $0.days } ?? all[0] }
    var next: GalaxyRank? { index + 1 < Self.all.count ? Self.all[index + 1] : nil }

    /// "5 more days to Moon Walker", or nil at the top.
    static var progress: String? {
        guard let next = current.next else { return nil }
        let left = next.days - daysUsed
        return "\(left) more day\(left == 1 ? "" : "s") of flying to \(next.title)"
    }

    /// Counts today once. The first time, days already in your history count too, so someone
    /// who has used Ufolio for months doesn't start as a Cadet.
    static func recordToday() {
        let d = UserDefaults.standard
        let today = LocalDay.today
        if !d.bool(forKey: "galaxySeeded"), !HistoryStore.shared.entries.isEmpty {
            d.set(true, forKey: "galaxySeeded")
            let cal = Calendar.current
            let days = Set(HistoryStore.shared.entries.values.map { cal.startOfDay(for: $0.lastVisit) })
            // Today is counted below.
            let earlier = days.filter { !cal.isDateInToday($0) }.count
            if earlier > daysUsed { d.set(earlier, forKey: "galaxyDayCount") }
        }
        guard d.string(forKey: "galaxyLastDay") != today else { return }
        d.set(today, forKey: "galaxyLastDay")
        d.set(daysUsed + 1, forKey: "galaxyDayCount")
    }
}

/// Each rank's own small badge, drawn by hand: chevrons for the first three ranks, stars for
/// the next three, then a gold saucer and the Admiral's ringed star.
struct RankBadge: View {
    let rank: GalaxyRank
    var size: CGFloat = 22

    private var colors: [Color] {
        switch rank.index {
        case 0...2: return [Color(red: 0.36, green: 0.62, blue: 1.0), Color(red: 0.16, green: 0.30, blue: 0.72)]
        case 3...5: return [Color(red: 0.70, green: 0.52, blue: 1.0), Color(red: 0.36, green: 0.20, blue: 0.72)]
        default: return [Color(red: 1.0, green: 0.84, blue: 0.40), Color(red: 0.80, green: 0.52, blue: 0.10)]
        }
    }

    var body: some View {
        ZStack {
            base.fill(LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom))
            base.stroke(Color.white.opacity(0.55), lineWidth: max(0.75, size * 0.045))
            insignia.foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .shadow(color: colors[1].opacity(0.35), radius: size * 0.08, y: size * 0.04)
        .accessibilityLabel("Galaxy rank: \(rank.title)")
    }

    private var base: AnyShape {
        switch rank.index {
        case 0...2: return AnyShape(Circle())
        case 3...5: return AnyShape(Hexagon())
        case 6: return AnyShape(Hexagon())
        default: return AnyShape(Circle())
        }
    }

    @ViewBuilder private var insignia: some View {
        switch rank.index {
        case 0...2:
            VStack(spacing: -size * 0.07) {
                ForEach(0...rank.index, id: \.self) { _ in
                    Chevron().stroke(style: StrokeStyle(lineWidth: size * 0.09, lineCap: .round, lineJoin: .round))
                        .frame(width: size * 0.46, height: size * 0.2)
                }
            }
            .offset(y: size * 0.02)
        case 3...5:
            let count = rank.index - 2
            HStack(spacing: size * 0.02) {
                ForEach(0..<count, id: \.self) { _ in
                    StarShape().frame(width: size * (count == 3 ? 0.24 : 0.32), height: size * (count == 3 ? 0.24 : 0.32))
                }
            }
        case 6:
            ZStack {
                Ellipse().frame(width: size * 0.26, height: size * 0.24).offset(y: -size * 0.07)
                Ellipse().frame(width: size * 0.6, height: size * 0.17).offset(y: size * 0.04)
            }
        default:
            ZStack {
                Ellipse().stroke(lineWidth: size * 0.06)
                    .frame(width: size * 0.74, height: size * 0.3)
                    .rotationEffect(.degrees(-18))
                StarShape().frame(width: size * 0.42, height: size * 0.42)
            }
        }
    }
}

private struct Chevron: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.midX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        return p
    }
}

private struct Hexagon: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        for i in 0..<6 {
            let a = Double(i) * .pi / 3 - .pi / 2
            let pt = CGPoint(x: r.midX + cos(a) * r.width / 2, y: r.midY + sin(a) * r.height / 2)
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.closeSubpath()
        return p
    }
}

struct StarShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        for i in 0..<10 {
            let a = Double(i) * .pi / 5 - .pi / 2
            let radius = (i % 2 == 0 ? 1.0 : 0.45) * min(r.width, r.height) / 2
            let pt = CGPoint(x: r.midX + cos(a) * radius, y: r.midY + sin(a) * radius)
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.closeSubpath()
        return p
    }
}

/// One quiet line: the badge, the rank and how far to the next.
struct GalaxyRankLine: View {
    var body: some View {
        let rank = GalaxyRank.current
        HStack(spacing: 8) {
            RankBadge(rank: rank, size: 20)
            Text("Galaxy rank: ").font(.system(size: 12)).foregroundColor(.secondary)
                + Text(rank.title).font(.system(size: 12, weight: .semibold))
            if let progress = GalaxyRank.progress {
                Text("· \(progress)").font(.system(size: 11.5)).foregroundStyle(.tertiary).lineLimit(1)
            }
        }
    }
}

/// Every rank, for Settings: the ones earned in colour, the rest faded.
struct GalaxyRankLadder: View {
    var body: some View {
        let current = GalaxyRank.current
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                RankBadge(rank: current, size: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(current.title).font(.system(size: 14, weight: .semibold, design: .rounded))
                    Text(GalaxyRank.progress ?? "The highest rank in the galaxy. Salute!")
                        .font(.system(size: 11.5)).foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 6) {
                ForEach(GalaxyRank.all) { rank in
                    VStack(spacing: 3) {
                        RankBadge(rank: rank, size: 22)
                            .saturation(rank.index <= current.index ? 1 : 0)
                            .opacity(rank.index <= current.index ? 1 : 0.35)
                        Text(rank.days == 0 ? "Day 1" : "\(rank.days)d").font(.system(size: 9.5)).foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(rank.title), \(rank.days) days\(rank.index <= current.index ? ", earned" : "")")
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Saucer pet

/// A little saucer that hovers in a corner of the start page. Now and then it does something
/// (a bob, a blink, its lights chasing round, a spin), then rests. It picks up extras as
/// achievements and ranks are earned: an antenna, a glow underneath, a tiny moon, a gold rim.
struct SaucerPet: View {
    @AppStorage(Prefs.saucerPet) private var shown = true
    @Environment(\.controlActiveState) private var activeState
    @ObservedObject private var stats = BlockStats.shared

    @State private var lift: CGFloat = 0
    @State private var spin: Double = 0
    @State private var eyesClosed = false
    @State private var lightStep = -1
    @State private var tilt: Double = 0

    static let size: CGFloat = 62
    /// Set only for previews.
    var fixedLevel: Int? = nil

    /// 0–4: one for each achievement earned, and one for reaching Comet Chaser.
    private var level: Int {
        if let fixedLevel { return fixedLevel }
        return Achievement.all(lifetime: stats.total).filter(\.earned).count + (GalaxyRank.current.index >= 4 ? 1 : 0)
    }

    var body: some View {
        if shown {
            pet
                .frame(width: Self.size, height: Self.size)
                .contentShape(Ellipse().inset(by: 6))
                .onTapGesture { Task { await spinAround() } }
                .contextMenu {
                    Button("Hide Saucer Pet") { shown = false }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Saucer pet, level \(level). Right-click to hide.")
                .task(id: activeState != .inactive) { await idle() }
        }
    }

    private var pet: some View {
        let s = Self.size
        return ZStack {
            if level >= 2 {
                // A soft glow underneath.
                Ellipse()
                    .fill(RadialGradient(colors: [Color(red: 0.45, green: 1.0, blue: 0.75).opacity(0.45), .clear],
                                         center: .center, startRadius: 0, endRadius: s * 0.34))
                    .frame(width: s * 0.8, height: s * 0.32)
                    .offset(y: s * 0.30)
            }
            ZStack {
                if level >= 1 {
                    // Antenna with a light on top.
                    Capsule().fill(Color(white: 0.62)).frame(width: s * 0.03, height: s * 0.16)
                        .offset(y: -s * 0.33)
                    Circle().fill(lightStep >= 0 ? Color(red: 1, green: 0.45, blue: 0.55) : Color(red: 0.95, green: 0.35, blue: 0.45).opacity(0.75))
                        .frame(width: s * 0.075, height: s * 0.075)
                        .shadow(color: .pink.opacity(lightStep >= 0 ? 0.9 : 0), radius: 3)
                        .offset(y: -s * 0.42)
                }
                // The dome, with two big friendly eyes.
                ZStack {
                    Ellipse().fill(LinearGradient(colors: [Color(red: 0.70, green: 1.0, blue: 0.90).opacity(0.85),
                                                           Color(red: 0.30, green: 0.80, blue: 0.75).opacity(0.75)],
                                                  startPoint: .top, endPoint: .bottom))
                    HStack(spacing: s * 0.06) {
                        ForEach(0..<2, id: \.self) { _ in
                            ZStack {
                                Ellipse().fill(Color(white: 0.08))
                                Circle().fill(.white).frame(width: s * 0.035).offset(x: s * 0.015, y: -s * 0.025)
                            }
                            .frame(width: s * 0.09, height: s * 0.12)
                            .scaleEffect(x: 1, y: eyesClosed ? 0.1 : 1)
                        }
                    }
                    .offset(y: s * 0.02)
                    Ellipse().fill(.white.opacity(0.5)).frame(width: s * 0.08, height: s * 0.04).offset(x: -s * 0.1, y: -s * 0.08)
                }
                .clipShape(Ellipse())
                .frame(width: s * 0.42, height: s * 0.34)
                .offset(y: -s * 0.12)
                // The disc.
                Ellipse().fill(LinearGradient(colors: [Color(red: 0.86, green: 0.84, blue: 0.98), Color(red: 0.52, green: 0.48, blue: 0.70)],
                                              startPoint: .top, endPoint: .bottom))
                    .frame(width: s * 0.92, height: s * 0.28)
                    .offset(y: s * 0.06)
                if level >= 4 {
                    Ellipse().stroke(LinearGradient(colors: [Color(red: 1, green: 0.88, blue: 0.45), Color(red: 0.85, green: 0.58, blue: 0.15)],
                                                    startPoint: .leading, endPoint: .trailing), lineWidth: s * 0.03)
                        .frame(width: s * 0.92, height: s * 0.28)
                        .offset(y: s * 0.06)
                }
                Ellipse().fill(Color(red: 0.40, green: 0.36, blue: 0.56))
                    .frame(width: s * 0.6, height: s * 0.1)
                    .offset(y: s * 0.15)
                // Rim lights: they chase round during a light show.
                HStack(spacing: s * 0.07) {
                    ForEach(0..<5, id: \.self) { i in
                        let lit = lightStep >= 0 && (lightStep % 5 == i)
                        Circle()
                            .fill(lit ? Color.white : [Color.yellow, Color.mint, Color.cyan, Color.mint, Color.yellow][i])
                            .frame(width: s * 0.06, height: s * 0.06)
                            .shadow(color: lit ? .white : .clear, radius: 2.5)
                    }
                }
                .offset(y: s * 0.07)
                if level >= 3 {
                    // A tiny moon of its own, which swings round with it when it spins.
                    Circle().fill(LinearGradient(colors: [Color(white: 0.95), Color(white: 0.6)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: s * 0.09, height: s * 0.09)
                        .offset(x: s * 0.40, y: -s * 0.22)
                }
            }
            .rotation3DEffect(.degrees(spin), axis: (x: 0, y: 1, z: 0), perspective: 0.4)
            .rotationEffect(.degrees(tilt))
            .offset(y: lift)
        }
    }

    // MARK: Moves

    /// One small move every 8 to 15 seconds while the window is in front, resting in between.
    /// Still with Reduce Motion or Effects off.
    private func idle() async {
        guard Effects.on, activeState != .inactive else { return }
        var random = SeededRandom(seed: UInt64(Date().timeIntervalSince1970))
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: UInt64((8 + random.next() * 7) * 1_000_000_000))
            guard !Task.isCancelled, Effects.on else { return }
            switch Int(random.next() * 4) {
            case 0: await bob()
            case 1: await blink()
            case 2: await lightShow()
            default: await spinAround()
            }
        }
    }

    private func pause(_ seconds: Double) async { try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000)) }

    private func bob() async {
        for _ in 0..<2 {
            withAnimation(.easeInOut(duration: 0.7)) { lift = -5; tilt = -3 }
            await pause(0.7)
            withAnimation(.easeInOut(duration: 0.7)) { lift = 0; tilt = 2 }
            await pause(0.7)
        }
        withAnimation(.easeOut(duration: 0.4)) { tilt = 0 }
    }

    private func blink() async {
        for _ in 0..<2 {
            withAnimation(.easeIn(duration: 0.08)) { eyesClosed = true }
            await pause(0.1)
            withAnimation(.easeOut(duration: 0.12)) { eyesClosed = false }
            await pause(0.25)
        }
    }

    private func lightShow() async {
        for step in 0..<10 {
            lightStep = step
            await pause(0.12)
        }
        lightStep = -1
    }

    @MainActor private func spinAround() async {
        guard Effects.on else { return }
        withAnimation(.easeInOut(duration: 0.3)) { lift = -6 }
        withAnimation(.easeInOut(duration: 0.9)) { spin += 360 }
        await pause(0.9)
        withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) { lift = 0 }
        // Back to 0 without animating, so the angle never grows without end.
        var still = Transaction(animation: nil)
        still.disablesAnimations = true
        withTransaction(still) { spin = 0 }
    }
}

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

// MARK: - Planet of the week

struct PlanetFacts {
    struct Stat { let symbol: String; let label: String; let value: String }
    let name: String
    let kind: String
    let tagline: String
    let stats: [Stat]
    let facts: [String]
    /// Colours for the card.
    let tint: Color
}

enum Planet: Int, CaseIterable {
    case mercury, venus, earth, mars, jupiter, saturn, uranus, neptune, pluto

    /// A different one each week, changing on Monday at your midnight.
    static var thisWeek: Planet {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        let reference = cal.date(from: DateComponents(year: 2024, month: 1, day: 1)) ?? Date(timeIntervalSince1970: 0) // a Monday
        let days = cal.dateComponents([.day], from: reference, to: cal.startOfDay(for: Date())).day ?? 0
        let week = days >= 0 ? days / 7 : 0
        return allCases[week % allCases.count]
    }

    var hasRings: Bool { self == .saturn }

    var facts: PlanetFacts {
        switch self {
        case .mercury:
            return PlanetFacts(name: "Mercury", kind: "The 1st planet from the Sun", tagline: "The smallest planet, and the fastest round the Sun.",
                               stats: [.init(symbol: "circle.dashed", label: "Diameter", value: "4,879 km"),
                                       .init(symbol: "sun.max", label: "From the Sun", value: "57.9 million km"),
                                       .init(symbol: "clock", label: "Sunrise to sunrise", value: "176 Earth days"),
                                       .init(symbol: "arrow.triangle.2.circlepath", label: "Year", value: "88 Earth days"),
                                       .init(symbol: "moon", label: "Moons", value: "None"),
                                       .init(symbol: "thermometer.medium", label: "Temperature", value: "−180 to 430 °C")],
                               facts: ["One day on Mercury, sunrise to sunrise, lasts two of its years.",
                                       "With almost no atmosphere to hold heat, its nights are far colder than its days are hot.",
                                       "Sunlight takes about 3 minutes to reach it."],
                               tint: Color(red: 0.62, green: 0.60, blue: 0.58))
        case .venus:
            return PlanetFacts(name: "Venus", kind: "The 2nd planet from the Sun", tagline: "The hottest planet, wrapped in thick clouds.",
                               stats: [.init(symbol: "circle.dashed", label: "Diameter", value: "12,104 km"),
                                       .init(symbol: "sun.max", label: "From the Sun", value: "108.2 million km"),
                                       .init(symbol: "clock", label: "One spin", value: "243 Earth days"),
                                       .init(symbol: "arrow.triangle.2.circlepath", label: "Year", value: "225 Earth days"),
                                       .init(symbol: "moon", label: "Moons", value: "None"),
                                       .init(symbol: "thermometer.medium", label: "Surface", value: "About 465 °C")],
                               facts: ["It spins backwards compared with most planets, so the Sun rises in the west.",
                                       "One spin takes longer than its whole trip round the Sun.",
                                       "Its thick carbon dioxide air traps heat, making it hotter than Mercury."],
                               tint: Color(red: 0.92, green: 0.78, blue: 0.48))
        case .earth:
            return PlanetFacts(name: "Earth", kind: "The 3rd planet from the Sun", tagline: "Home: the only world known to have life.",
                               stats: [.init(symbol: "circle.dashed", label: "Diameter", value: "12,742 km"),
                                       .init(symbol: "sun.max", label: "From the Sun", value: "149.6 million km"),
                                       .init(symbol: "clock", label: "Day", value: "24 hours"),
                                       .init(symbol: "arrow.triangle.2.circlepath", label: "Year", value: "365.25 days"),
                                       .init(symbol: "moon", label: "Moons", value: "1"),
                                       .init(symbol: "thermometer.medium", label: "Average", value: "About 15 °C")],
                               facts: ["About 71% of its surface is covered in water.",
                                       "It's the densest planet in the Solar System.",
                                       "Sunlight takes about 8 minutes 20 seconds to get here."],
                               tint: Color(red: 0.30, green: 0.55, blue: 0.95))
        case .mars:
            return PlanetFacts(name: "Mars", kind: "The 4th planet from the Sun", tagline: "The red planet, rusty with iron oxide.",
                               stats: [.init(symbol: "circle.dashed", label: "Diameter", value: "6,779 km"),
                                       .init(symbol: "sun.max", label: "From the Sun", value: "227.9 million km"),
                                       .init(symbol: "clock", label: "Day", value: "24 h 37 min"),
                                       .init(symbol: "arrow.triangle.2.circlepath", label: "Year", value: "687 Earth days"),
                                       .init(symbol: "moon", label: "Moons", value: "2: Phobos and Deimos"),
                                       .init(symbol: "thermometer.medium", label: "Average", value: "About −65 °C")],
                               facts: ["Olympus Mons, a volcano about 22 km high, is roughly two and a half times the height of Everest.",
                                       "Valles Marineris, a canyon about 4,000 km long, would stretch across the United States.",
                                       "A day on Mars is only about 40 minutes longer than ours."],
                               tint: Color(red: 0.85, green: 0.42, blue: 0.25))
        case .jupiter:
            return PlanetFacts(name: "Jupiter", kind: "The 5th planet from the Sun", tagline: "The giant: bigger than all the other planets put together.",
                               stats: [.init(symbol: "circle.dashed", label: "Diameter", value: "139,820 km"),
                                       .init(symbol: "sun.max", label: "From the Sun", value: "778.5 million km"),
                                       .init(symbol: "clock", label: "Day", value: "9 h 56 min"),
                                       .init(symbol: "arrow.triangle.2.circlepath", label: "Year", value: "11.9 Earth years"),
                                       .init(symbol: "moon", label: "Moons", value: "Over 90 known"),
                                       .init(symbol: "thermometer.medium", label: "Cloud tops", value: "About −110 °C")],
                               facts: ["The Great Red Spot is a storm wider than Earth that has raged for centuries.",
                                       "It has more than twice the mass of all the other planets combined.",
                                       "Its moon Ganymede is the largest in the Solar System, bigger than Mercury."],
                               tint: Color(red: 0.82, green: 0.62, blue: 0.42))
        case .saturn:
            return PlanetFacts(name: "Saturn", kind: "The 6th planet from the Sun", tagline: "The ringed planet, light enough to float.",
                               stats: [.init(symbol: "circle.dashed", label: "Diameter", value: "116,460 km"),
                                       .init(symbol: "sun.max", label: "From the Sun", value: "1.43 billion km"),
                                       .init(symbol: "clock", label: "Day", value: "10 h 33 min"),
                                       .init(symbol: "arrow.triangle.2.circlepath", label: "Year", value: "29.4 Earth years"),
                                       .init(symbol: "moon", label: "Moons", value: "Over 270 known"),
                                       .init(symbol: "thermometer.medium", label: "Cloud tops", value: "About −140 °C")],
                               facts: ["It's less dense than water: in a big enough bath, it would float.",
                                       "Its rings are mostly ice, hundreds of thousands of kilometres wide but often only about 10 metres thick.",
                                       "Its moon Titan has rivers and lakes of liquid methane."],
                               tint: Color(red: 0.88, green: 0.78, blue: 0.55))
        case .uranus:
            return PlanetFacts(name: "Uranus", kind: "The 7th planet from the Sun", tagline: "The ice giant that rolls round the Sun on its side.",
                               stats: [.init(symbol: "circle.dashed", label: "Diameter", value: "50,724 km"),
                                       .init(symbol: "sun.max", label: "From the Sun", value: "2.87 billion km"),
                                       .init(symbol: "clock", label: "Day", value: "17 h 14 min"),
                                       .init(symbol: "arrow.triangle.2.circlepath", label: "Year", value: "84 Earth years"),
                                       .init(symbol: "moon", label: "Moons", value: "28 known"),
                                       .init(symbol: "thermometer.medium", label: "Coldest", value: "About −224 °C")],
                               facts: ["It's tipped over by about 98°, so each pole gets 42 years of sunlight, then 42 of darkness.",
                                       "It was the first planet found with a telescope, by William Herschel in 1781.",
                                       "It has the coldest atmosphere of any planet."],
                               tint: Color(red: 0.55, green: 0.85, blue: 0.88))
        case .neptune:
            return PlanetFacts(name: "Neptune", kind: "The 8th planet from the Sun", tagline: "The windiest planet, deep blue and far away.",
                               stats: [.init(symbol: "circle.dashed", label: "Diameter", value: "49,244 km"),
                                       .init(symbol: "sun.max", label: "From the Sun", value: "4.5 billion km"),
                                       .init(symbol: "clock", label: "Day", value: "16 h 6 min"),
                                       .init(symbol: "arrow.triangle.2.circlepath", label: "Year", value: "165 Earth years"),
                                       .init(symbol: "moon", label: "Moons", value: "16 known"),
                                       .init(symbol: "thermometer.medium", label: "Cloud tops", value: "About −200 °C")],
                               facts: ["Its winds reach about 2,000 km/h, the fastest in the Solar System.",
                                       "It was found by maths before anyone saw it, in 1846.",
                                       "Its big moon Triton orbits backwards, and may be a captured dwarf planet."],
                               tint: Color(red: 0.28, green: 0.42, blue: 0.95))
        case .pluto:
            return PlanetFacts(name: "Pluto", kind: "A dwarf planet in the Kuiper Belt", tagline: "Small, icy and far away, with a heart on its surface.",
                               stats: [.init(symbol: "circle.dashed", label: "Diameter", value: "2,377 km"),
                                       .init(symbol: "sun.max", label: "From the Sun", value: "5.9 billion km"),
                                       .init(symbol: "clock", label: "Day", value: "6.4 Earth days"),
                                       .init(symbol: "arrow.triangle.2.circlepath", label: "Year", value: "248 Earth years"),
                                       .init(symbol: "moon", label: "Moons", value: "5"),
                                       .init(symbol: "thermometer.medium", label: "Surface", value: "About −230 °C")],
                               facts: ["The big pale heart, Tombaugh Regio, is partly a vast plain of frozen nitrogen.",
                                       "It was called a planet until 2006, when it became a dwarf planet.",
                                       "NASA’s New Horizons flew past in 2015 and sent back the first close-up pictures."],
                               tint: Color(red: 0.80, green: 0.68, blue: 0.56))
        }
    }
}

/// The planet in the corner of the start page. Click it for its card.
struct PlanetOfTheWeek: View {
    @AppStorage(Prefs.planetOfWeek) private var shown = true
    @State private var showingCard = false
    private let planet = Planet.thisWeek

    var body: some View {
        if shown {
            Button { showingCard.toggle() } label: {
                PlanetGlobe(planet: planet, diameter: 44, spinning: Effects.on)
                    .frame(width: 70, height: 56)
                    .contentShape(Circle().inset(by: 4))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Planet of the week: \(planet.facts.name)")
            .contextMenu { Button("Hide Planet of the Week") { shown = false } }
            .popover(isPresented: $showingCard, arrowEdge: .top) { PlanetCard(planet: planet) }
        }
    }
}

/// The styled card with the week's planet and its facts.
struct PlanetCard: View {
    let planet: Planet

    var body: some View {
        let f = planet.facts
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 16) {
                PlanetGlobe(planet: planet, diameter: 84, spinning: Effects.on)
                    .frame(width: 120, height: 96)
                VStack(alignment: .leading, spacing: 4) {
                    Text("PLANET OF THE WEEK").font(.system(size: 10, weight: .bold)).tracking(1.2).foregroundStyle(f.tint)
                    Text(f.name).font(.system(size: 26, weight: .bold, design: .rounded))
                    Text(f.kind).font(.system(size: 11.5)).foregroundStyle(.secondary)
                    Text(f.tagline).font(.system(size: 12.5, weight: .medium)).fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)
                }
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ForEach(f.stats, id: \.label) { stat in
                    HStack(spacing: 8) {
                        Image(systemName: stat.symbol).font(.system(size: 12, weight: .semibold)).foregroundStyle(f.tint).frame(width: 18)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(stat.label).font(.system(size: 10)).foregroundStyle(.secondary)
                            Text(stat.value).font(.system(size: 12, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 9).padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.primary.opacity(0.05)))
                }
            }
            VStack(alignment: .leading, spacing: 7) {
                Text("Did you know?").font(.system(size: 12.5, weight: .bold, design: .rounded))
                ForEach(f.facts, id: \.self) { fact in
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        StarShape().fill(f.tint).frame(width: 9, height: 9)
                        Text(fact).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            Text("A new planet every Monday. Figures from NASA; moon counts as of 2025.")
                .font(.system(size: 10.5)).foregroundStyle(.tertiary)
        }
        .padding(18)
        .frame(width: 380)
        .background(
            ZStack {
                LinearGradient(colors: [f.tint.opacity(0.16), .clear], startPoint: .topLeading, endPoint: .center)
                StarDust().opacity(0.5)
            }
        )
    }
}

/// A few faint stars behind the card's heading.
private struct StarDust: View {
    var body: some View {
        Canvas { ctx, size in
            var random = SeededRandom(seed: 7)
            for _ in 0..<26 {
                let x = random.next() * size.width, y = random.next() * size.height * 0.4
                let r = 0.5 + random.next() * 1.1
                ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: r, height: r)), with: .color(.primary.opacity(0.35)))
            }
        }
        .allowsHitTesting(false)
    }
}

/// A planet drawn as a turning globe, with Saturn's rings in front and behind.
struct PlanetGlobe: View {
    let planet: Planet
    let diameter: CGFloat
    let spinning: Bool

    var body: some View {
        ZStack {
            if planet.hasRings { ring.mask(Rectangle().frame(height: diameter * 0.5).offset(y: -diameter * 0.25)) }
            PlanetLayerView(planet: planet, diameter: diameter, spinning: spinning)
                .frame(width: diameter, height: diameter)
                .shadow(color: planet.facts.tint.opacity(0.35), radius: diameter * 0.12)
            if planet.hasRings { ring.mask(Rectangle().frame(height: diameter * 0.5).offset(y: diameter * 0.25)) }
        }
        .rotationEffect(.degrees(planet.hasRings ? -14 : 0))
    }

    private var ring: some View {
        ZStack {
            Ellipse().stroke(Color(red: 0.90, green: 0.82, blue: 0.62).opacity(0.85), lineWidth: diameter * 0.07)
                .frame(width: diameter * 1.55, height: diameter * 0.38)
            Ellipse().stroke(Color(red: 0.75, green: 0.66, blue: 0.48).opacity(0.7), lineWidth: diameter * 0.03)
                .frame(width: diameter * 1.32, height: diameter * 0.30)
        }
    }
}

/// The globe itself: a painted surface sliding behind a round window, with shading on top.
/// The turning is a Core Animation animation, so it runs on the render server and costs the
/// page nothing. It pauses while the window isn't in front.
private struct PlanetLayerView: NSViewRepresentable {
    let planet: Planet
    let diameter: CGFloat
    let spinning: Bool

    func makeNSView(context: Context) -> PlanetNSView { PlanetNSView(planet: planet, diameter: diameter, spinning: spinning) }
    func updateNSView(_ view: PlanetNSView, context: Context) {}
}

final class PlanetNSView: NSView {
    private let planet: Planet
    private let diameter: CGFloat
    private let spinning: Bool
    private let surface = CALayer()
    private var observers: [NSObjectProtocol] = []

    init(planet: Planet, diameter: CGFloat, spinning: Bool) {
        self.planet = planet
        self.diameter = diameter
        self.spinning = spinning
        super.init(frame: NSRect(x: 0, y: 0, width: diameter, height: diameter))
        wantsLayer = true
        build()
    }
    required init?(coder: NSCoder) { fatalError() }

    deinit { observers.forEach(NotificationCenter.default.removeObserver) }

    private func build() {
        guard let root = layer else { return }
        let d = diameter
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let globe = CALayer()
        globe.frame = CGRect(x: 0, y: 0, width: d, height: d)
        globe.cornerRadius = d / 2
        globe.masksToBounds = true
        root.addSublayer(globe)

        // Two copies of the surface side by side, slid along by one width and repeated: seamless.
        let width = d * 2
        if let image = PlanetPainter.surface(planet, width: width, height: d, scale: scale) {
            surface.frame = CGRect(x: 0, y: 0, width: width * 2, height: d)
            for i in 0..<2 {
                let tile = CALayer()
                tile.contents = image
                tile.contentsScale = scale
                tile.frame = CGRect(x: CGFloat(i) * width, y: 0, width: width, height: d)
                surface.addSublayer(tile)
            }
            globe.addSublayer(surface)
        }

        // Shading: lit from the upper left, darkening to the night side.
        let shade = CAGradientLayer()
        shade.type = .radial
        shade.frame = globe.bounds
        shade.colors = [NSColor.white.withAlphaComponent(0.16).cgColor, NSColor.clear.cgColor, NSColor.black.withAlphaComponent(0.62).cgColor]
        shade.locations = [0, 0.45, 1]
        shade.startPoint = CGPoint(x: 0.32, y: 0.70)
        shade.endPoint = CGPoint(x: 1.25, y: -0.25)
        globe.addSublayer(shade)
        // A thin bright edge, like an atmosphere.
        let rim = CALayer()
        rim.frame = globe.bounds
        rim.cornerRadius = d / 2
        rim.borderWidth = max(0.5, d * 0.012)
        rim.borderColor = NSColor.white.withAlphaComponent(0.18).cgColor
        globe.addSublayer(rim)

        guard spinning else { return }
        let turn = CABasicAnimation(keyPath: "position.x")
        turn.fromValue = width          // the layer's centre at its starting place
        turn.toValue = 0                // one surface-width to the left
        turn.duration = 150             // a slow, steady turn
        turn.repeatCount = .infinity
        turn.isRemovedOnCompletion = false
        surface.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        surface.position = CGPoint(x: width, y: d / 2)
        surface.add(turn, forKey: "turn")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        guard let window, spinning else { return }
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification, NSWindow.didChangeOcclusionStateNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                self?.updatePaused()
            })
        }
        updatePaused()
    }

    /// Turns only while its window is in front and visible.
    private func updatePaused() {
        guard let window else { return }
        let run = window.isKeyWindow && window.occlusionState.contains(.visible)
        let layer = surface
        if run && layer.speed == 0 {
            let paused = layer.timeOffset
            layer.speed = 1
            layer.timeOffset = 0
            layer.beginTime = 0
            layer.beginTime = layer.convertTime(CACurrentMediaTime(), from: nil) - paused
        } else if !run && layer.speed != 0 {
            let paused = layer.convertTime(CACurrentMediaTime(), from: nil)
            layer.speed = 0
            layer.timeOffset = paused
        }
    }
}

/// Paints each planet's surface once, as a picture that wraps round seamlessly.
enum PlanetPainter {
    private static var cache: [String: CGImage] = [:]

    static func surface(_ planet: Planet, width: CGFloat, height: CGFloat, scale: CGFloat) -> CGImage? {
        let key = "\(planet.rawValue)-\(Int(width))-\(Int(height))-\(scale)"
        if let hit = cache[key] { return hit }
        let w = Int(width * scale), h = Int(height * scale)
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        let W = CGFloat(w), H = CGFloat(h)
        var rnd = SeededRandom(seed: UInt64(planet.rawValue + 11))
        func rgb(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: a) }
        func fill(_ color: CGColor) { ctx.setFillColor(color); ctx.fill(CGRect(x: 0, y: 0, width: W, height: H)) }
        /// An ellipse drawn three times (left, centre, right) so it wraps round.
        func blob(_ x: CGFloat, _ y: CGFloat, _ rw: CGFloat, _ rh: CGFloat, _ color: CGColor) {
            ctx.setFillColor(color)
            for dx in [-W, 0, W] { ctx.fillEllipse(in: CGRect(x: x + dx - rw, y: y - rh, width: rw * 2, height: rh * 2)) }
        }
        /// A band across the planet with gently wavy edges (whole waves, so it wraps).
        func band(_ y0: CGFloat, _ y1: CGFloat, _ color: CGColor, waves: Int = 3, amplitude: CGFloat = 0.012) {
            let amp = H * amplitude
            let phase = rnd.next() * 2 * .pi
            let path = CGMutablePath()
            let steps = 64
            for i in 0...steps {
                let x = W * CGFloat(i) / CGFloat(steps)
                let y = y0 * H + amp * CGFloat(sin(Double(x / W) * 2 * .pi * Double(waves) + phase))
                if i == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
            }
            for i in stride(from: steps, through: 0, by: -1) {
                let x = W * CGFloat(i) / CGFloat(steps)
                let y = y1 * H + amp * CGFloat(sin(Double(x / W) * 2 * .pi * Double(waves + 1) + phase * 1.3))
                path.addLine(to: CGPoint(x: x, y: y))
            }
            path.closeSubpath()
            ctx.addPath(path)
            ctx.setFillColor(color)
            ctx.fillPath()
        }
        func craters(_ count: Int, dark: CGColor, light: CGColor, maxSize: Double) {
            for _ in 0..<count {
                let x = CGFloat(rnd.next()) * W, y = CGFloat(0.12 + rnd.next() * 0.76) * H
                let r = CGFloat(0.012 + rnd.next() * maxSize) * H
                blob(x + r * 0.15, y - r * 0.15, r, r, light)
                blob(x, y, r, r, dark)
            }
        }

        // Core Graphics' y runs upwards, so y = 0 is the south pole.
        switch planet {
        case .mercury:
            fill(rgb(0.60, 0.58, 0.56))
            for _ in 0..<14 { blob(CGFloat(rnd.next()) * W, CGFloat(rnd.next()) * H, CGFloat(0.05 + rnd.next() * 0.1) * H, CGFloat(0.04 + rnd.next() * 0.08) * H, rgb(0.50, 0.48, 0.46, 0.6)) }
            craters(40, dark: rgb(0.42, 0.40, 0.39), light: rgb(0.74, 0.72, 0.70), maxSize: 0.05)
        case .venus:
            fill(rgb(0.90, 0.76, 0.48))
            for i in 0..<7 {
                let y = 0.08 + Double(i) * 0.13
                band(CGFloat(y), CGFloat(y + 0.07), i % 2 == 0 ? rgb(0.96, 0.86, 0.62, 0.7) : rgb(0.80, 0.62, 0.36, 0.45), waves: 2, amplitude: 0.03)
            }
        case .earth:
            fill(rgb(0.13, 0.36, 0.72))
            // Continents: clusters of green and sandy patches.
            let land: [(Double, Double, Double)] = [(0.08, 0.62, 0.11), (0.14, 0.40, 0.08), (0.30, 0.58, 0.10), (0.33, 0.38, 0.09),
                                                     (0.52, 0.66, 0.13), (0.60, 0.50, 0.08), (0.72, 0.35, 0.07), (0.86, 0.60, 0.09)]
            for (x, y, r) in land {
                let cx = CGFloat(x) * W, cy = CGFloat(y) * H
                for _ in 0..<6 {
                    blob(cx + CGFloat(rnd.next() - 0.5) * CGFloat(r) * H * 1.6, cy + CGFloat(rnd.next() - 0.5) * CGFloat(r) * H * 1.6,
                         CGFloat(r) * H * CGFloat(0.5 + rnd.next() * 0.6), CGFloat(r) * H * CGFloat(0.4 + rnd.next() * 0.5),
                         rnd.next() < 0.7 ? rgb(0.24, 0.55, 0.26) : rgb(0.70, 0.62, 0.40))
                }
            }
            band(0, 0.07, rgb(0.95, 0.97, 1.0), waves: 4, amplitude: 0.01)
            band(0.94, 1.0, rgb(0.95, 0.97, 1.0), waves: 4, amplitude: 0.01)
            // Clouds.
            for _ in 0..<16 {
                blob(CGFloat(rnd.next()) * W, CGFloat(0.12 + rnd.next() * 0.76) * H, CGFloat(0.06 + rnd.next() * 0.12) * H, CGFloat(0.012 + rnd.next() * 0.02) * H, rgb(1, 1, 1, 0.55))
            }
        case .mars:
            fill(rgb(0.78, 0.38, 0.20))
            for _ in 0..<18 { blob(CGFloat(rnd.next()) * W, CGFloat(0.15 + rnd.next() * 0.7) * H, CGFloat(0.04 + rnd.next() * 0.12) * H, CGFloat(0.03 + rnd.next() * 0.06) * H, rgb(0.55, 0.24, 0.13, 0.6)) }
            for _ in 0..<10 { blob(CGFloat(rnd.next()) * W, CGFloat(0.15 + rnd.next() * 0.7) * H, CGFloat(0.03 + rnd.next() * 0.08) * H, CGFloat(0.02 + rnd.next() * 0.05) * H, rgb(0.88, 0.56, 0.34, 0.5)) }
            band(0.93, 1.0, rgb(0.96, 0.94, 0.92), waves: 3, amplitude: 0.01)
            band(0, 0.04, rgb(0.92, 0.88, 0.84), waves: 3, amplitude: 0.008)
        case .jupiter:
            fill(rgb(0.86, 0.76, 0.62))
            let colors = [rgb(0.70, 0.50, 0.34), rgb(0.94, 0.88, 0.76), rgb(0.62, 0.42, 0.30), rgb(0.90, 0.80, 0.64), rgb(0.74, 0.56, 0.40)]
            var y = 0.04
            var i = 0
            while y < 0.96 {
                let t = 0.04 + rnd.next() * 0.07
                band(CGFloat(y), CGFloat(y + t), colors[i % colors.count], waves: 4, amplitude: 0.01)
                y += t + 0.015
                i += 1
            }
            // The Great Red Spot, in the southern half.
            blob(W * 0.3, H * 0.34, H * 0.13, H * 0.065, rgb(0.80, 0.40, 0.26))
            blob(W * 0.3, H * 0.34, H * 0.08, H * 0.035, rgb(0.86, 0.50, 0.34))
        case .saturn:
            fill(rgb(0.90, 0.80, 0.58))
            var y = 0.05
            var i = 0
            while y < 0.95 {
                let t = 0.05 + rnd.next() * 0.08
                band(CGFloat(y), CGFloat(y + t), i % 2 == 0 ? rgb(0.84, 0.70, 0.46, 0.7) : rgb(0.96, 0.90, 0.72, 0.6), waves: 2, amplitude: 0.006)
                y += t + 0.02
                i += 1
            }
        case .uranus:
            fill(rgb(0.62, 0.88, 0.90))
            band(0.30, 0.40, rgb(0.56, 0.82, 0.86, 0.6), waves: 1, amplitude: 0.004)
            band(0.62, 0.70, rgb(0.70, 0.92, 0.94, 0.6), waves: 1, amplitude: 0.004)
            band(0.88, 1.0, rgb(0.76, 0.95, 0.96, 0.7), waves: 1, amplitude: 0.004)
        case .neptune:
            fill(rgb(0.22, 0.38, 0.86))
            band(0.20, 0.30, rgb(0.18, 0.30, 0.74, 0.7), waves: 2, amplitude: 0.01)
            band(0.62, 0.72, rgb(0.30, 0.48, 0.92, 0.6), waves: 2, amplitude: 0.01)
            blob(W * 0.62, H * 0.38, H * 0.10, H * 0.05, rgb(0.10, 0.18, 0.50, 0.9))   // a dark storm
            for _ in 0..<6 { blob(CGFloat(rnd.next()) * W, CGFloat(0.3 + rnd.next() * 0.5) * H, CGFloat(0.05 + rnd.next() * 0.07) * H, H * 0.01, rgb(0.92, 0.96, 1.0, 0.8)) }
        case .pluto:
            fill(rgb(0.74, 0.62, 0.50))
            for _ in 0..<14 { blob(CGFloat(rnd.next()) * W, CGFloat(0.1 + rnd.next() * 0.8) * H, CGFloat(0.05 + rnd.next() * 0.1) * H, CGFloat(0.03 + rnd.next() * 0.06) * H, rgb(0.48, 0.34, 0.26, 0.55)) }
            // The heart: two lobes and a point.
            let cx = W * 0.55, cy = H * 0.52, r = H * 0.14
            blob(cx - r * 0.7, cy + r * 0.25, r, r, rgb(0.96, 0.92, 0.86))
            blob(cx + r * 0.7, cy + r * 0.25, r, r, rgb(0.96, 0.92, 0.86))
            let point = CGMutablePath()
            point.move(to: CGPoint(x: cx - r * 1.62, y: cy + r * 0.0))
            point.addLine(to: CGPoint(x: cx + r * 1.62, y: cy + r * 0.0))
            point.addLine(to: CGPoint(x: cx, y: cy - r * 1.5))
            point.closeSubpath()
            ctx.addPath(point)
            ctx.setFillColor(rgb(0.96, 0.92, 0.86))
            ctx.fillPath()
        }
        let image = ctx.makeImage()
        if let image { cache[key] = image }
        return image
    }
}
