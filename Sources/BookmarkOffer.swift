import SwiftUI

/// Notices sites you keep coming back to (at least 6 visits a day, 3 days in a row) and offers,
/// once, to add them to your Favourites. The counts stay on this Mac and only cover the last
/// few days.
final class BookmarkOffer: ObservableObject {
    static let shared = BookmarkOffer()

    static let visitsPerDay = 6
    static let daysInARow = 3
    /// Moving around inside one site counts as one visit; coming back after this long counts again.
    private static let revisitGap: TimeInterval = 30 * 60
    private static let snooze: TimeInterval = 7 * 86_400

    /// The site Hush is offering to bookmark right now (e.g. "bbc.co.uk").
    @Published private(set) var site: String?

    private var counts: [String: [String: Int]]   // site → "2026-11-21" → visits
    private var dismissed: [String: Date]         // site → don't ask again until
    private var lastCounted: [String: Date] = [:]

    private static let countsKey = "frequentVisitCounts"
    private static let dismissedKey = "bookmarkOfferDismissed"

    private init() {
        counts = UserDefaults.standard.dictionary(forKey: Self.countsKey) as? [String: [String: Int]] ?? [:]
        let saved = UserDefaults.standard.dictionary(forKey: Self.dismissedKey) as? [String: Double] ?? [:]
        dismissed = saved.mapValues { Date(timeIntervalSince1970: $0) }
    }

    private var isEnabled: Bool {
        // Counting needs a few days of memory; skip it if history is cleared every day.
        Prefs.bool(Prefs.offerBookmarks) && HistoryRetention.current != .day
    }

    /// Called when a page finishes loading. `previousHost` is the site the tab showed before.
    func record(_ url: URL, previousHost: String?) {
        guard isEnabled, let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = url.host?.lowercased().strippingWWW, !host.isEmpty else { return }
        let now = Date()
        let arrived = previousHost?.lowercased().strippingWWW != host
        if !arrived, let last = lastCounted[host], now.timeIntervalSince(last) < Self.revisitGap { return }
        lastCounted[host] = now

        counts[host, default: [:]][Self.dayKey(now), default: 0] += 1
        prune()
        UserDefaults.standard.set(counts, forKey: Self.countsKey)

        if site == nil, qualifies(host), !isBookmarked(host), (dismissed[host] ?? .distantPast) < now {
            site = host
        }
    }

    func add(from tab: BrowserTab) {
        guard let site else { return }
        let scheme = tab.url?.scheme ?? "https"
        let realHost = tab.url?.host ?? site
        guard let home = URL(string: "\(scheme)://\(realHost)/") else { return }
        let title = HistoryStore.siteName(host: site, title: tab.url?.path == "/" ? tab.title : "")
        if !BookmarkStore.shared.contains(home) { BookmarkStore.shared.toggle(url: home, title: title) }
        finish(site, until: .distantFuture)
    }

    func notNow() {
        guard let site else { return }
        finish(site, until: Date().addingTimeInterval(Self.snooze))
    }

    func never() {
        guard let site else { return }
        finish(site, until: .distantFuture)
    }

    /// Forgets one site's counts (Forget This Site).
    func forget(site: String) {
        counts = counts.filter { Domains.site($0.key) != site }
        lastCounted = lastCounted.filter { Domains.site($0.key) != site }
        if let current = self.site, Domains.site(current) == site { self.site = nil }
        UserDefaults.standard.set(counts, forKey: Self.countsKey)
    }

    /// Forgets the counts (when history is cleared).
    func reset() {
        counts = [:]
        lastCounted = [:]
        site = nil
        UserDefaults.standard.removeObject(forKey: Self.countsKey)
    }

    // MARK: -

    private func finish(_ site: String, until: Date) {
        dismissed[site] = until
        counts[site] = nil
        UserDefaults.standard.set(counts, forKey: Self.countsKey)
        UserDefaults.standard.set(dismissed.mapValues { $0.timeIntervalSince1970 }, forKey: Self.dismissedKey)
        self.site = nil
    }

    private func qualifies(_ host: String) -> Bool {
        guard let days = counts[host] else { return false }
        return (0..<Self.daysInARow).allSatisfy { back in
            guard let day = Calendar.current.date(byAdding: .day, value: -back, to: Date()) else { return false }
            return days[Self.dayKey(day), default: 0] >= Self.visitsPerDay
        }
    }

    private func isBookmarked(_ host: String) -> Bool {
        BookmarkStore.shared.items.contains { $0.url.host?.lowercased().strippingWWW == host }
    }

    /// Keeps only the days that can still count.
    private func prune() {
        let keep = Set((0..<Self.daysInARow).compactMap {
            Calendar.current.date(byAdding: .day, value: -$0, to: Date()).map(Self.dayKey)
        })
        for (host, days) in counts {
            let recent = days.filter { keep.contains($0.key) }
            counts[host] = recent.isEmpty ? nil : recent
        }
        // Expired "not now" answers don't need keeping.
        dismissed = dismissed.filter { $0.value > Date() }
    }

    private static func dayKey(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}

/// A slim bar above the page: "You visit bbc.co.uk a lot. Add it to your Favourites?"
struct BookmarkOfferBar: View {
    @ObservedObject var tab: BrowserTab
    @ObservedObject private var offer = BookmarkOffer.shared

    var body: some View {
        if let site = offer.site, tab.url?.host?.lowercased().strippingWWW == site {
            VStack(spacing: 0) {
                Hairline()
                HStack(spacing: 12) {
                    IconTile(symbol: "star.fill",
                             colors: [Color(red: 1.0, green: 0.78, blue: 0.25), Color(red: 0.96, green: 0.55, blue: 0.12)], size: 30)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("You visit \(site) a lot")
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(1)
                        Text("Add it to your Favourites so it’s always one click away.")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 12)
                    Menu("Not Now") {
                        Button("Ask Me Again Next Week") { withAnimation { offer.notNow() } }
                        Button("Never for This Site") { withAnimation { offer.never() } }
                    } primaryAction: {
                        withAnimation { offer.notNow() }
                    }
                    .fixedSize()
                    // No Return shortcut: this bar sits over web pages, and pressing Return in any
                    // site's form would have added the favourite.
                    Button("Add to Favourites") { withAnimation { offer.add(from: tab) } }
                        .buttonStyle(.borderedProminent)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
            }
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}
