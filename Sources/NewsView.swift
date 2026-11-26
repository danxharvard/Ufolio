import SwiftUI

/// News on the start page: a hero story, then a varied, editorial layout of picture cards,
/// wide stories and headline lists, with topics along the top.
struct NewsSection: View {
    let model: BrowserModel   // only used to open pages; tab changes needn't redraw this
    @Binding var customising: Bool
    @ObservedObject private var store = NewsStore.shared
    @AppStorage(Prefs.startNews) private var newsOn = false
    @AppStorage("news.introDismissed") private var introDismissed = false
    @State private var channel: NewsChannel?
    @State private var limit = 25

    var body: some View {
        if newsOn {
            feed
                .onAppear { store.refreshIfNeeded() }
        } else if !introDismissed {
            NewsIntro {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { newsOn = true }
                Task { await store.refresh() }
            } onDismiss: {
                withAnimation(.easeOut(duration: 0.25)) { introDismissed = true }
            }
        }
    }

    private var feed: some View {
        let stories = store.stories(for: channel)
        return VStack(alignment: .leading, spacing: 18) {
            header
            chips
            if stories.isEmpty {
                if store.isLoading { NewsSkeleton() } else if store.articles.isEmpty {
                    // Couldn't load (offline, say): a still note, not the shimmer, which used to run
                    // 30 times a second for as long as the start page was open.
                    VStack(spacing: 10) {
                        Text("News couldn’t load just now.").font(.system(size: 13)).foregroundStyle(.secondary)
                        Button("Try Again") { Task { await store.refresh() } }.buttonStyle(.link).font(.system(size: 12.5))
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 40)
                } else {
                    Text("No stories in \(channel?.title ?? "your topics") right now.")
                        .font(.system(size: 13)).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity).padding(.vertical, 40)
                }
            } else {
                NewsLayout(model: model, stories: Array(stories.prefix(limit)))
                    .id(channel?.rawValue ?? "all")
                    .transition(.opacity)
                if stories.count > limit {
                    Button {
                        withAnimation(.easeOut(duration: 0.25)) { limit += 25 }
                    } label: {
                        Label("Show more stories", systemImage: "chevron.down")
                            .font(.system(size: 12.5, weight: .semibold))
                            .padding(.horizontal, 18).padding(.vertical, 9)
                            .background(Capsule().fill(Color.primary.opacity(0.07)))
                            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08)))
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                }
            }
            HStack(spacing: 6) {
                Image(systemName: "hand.raised.fill")
                Text("Stories come straight from each publisher’s own feed, fetched privately by Ufolio. No tracking, no account, no news service in between.")
            }
            .font(.system(size: 11))
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity)
            .padding(.top, 6)
        }
        .animation(.smooth(duration: 0.26), value: channel)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            IconTile(symbol: "newspaper.fill", colors: [Color(red: 0.62, green: 0.49, blue: 1.0), Color(red: 0.38, green: 0.26, blue: 0.86)], size: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text("News").font(.system(size: 21, weight: .bold))
                Text(updatedLine).font(.system(size: 11.5)).foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                Task { await store.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .semibold))
                    .rotationEffect(.degrees(store.isLoading ? 360 : 0))
                    .animation(store.isLoading ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: store.isLoading)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Color.primary.opacity(0.07)))
            }
            .buttonStyle(.plain)
            .help("Refresh")
            .disabled(store.isLoading)
            Button { customising = true } label: {
                Label("Customise", systemImage: "slider.horizontal.3")
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 12).frame(height: 30)
                    .background(Capsule().fill(Color.primary.opacity(0.07)))
            }
            .buttonStyle(.plain)
        }
    }

    private var updatedLine: String {
        let publishers = Set(store.activeSources.map(\.name)).count
        guard let updated = store.lastUpdated else { return "From \(publishers) publishers" }
        if Date().timeIntervalSince(updated) < 60 { return "From \(publishers) publishers · Just updated" }
        return "From \(publishers) publishers · Updated \(NewsTime.ago(updated))"
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                NewsChip(title: "For You", symbol: "sparkles", colors: [Color(red: 0.62, green: 0.49, blue: 1.0), Color(red: 0.38, green: 0.26, blue: 0.86)],
                         selected: channel == nil) { channel = nil; limit = 25 }
                ForEach(NewsChannel.allCases.filter { store.followed.contains($0) }) { c in
                    NewsChip(title: c.title, symbol: c.symbol, colors: c.colors, selected: channel == c) { channel = c; limit = 25 }
                }
            }
            .padding(.vertical, 2)
        }
    }
}

private struct NewsChip: View {
    let title: String
    let symbol: String
    let colors: [Color]
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 10.5, weight: .semibold))
                Text(title).font(.system(size: 12.5, weight: selected ? .semibold : .medium))
            }
            .foregroundStyle(selected ? Color.white : Color.primary.opacity(0.8))
            .padding(.horizontal, 13).frame(height: 30)
            .background {
                if selected {
                    Capsule().fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                        .shadow(color: colors[1].opacity(0.35), radius: 6, y: 2)
                } else {
                    Capsule().fill(Color.primary.opacity(0.07))
                        .overlay(Capsule().fill(Color.primary.opacity(hovering ? 0.06 : 0)))
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: selected)
    }
}

// MARK: - Layout

/// A hero story, then a repeating rhythm: two picture cards, a wide story, three compact
/// cards and a list of headlines, so the page reads like a magazine rather than a grid.
private struct NewsLayout: View {
    let model: BrowserModel   // only used to open pages; tab changes needn't redraw this
    let stories: [NewsArticle]

    private enum Row: Identifiable {
        case hero(NewsArticle), pair([NewsArticle]), wide(NewsArticle), trio([NewsArticle]), headlines([NewsArticle])
        var id: String {
            switch self {
            case .hero(let a), .wide(let a): return "h" + a.id
            case .pair(let l), .trio(let l), .headlines(let l): return l.map(\.id).joined()
            }
        }
    }

    private var rows: [Row] {
        var pictures = stories.filter { $0.image != nil }
        var words = stories.filter { $0.image == nil }
        var rows: [Row] = []
        if !pictures.isEmpty { rows.append(.hero(pictures.removeFirst())) }
        var step = 0
        func take(_ n: Int) -> [NewsArticle] {
            let chunk = Array(pictures.prefix(n)); pictures.removeFirst(chunk.count); return chunk
        }
        while !pictures.isEmpty || !words.isEmpty {
            switch step % 4 {
            case 0: let c = take(2); if c.count == 2 { rows.append(.pair(c)) } else if let a = c.first { rows.append(.wide(a)) }
            case 1: let c = take(1); if let a = c.first { rows.append(.wide(a)) }
            case 2: let c = take(3); if c.count == 3 { rows.append(.trio(c)) } else { c.forEach { rows.append(.wide($0)) } }
            default:
                // Headlines: stories without pictures first, then the oldest pictures.
                var list = Array(words.prefix(5)); words.removeFirst(list.count)
                if list.count < 5 { let extra = Array(pictures.suffix(5 - list.count)); pictures.removeLast(extra.count); list += extra }
                if !list.isEmpty { rows.append(.headlines(list)) }
            }
            step += 1
            if step > 400 { break }
        }
        return rows
    }

    var body: some View {
        LazyVStack(spacing: 16) {
            ForEach(rows) { row in
                switch row {
                case .hero(let a): HeroCard(model: model, article: a)
                case .pair(let l):
                    HStack(alignment: .top, spacing: 16) { ForEach(l) { StoryCard(model: model, article: $0, imageHeight: 200, titleSize: 17) } }
                case .wide(let a): WideCard(model: model, article: a)
                case .trio(let l):
                    HStack(alignment: .top, spacing: 16) { ForEach(l) { StoryCard(model: model, article: $0, imageHeight: 130, titleSize: 14.5, showSummary: false) } }
                case .headlines(let l): HeadlinesCard(model: model, stories: l)
                }
            }
        }
    }
}

// MARK: - Cards

/// Shared behaviour for every story: open it (⌘-click for a new tab), mark it read, and a
/// right-click menu.
private struct StoryButton<Label: View>: View {
    let model: BrowserModel   // only used to open pages; tab changes needn't redraw this
    let article: NewsArticle
    @ViewBuilder let label: (_ hovering: Bool) -> Label
    @State private var hovering = false

    var body: some View {
        Button {
            NewsStore.shared.markRead(article)
            model.open(article.link, inNewTab: NSEvent.modifierFlags.contains(.command))
        } label: {
            label(hovering)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: hovering)
        .accessibilityLabel(article.title)
        .contextMenu {
            Button { NewsStore.shared.markRead(article); model.open(article.link) } label: { SwiftUI.Label("Open", systemImage: "arrow.up.forward.square") }
            Button { NewsStore.shared.markRead(article); model.open(article.link, inNewTab: true) } label: { SwiftUI.Label("Open in New Tab", systemImage: "plus.square.on.square") }
            Button("Copy Link") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(CleanLinks.clean(article.link).absoluteString, forType: .string)
            }
            Divider()
            if let source = NewsStore.shared.allSources.first(where: { $0.id == article.sourceID }) {
                Button("Hide Stories from \(article.sourceName)") { NewsStore.shared.setSource(source, shown: false) }
            }
        }
    }
}

private struct HeroCard: View {
    let model: BrowserModel   // only used to open pages; tab changes needn't redraw this
    let article: NewsArticle
    @ObservedObject private var store = NewsStore.shared

    var body: some View {
        StoryButton(model: model, article: article) { hovering in
            ZStack(alignment: .bottomLeading) {
                NewsPicture(url: article.image, channel: article.channel, site: article.site, maxPixels: 1400, zoomed: hovering)
                    .frame(height: 360)
                LinearGradient(colors: [.clear, .black.opacity(0.25), .black.opacity(0.82)], startPoint: .center, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 10) {
                    ChannelTag(channel: article.channel)
                    Text(article.title)
                        .font(.system(size: 30, weight: .bold, design: .serif))
                        .foregroundStyle(.white)
                        .lineLimit(3)
                        .shadow(color: .black.opacity(0.35), radius: 6, y: 2)
                    if !article.summary.isEmpty {
                        Text(article.summary).font(.system(size: 13.5)).foregroundStyle(.white.opacity(0.85)).lineLimit(2)
                    }
                    Byline(article: article, light: true)
                }
                .padding(24)
                .frame(maxWidth: 760, alignment: .leading)
            }
            .frame(height: 360)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.white.opacity(0.08)))
            .drawingGroup()
            .shadow(color: .black.opacity(0.16), radius: 5, y: 3)
            .offset(y: hovering ? -2 : 0)
            .opacity(store.read.contains(article.id) ? 0.75 : 1)
        }
    }
}

private struct StoryCard: View {
    let model: BrowserModel   // only used to open pages; tab changes needn't redraw this
    let article: NewsArticle
    let imageHeight: CGFloat
    let titleSize: CGFloat
    var showSummary = true
    @ObservedObject private var store = NewsStore.shared

    var body: some View {
        StoryButton(model: model, article: article) { hovering in
            VStack(alignment: .leading, spacing: 0) {
                NewsPicture(url: article.image, channel: article.channel, site: article.site, maxPixels: 800, zoomed: hovering)
                    .frame(height: imageHeight)
                    .clipped()
                VStack(alignment: .leading, spacing: 7) {
                    Byline(article: article, light: false)
                    Text(article.title)
                        .font(.system(size: titleSize, weight: .semibold, design: .serif))
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .opacity(store.read.contains(article.id) ? 0.55 : 1)
                    if showSummary, !article.summary.isEmpty {
                        Text(article.summary).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .modifier(CardStyle(hovering: hovering))
        }
        .frame(maxWidth: .infinity)
    }
}

private struct WideCard: View {
    let model: BrowserModel   // only used to open pages; tab changes needn't redraw this
    let article: NewsArticle
    @ObservedObject private var store = NewsStore.shared

    var body: some View {
        StoryButton(model: model, article: article) { hovering in
            HStack(spacing: 0) {
                NewsPicture(url: article.image, channel: article.channel, site: article.site, maxPixels: 700, zoomed: hovering)
                    .frame(width: 330, height: 190)
                    .clipped()
                VStack(alignment: .leading, spacing: 9) {
                    ChannelTag(channel: article.channel, compact: true)
                    Text(article.title)
                        .font(.system(size: 20, weight: .bold, design: .serif))
                        .lineLimit(3)
                        .opacity(store.read.contains(article.id) ? 0.55 : 1)
                    if !article.summary.isEmpty {
                        Text(article.summary).font(.system(size: 12.5)).foregroundStyle(.secondary).lineLimit(3)
                    }
                    Spacer(minLength: 0)
                    Byline(article: article, light: false)
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 190)
            .modifier(CardStyle(hovering: hovering))
        }
    }
}

private struct HeadlinesCard: View {
    let model: BrowserModel   // only used to open pages; tab changes needn't redraw this
    let stories: [NewsArticle]
    @ObservedObject private var store = NewsStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "list.number").font(.system(size: 12, weight: .bold)).foregroundStyle(Color.accentColor)
                Text("Also in the news").font(.system(size: 13, weight: .semibold))
            }
            .padding(.bottom, 6)
            ForEach(Array(stories.enumerated()), id: \.element.id) { index, article in
                StoryButton(model: model, article: article) { hovering in
                    HStack(alignment: .firstTextBaseline, spacing: 14) {
                        Text("\(index + 1)")
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                            .foregroundStyle(LinearGradient(colors: article.channel.colors, startPoint: .top, endPoint: .bottom))
                            .frame(width: 28, alignment: .trailing)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(article.title)
                                .font(.system(size: 15, weight: .semibold, design: .serif))
                                .lineLimit(2)
                                .opacity(store.read.contains(article.id) ? 0.55 : 1)
                                .underline(hovering, color: .primary.opacity(0.3))
                            Byline(article: article, light: false)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 6)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(hovering ? 0.05 : 0)))
                }
                if index < stories.count - 1 { Divider().padding(.leading, 48) }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(CardStyle(hovering: false))
    }
}

private struct CardStyle: ViewModifier {
    let hovering: Bool
    func body(content: Content) -> some View {
        content
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.primary.opacity(0.07)))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.primary.opacity(hovering ? 0.12 : 0.06)))
            .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
            .offset(y: hovering ? -2 : 0)
    }
}

// MARK: - Pieces

private struct ChannelTag: View {
    let channel: NewsChannel
    var compact = false

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: channel.symbol).font(.system(size: compact ? 9 : 10, weight: .bold))
            Text(channel.title.uppercased()).font(.system(size: compact ? 9.5 : 10.5, weight: .bold)).tracking(0.6)
        }
        .foregroundStyle(compact ? AnyShapeStyle(LinearGradient(colors: channel.colors, startPoint: .leading, endPoint: .trailing)) : AnyShapeStyle(Color.white))
        .padding(.horizontal, compact ? 0 : 9).padding(.vertical, compact ? 0 : 4)
        .background {
            if !compact { Capsule().fill(LinearGradient(colors: channel.colors, startPoint: .leading, endPoint: .trailing)) }
        }
    }
}

private struct Byline: View {
    let article: NewsArticle
    let light: Bool

    var body: some View {
        HStack(spacing: 6) {
            Favicon(url: article.site, size: 14)
            Text(article.sourceName).font(.system(size: 11.5, weight: .semibold)).lineLimit(1)
            Text("·").opacity(0.5)
            Text(NewsTime.ago(article.published)).font(.system(size: 11.5))
        }
        .foregroundStyle(light ? Color.white.opacity(0.85) : Color.secondary)
    }
}

/// A story's picture: a soft, topic-coloured placeholder that the photo fades in over.
private struct NewsPicture: View {
    let url: URL?
    let channel: NewsChannel
    let site: URL
    let maxPixels: Int
    let zoomed: Bool
    @State private var image: NSImage?

    var body: some View {
        GeometryReader { geo in
            ZStack {
                LinearGradient(colors: [channel.colors[0].opacity(0.45), channel.colors[1].opacity(0.25)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                if image == nil {
                    Favicon(url: site, size: 30).opacity(0.5)
                }
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .scaleEffect(zoomed ? 1.04 : 1)
                        .animation(.easeOut(duration: 0.5), value: zoomed)
                        .transition(.opacity)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
        }
        .task(id: url) {
            guard let url else { return }
            let loaded = await NewsImages.shared.image(url, maxPixels: maxPixels)
            withAnimation(.easeOut(duration: 0.35)) { image = loaded }
        }
    }
}

/// Shimmering placeholders while the first stories arrive.
private struct NewsSkeleton: View {
    /// Still while the window isn't the one you're using.
    @Environment(\.controlActiveState) private var activeState

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: activeState == .inactive)) { context in
            let phase = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.6) / 1.6
            VStack(spacing: 16) {
                block(height: 360, phase: phase)
                HStack(spacing: 16) { block(height: 280, phase: phase); block(height: 280, phase: phase) }
            }
        }
    }

    private func block(height: CGFloat, phase: Double) -> some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(Color.primary.opacity(0.06))
            .overlay(
                GeometryReader { geo in
                    LinearGradient(colors: [.clear, Color.primary.opacity(0.07), .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: geo.size.width * 0.5)
                        .offset(x: -geo.size.width * 0.5 + geo.size.width * 1.5 * phase)
                }
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            )
            .frame(height: height)
    }
}

enum NewsTime {
    private static let formatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f
    }()

    static func ago(_ date: Date) -> String {
        let seconds = Date().timeIntervalSince(date)
        if seconds < 60 { return "just now" }
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Turning News on

private struct NewsIntro: View {
    let onEnable: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 22) {
            DialogScene(art: .symbol("newspaper.fill"), badge: "sparkles",
                        colors: [Color(red: 0.62, green: 0.49, blue: 1.0), Color(red: 0.38, green: 0.26, blue: 0.86)], motion: .sparkle)
                .frame(width: 180, height: 130)
            VStack(alignment: .leading, spacing: 8) {
                Text("Ufolio News").font(.system(size: 22, weight: .bold, design: .serif))
                Text("Headlines from the BBC, the Guardian, The Verge, NASA and more, right here on your start page. Fetched privately by Ufolio, straight from each publisher: no tracking and no account.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    Button("Turn On News", action: onEnable)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    Button("Not Now", action: onDismiss)
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 4)
            }
            Spacer(minLength: 0)
        }
        .padding(22)
        .modifier(CardStyle(hovering: false))
    }
}

// MARK: - Customise

struct NewsCustomiseCard: View {
    let onDone: () -> Void
    @ObservedObject private var store = NewsStore.shared
    @State private var feedText = ""
    @State private var adding = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                IconTile(symbol: "slider.horizontal.3", colors: [Color(red: 0.62, green: 0.49, blue: 1.0), Color(red: 0.38, green: 0.26, blue: 0.86)], size: 36)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Customise News").font(.system(size: 18, weight: .bold))
                    Text("Choose your topics and publishers, or add any news feed.").font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
            .padding(20)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("TOPICS").font(.system(size: 10.5, weight: .semibold)).tracking(0.8).foregroundStyle(.secondary)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 8)], spacing: 8) {
                            ForEach(NewsChannel.allCases) { channel in
                                let on = store.followed.contains(channel)
                                Button { store.toggle(channel) } label: {
                                    HStack(spacing: 8) {
                                        IconTile(symbol: channel.symbol, colors: on ? channel.colors : [Color.gray.opacity(0.5), Color.gray.opacity(0.35)], size: 24)
                                        Text(channel.title).font(.system(size: 12.5, weight: .medium))
                                        Spacer(minLength: 0)
                                        Image(systemName: on ? "checkmark.circle.fill" : "circle")
                                            .foregroundStyle(on ? Color.accentColor : Color.secondary.opacity(0.5))
                                    }
                                    .padding(8)
                                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(on ? 0.07 : 0.035)))
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("PUBLISHERS").font(.system(size: 10.5, weight: .semibold)).tracking(0.8).foregroundStyle(.secondary)
                        VStack(spacing: 0) {
                            ForEach(NewsCatalogue.sources.filter { store.followed.contains($0.channel) }) { source in
                                SourceRow(source: source)
                                Divider().padding(.leading, 36)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("YOUR FEEDS").font(.system(size: 10.5, weight: .semibold)).tracking(0.8).foregroundStyle(.secondary)
                        ForEach(store.customSources) { source in
                            HStack(spacing: 10) {
                                Favicon(url: source.site, size: 18)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(source.name).font(.system(size: 12.5))
                                    Text(source.feed.host ?? "").font(.system(size: 10.5)).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("Remove") { store.removeFeed(source) }.controlSize(.small)
                            }
                        }
                        HStack(spacing: 8) {
                            TextField("Paste a news feed address (RSS or Atom)", text: $feedText)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit(add)
                            Button(adding ? "Adding…" : "Add", action: add)
                                .disabled(adding || feedText.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                        if let error {
                            Label(error, systemImage: "exclamationmark.circle.fill").font(.system(size: 11.5)).foregroundStyle(.orange)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 10)
            }
            .frame(height: 420)

            HStack {
                Button("Turn Off News") {
                    UserDefaults.standard.set(false, forKey: Prefs.startNews)
                    onDone()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                Spacer()
                Button("Done", action: onDone)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
            .padding(20)
        }
        .frame(width: 540)
    }

    private func add() {
        guard !adding else { return }
        adding = true
        error = nil
        Task { @MainActor in
            error = await store.addFeed(feedText)
            if error == nil { feedText = "" }
            adding = false
        }
    }
}

private struct SourceRow: View {
    let source: NewsSource
    @ObservedObject private var store = NewsStore.shared

    var body: some View {
        HStack(spacing: 10) {
            Favicon(url: source.site, size: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(source.name).font(.system(size: 12.5))
                Text(source.channel.title).font(.system(size: 10.5)).foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: Binding(get: { !store.hiddenSources.contains(source.id) },
                                     set: { store.setSource(source, shown: $0) }))
                .toggleStyle(.switch).labelsHidden().controlSize(.small)
        }
        .padding(.vertical, 7)
    }
}
