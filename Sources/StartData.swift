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

    private func save() {
        let snapshot = tabs, file = self.file
        DispatchQueue.global(qos: .utility).async {
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
        changed()
    }

    private func changed() {
        recompute()
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

    func save() {
        prune()
        let snapshot = days, file = self.file
        DispatchQueue.global(qos: .utility).async {
            if let data = try? JSONEncoder().encode(snapshot) { try? data.write(to: file, options: .atomic) }
        }
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
        let parts = host.lowercased().strippingWWW.split(separator: ".").map(String.init)
        guard parts.count > 2 else { return parts.joined(separator: ".") }
        let lastTwo = parts.suffix(2).joined(separator: ".")
        if twoPartSuffixes.contains(lastTwo) { return parts.suffix(3).joined(separator: ".") }
        return lastTwo
    }
}
