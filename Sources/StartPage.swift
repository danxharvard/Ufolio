import SwiftUI

/// What a new tab shows: a calm, frosted page with recently closed tabs,
/// your favourites, suggestions from your history and a privacy report.
struct StartPage: View {
    @ObservedObject var model: BrowserModel
    @ObservedObject private var bookmarks = BookmarkStore.shared
    @ObservedObject private var history = HistoryStore.shared
    @ObservedObject private var closed = RecentlyClosed.shared
    @ObservedObject private var weather = LocalWeather.shared
    @AppStorage(Prefs.startBackground) private var backgroundStyle = StartBackground.twilight.rawValue
    @AppStorage(Prefs.startTranslucent) private var translucent = true
    @AppStorage(Prefs.startGreeting) private var showGreeting = true
    @AppStorage(Prefs.startRecentlyClosed) private var showClosed = true
    @AppStorage(Prefs.startBookmarks) private var showFavourites = true
    @AppStorage(Prefs.startFrequent) private var showSuggestions = true
    @AppStorage(Prefs.startPrivacyReport) private var showPrivacy = true
    @AppStorage(Prefs.startPageWeather) private var showWeather = false

    var body: some View {
        let favouriteHosts = Set(bookmarks.items.compactMap { $0.url.host?.lowercased().strippingWWW })
        let suggestions = showSuggestions ? history.frequentSites(limit: 6, excluding: favouriteHosts) : []
        ZStack {
            StartBackdrop(style: StartBackground(rawValue: backgroundStyle) ?? .twilight, translucent: translucent)
            ScrollView {
                VStack(alignment: .leading, spacing: 46) {
                    header
                    if showClosed && !closed.tabs.isEmpty {
                        RecentlyClosedSection(model: model, tabs: Array(closed.tabs.prefix(9)))
                    }
                    if showFavourites && !bookmarks.items.isEmpty {
                        StartSection(title: "Favourites") {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 92, maximum: 104), spacing: 14)],
                                      alignment: .leading, spacing: 20) {
                                ForEach(bookmarks.items) { bookmark in
                                    FavouriteTile(bookmark: bookmark, model: model)
                                }
                            }
                        }
                    }
                    if !suggestions.isEmpty {
                        StartSection(title: "Suggestions") {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 158, maximum: 190), spacing: 16)],
                                      alignment: .leading, spacing: 16) {
                                ForEach(suggestions) { site in
                                    SuggestionCard(site: site, model: model)
                                }
                            }
                        }
                    }
                    if showPrivacy {
                        PrivacyReportSection()
                    }
                }
                .frame(maxWidth: 940, alignment: .leading)
                .padding(.horizontal, 48)
                .padding(.top, 54)
                .padding(.bottom, 64)
                .frame(maxWidth: .infinity)
            }
        }
        .animation(.easeOut(duration: 0.25), value: closed.tabs.count)
        .onAppear { weather.refreshIfNeeded() }
        .onChange(of: showWeather) { on in if on { weather.request() } }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Text("Hush")
                .font(.system(size: 50, weight: .thin, design: .rounded))
                .tracking(2)
            if showGreeting || (showWeather && weather.temperature != nil) {
                HStack(spacing: 8) {
                    if showGreeting { Text(greeting) }
                    if showWeather, let temperature = weather.temperature {
                        if showGreeting { Text("·").foregroundStyle(.tertiary) }
                        Image(systemName: weather.symbol).symbolRenderingMode(.multicolor)
                        Text("\(temperature)°")
                        if let city = weather.city { Text(city) }
                    }
                }
                .font(.system(size: 14, design: .rounded))
                .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12: return "Good morning"
        case 12..<18: return "Good afternoon"
        default: return "Good evening"
        }
    }
}

// MARK: - Sections

private struct StartSection<Content: View, Accessory: View>: View {
    let title: String
    let accessory: Accessory
    let content: Content

    init(title: String, @ViewBuilder accessory: () -> Accessory = { EmptyView() }, @ViewBuilder content: () -> Content) {
        self.title = title
        self.accessory = accessory()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.system(size: 21, weight: .bold))
                Spacer()
                accessory
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct RecentlyClosedSection: View {
    @ObservedObject var model: BrowserModel
    let tabs: [ClosedTab]

    var body: some View {
        StartSection(title: "Recently Closed Tabs") {
            Button {
                RecentlyClosed.shared.clear()
            } label: {
                Label("Clear All", systemImage: "xmark.circle.fill")
                    .font(.system(size: 12.5, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
        } content: {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
                ForEach(tabs) { tab in
                    ClosedTabPill(tab: tab) { model.reopenClosedTab(tab) }
                }
            }
        }
    }
}

private struct ClosedTabPill: View {
    let tab: ClosedTab
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Favicon(url: tab.url, size: 16)
                Text(tab.title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .frame(height: 40)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.primary.opacity(hovering ? 0.14 : 0.08))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .help(tab.url.absoluteString)
    }
}

/// A favourite: an app-icon-style tile. Big site icons fill it; small ones sit centred.
private struct FavouriteTile: View {
    let bookmark: Bookmark
    @ObservedObject var model: BrowserModel
    @State private var icon: SiteIcon?
    @State private var loaded = false
    @State private var hovering = false

    var body: some View {
        Button {
            model.open(bookmark.url, inNewTab: NSEvent.modifierFlags.contains(.command))
        } label: {
            VStack(spacing: 9) {
                tile
                    .frame(width: 66, height: 66)
                    .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).strokeBorder(Color.black.opacity(0.08)))
                    .shadow(color: .black.opacity(hovering ? 0.25 : 0.12), radius: hovering ? 10 : 4, y: hovering ? 5 : 2)
                    .scaleEffect(hovering ? 1.05 : 1)
                Text(bookmark.title)
                    .font(.system(size: 12))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(width: 92)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.spring(response: 0.25, dampingFraction: 0.75), value: hovering)
        .help(bookmark.url.absoluteString)
        .task(id: bookmark.url) {
            icon = await FaviconCache.shared.info(for: bookmark.url)
            loaded = true
        }
        .contextMenu {
            Button("Open in New Tab") { model.open(bookmark.url, inNewTab: true) }
            Divider()
            Button("Remove from Favourites") { BookmarkStore.shared.remove(bookmark) }
        }
    }

    @ViewBuilder private var tile: some View {
        if let icon, icon.isLarge {
            Image(nsImage: icon.image).resizable().interpolation(.high).aspectRatio(contentMode: .fill)
        } else if let icon {
            ZStack {
                Color(nsColor: .controlBackgroundColor)
                Image(nsImage: icon.image).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                    .frame(width: 34, height: 34)
            }
        } else {
            Favicon(url: loaded ? bookmark.url : nil, size: 66)
        }
    }
}

/// A suggestion: a card tinted with the site's own colour.
private struct SuggestionCard: View {
    let site: FrequentSite
    @ObservedObject var model: BrowserModel
    @State private var icon: SiteIcon?
    @State private var hovering = false

    private var tint: Color {
        if let c = icon?.tint?.usingColorSpace(.deviceRGB) {
            // Darken a little so white text always reads well.
            return Color(red: c.redComponent * 0.72, green: c.greenComponent * 0.72, blue: c.blueComponent * 0.72)
        }
        let hue = Double(site.host.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) % 360 }) / 360
        return Color(hue: hue, saturation: 0.5, brightness: 0.5)
    }

    var body: some View {
        Button {
            model.open(site.url, inNewTab: NSEvent.modifierFlags.contains(.command))
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                ZStack {
                    if let icon, icon.isLarge {
                        Image(nsImage: icon.image).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                            .frame(width: 52, height: 52)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    } else {
                        Favicon(url: site.url, size: 34)
                            .padding(9)
                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white))
                    }
                }
                .shadow(color: .black.opacity(0.2), radius: 6, y: 3)
                .frame(maxWidth: .infinity)
                .frame(height: 104)

                VStack(alignment: .leading, spacing: 3) {
                    Text(site.title).font(.system(size: 13.5, weight: .semibold)).lineLimit(1)
                    Text(site.host).font(.system(size: 11.5)).opacity(0.75).lineLimit(1)
                    Spacer(minLength: 10)
                    Text(Self.when(site.lastVisit)).font(.system(size: 11.5)).opacity(0.7)
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 13)
                .frame(height: 92, alignment: .top)
            }
            .foregroundStyle(.white)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(LinearGradient(colors: [tint.opacity(0.92), tint], startPoint: .top, endPoint: .bottom))
            )
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.white.opacity(0.08)))
            .shadow(color: .black.opacity(hovering ? 0.3 : 0.14), radius: hovering ? 14 : 6, y: hovering ? 7 : 3)
            .scaleEffect(hovering ? 1.025 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.spring(response: 0.28, dampingFraction: 0.8), value: hovering)
        .animation(.easeOut(duration: 0.3), value: icon?.pixels)
        .help(site.url.absoluteString)
        .task(id: site.host) { icon = await FaviconCache.shared.info(for: site.url) }
        .contextMenu {
            Button("Open in New Tab") { model.open(site.url, inNewTab: true) }
            Button("Add to Favourites") { BookmarkStore.shared.toggle(url: site.url, title: site.title) }
            Divider()
            Button("Remove from Suggestions") { HistoryStore.shared.hideFromStartPage(site.host) }
        }
    }

    static func when(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        if let days = calendar.dateComponents([.day], from: date, to: Date()).day, days < 7 {
            return date.formatted(.dateTime.weekday(.wide))
        }
        return date.formatted(.dateTime.day().month(.abbreviated))
    }
}

private struct PrivacyReportSection: View {
    @ObservedObject private var report = PrivacyReport.shared
    @State private var showingMore = false

    var body: some View {
        let s = report.summary
        StartSection(title: "Privacy Report") {
            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 18) {
                    Image(systemName: "shield.lefthalf.filled")
                        .font(.system(size: 44, weight: .medium))
                        .foregroundStyle(LinearGradient(colors: [Color(red: 0.55, green: 0.45, blue: 1.0),
                                                                 Color(red: 0.30, green: 0.55, blue: 1.0)],
                                                        startPoint: .top, endPoint: .bottom))
                    Text("Hush stops trackers from following you around the web.")
                        .font(.system(size: 17))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button("Show More") { showingMore = true }
                        .buttonStyle(.link)
                        .disabled(s.trackers.isEmpty)
                        .popover(isPresented: $showingMore, arrowEdge: .top) { TrackerList(summary: s) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 12) {
                    Text("Last 30 days").font(.system(size: 12.5)).foregroundStyle(.secondary)
                    HStack(spacing: 12) {
                        ReportTile(label: "Trackers blocked", value: s.blocked.formatted())
                        ReportTile(label: "Websites that tried to track you",
                                   value: s.sitesVisited == 0 ? "–" : "\(s.percentWithTrackers)%")
                    }
                    if let top = s.trackers.first {
                        ReportTile(label: "Most widespread tracker",
                                   value: "\(top.tracker) was blocked on \(top.sites) website\(top.sites == 1 ? "" : "s")",
                                   smallValue: true)
                    } else {
                        ReportTile(label: "Most widespread tracker", value: "Nothing blocked yet", smallValue: true)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.primary.opacity(0.07))
            )
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.primary.opacity(0.06)))
        }
    }
}

private struct ReportTile: View {
    let label: String
    let value: String
    var smallValue = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(.system(size: 12)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(value)
                .font(.system(size: smallValue ? 16 : 26, weight: .bold, design: smallValue ? .default : .rounded))
                .monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.primary.opacity(0.08)))
    }
}

private struct TrackerList: View {
    let summary: PrivacyReport.Summary

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Trackers blocked in the last 30 days")
                .font(.system(size: 13, weight: .semibold))
                .padding(14)
            Divider()
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(summary.trackers.prefix(50), id: \.tracker) { item in
                        HStack {
                            Favicon(url: URL(string: "https://\(item.tracker)"), size: 16)
                            Text(item.tracker).font(.system(size: 12.5))
                            Spacer()
                            Text("\(item.sites) site\(item.sites == 1 ? "" : "s")")
                                .font(.system(size: 12)).foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                    }
                }
            }
            .frame(maxHeight: 320)
        }
        .frame(width: 330)
    }
}

// MARK: - Backdrop

/// Frosted glass (the desktop softly blurred behind the window) with the chosen theme on top.
private struct StartBackdrop: View {
    let style: StartBackground
    let translucent: Bool

    var body: some View {
        ZStack {
            if translucent {
                VisualEffect(material: .underWindowBackground, blending: .behindWindow)
                StartBackgroundView(style: style, translucent: true)
            } else {
                StartBackgroundView(style: style, translucent: false)
            }
        }
        .clipped()
        .allowsHitTesting(false)
    }
}

/// The theme layer: a soft twilight gradient, slow-drifting aurora, or plain.
struct StartBackgroundView: View {
    let style: StartBackground
    var translucent = false
    @Environment(\.colorScheme) private var scheme
    @AppStorage(Prefs.reduceMotion) private var reduceMotion = false

    var body: some View {
        Group {
            switch style {
            case .plain:
                if translucent { Color.clear } else { Color(nsColor: .windowBackgroundColor) }
            case .twilight:
                LinearGradient(
                    colors: scheme == .dark
                        ? [Color(red: 0.09, green: 0.09, blue: 0.13), Color(red: 0.13, green: 0.11, blue: 0.19)]
                        : [Color(red: 0.98, green: 0.97, blue: 1.0), Color(red: 0.93, green: 0.93, blue: 0.98)],
                    startPoint: .top, endPoint: .bottom)
                .opacity(translucent ? 0.55 : 1)
            case .aurora:
                AuroraView(dark: scheme == .dark, animate: !reduceMotion, translucent: translucent)
            }
        }
        // A backdrop must never catch clicks or spill outside the page.
        .clipped()
        .allowsHitTesting(false)
    }
}

/// Slowly drifting colour fields. Drawn frame by frame from the clock (no long-running
/// SwiftUI animation that could leak into the toolbar), with cheap radial gradients.
private struct AuroraView: View {
    let dark: Bool
    let animate: Bool
    var translucent = false
    /// Pauses the drift when the window isn't the one in use (saves power).
    @Environment(\.controlActiveState) private var activeState

    private struct Field {
        let color: Color
        let from: CGPoint
        let to: CGPoint
        let radius: CGFloat
        let speed: Double
    }

    private let fields = [
        Field(color: Color(red: 0.45, green: 0.35, blue: 0.95), from: CGPoint(x: 0.25, y: 0.32), to: CGPoint(x: 0.34, y: 0.22), radius: 0.48, speed: 28),
        Field(color: Color(red: 0.15, green: 0.65, blue: 0.85), from: CGPoint(x: 0.66, y: 0.40), to: CGPoint(x: 0.74, y: 0.55), radius: 0.40, speed: 34),
        Field(color: Color(red: 0.95, green: 0.45, blue: 0.65), from: CGPoint(x: 0.56, y: 0.72), to: CGPoint(x: 0.46, y: 0.80), radius: 0.36, speed: 40),
    ]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24, paused: !animate || activeState == .inactive)) { context in
            Canvas { ctx, size in
                let base = dark ? Color(red: 0.07, green: 0.07, blue: 0.11) : Color(red: 0.97, green: 0.97, blue: 0.99)
                ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(base.opacity(translucent ? 0.45 : 1)))
                let t = animate ? context.date.timeIntervalSinceReferenceDate : 0
                let strength = dark ? 0.55 : 0.32
                for field in fields {
                    let phase = (sin(t * 2 * .pi / field.speed) + 1) / 2
                    let center = CGPoint(x: (field.from.x + (field.to.x - field.from.x) * phase) * size.width,
                                         y: (field.from.y + (field.to.y - field.from.y) * phase) * size.height)
                    let r = field.radius * size.width
                    let rect = CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)
                    ctx.fill(Path(ellipseIn: rect), with: .radialGradient(
                        Gradient(stops: [
                            .init(color: field.color.opacity(strength), location: 0),
                            .init(color: field.color.opacity(strength * 0.45), location: 0.45),
                            .init(color: field.color.opacity(0), location: 1),
                        ]),
                        center: center, startRadius: 0, endRadius: r))
                }
            }
        }
    }
}
