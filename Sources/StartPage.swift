import SwiftUI

/// What a new tab shows: a fast, frosted page with recently closed tabs,
/// your favourites, suggestions from your history and a privacy report.
struct StartPage: View {
    let model: BrowserModel   // only used to open pages; tab changes needn't redraw this
    /// The current Orbit's profile's bookmarks and history.
    @ObservedObject private var bookmarks: BookmarkStore
    @ObservedObject private var history: HistoryStore
    @ObservedObject private var closed = RecentlyClosed.shared
    @ObservedObject private var weather = LocalWeather.shared
    @ObservedObject private var background = BackgroundStore.shared
    @Environment(\.colorScheme) private var scheme
    @AppStorage(Prefs.startGreeting) private var showGreeting = true
    @AppStorage(Prefs.startRecentlyClosed) private var showClosed = true
    @AppStorage(Prefs.startBookmarks) private var showFavourites = true
    @AppStorage(Prefs.startFrequent) private var showSuggestions = true
    @AppStorage(Prefs.startPrivacyReport) private var showPrivacy = true
    @AppStorage(Prefs.startShowAdult) private var showAdult = false
    @AppStorage(Prefs.startBackground) private var backgroundChoice = StartBackground.frosted.rawValue
    @State private var personalising = false
    @State private var customisingNews = false
    /// The measured height of each section (and the header), so the page can tell which
    /// sections fit without building several copies of itself to find out.
    @State private var partHeights: [Part: CGFloat] = [:]
    @State private var headerHeight: CGFloat = 0

    init(model: BrowserModel) {
        self.model = model
        _bookmarks = ObservedObject(wrappedValue: model.bookmarks)
        _history = ObservedObject(wrappedValue: model.history)
    }

    var body: some View {
        // Only the favourites actually shown (all bookmarks made a huge cache key on every redraw).
        let favouriteHosts = Set(bookmarks.items(in: nil).prefix(16).compactMap { $0.url.host?.lowercased().strippingWWW })
        // Adult sites stay off the start page unless you've chosen to show them.
        let hideAdult = !showAdult
        let suggestions = showSuggestions ? history.frequentSites(limit: hideAdult ? 12 : 6, excluding: favouriteHosts)
            .filter { !hideAdult || !AdultSites.isAdult($0.url) }.prefix(6).map { $0 } : []
        let profile = model.profileID
        let closedTabs = closed.tabs.filter { $0.profile == profile && (!hideAdult || !AdultSites.isAdult($0.url)) }
        ZStack {
            // In the background, so it can never affect the page's size.
            Color.clear.background { StartBackdrop() }
            // A static page, no scrolling: the fullest layout that fits the window is shown,
            // leaving out the least important sections first (News, then the Privacy Report, then
            // Recently Closed) when the window is small.
            let parts = startParts(closedTabs: closedTabs, suggestions: suggestions)
            GeometryReader { geo in
                let shown = fitting(parts, available: geo.size.height - 52)
                page(shown, closedTabs: closedTabs, suggestions: suggestions)
                    .frame(maxWidth: 940, alignment: .leading)
                    .padding(.horizontal, 48)
                    .padding(.vertical, 26)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .clipped()
            // Over a picture, light text reads best.
            .environment(\.colorScheme, background.image != nil || backgroundChoice == StartBackground.sky.rawValue ? .dark : scheme)
        }
        .overlay(alignment: .bottomLeading) {
            if let credit = background.credit, background.image != nil {
                Text(credit)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(1)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Capsule().fill(.black.opacity(0.25)))
                    .padding(14)
            }
        }
        .overlay(alignment: .topTrailing) {
            PersonaliseButton { personalising = true }
                .padding(.top, 16)
                .padding(.trailing, 18)
                .opacity(personalising ? 0 : 1)
        }
        .overlay {
            if personalising {
                LaunchCardOverlay { PersonaliseCard { personalising = false } }
                    .transition(.opacity)
            }
            if customisingNews {
                LaunchCardOverlay { NewsCustomiseCard { customisingNews = false } }
                    .transition(.opacity)
            }
        }
        .animation(.smooth(duration: 0.26), value: customisingNews)
        .animation(.smooth(duration: 0.26), value: closed.tabs.count)
        .animation(.smooth(duration: 0.26), value: personalising)
        .onAppear {
            weather.refreshIfNeeded()
            // The sites you're most likely to open from here get their connections ready now
            // (a look-up and a secure handshake, nothing downloaded), so even a quick click on a
            // favourite skips that part of the wait. Each site at most once every 30 seconds.
            let likely = bookmarks.items(in: nil).prefix(6).map(\.url) + suggestions.prefix(3).map(\.url)
            let view = model.selectedTab?.webView
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                for url in likely { Speed.preconnect(url, in: view) }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: QuitHelper.closeSheets)) { _ in personalising = false }
    }

    enum Part: Hashable { case closed, favourites, suggestions, privacy, news }

    private func startParts(closedTabs: [ClosedTab], suggestions: [FrequentSite]) -> [Part] {
        var parts: [Part] = []
        if showClosed && !closedTabs.isEmpty { parts.append(.closed) }
        if showFavourites && bookmarks.items.contains(where: { $0.folder == nil }) { parts.append(.favourites) }
        if !suggestions.isEmpty { parts.append(.suggestions) }
        if showPrivacy { parts.append(.privacy) }
        if Prefs.bool(Prefs.startNews) { parts.append(.news) }
        return parts
    }

    /// Layouts from fullest to simplest, dropping the least important section each time.
    static func layouts(for parts: [Part]) -> [[Part]] {
        var result = [parts]
        var current = parts
        for drop in [Part.news, .privacy, .closed, .suggestions] where current.contains(drop) {
            current.removeAll { $0 == drop }
            result.append(current)
        }
        return result
    }

    /// The fullest layout whose measured sections fit in the height available. A section not
    /// measured yet counts as nothing, so it's shown once, measured, and dropped if it doesn't fit.
    private func fitting(_ parts: [Part], available: CGFloat) -> [Part] {
        for layout in Self.layouts(for: parts) {
            let total = headerHeight + layout.reduce(0) { $0 + (partHeights[$1] ?? 0) + 30 }
            if total <= available { return layout }
        }
        return []
    }

    private func page(_ parts: [Part], closedTabs: [ClosedTab], suggestions: [FrequentSite]) -> some View {
        VStack(alignment: .leading, spacing: 30) {
            header.riseIn(0)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { headerHeight = $0 }
            ForEach(parts, id: \.self) { part in
                Group {
                    switch part {
                    case .closed: RecentlyClosedSection(model: model, tabs: Array(closedTabs.prefix(6))).riseIn(1)
                    case .favourites: favourites.riseIn(2)
                    case .suggestions: suggestionSection(suggestions).riseIn(3)
                    case .privacy: PrivacyReportSection().riseIn(4)
                    case .news: NewsSection(model: model, customising: $customisingNews).riseIn(5)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGFloat.self) { ($0.size.height).rounded() } action: { height in
                    if partHeights[part] != height { partHeights[part] = height }
                }
            }
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            AnimatedHushLogo(size: 54)
                .contentShape(Rectangle())
                .onTapGesture { DeveloperArea.iconClicked(in: model.window) }   // five clicks: the developer area
                .padding(.bottom, 4)
            AlienTitle(size: 50)
            if UFODay.isToday {
                Label("Happy World UFO Day! Keep watching the skies.", systemImage: "sparkles")
                    .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.accentColor)
            } else if let years = UfolioBirthday.yearsToday {
                HStack(spacing: 8) {
                    MiniSaucer(size: 24, partyHat: true)
                    Text("Happy birthday, Ufolio! \(years) year\(years == 1 ? "" : "s") of flying with you.")
                        .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                }
            }
            if showGreeting || weather.temperature != nil {
                HStack(spacing: 8) {
                    if showGreeting { Text(greeting) }
                    if let temperature = weather.temperature {
                        if showGreeting { Text("·").foregroundStyle(.tertiary) }
                        Image(systemName: weather.symbol).symbolRenderingMode(.multicolor)
                        Text("\(temperature)°")
                        if let city = weather.city { Text(city) }
                    }
                }
                .font(.system(size: 14, design: .rounded))
                .foregroundStyle(.secondary)
            }
            AbductionCounter().padding(.top, 4)
            SignalFromSpace()
        }
        .frame(maxWidth: .infinity)
    }

    private var favourites: some View {
        StartSection(title: "Favourites") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 92, maximum: 104), spacing: 14)],
                      alignment: .leading, spacing: 20) {
                // Two rows' worth, from bookmarks not in a folder: showing every bookmark (after
                // importing hundreds) made the section too tall to fit, so it vanished, and
                // fetched every one of their icons each time a new tab opened.
                ForEach(bookmarks.items(in: nil).prefix(16)) { bookmark in
                    FavouriteTile(bookmark: bookmark, model: model)
                }
            }
        }
    }

    private func suggestionSection(_ suggestions: [FrequentSite]) -> some View {
        StartSection(title: "Suggestions") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 158, maximum: 190), spacing: 16)],
                      alignment: .leading, spacing: 16) {
                ForEach(suggestions) { site in
                    SuggestionCard(site: site, model: model)
                }
            }
        }
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
    let model: BrowserModel   // only used to open pages; tab changes needn't redraw this
    let tabs: [ClosedTab]

    var body: some View {
        StartSection(title: "Recently Closed Tabs") {
            Button {
                RecentlyClosed.shared.clear(profile: model.profileID)
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
        .animation(.snappy(duration: 0.16), value: hovering)
    }
}

/// A favourite: an app-icon-style tile. Big site icons fill it; small ones sit centred.
private struct FavouriteTile: View {
    let bookmark: Bookmark
    let model: BrowserModel   // only used to open pages; tab changes needn't redraw this
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
                    .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).strokeBorder(Color.primary.opacity(0.09)))
                    .drawingGroup()   // one flat picture: scrolls without redrawing its layers
                    .shadow(color: .black.opacity(0.14), radius: 3, y: 2)
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
        .onHover { inside in
            hovering = inside
            // Pointing at a favourite: get its connection ready before the click.
            if inside {
                Speed.preconnect(bookmark.url, in: model.selectedTab?.webView)
                Preloader.preloadSoon(bookmark.url, for: model.selectedTab, delay: Preloader.restDelay)   // rested on it: load it
            } else { Preloader.cancelSoon() }
        }
        .animation(.spring(response: 0.25, dampingFraction: 0.75), value: hovering)
        .task(id: bookmark.url) {
            icon = await FaviconCache.shared.info(for: bookmark.url)
            loaded = true
        }
        .contextMenu {
            Button { model.open(bookmark.url, inNewTab: true) } label: { Label("Open in New Tab", systemImage: "plus.square.on.square") }
            Divider()
            Button { model.bookmarks.remove(bookmark) } label: { Label("Remove from Favourites", systemImage: "star.slash") }
        }
    }

    @ViewBuilder private var tile: some View {
        if let icon, icon.isLarge {
            Image(nsImage: icon.image).resizable().interpolation(.high).aspectRatio(contentMode: .fill)
        } else if let icon {
            ZStack {
                StartColors.tile
                Image(nsImage: icon.image).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                    .frame(width: 34, height: 34)
            }
        } else {
            Favicon(url: loaded ? bookmark.url : nil, size: 66)
        }
    }
}

enum StartColors {
    /// Behind small site icons: white in light mode, a soft lift in dark mode.
    static let tile = Color(nsColor: NSColor(name: nil) { a in
        a.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(white: 0.26, alpha: 1) : NSColor(white: 1, alpha: 1)
    })
}

/// A suggestion: a card tinted with the site's own colour.
private struct SuggestionCard: View {
    let site: FrequentSite
    let model: BrowserModel   // only used to open pages; tab changes needn't redraw this
    @State private var icon: SiteIcon?
    @State private var hovering = false

    /// The site's colour, kept rich but dark enough for white text: (hue, saturation, brightness).
    private var tone: (Double, Double, Double) {
        if let c = icon?.tint?.usingColorSpace(.deviceRGB) {
            var h: CGFloat = 0, sat: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            c.getHue(&h, saturation: &sat, brightness: &b, alpha: &a)
            // Near-grey icons stay a soft grey; colourful ones get a clean, even tone.
            let saturation = sat < 0.12 ? sat * 0.5 : min(max(sat * 1.05, 0.38), 0.72)
            return (Double(h), Double(saturation), Double(min(max(b, 0.46), 0.6)))
        }
        let hue = Double(site.host.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) % 360 }) / 360
        return (hue, 0.5, 0.52)
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
                    .fill(LinearGradient(colors: [Color(hue: tone.0, saturation: tone.1 * 0.9, brightness: min(tone.2 + 0.1, 0.72)),
                                                  Color(hue: tone.0, saturation: tone.1, brightness: tone.2 - 0.08)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
            )
            .overlay(alignment: .top) {
                // A soft sheen across the top, like light on glass.
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(LinearGradient(colors: [.white.opacity(0.14), .clear], startPoint: .top, endPoint: .center))
                    .allowsHitTesting(false)
            }
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.white.opacity(0.08)))
            .drawingGroup()   // one flat picture: scrolls without redrawing its layers
            .shadow(color: .black.opacity(0.16), radius: 4, y: 2)
            .scaleEffect(hovering ? 1.025 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { inside in
            hovering = inside
            if inside {
                Speed.preconnect(site.url, in: model.selectedTab?.webView)
                Preloader.preloadSoon(site.url, for: model.selectedTab, delay: Preloader.restDelay)
            } else { Preloader.cancelSoon() }
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.8), value: hovering)
        .animation(.easeOut(duration: 0.3), value: icon?.pixels)
        .task(id: site.host) { icon = await FaviconCache.shared.info(for: site.url) }
        .contextMenu {
            Button { model.open(site.url, inNewTab: true) } label: { Label("Open in New Tab", systemImage: "plus.square.on.square") }
            Button { model.bookmarks.toggle(url: site.url, title: site.title) } label: { Label("Add to Favourites", systemImage: "star") }
            Divider()
            Button { model.history.hideFromStartPage(site.host) } label: { Label("Remove from Suggestions", systemImage: "eye.slash") }
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
            VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 18) {
                    HushLogoTile(size: 52)
                    Text("Ufolio stops trackers from following you around the web.")
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
            Divider().opacity(0.6)
            WeeklyReportCard(summary: s)
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
                            Favicon(url: URL(string: "https://\(item.tracker)"), size: 16, offline: true)
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

private struct RiseIn: ViewModifier {
    let order: Int
    @State private var shown = false
    @AppStorage(Prefs.reduceMotion) private var reduceMotion = false

    func body(content: Content) -> some View {
        content
            .opacity(shown || reduceMotion ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 14)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.smooth(duration: 0.5).delay(0.04 + Double(order) * 0.05)) { shown = true }
            }
    }
}

private extension View {
    func riseIn(_ order: Int) -> some View { modifier(RiseIn(order: order)) }
}
