import Foundation
import SQLite3

struct HistoryEntry: Codable, Identifiable {
    var url: URL
    var title: String
    var visits: Int
    var lastVisit: Date
    var id: String { url.absoluteString }

    /// Visits weighted by how recent they are (“frecency”).
    var score: Double {
        let age = Date().timeIntervalSince(lastVisit) / 86_400
        let weight: Double = age < 4 ? 1 : age < 14 ? 0.7 : age < 31 ? 0.5 : age < 90 ? 0.3 : 0.1
        return Double(visits) * weight
    }
}

/// A site, for the start page's Frequently Visited.
struct FrequentSite: Identifiable {
    var host: String
    var title: String
    var url: URL
    var score: Double
    var lastVisit: Date
    var id: String { host }
}

/// Browsing history, kept on this Mac only
/// (~/Library/Application Support/Hush Browser/history.json).
final class HistoryStore: ObservableObject {
    static let shared = HistoryStore()
    private static let maxEntries = 10_000

    @Published private(set) var entries: [String: HistoryEntry] = [:] {
        didSet { frequentCache = nil }
    }
    /// The start page asks for frequent sites on every redraw; work them out once per change.
    private var frequentCache: (key: String, sites: [FrequentSite])?
    /// Saves run one at a time, in order, so an older snapshot never overwrites a newer one.
    private let saveQueue = DispatchQueue(label: "hush.history.save", qos: .utility)
    @Published private(set) var hiddenHosts: Set<String> = []
    private let file: URL
    private var saveWork: DispatchWorkItem?

    private init() {
        let folder = AppPaths.support
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        file = folder.appendingPathComponent("history.json")
        if let data = try? Data(contentsOf: file),
           let saved = try? JSONDecoder().decode([HistoryEntry].self, from: data) {
            entries = Dictionary(saved.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        }
        hiddenHosts = Set(UserDefaults.standard.stringArray(forKey: "hiddenFrequentHosts") ?? [])
        prune()
    }

    private static func key(_ url: URL) -> URL? {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        components.fragment = nil
        return components.url
    }

    func record(_ url: URL, title: String) {
        guard let url = Self.key(url) else { return }
        var entry = entries[url.absoluteString] ?? HistoryEntry(url: url, title: title, visits: 0, lastVisit: Date())
        entry.visits += 1
        entry.lastVisit = Date()
        if !title.isEmpty { entry.title = title }
        entries[url.absoluteString] = entry
        scheduleSave()
    }

    func updateTitle(_ url: URL, title: String) {
        guard !title.isEmpty, let url = Self.key(url), entries[url.absoluteString] != nil,
              entries[url.absoluteString]?.title != title else { return }
        entries[url.absoluteString]?.title = title
        scheduleSave()
    }

    /// The sites you visit most, one tile per site.
    func frequentSites(limit: Int = 8, excluding: Set<String> = []) -> [FrequentSite] {
        let key = "\(limit)|\(hiddenHosts.sorted().joined(separator: ","))|\(excluding.sorted().joined(separator: ","))"
        if let cache = frequentCache, cache.key == key { return cache.sites }
        let sites = computeFrequentSites(limit: limit, excluding: excluding)
        frequentCache = (key, sites)
        return sites
    }

    private func computeFrequentSites(limit: Int, excluding: Set<String>) -> [FrequentSite] {
        var bySite: [String: (score: Double, best: HistoryEntry, last: Date)] = [:]
        for entry in entries.values {
            guard let host = entry.url.host?.lowercased().strippingWWW, !hiddenHosts.contains(host),
                  !excluding.contains(host) else { continue }
            let current = bySite[host]
            let score = (current?.score ?? 0) + entry.score
            let best = current.map { $0.best.visits >= entry.visits ? $0.best : entry } ?? entry
            bySite[host] = (score, best, max(current?.last ?? .distantPast, entry.lastVisit))
        }
        return bySite
            .sorted { $0.value.score > $1.value.score }
            .prefix(limit)
            .map { host, value in
                let scheme = value.best.url.scheme ?? "https"
                let home = URL(string: "\(scheme)://\(value.best.url.host ?? host)/") ?? value.best.url
                return FrequentSite(host: host, title: Self.siteName(host: host, title: value.best.title),
                                    url: home, score: value.score, lastVisit: value.last)
            }
    }

    /// History entries matching what's typed in the address bar, best first.
    func search(_ query: String, limit: Int) -> [HistoryEntry] {
        let q = query.lowercased()
        guard q.count >= 2 else { return [] }
        return entries.values
            .filter { $0.title.lowercased().contains(q) || $0.url.absoluteString.lowercased().contains(q) }
            .sorted { $0.score > $1.score }
            .prefix(limit)
            .map { $0 }
    }

    /// Removes one page from history.
    func remove(_ entry: HistoryEntry) {
        entries[entry.id] = nil
        scheduleSave()
    }

    /// Removes every page from a site (Forget This Site).
    func remove(site: String) {
        let site = Domains.site(site)
        entries = entries.filter { Domains.site($0.value.url.host ?? "") != site }
        scheduleSave()
    }

    func hideFromStartPage(_ host: String) {
        hiddenHosts.insert(host)
        UserDefaults.standard.set(Array(hiddenHosts), forKey: "hiddenFrequentHosts")
    }

    func clear() {
        BookmarkOffer.shared.reset()
        DispatchQueue.global(qos: .utility).async { FaviconCache.clearDisk() }
        entries = [:]
        hiddenHosts = []
        UserDefaults.standard.removeObject(forKey: "hiddenFrequentHosts")
        save()
    }

    /// Removes entries older than the chosen limit (Settings › General).
    func prune() {
        guard let maxAge = HistoryRetention.current.maxAge else { return }
        let cutoff = Date().addingTimeInterval(-maxAge)
        let before = entries.count
        entries = entries.filter { $0.value.lastVisit >= cutoff }
        if entries.count != before { scheduleSave() }
    }

    func add(imported: [HistoryEntry]) -> Int {
        var added = 0
        for item in imported {
            guard let url = Self.key(item.url) else { continue }
            var entry = entries[url.absoluteString] ?? HistoryEntry(url: url, title: item.title, visits: 0, lastVisit: item.lastVisit)
            entry.visits += item.visits
            entry.lastVisit = max(entry.lastVisit, item.lastVisit)
            if entry.title.isEmpty { entry.title = item.title }
            entries[url.absoluteString] = entry
            added += 1
        }
        scheduleSave()
        return added
    }

    private func scheduleSave() {
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.save() }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: work)
    }

    /// Writes history to disk. `waiting` blocks until it's written (used when Hush quits).
    func save(waiting: Bool = false) {
        saveWork?.cancel()
        var list = Array(entries.values)
        if list.count > Self.maxEntries {
            list = Array(list.sorted { $0.score > $1.score }.prefix(Self.maxEntries))
        }
        let snapshot = list
        let file = self.file
        let write = {
            if let data = try? JSONEncoder().encode(snapshot) {
                try? data.write(to: file, options: .atomic)
            }
        }
        if waiting { saveQueue.sync(execute: write) } else { saveQueue.async(execute: write) }
    }

    /// "GitHub: Let’s build from here" → "GitHub"; falls back to a tidy host name.
    static func siteName(host: String, title: String) -> String {
        let separators = [" | ", " - ", " — ", " – ", ": ", " · "]
        // The site's own name: "bbc" for news.bbc.co.uk, "github" for github.com.
        let base = Domains.site(host).split(separator: ".").first.map { String($0).lowercased() } ?? host
        for sep in separators where title.contains(sep) {
            let parts = title.components(separatedBy: sep).map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { (2...24).contains($0.count) }
            // Prefer the part that names the site ("Home - BBC News" → "BBC News" on bbc.co.uk).
            if let named = parts.first(where: { $0.lowercased().replacingOccurrences(of: " ", with: "").contains(base) }) {
                return named
            }
            if let short = parts.min(by: { $0.count < $1.count }) { return short }
        }
        if (2...24).contains(title.count) { return title }
        // "News, sport and opinion from the Guardian" on theguardian.com → "The Guardian".
        let words = title.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        for size in 1...3 where words.count >= size {
            for start in 0...(words.count - size) {
                let run = words[start..<(start + size)]
                if run.joined().lowercased() == base {
                    let name = run.joined(separator: " ")
                    return name.prefix(1).uppercased() + name.dropFirst()
                }
            }
        }
        return base.prefix(1).uppercased() + base.dropFirst()
    }
}

// MARK: - Importing from other browsers

/// Brings your most-visited sites over from other browsers on this Mac.
/// Only runs when you ask it to, and only reads addresses, titles and visit counts.
enum BrowserImporter {
    enum Kind { case chromium, firefox, safari }

    struct Source: Identifiable {
        let name: String
        let kind: Kind
        let database: URL
        let appPath: String
        var id: String { name }
    }

    static func available() -> [Source] {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let home = FileManager.default.homeDirectoryForCurrentUser
        var sources: [Source] = [
            Source(name: "Safari", kind: .safari, database: home.appendingPathComponent("Library/Safari/History.db"),
                   appPath: "/Applications/Safari.app"),
        ]
        let chromium: [(String, String, String)] = [
            ("Google Chrome", "Google/Chrome/Default/History", "/Applications/Google Chrome.app"),
            ("Brave", "BraveSoftware/Brave-Browser/Default/History", "/Applications/Brave Browser.app"),
            ("Microsoft Edge", "Microsoft Edge/Default/History", "/Applications/Microsoft Edge.app"),
            ("Arc", "Arc/User Data/Default/History", "/Applications/Arc.app"),
            ("Vivaldi", "Vivaldi/Default/History", "/Applications/Vivaldi.app"),
        ]
        for (name, path, app) in chromium {
            sources.append(Source(name: name, kind: .chromium, database: support.appendingPathComponent(path), appPath: app))
        }
        let profiles = support.appendingPathComponent("Firefox/Profiles")
        if let dirs = try? FileManager.default.contentsOfDirectory(at: profiles, includingPropertiesForKeys: nil) {
            let places = dirs.map { $0.appendingPathComponent("places.sqlite") }
                .filter { FileManager.default.fileExists(atPath: $0.path) }
                .max { size(of: $0) < size(of: $1) }
            if let places {
                sources.append(Source(name: "Firefox", kind: .firefox, database: places, appPath: "/Applications/Firefox.app"))
            }
        }
        return sources.filter { FileManager.default.fileExists(atPath: $0.database.path) || $0.kind == .safari && FileManager.default.fileExists(atPath: $0.appPath) }
    }

    private static func size(of url: URL) -> Int {
        (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
    }

    enum ImportError: LocalizedError {
        case needsFullDiskAccess
        case unreadable

        var errorDescription: String? {
            switch self {
            case .needsFullDiskAccess:
                return "macOS protects Safari’s history. Give Hush Full Disk Access in System Settings › Privacy & Security, then try again."
            case .unreadable:
                return "That browser’s history couldn’t be read."
            }
        }
    }

    /// Imports up to 300 of the most-visited pages. Returns how many were added.
    static func importTopSites(from source: Source) throws -> Int {
        // Work on a copy: the browser may have its database open.
        let copy = FileManager.default.temporaryDirectory.appendingPathComponent("hush-import-\(UUID().uuidString).db")
        do {
            try FileManager.default.copyItem(at: source.database, to: copy)
            // Recent visits may still be in the write-ahead log beside the database.
            for suffix in ["-wal", "-shm"] {
                let extra = URL(fileURLWithPath: source.database.path + suffix)
                if FileManager.default.fileExists(atPath: extra.path) {
                    try? FileManager.default.copyItem(at: extra, to: URL(fileURLWithPath: copy.path + suffix))
                }
            }
        } catch {
            throw source.kind == .safari ? ImportError.needsFullDiskAccess : ImportError.unreadable
        }
        defer {
            for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: copy.path + suffix) }
        }

        var db: OpaquePointer?
        guard sqlite3_open_v2(copy.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            sqlite3_close(db)
            throw ImportError.unreadable
        }
        defer { sqlite3_close(db) }

        let sql: String
        let toDate: (Double) -> Date
        switch source.kind {
        case .chromium:
            sql = "SELECT url, title, visit_count, last_visit_time FROM urls WHERE hidden = 0 ORDER BY visit_count DESC LIMIT 300"
            toDate = { Date(timeIntervalSince1970: $0 / 1_000_000 - 11_644_473_600) } // microseconds since 1601
        case .firefox:
            sql = "SELECT url, title, visit_count, last_visit_date FROM moz_places WHERE visit_count > 0 AND hidden = 0 ORDER BY visit_count DESC LIMIT 300"
            toDate = { Date(timeIntervalSince1970: $0 / 1_000_000) }
        case .safari:
            sql = """
            SELECT i.url, (SELECT v.title FROM history_visits v WHERE v.history_item = i.id ORDER BY v.visit_time DESC LIMIT 1),
                   i.visit_count, (SELECT MAX(v.visit_time) FROM history_visits v WHERE v.history_item = i.id)
            FROM history_items i ORDER BY i.visit_count DESC LIMIT 300
            """
            toDate = { Date(timeIntervalSinceReferenceDate: $0) }
        }

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { throw ImportError.unreadable }
        defer { sqlite3_finalize(statement) }

        var imported: [HistoryEntry] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let rawURL = sqlite3_column_text(statement, 0),
                  let url = URL(string: String(cString: rawURL)),
                  let scheme = url.scheme, scheme.hasPrefix("http") else { continue }
            let title = sqlite3_column_text(statement, 1).map { String(cString: $0) } ?? ""
            let visits = Int(sqlite3_column_int64(statement, 2))
            let last = sqlite3_column_double(statement, 3)
            imported.append(HistoryEntry(url: url, title: title, visits: max(1, visits),
                                         lastVisit: last > 0 ? min(toDate(last), Date()) : Date()))
        }
        return DispatchQueue.main.sync { HistoryStore.shared.add(imported: imported) }
    }
}
