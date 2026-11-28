import Foundation
import Network
import WebKit

// Project Skywalker: the web at your fingertips, so fast it feels instant.

/// The servers a site's pages fetch their files from (pictures, scripts, video) get their
/// connections opened the moment you head to the site, alongside the page itself, instead of one
/// by one as the page asks for them. Facebook, X and Reddit are known from the start; any other
/// site is learned on your first visit (the outside servers its page used in its first seconds).
/// A connection is a look-up and a secure handshake: nothing is downloaded, and never to an ad or
/// tracking server.
enum OriginWarmup {
    static let enabled = Speed.enabled && ProcessInfo.processInfo.environment["UFOLIO_ORIGINS_OFF"] == nil

    /// Known from the start: the servers these sites' pages always use.
    private static let known: [String: [String]] = [
        "facebook.com": ["https://static.xx.fbcdn.net", "https://scontent.xx.fbcdn.net", "https://video.xx.fbcdn.net"],
        "x.com": ["https://abs.twimg.com", "https://api.x.com", "https://pbs.twimg.com", "https://video.twimg.com"],
        "twitter.com": ["https://abs.twimg.com", "https://api.x.com", "https://pbs.twimg.com", "https://video.twimg.com"],
        "reddit.com": ["https://www.redditstatic.com", "https://styles.redditmedia.com", "https://preview.redd.it",
                       "https://i.redd.it", "https://external-preview.redd.it", "https://v.redd.it"],
    ]
    private static let storeKey = "skywalker.origins"
    private static let maxSites = 300
    private static let perSite = 6
    /// Learned per site, newest last (the oldest go first past the limit).
    private static var learned: [String: [String]] = (UserDefaults.standard.dictionary(forKey: storeKey) as? [String: [String]] ?? [:])
        .reduce(into: [:]) { kept, entry in
            let ok = entry.value.filter { URL(string: $0)?.host.map { isContentServer($0, on: entry.key) } ?? false }
            if !ok.isEmpty { kept[entry.key] = ok }
        }
    private static var order: [String] = Array(learned.keys)
    /// Sites already looked at since launch: each is learned (or refreshed) once per run at most.
    private static var checked: Set<String> = []
    private static var saveWork: DispatchWorkItem?

    /// Opens the connections a page on this site is about to need, through this web view (its
    /// profile, or a Stealth window's own). Stealth windows use only the built-in list.
    static func warm(_ url: URL?, in webView: WKWebView?, privately: Bool = false) {
        guard enabled, let host = url?.host, let webView else { return }
        let site = Domains.site(host)
        var origins = known[site] ?? []
        if !privately { origins += (learned[site] ?? []).filter { !origins.contains($0) } }
        for origin in origins.prefix(8) { Speed.preconnect(URL(string: origin), in: webView, related: false) }
    }

    /// After a page has loaded: notes the outside servers it used in its first few seconds.
    @MainActor static func learn(from webView: WKWebView, url: URL) {
        guard enabled, let host = url.host, url.scheme == "https" else { return }
        let site = Domains.site(host)
        guard !site.isEmpty, known[site] == nil, checked.insert(site).inserted else { return }
        // In Ufolio's own script world: the page can't see or change this.
        let script = """
        const here = location.origin, seen = new Map();
        for (const e of performance.getEntriesByType('resource')) {
          if (e.startTime > 4000) continue;
          let o; try { o = new URL(e.name).origin; } catch (_) { continue; }
          if (o === here || !o.startsWith('https://')) continue;
          const s = seen.get(o) || [0, e.startTime]; s[0] += 1; seen.set(o, s);
        }
        return [...seen.entries()].filter(x => x[1][0] >= 2)
          .sort((a, b) => b[1][0] - a[1][0] || a[1][1] - b[1][1]).slice(0, 12).map(x => x[0]);
        """
        Task { @MainActor in
            guard let found = (try? await webView.callAsyncJavaScript(script, contentWorld: .defaultClient)) as? [String] else { return }
            let keep = found.filter { URL(string: $0)?.host.map { isContentServer($0, on: site) } ?? false }
            remember(site, Array(keep.prefix(perSite)))
        }
    }

    /// Only servers that deliver the page's own pictures, scripts and video: never one that's
    /// blocked, a known tracking company's, or named like an ad, analytics or consent server
    /// (some get past the blocker, and a connection made ahead would tell them you're coming).
    /// Servers used for a single request (a tracking ping, typically) were already left out.
    static func isContentServer(_ host: String, on page: String) -> Bool {
        let host = host.lowercased()
        if BuiltInRules.isBlocked(host) || TorrentTools.isAdNetwork(host) { return false }
        let site = Domains.site(host)
        if TrackerCompanies.owner(of: site) != site { return false }
        // The big search and social sites on someone else's page are there for ads, sign-in
        // buttons or tracking, not the page's own content.
        if site != page, bigWatchers.contains(site) { return false }
        if adWords.contains(where: { host.contains($0) }) { return false }
        return host.split(whereSeparator: { $0 == "." || $0 == "-" }).allSatisfy { !adLabels.contains(String($0)) }
    }
    private static let bigWatchers: Set<String> = ["google.com", "facebook.com", "facebook.net", "x.com", "twitter.com",
        "linkedin.com", "tiktok.com", "instagram.com", "pinterest.com", "amazon.com", "microsoft.com", "bing.com", "yahoo.com"]
    private static let adLabels: Set<String> = ["ad", "ads", "adserver", "adservice", "adsystem", "metrics", "smetrics", "securemetrics",
        "analytics", "stats", "stat", "track", "tracker", "tracking", "pixel", "beacon", "telemetry", "tag", "tags",
        "collect", "collector", "log", "logs", "logging", "consent", "cmp", "privacy", "survey", "insights"]
    private static let adWords = ["doubleclick", "googletag", "googlesyndication", "adnxs", "cookielaw", "onetrust", "btloader",
        "concert.io", "ad-delivery", "adsafe", "taboola", "outbrain", "criteo", "quantserve", "scorecardresearch", "hotjar", "segment."]

    private static func remember(_ site: String, _ origins: [String]) {
        if origins.isEmpty { if learned.removeValue(forKey: site) != nil { order.removeAll { $0 == site }; saveSoon() }; return }
        guard learned[site] != origins else { return }
        learned[site] = origins
        order.removeAll { $0 == site }
        order.append(site)
        while order.count > maxSites { learned[order.removeFirst()] = nil }
        saveSoon()
    }

    /// Clear History and Forget This Site take these notes too (they show which sites you visit).
    static func forgetAll() { learned = [:]; order = []; checked = []; saveSoon() }
    static func forget(site: String) {
        guard learned.removeValue(forKey: site) != nil else { return }
        order.removeAll { $0 == site }
        saveSoon()
    }

    private static func saveSoon() {
        saveWork?.cancel()
        let work = DispatchWorkItem { UserDefaults.standard.set(learned, forKey: storeKey) }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: work)
    }
}

/// The site you usually open first is loading before you click it: on a fast connection, the
/// first start page after launch loads that site in the background (the one you opened first
/// last time, or your first favourite). One page at most, let go after a minute if you don't
/// open it. Not on a metered or Low Data connection, in Low Power Mode, or with Instant pages off.
enum LaunchWarmup {
    private static let key = "skywalker.firstSite"
    private static var noted = false
    private static var started = false
    private static let off = ProcessInfo.processInfo.environment["UFOLIO_WARMUP_OFF"] != nil

    /// The first page opened from a bookmark or favourite since launch.
    static func noteOpen(_ url: URL, privately: Bool) {
        guard !noted, !privately, ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return }
        noted = true
        UserDefaults.standard.set(url.absoluteString, forKey: key)
    }

    /// The first start page since launch: load the likely first site, if the connection is fast.
    static func startIfFast(in model: BrowserModel) {
        guard !started, !off, !model.isPrivate, Preloader.enabled, !ProcessInfo.processInfo.isLowPowerModeEnabled else { return }
        started = true
        let favourites = model.bookmarks.items(in: nil).map(\.url)
        // Last time's first pick, while it's still one of your bookmarks; otherwise your first favourite.
        let last = UserDefaults.standard.string(forKey: key).flatMap(URL.init(string:))
        guard let target = last.flatMap({ url in model.bookmarks.contains(url) ? url : nil }) ?? favourites.first else { return }
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak model] path in
            monitor.cancel()
            guard path.status == .satisfied, !path.isExpensive, !path.isConstrained else { return }
            DispatchQueue.main.async {
                // Still on the start page: a click elsewhere already went somewhere.
                guard let model, let tab = model.selectedTab, tab.url == nil, !noted else { return }
                Preloader.preload(target, for: tab, lifetime: 60)
            }
        }
        monitor.start(queue: .global(qos: .utility))
    }
}
