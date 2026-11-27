import SwiftUI
import AppKit

// The playful side of Ufolio. Everything animated here respects Reduce Motion, and the
// animations can be switched off together in Settings › Appearance › Effects.

/// Whether the playful animations should run.
enum Effects {
    static var on: Bool { Prefs.bool(Prefs.funEffects) && !Prefs.bool(Prefs.reduceMotion) }

    /// Whether someone has touched the mouse, trackpad or keyboard in the last minute. The
    /// start page's little moves (the saucer pet, shooting stars) only play then: they used to
    /// keep going with nobody there, costing about a second of processor time every minute.
    static var someoneIsHere: Bool {
        let anyInput = CGEventType(rawValue: ~0) ?? .null
        return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput) < 60
    }
}

// MARK: - The Area 51 theme

/// One complete alien look: a radioactive-green accent, green-tinted glass, a green aurora on
/// the start page and a green saucer tile, each tuned for light and dark mode.
enum AlienTheme {
    static func isActive(_ theme: String) -> Bool { theme == "area51" || UFODay.isToday }
    static var isActive: Bool { isActive(Prefs.string(Prefs.theme)) }

    private static func dynamic(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light })
    }

    /// Deep enough to read on white in light mode, glowing in dark mode.
    static let accent = dynamic(light: NSColor(srgbRed: 0.10, green: 0.56, blue: 0.24, alpha: 1),
                                dark: NSColor(srgbRed: 0.42, green: 0.93, blue: 0.47, alpha: 1))
    /// Laid over the frosted glass of the window, sidebar and tab column.
    static let glass = dynamic(light: NSColor(srgbRed: 0.30, green: 0.85, blue: 0.40, alpha: 0.07),
                               dark: NSColor(srgbRed: 0.25, green: 0.95, blue: 0.40, alpha: 0.06))
    /// The saucer tile (the logo on the start page and in Settings).
    static let tile: [Color] = [Color(red: 0.30, green: 0.78, blue: 0.40), Color(red: 0.08, green: 0.36, blue: 0.20),
                                Color(red: 0.02, green: 0.12, blue: 0.08)]

    /// A soft green-and-teal aurora for the start page.
    static var aurora: some View {
        ZStack {
            RadialGradient(colors: [Color(red: 0.30, green: 0.95, blue: 0.45).opacity(0.22), .clear],
                           center: .topLeading, startRadius: 0, endRadius: 700)
            RadialGradient(colors: [Color(red: 0.10, green: 0.75, blue: 0.70).opacity(0.16), .clear],
                           center: .bottomTrailing, startRadius: 0, endRadius: 800)
        }
        .allowsHitTesting(false)
    }
}

/// 2 July: World UFO Day. Ufolio dresses up in its Area 51 colours and says hello.
enum UFODay {
    static var isToday: Bool {
        let c = Calendar.current.dateComponents([.month, .day], from: Date())
        return c.month == 7 && c.day == 2
    }
}

// MARK: - Live sky

/// The start page background that follows the real time of day: dawn, a blue day, sunset, dusk
/// and a starry night. (Its colours change once a minute; there are no moving parts.)
struct LiveSky: View {
    var body: some View {
        TimelineView(.everyMinute) { context in
            let hour = Self.hour(context.date)
            let night = Self.starAmount(hour)
            GeometryReader { _ in
                ZStack {
                    LinearGradient(colors: Self.colors(hour), startPoint: .top, endPoint: .bottom)
                    if night > 0 {
                        Canvas { ctx, size in
                            var rng = SeededRandom(seed: 51)
                            for _ in 0..<140 {
                                let x = rng.next() * size.width, y = rng.next() * size.height * 0.75
                                let r = 0.4 + rng.next() * 1.3
                                ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: r, height: r)),
                                         with: .color(.white.opacity((0.35 + rng.next() * 0.65) * night)))
                            }
                        }
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }

    private static func hour(_ date: Date) -> Double {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return Double(c.hour ?? 12) + Double(c.minute ?? 0) / 60
    }

    /// Sky colours through the day, top to bottom, blended between key moments.
    private static let keys: [(hour: Double, top: (Double, Double, Double), bottom: (Double, Double, Double))] = [
        (0, (0.02, 0.03, 0.12), (0.07, 0.09, 0.22)),
        (5, (0.04, 0.05, 0.18), (0.14, 0.12, 0.32)),
        (6.5, (0.20, 0.22, 0.48), (0.95, 0.60, 0.42)),
        (8.5, (0.24, 0.52, 0.88), (0.62, 0.80, 0.98)),
        (16.5, (0.22, 0.48, 0.86), (0.60, 0.78, 0.96)),
        (18.5, (0.26, 0.20, 0.46), (0.98, 0.52, 0.32)),
        (20, (0.08, 0.10, 0.30), (0.40, 0.22, 0.46)),
        (21.5, (0.03, 0.04, 0.15), (0.08, 0.09, 0.24)),
        (24, (0.02, 0.03, 0.12), (0.07, 0.09, 0.22)),
    ]

    private static func colors(_ hour: Double) -> [Color] {
        let i = max(0, (keys.firstIndex { $0.hour > hour } ?? keys.count) - 1)
        let a = keys[i], b = keys[min(i + 1, keys.count - 1)]
        let t = b.hour > a.hour ? (hour - a.hour) / (b.hour - a.hour) : 0
        func mix(_ x: (Double, Double, Double), _ y: (Double, Double, Double)) -> Color {
            Color(red: x.0 + (y.0 - x.0) * t, green: x.1 + (y.1 - x.1) * t, blue: x.2 + (y.2 - x.2) * t)
        }
        return [mix(a.top, b.top), mix(a.bottom, b.bottom)]
    }

    /// 1 at night, fading at dusk and dawn, 0 by day.
    private static func starAmount(_ hour: Double) -> Double {
        if hour >= 21 || hour < 5 { return 1 }
        if hour >= 19.5 { return (hour - 19.5) / 1.5 }
        if hour < 6.5 { return 1 - (hour - 5) / 1.5 }
        return 0
    }
}

/// The same "random" stars every time, so the sky doesn't jump about.
struct SeededRandom {
    private var state: UInt64
    init(seed: UInt64) { state = seed &* 0x9E3779B97F4A7C15 }
    mutating func next() -> Double {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Double(state >> 11) / Double(1 << 53)
    }
}

// MARK: - A small saucer

struct MiniSaucer: View {
    var size: CGFloat = 18
    var partyHat = false

    var body: some View {
        ZStack(alignment: .top) {
            SaucerArt(beam: 0).frame(width: size, height: size)
            if partyHat {
                PartyHat().fill(LinearGradient(colors: [Color(red: 1, green: 0.4, blue: 0.6), Color(red: 1, green: 0.8, blue: 0.3)],
                                               startPoint: .top, endPoint: .bottom))
                    .frame(width: size * 0.32, height: size * 0.42)
                    .offset(y: -size * 0.24)
            }
        }

    }
}

private struct PartyHat: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.midX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

// MARK: - Abducted counter and log

/// "🛸 1,204 abducted today" on the start page; click it for the abduction log.
struct AbductionCounter: View {
    @ObservedObject private var report = PrivacyReport.shared
    @State private var showing = false

    var body: some View {
        Button { showing.toggle() } label: {
            HStack(spacing: 7) {
                MiniSaucer(size: 18)
                Text("\(report.summary.today.formatted()) ads and trackers abducted today")
                    .font(.system(size: 12.5, weight: .medium, design: .rounded))
            }
            .padding(.horizontal, 12).padding(.vertical, 5)
            .background(Capsule().fill(Color.primary.opacity(0.07)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("See what the saucer abducted today")
        .popover(isPresented: $showing, arrowEdge: .bottom) { AbductionLog(summary: report.summary) }
    }
}

struct AbductionLog: View {
    let summary: PrivacyReport.Summary

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                MiniSaucer(size: 22)
                Text("Abduction log").font(.system(size: 15, weight: .bold, design: .rounded))
                Spacer()
                Text("Today").font(.system(size: 11.5)).foregroundStyle(.secondary)
            }
            if summary.todayTrackers.isEmpty {
                Text("Nothing abducted yet today. The saucer is watching.")
                    .font(.system(size: 12.5)).foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(summary.todayTrackers.prefix(40), id: \.tracker) { item in
                            HStack(spacing: 8) {
                                Favicon(url: URL(string: "https://\(item.tracker)"), size: 14, offline: true).frame(width: 18)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(item.tracker).font(.system(size: 12.5, weight: .medium)).lineLimit(1)
                                    let owner = TrackerCompanies.owner(of: item.tracker)
                                    if owner != item.tracker {
                                        Text(owner).font(.system(size: 10.5)).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer(minLength: 8)
                                Text(item.sites == 1 ? "1 site" : "\(item.sites) sites")
                                    .font(.system(size: 11)).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .frame(maxHeight: 300)
            }
            Divider()
            Text("\(summary.today.formatted()) abducted today · \(summary.week.formatted()) this week")
                .font(.system(size: 11.5)).foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(width: 330)
    }
}

// MARK: - Weekly report card and achievements

struct WeeklyReportCard: View {
    let summary: PrivacyReport.Summary
    @AppStorage(Prefs.achievements) private var achievementsOn = false
    @ObservedObject private var stats = BlockStats.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "calendar.badge.checkmark").foregroundStyle(Color.accentColor)
                Text("This week the saucer zapped \(summary.week.formatted()) ads and trackers and saved you \(Self.megabytes(summary.week)).")
                    .font(.system(size: 13, weight: .medium))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if achievementsOn {
                HStack(spacing: 8) {
                    ForEach(Achievement.all(lifetime: stats.total), id: \.title) { badge in
                        HStack(spacing: 5) {
                            Image(systemName: badge.symbol)
                            Text(badge.title).font(.system(size: 11, weight: .semibold))
                        }
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .foregroundStyle(badge.earned ? Color.accentColor : Color.secondary.opacity(0.6))
                        .background(Capsule().fill(Color.primary.opacity(badge.earned ? 0.08 : 0.04)))
                        .accessibilityLabel(badge.detail + (badge.earned ? "" : " (not yet)"))
                    }
                }
            }
        }
    }

    /// The same rough estimate as the footprint card: about 20 KB per blocked request.
    static func megabytes(_ blocked: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowsNonnumericFormatting = false   // "0 KB", not "Zero KB"
        return formatter.string(fromByteCount: Int64(blocked) * 20_000)
    }
}

struct Achievement {
    let title: String
    let detail: String
    let symbol: String
    let earned: Bool

    static func all(lifetime: Int) -> [Achievement] {
        [
            Achievement(title: "First Contact", detail: "1,000 ads and trackers blocked", symbol: "antenna.radiowaves.left.and.right",
                        earned: lifetime >= 1_000),
            Achievement(title: "Area 51", detail: "Stealth Mode used on 30 different days", symbol: "theatermasks.fill",
                        earned: StealthDays.count >= 30),
            Achievement(title: "Lightyear", detail: "1,000,000 ads and trackers blocked", symbol: "sparkles",
                        earned: lifetime >= 1_000_000),
        ]
    }
}

/// Today's date as yyyy-MM-dd in your own time zone. (The ISO 8601 formatter uses UTC, so "today"
/// used to change at 1 am in a UK summer, or in the evening in America.)
enum LocalDay {
    static var today: String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}

/// How many different days Stealth Mode has been used: only a count and the last day are kept,
/// never which days.
enum StealthDays {
    static var count: Int { UserDefaults.standard.integer(forKey: "stealthDayCount") }
    static func recordToday() {
        let today = LocalDay.today
        guard UserDefaults.standard.string(forKey: "stealthLastDay") != today else { return }
        UserDefaults.standard.set(today, forKey: "stealthLastDay")
        UserDefaults.standard.set(count + 1, forKey: "stealthDayCount")
    }
}

// MARK: - Signal from space (a daily tip)

/// Which features you've tried, so the start page can suggest one you haven't.
enum FeatureUsage: String, CaseIterable {
    case palette, split, reader, stealth, zapper, sidebar, orbits, find, sideTabs, hushlist, linkPreview, compact, docked

    static func mark(_ feature: FeatureUsage) {
        let key = "used." + feature.rawValue
        if !UserDefaults.standard.bool(forKey: key) { UserDefaults.standard.set(true, forKey: key) }
    }
    var used: Bool {
        switch self {
        case .sideTabs: return Prefs.string(Prefs.tabLayout) == TabLayout.side.rawValue || UserDefaults.standard.bool(forKey: "used.sideTabs")
        case .hushlist: return ContentBlocker.shared.hushlist != nil
        default: return UserDefaults.standard.bool(forKey: "used." + rawValue)
        }
    }

    var tip: String {
        switch self {
        case .palette: return "Press ⌘K for the Command Palette: tabs, commands, bookmarks and history in one box."
        case .split: return "Put two pages side by side with Split View (right-click a tab)."
        case .reader: return "Long article? Press ⇧⌘R for Reader: just the words, no clutter."
        case .stealth: return "Press ⇧⌘N for a Stealth window that forgets everything when you close it."
        case .zapper: return "Right-click anything annoying on a page and choose Hide Elements to zap it for good."
        case .sidebar: return "Press ⇧⌘L for your bookmarks and history in a sidebar."
        case .orbits: return "Keep work and personal tabs apart with Orbits (the icon left of your tabs)."
        case .find: return "Press ⌘F to find words on a page."
        case .sideTabs: return "Prefer tabs down the side? Switch in Settings › Appearance."
        case .hushlist: return "Block even more with Hushlist, free in Settings › Force Field."
        case .linkPreview: return "⌥-click a link to preview it over the page, without leaving where you are."
        case .compact: return "Press ⌃⌘C for Compact mode: just the page, with the tabs and toolbar a push of the pointer away."
        case .docked: return "Keep chat or music beside every page: right-click a tab and choose Dock This Site."
        }
    }
}

/// One small tip a day about something you haven't tried yet.
struct SignalFromSpace: View {
    @State private var hidden = false

    private var today: String { LocalDay.today }

    private var feature: FeatureUsage? {
        guard UserDefaults.standard.string(forKey: "signalDismissedDay") != today else { return nil }
        let unused = FeatureUsage.allCases.filter { !$0.used }
        guard !unused.isEmpty else { return nil }
        let day = Calendar.current.ordinality(of: .day, in: .era, for: Date()) ?? 0
        return unused[day % unused.count]
    }

    var body: some View {
        if !hidden, let feature {
            HStack(spacing: 8) {
                Image(systemName: "antenna.radiowaves.left.and.right").foregroundStyle(Color.accentColor)
                Text(feature.tip).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(2)
                Button {
                    UserDefaults.standard.set(today, forKey: "signalDismissedDay")
                    withAnimation(.easeOut(duration: 0.2)) { hidden = true }
                } label: { Image(systemName: "xmark").font(.system(size: 9, weight: .bold)) }
                .buttonStyle(.plain)
                .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Capsule().fill(Color.primary.opacity(0.05)))
            .frame(maxWidth: 620)
        }
    }
}

// MARK: - Ufolio's birthday

enum UfolioBirthday {
    /// When Ufolio was first used on this Mac (the start of its block counter, for earlier installs).
    static var installed: Date {
        if let date = UserDefaults.standard.object(forKey: "installDate") as? Date { return date }
        let date = (UserDefaults.standard.object(forKey: "stats.since") as? Date) ?? Date()
        UserDefaults.standard.set(date, forKey: "installDate")
        return date
    }

    /// How many years old Ufolio turns today, or nil if it isn't its birthday.
    static var yearsToday: Int? {
        let cal = Calendar.current
        let a = cal.dateComponents([.year, .month, .day], from: installed)
        let b = cal.dateComponents([.year, .month, .day], from: Date())
        guard a.month == b.month, a.day == b.day, let y1 = a.year, let y2 = b.year, y2 > y1 else { return nil }
        return y2 - y1
    }
}

// MARK: - "take me to your leader"

/// The address bar easter egg: a saucer beams down a greeting for a moment.
struct LeaderEasterEgg: View {
    let onDone: () -> Void
    @State private var phase = 0   // 0 offstage left, 1 hovering, 2 gone right

    var body: some View {
        GeometryReader { geo in
            ZStack {
                VStack(spacing: 0) {
                    SaucerArt(beam: phase == 1 ? 1 : 0).frame(width: 110, height: 110)
                    if phase == 1 {
                        Text("Greetings, Earthling. Our leader is… you. 👽")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .padding(.horizontal, 18).padding(.vertical, 10)
                            .background(Capsule().fill(.regularMaterial))
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .position(x: phase == 0 ? -120 : phase == 1 ? geo.size.width / 2 : geo.size.width + 160,
                          y: geo.size.height * 0.35)
            }
        }
        .allowsHitTesting(false)
        .task {
            // Shown still for a moment (no flying in and out: animated pictures cost the Mac work).
            phase = 1
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            onDone()
        }
    }
}
