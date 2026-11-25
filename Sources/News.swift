import SwiftUI
import AppKit
import ImageIO

// MARK: - Topics and sources

/// News topics you can follow on the start page.
enum NewsChannel: String, CaseIterable, Codable, Identifiable {
    case top, world, uk, technology, science, business, sport, entertainment
    var id: String { rawValue }

    var title: String {
        switch self {
        case .top: return "Top Stories"
        case .world: return "World"
        case .uk: return "UK"
        case .technology: return "Technology"
        case .science: return "Science"
        case .business: return "Business"
        case .sport: return "Sport"
        case .entertainment: return "Culture"
        }
    }

    var symbol: String {
        switch self {
        case .top: return "flame.fill"
        case .world: return "globe.europe.africa.fill"
        case .uk: return "building.columns.fill"
        case .technology: return "cpu.fill"
        case .science: return "atom"
        case .business: return "chart.line.uptrend.xyaxis"
        case .sport: return "sportscourt.fill"
        case .entertainment: return "theatermasks.fill"
        }
    }

    var colors: [Color] {
        switch self {
        case .top: return [Color(red: 1.0, green: 0.48, blue: 0.32), Color(red: 0.92, green: 0.26, blue: 0.36)]
        case .world: return [Color(red: 0.30, green: 0.62, blue: 1.0), Color(red: 0.18, green: 0.40, blue: 0.92)]
        case .uk: return [Color(red: 0.55, green: 0.45, blue: 1.0), Color(red: 0.36, green: 0.26, blue: 0.86)]
        case .technology: return [Color(red: 0.25, green: 0.78, blue: 0.85), Color(red: 0.10, green: 0.52, blue: 0.70)]
        case .science: return [Color(red: 0.36, green: 0.80, blue: 0.52), Color(red: 0.14, green: 0.58, blue: 0.40)]
        case .business: return [Color(red: 1.0, green: 0.74, blue: 0.28), Color(red: 0.92, green: 0.52, blue: 0.14)]
        case .sport: return [Color(red: 0.40, green: 0.84, blue: 0.40), Color(red: 0.16, green: 0.62, blue: 0.30)]
        case .entertainment: return [Color(red: 1.0, green: 0.44, blue: 0.68), Color(red: 0.82, green: 0.24, blue: 0.54)]
        }
    }
}

struct NewsSource: Codable, Identifiable, Hashable {
    var name: String
    var feed: URL
    var site: URL
    var channel: NewsChannel
    var custom = false
    var id: String { feed.absoluteString }
}

struct NewsArticle: Codable, Identifiable, Hashable {
    var title: String
    var summary: String
    var link: URL
    var image: URL?
    var published: Date
    var sourceID: String
    var sourceName: String
    var site: URL
    var channel: NewsChannel
    var id: String { link.absoluteString }
}

enum NewsCatalogue {
    private static func s(_ name: String, _ feed: String, _ site: String, _ channel: NewsChannel) -> NewsSource {
        NewsSource(name: name, feed: URL(string: feed)!, site: URL(string: site)!, channel: channel)
    }

    /// Publishers with public RSS feeds, fetched directly (no news service in between).
    static let sources: [NewsSource] = [
        s("BBC News", "https://feeds.bbci.co.uk/news/rss.xml", "https://www.bbc.co.uk/news", .top),
        s("Sky News", "https://feeds.skynews.com/feeds/rss/home.xml", "https://news.sky.com", .top),
        s("The Guardian", "https://www.theguardian.com/world/rss", "https://www.theguardian.com", .world),
        s("Al Jazeera", "https://www.aljazeera.com/xml/rss/all.xml", "https://www.aljazeera.com", .world),
        s("NPR", "https://feeds.npr.org/1001/rss.xml", "https://www.npr.org", .world),
        s("BBC UK", "https://feeds.bbci.co.uk/news/uk/rss.xml", "https://www.bbc.co.uk/news/uk", .uk),
        s("The Guardian UK", "https://www.theguardian.com/uk-news/rss", "https://www.theguardian.com/uk-news", .uk),
        s("The Verge", "https://www.theverge.com/rss/index.xml", "https://www.theverge.com", .technology),
        s("Ars Technica", "https://feeds.arstechnica.com/arstechnica/index", "https://arstechnica.com", .technology),
        s("Wired", "https://www.wired.com/feed/rss", "https://www.wired.com", .technology),
        s("Engadget", "https://www.engadget.com/rss.xml", "https://www.engadget.com", .technology),
        s("BBC Technology", "https://feeds.bbci.co.uk/news/technology/rss.xml", "https://www.bbc.co.uk/news/technology", .technology),
        s("NASA", "https://www.nasa.gov/news-release/feed/", "https://www.nasa.gov", .science),
        s("New Scientist", "https://www.newscientist.com/feed/home/", "https://www.newscientist.com", .science),
        s("BBC Science", "https://feeds.bbci.co.uk/news/science_and_environment/rss.xml", "https://www.bbc.co.uk/news/science_and_environment", .science),
        s("BBC Business", "https://feeds.bbci.co.uk/news/business/rss.xml", "https://www.bbc.co.uk/news/business", .business),
        s("The Guardian Business", "https://www.theguardian.com/uk/business/rss", "https://www.theguardian.com/business", .business),
        s("BBC Sport", "https://feeds.bbci.co.uk/sport/rss.xml", "https://www.bbc.co.uk/sport", .sport),
        s("Sky Sports", "https://www.skysports.com/rss/12040", "https://www.skysports.com", .sport),
        s("BBC Culture", "https://feeds.bbci.co.uk/news/entertainment_and_arts/rss.xml", "https://www.bbc.co.uk/news/entertainment_and_arts", .entertainment),
        s("The Guardian Culture", "https://www.theguardian.com/uk/culture/rss", "https://www.theguardian.com/culture", .entertainment),
    ]
}

// MARK: - The store

/// Fetches, keeps and arranges the news. Everything is fetched by Hush itself, without
/// cookies, straight from each publisher: no news service sees what you read.
@MainActor
final class NewsStore: ObservableObject {
    static let shared = NewsStore()

    @Published private(set) var articles: [NewsArticle] = []
    @Published private(set) var isLoading = false
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var followed: Set<NewsChannel>
    @Published private(set) var hiddenSources: Set<String>
    @Published private(set) var customSources: [NewsSource]
    @Published private(set) var read: Set<String>

    private let cacheFile: URL = {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let dir = caches.appendingPathComponent("Hush Browser", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("news.json")
    }()

    static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        config.timeoutIntervalForRequest = 15
        config.httpAdditionalHeaders = ["User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"]
        return URLSession(configuration: config)
    }()

    private init() {
        let d = UserDefaults.standard
        followed = Set((d.stringArray(forKey: "news.followed") ?? NewsChannel.allCases.map(\.rawValue)).compactMap(NewsChannel.init(rawValue:)))
        hiddenSources = Set(d.stringArray(forKey: "news.hiddenSources") ?? [])
        read = Set(d.stringArray(forKey: "news.read") ?? [])
        if let data = d.data(forKey: "news.customSources"), let saved = try? JSONDecoder().decode([NewsSource].self, from: data) {
            customSources = saved
        } else {
            customSources = []
        }
        if let data = try? Data(contentsOf: cacheFile),
           let cached = try? JSONDecoder().decode(Cache.self, from: data) {
            articles = cached.articles
            lastUpdated = cached.date
        }
    }

    private struct Cache: Codable { var date: Date; var articles: [NewsArticle] }

    var allSources: [NewsSource] { NewsCatalogue.sources + customSources }
    var activeSources: [NewsSource] {
        allSources.filter { !hiddenSources.contains($0.id) && (followed.contains($0.channel) || $0.custom) }
    }

    /// Stories in a topic (or everything you follow), newest first.
    func stories(for channel: NewsChannel?) -> [NewsArticle] {
        let active = Set(activeSources.map(\.id))
        return articles.filter { active.contains($0.sourceID) && (channel == nil || $0.channel == channel) }
    }

    // MARK: Refreshing

    func refreshIfNeeded() {
        guard Prefs.bool(Prefs.startNews) else { return }
        if let lastUpdated, Date().timeIntervalSince(lastUpdated) < 15 * 60, !articles.isEmpty { return }
        Task { await refresh() }
    }

    /// A refresh asked for while one was running (say, a topic switched on mid-refresh): it runs
    /// again afterwards, so the new choice isn't left empty until the next refresh.
    private var refreshAgain = false

    func refresh() async {
        guard !isLoading else { refreshAgain = true; return }
        isLoading = true
        defer {
            if refreshAgain {
                refreshAgain = false
                Task { await refresh() }
            }
        }
        let sources = activeSources
        let fetched = await withTaskGroup(of: [NewsArticle].self) { group in
            for source in sources { group.addTask { await Self.fetch(source) } }
            var all: [NewsArticle] = []
            for await batch in group { all += batch }
            return all
        }
        isLoading = false
        guard !fetched.isEmpty else { return }
        articles = Self.arrange(fetched)
        lastUpdated = Date()
        let snapshot = Cache(date: Date(), articles: articles), file = cacheFile
        Task.detached(priority: .utility) {
            if let data = try? JSONEncoder().encode(snapshot) { try? data.write(to: file, options: .atomic) }
        }
    }

    /// Newest first, no repeats (the same story from two feeds), at most a few days old.
    private static func arrange(_ all: [NewsArticle]) -> [NewsArticle] {
        var seenLinks = Set<String>(), seenTitles = Set<String>()
        let cutoff = Date().addingTimeInterval(-4 * 86_400)
        return all.sorted { $0.published > $1.published }.filter { article in
            let key = article.title.lowercased().filter { $0.isLetter }.prefix(60)
            guard article.published > cutoff, seenLinks.insert(article.id).inserted, seenTitles.insert(String(key)).inserted else { return false }
            return true
        }
        .prefix(400).map { $0 }
    }

    nonisolated static func fetch(_ source: NewsSource) async -> [NewsArticle] {
        guard let (data, response) = try? await session.data(from: source.feed),
              (response as? HTTPURLResponse)?.statusCode == 200, data.count < 6_000_000 else { return [] }
        return FeedParser.parse(data, source: source).prefix(40).map { $0 }
    }

    // MARK: Your choices

    func toggle(_ channel: NewsChannel) {
        if followed.contains(channel) { followed.remove(channel) } else { followed.insert(channel) }
        UserDefaults.standard.set(followed.map(\.rawValue), forKey: "news.followed")
        Task { await refresh() }
    }

    func setSource(_ source: NewsSource, shown: Bool) {
        if shown { hiddenSources.remove(source.id) } else { hiddenSources.insert(source.id) }
        UserDefaults.standard.set(Array(hiddenSources), forKey: "news.hiddenSources")
        if shown { Task { await refresh() } }
    }

    func markRead(_ article: NewsArticle) {
        read.insert(article.id)
        if read.count > 3000 { read = Set(read.suffix(2000)) }
        UserDefaults.standard.set(Array(read), forKey: "news.read")
    }

    private var adding: Set<URL> = []

    /// Adds your own feed after checking it really is one. Returns an error message, or nil.
    func addFeed(_ text: String) async -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed.contains("://") ? trimmed : "https://" + trimmed),
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""), let host = url.host else {
            return "That doesn’t look like a web address."
        }
        guard !allSources.contains(where: { $0.feed == url }), !adding.contains(url) else { return "You already have that feed." }
        // Pressing Add twice quickly used to add the same feed twice (both checks ran before either finished).
        adding.insert(url)
        defer { adding.remove(url) }
        // Every refresh fetches every feed: a sensible number keeps the start page quick.
        guard customSources.count < 30 else { return "You can add up to 30 of your own feeds." }
        guard let (data, response) = try? await Self.session.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return "Ufolio couldn’t reach that feed." }
        // The same limit as the regular refresh (a huge "feed" would be read in on the main thread).
        guard data.count < 6_000_000 else { return "That feed is too large." }
        let title = FeedParser.title(of: data) ?? host.strippingWWW
        var source = NewsSource(name: String(title.prefix(60)), feed: url, site: URL(string: "https://\(host)") ?? url, channel: .top, custom: true)
        source.custom = true
        guard !FeedParser.parse(data, source: source).isEmpty else {
            return "That address isn’t an RSS or Atom news feed."
        }
        customSources.append(source)
        saveCustom()
        await refresh()
        return nil
    }

    func removeFeed(_ source: NewsSource) {
        customSources.removeAll { $0.id == source.id }
        articles.removeAll { $0.sourceID == source.id }
        saveCustom()
    }

    private func saveCustom() {
        UserDefaults.standard.set(try? JSONEncoder().encode(customSources), forKey: "news.customSources")
    }
}

// MARK: - RSS and Atom

/// Reads RSS and Atom feeds into articles. Everything is treated as plain text: no HTML from a
/// feed is ever shown or run.
final class FeedParser: NSObject, XMLParserDelegate {
    private let source: NewsSource
    private var items: [NewsArticle] = []
    private var inItem = false
    private var text = ""
    private var title = "", link = "", summary = "", date = "", content = ""
    private var image: (url: String, width: Int)?
    private var feedTitle: String?
    private var depth = 0

    private init(source: NewsSource) { self.source = source }

    static func parse(_ data: Data, source: NewsSource) -> [NewsArticle] {
        let delegate = FeedParser(source: source)
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldResolveExternalEntities = false   // never fetch anything a feed points to
        parser.parse()
        return delegate.items
    }

    static func title(of data: Data) -> String? {
        let delegate = FeedParser(source: NewsSource(name: "", feed: URL(string: "https://x")!, site: URL(string: "https://x")!, channel: .top))
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldResolveExternalEntities = false
        parser.parse()
        return delegate.feedTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
        text = ""
        let tag = (qualifiedName ?? name).lowercased()
        if tag == "item" || tag == "entry" {
            inItem = true
            title = ""; link = ""; summary = ""; date = ""; content = ""; image = nil
            return
        }
        guard inItem else { return }
        switch tag {
        case "link":
            // Atom: <link rel="alternate" href="…"/>
            if let href = attributes["href"], (attributes["rel"] ?? "alternate") == "alternate", link.isEmpty { link = href }
        case "media:content", "media:thumbnail":
            if let url = attributes["url"], (attributes["medium"] ?? "image") == "image" || (attributes["type"] ?? "").hasPrefix("image") || tag == "media:thumbnail" {
                let width = Int(attributes["width"] ?? "") ?? 0
                if image == nil || width > (image?.width ?? 0) { image = (url, width) }
            }
        case "enclosure":
            if let url = attributes["url"], (attributes["type"] ?? "").hasPrefix("image"), image == nil { image = (url, 0) }
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        text += String(decoding: CDATABlock, as: UTF8.self)
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        let tag = (qualifiedName ?? name).lowercased()
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !inItem {
            if tag == "title", feedTitle == nil { feedTitle = value }
            return
        }
        switch tag {
        case "title": title = value
        case "link": if link.isEmpty { link = value }
        case "description", "summary": summary = value
        case "content:encoded", "content": content = value
        case "pubdate", "published", "updated", "dc:date": if date.isEmpty { date = value }
        case "item", "entry":
            inItem = false
            finishItem()
        default: break
        }
    }

    private func finishItem() {
        guard let url = URL(string: link.trimmingCharacters(in: .whitespacesAndNewlines)),
              ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return }
        let cleanTitle = Self.plain(title)
        guard !cleanTitle.isEmpty else { return }
        var picture = image?.url
        if picture == nil { picture = Self.firstImage(in: content.isEmpty ? summary : content) }
        var imageURL = picture.flatMap { URL(string: $0.replacingOccurrences(of: "&amp;", with: "&")) }
        if let u = imageURL, !["http", "https"].contains(u.scheme?.lowercased() ?? "") { imageURL = nil }
        imageURL = imageURL.map(Self.sharper)
        let text = Self.plain(summary.isEmpty ? content : summary)
        items.append(NewsArticle(title: cleanTitle, summary: String(text.prefix(260)), link: url, image: imageURL,
                                 // No usable date: kept, but below dated stories (as "now" they jumped to
                                 // the top as the newest story on every refresh).
                                 // A date in the future (a feed's time-zone mistake) counts as now, rather
                                 // than keeping the story pinned at the top.
                                 published: Self.date(date).map { min($0, Date()) } ?? Date().addingTimeInterval(-3 * 86_400),
                                 sourceID: source.id, sourceName: source.name,
                                 site: source.site, channel: source.channel))
    }

    /// Bigger pictures where a publisher's address says the size (BBC sends tiny thumbnails).
    private static func sharper(_ url: URL) -> URL {
        let s = url.absoluteString
        if s.contains("ichef.bbci.co.uk"), let range = s.range(of: #"/(standard|ace/standard)/\d+/"#, options: .regularExpression) {
            let replaced = s.replacingCharacters(in: range, with: s[range].replacingOccurrences(of: #"\d+"#, with: "976", options: .regularExpression))
            return URL(string: replaced) ?? url
        }
        return url
    }

    private static func firstImage(in html: String) -> String? {
        guard let range = html.range(of: #"<img[^>]+src=["']([^"']+)["']"#, options: [.regularExpression, .caseInsensitive]) else { return nil }
        let tag = String(html[range])
        guard let src = tag.range(of: #"https?://[^"']+"#, options: .regularExpression) else { return nil }
        return String(tag[src])
    }

    /// Strips tags and decodes entities, for showing as plain text.
    static func plain(_ html: String) -> String {
        var s = html.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
        // One pass, knowing every numeric entity: a fixed list replaced in random order missed
        // many (headlines showed "&#x2019;") and could decode "&amp;lt;" twice.
        s = BookmarkStore.decodeEntities(s)
        return s.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
    }

    private static let rfc822: [DateFormatter] = ["EEE, dd MMM yyyy HH:mm:ss zzz", "EEE, dd MMM yyyy HH:mm:ss Z", "dd MMM yyyy HH:mm:ss zzz",
                                                   "EEE, dd MMM yyyy HH:mm zzz", "EEE, d MMM yyyy HH:mm:ss Z"].map {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = $0
        return f
    }
    private static let iso = ISO8601DateFormatter()
    private static let isoFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static func date(_ text: String) -> Date? {
        let t = text.trimmingCharacters(in: .whitespaces)
        if let d = iso.date(from: t) ?? isoFraction.date(from: t) { return d }
        for f in rfc822 { if let d = f.date(from: t) { return d } }
        return nil
    }
}

// MARK: - Pictures

/// Loads news pictures without cookies, shrunk to the size shown and kept in memory.
actor NewsImages {
    static let shared = NewsImages()
    private let cache = NSCache<NSURL, NSImage>()
    private var inFlight: [URL: Task<NSImage?, Never>] = [:]

    init() {
        cache.countLimit = 80
        cache.totalCostLimit = 48_000_000   // about 48 MB of decoded pictures at most
    }

    func purgeMemory() { cache.removeAllObjects() }

    func image(_ url: URL, maxPixels: Int) async -> NSImage? {
        if let hit = cache.object(forKey: url as NSURL) { return hit }
        if let running = inFlight[url] { return await running.value }
        let task = Task<NSImage?, Never> {
            guard let (data, response) = try? await NewsStore.session.data(from: url),
                  (response as? HTTPURLResponse)?.statusCode == 200, data.count < 15_000_000,
                  let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
            let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
                                            kCGImageSourceCreateThumbnailWithTransform: true,
                                            // Decode now, here in the background, not on first draw (mid-scroll).
                                            kCGImageSourceShouldCacheImmediately: true]
            guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
            return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        }
        inFlight[url] = task
        let image = await task.value
        inFlight[url] = nil
        if let image {
            let cost = image.representations.first.map { $0.pixelsWide * $0.pixelsHigh * 4 } ?? 1_000_000
            cache.setObject(image, forKey: url as NSURL, cost: cost)
        }
        return image
    }
}
