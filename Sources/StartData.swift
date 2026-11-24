import Foundation

// MARK: - Recently closed tabs

struct ClosedTab: Codable, Identifiable, Equatable {
    var id = UUID()
    var title: String
    var url: URL
    var closed: Date
}

/// The last tabs you closed, for the start page and History › Reopen Closed Tab.
final class RecentlyClosed: ObservableObject {
    static let shared = RecentlyClosed()
    private static let limit = 20

    @Published private(set) var tabs: [ClosedTab] = []
    private let file = AppPaths.support.appendingPathComponent("recently-closed.json")

    private init() {
        if let data = try? Data(contentsOf: file),
           let saved = try? JSONDecoder().decode([ClosedTab].self, from: data) {
            tabs = saved
        }
    }

    func add(title: String, url: URL) {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return }
        tabs.removeAll { $0.url == url }
        tabs.insert(ClosedTab(title: title.isEmpty ? (url.host ?? url.absoluteString) : title, url: url, closed: Date()), at: 0)
        if tabs.count > Self.limit { tabs.removeLast(tabs.count - Self.limit) }
        save()
    }

    /// Takes a tab off the list (when it's reopened).
    @discardableResult
    func take(_ tab: ClosedTab? = nil) -> ClosedTab? {
        guard let target = tab ?? tabs.first, let i = tabs.firstIndex(of: target) else { return nil }
        let taken = tabs.remove(at: i)
        save()
        return taken
    }

    func clear() {
        tabs = []
        save()
    }

    /// Drops a site's closed tabs (Forget This Site).
    func remove(site: String) {
        tabs.removeAll { Domains.site($0.url.host ?? "") == site }
        save()
    }

    private static let saveQueue = DispatchQueue(label: "hush.recently-closed.save", qos: .utility)

    private func save() {
        let snapshot = tabs, file = self.file
        Self.saveQueue.async {
            if let data = try? JSONEncoder().encode(snapshot) { try? data.write(to: file, options: .atomic) }
        }
    }
}

// MARK: - Privacy report

/// What Hush blocked over the last 30 days, kept on this Mac only: which tracking
/// companies tried to load on which sites, and how many sites you visited.
final class PrivacyReport: ObservableObject {
    static let shared = PrivacyReport()
    private static let days = 30

    private struct Day: Codable {
        var blocked = 0
        /// tracker domain → the sites it appeared on that day
        var trackers: [String: Set<String>] = [:]
        var visited: Set<String> = []
    }

    struct Summary {
        var blocked: Int
        var sitesVisited: Int
        var sitesWithTrackers: Int
        /// Trackers, most widespread first: (tracker, number of sites)
        var trackers: [(tracker: String, sites: Int)]

        var percentWithTrackers: Int {
            sitesVisited == 0 ? 0 : Int((Double(sitesWithTrackers) / Double(sitesVisited) * 100).rounded())
        }
    }

    @Published private(set) var summary = Summary(blocked: 0, sitesVisited: 0, sitesWithTrackers: 0, trackers: [])
    private var days: [String: Day] = [:]
    private let file = AppPaths.support.appendingPathComponent("privacy-report.json")
    private var saveWork: DispatchWorkItem?
    private var recomputeScheduled = false
    private let saveQueue = DispatchQueue(label: "hush.privacy-report.save", qos: .utility)
    private static let dayFormat: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private init() {
        if let data = try? Data(contentsOf: file), let saved = try? JSONDecoder().decode([String: Day].self, from: data) {
            days = saved
        }
        prune()
        recompute()
    }

    private var today: String { Self.dayFormat.string(from: Date()) }

    func recordVisit(site: String) {
        let site = Domains.site(site)
        guard !site.isEmpty, days[today, default: Day()].visited.insert(site).inserted else { return }
        changed()
    }

    func recordBlocked(tracker url: URL, on site: String?) {
        guard let host = url.host else { return }
        let tracker = Domains.site(host)
        let today = self.today
        var day = days[today, default: Day()]
        day.blocked += 1
        if let site, !site.isEmpty {
            let page = Domains.site(site)
            day.trackers[tracker, default: []].insert(page)
            day.visited.insert(page)
        } else {
            day.trackers[tracker, default: []] = day.trackers[tracker, default: []]
        }
        days[today] = day
        changed()
    }

    func reset() {
        days = [:]
        recompute()
        changed()
    }

    /// Removes one site from the report (Forget This Site): as a site you visited, and from
    /// the list of sites each tracker appeared on.
    func forget(site: String) {
        for key in days.keys {
            days[key]?.visited.remove(site)
            for tracker in days[key]?.trackers.keys.map({ $0 }) ?? [] {
                days[key]?.trackers[tracker]?.remove(site)
            }
        }
        changed()
    }

    /// Pages can block hundreds of requests as they load: add up the report at most twice a second.
    private func changed() {
        if !recomputeScheduled {
            recomputeScheduled = true
            // Recounting 30 days of trackers isn't free: done every couple of seconds at most.
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                self?.recomputeScheduled = false
                self?.recompute()
            }
        }
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.save() }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: work)
    }

    private func prune() {
        let cutoff = Self.dayFormat.string(from: Date().addingTimeInterval(-Double(Self.days) * 86_400))
        days = days.filter { $0.key > cutoff }
    }

    private func recompute() {
        var blocked = 0
        var visited = Set<String>()
        var withTrackers = Set<String>()
        var trackerSites: [String: Set<String>] = [:]
        for day in days.values {
            blocked += day.blocked
            visited.formUnion(day.visited)
            for (tracker, sites) in day.trackers {
                trackerSites[tracker, default: []].formUnion(sites)
                withTrackers.formUnion(sites)
            }
        }
        let ranked = trackerSites.map { (tracker: $0.key, sites: $0.value.count) }
            .sorted { $0.sites != $1.sites ? $0.sites > $1.sites : $0.tracker < $1.tracker }
        summary = Summary(blocked: blocked, sitesVisited: visited.count,
                          sitesWithTrackers: withTrackers.count, trackers: ranked)
    }

    func save(waiting: Bool = false) {
        saveWork?.cancel()
        prune()
        let snapshot = days, file = self.file
        let write = {
            if let data = try? JSONEncoder().encode(snapshot) { try? data.write(to: file, options: .atomic) }
        }
        if waiting { saveQueue.sync(execute: write) } else { saveQueue.async(execute: write) }
    }
}

/// Turns a host into the site it belongs to: "ads.eu.doubleclick.net" → "doubleclick.net",
/// "news.bbc.co.uk" → "bbc.co.uk".
enum Domains {
    private static let twoPartSuffixes: Set<String> = [
        "co.uk", "org.uk", "ac.uk", "gov.uk", "me.uk", "ltd.uk", "plc.uk", "net.uk", "sch.uk",
        "com.au", "net.au", "org.au", "edu.au", "gov.au", "co.nz", "org.nz", "co.jp", "ne.jp", "or.jp",
        "co.in", "co.za", "com.br", "com.mx", "com.ar", "com.tr", "com.cn", "com.hk", "com.sg", "com.tw",
        "co.kr", "co.id", "com.my", "com.ph", "co.il", "com.ua", "com.pl", "co.at", "com.es", "com.co",
    ]

    static func site(_ host: String) -> String {
        // IP addresses are whole sites: 192.168.1.1 used to become "1.1", lumping every local
        // device ending in .1.1 together (shared settings; Forget This Site forgot them all).
        let lower = host.lowercased()
        if lower.contains(":") || (!lower.isEmpty && lower.allSatisfy { $0.isNumber || $0 == "." }) { return lower }
        let parts = lower.strippingWWW.split(separator: ".").map(String.init)
        guard parts.count > 2 else { return parts.joined(separator: ".") }
        let lastTwo = parts.suffix(2).joined(separator: ".")
        if twoPartSuffixes.contains(lastTwo) { return parts.suffix(3).joined(separator: ".") }
        return lastTwo
    }
}

/// Adult websites, recognised by their address, so the start page (Recently Closed and
/// Suggestions) doesn't show them unless you choose to (Settings › Appearance › Start page).
enum AdultSites {
    private static let domains: Set<String> = [
        "pornhub.com", "xvideos.com", "xnxx.com", "xhamster.com", "redtube.com", "youporn.com", "tube8.com",
        "spankbang.com", "eporner.com", "txxx.com", "hqporner.com", "porn.com", "beeg.com", "tnaflix.com",
        "chaturbate.com", "stripchat.com", "livejasmin.com", "cam4.com", "camsoda.com", "bongacams.com", "myfreecams.com",
        "onlyfans.com", "fansly.com", "manyvids.com", "clips4sale.com", "brazzers.com", "realitykings.com", "bangbros.com",
        "nhentai.net", "e-hentai.org", "exhentai.org", "hanime.tv", "rule34.xxx", "rule34.paheal.net", "gelbooru.com",
        "motherless.com", "heavy-r.com", "efukt.com", "literotica.com", "adultfriendfinder.com", "fapello.com", "erome.com",
    ]
    private static let words = ["porn", "xxx", "hentai", "nsfw", "camgirl", "sexcam", "xvideo", "xhamster", "fetish", "milf", "nude"]

    static func isAdult(_ url: URL?) -> Bool {
        guard let host = url?.host?.lowercased() else { return false }
        if host.hasSuffix(".xxx") || host.hasSuffix(".porn") || host.hasSuffix(".adult") || host.hasSuffix(".sex") { return true }
        if domains.contains(Domains.site(host)) { return true }
        return words.contains { host.contains($0) }
    }

    static var showOnStartPage: Bool { Prefs.bool(Prefs.startShowAdult) }
}
