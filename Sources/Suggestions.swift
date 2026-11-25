import SwiftUI

struct Suggestion: Identifiable, Equatable {
    enum Kind { case search, website, bookmark, history }
    let id = UUID()
    let kind: Kind
    /// Shown in the list.
    let title: String
    /// Shown greyed after the title (bookmark address).
    var detail: String? = nil
    /// What goes into the address bar when chosen.
    let text: String
}

/// Live suggestions under the address bar: matching bookmarks plus Google's
/// suggestions, refreshed as you type.
final class SuggestionsModel: ObservableObject {
    @Published private(set) var items: [Suggestion] = []
    @Published private(set) var selectedIndex: Int?
    @Published private(set) var query = ""
    private var active = false
    private var task: Task<Void, Never>?
    /// The window these suggestions belong to: its Orbit's profile decides whose bookmarks and
    /// history are suggested.
    weak var browser: BrowserModel?

    var isVisible: Bool { active && !items.isEmpty }
    var selected: Suggestion? { selectedIndex.flatMap { items.indices.contains($0) ? items[$0] : nil } }

    func activate() {
        active = true
        items = []
        selectedIndex = nil
    }

    func dismiss() {
        task?.cancel()
        active = false
        items = []
        selectedIndex = nil
    }

    func move(by delta: Int) {
        guard !items.isEmpty else { return }
        // Cycles through: nothing selected → first … last → nothing selected.
        let current = selectedIndex ?? -1
        var next = current + delta
        if next < -1 { next = items.count - 1 }
        if next >= items.count { next = -1 }
        selectedIndex = next == -1 ? nil : next
    }

    func update(query raw: String) {
        active = true
        let q = raw.trimmingCharacters(in: .whitespaces)
        query = q
        task?.cancel()
        selectedIndex = nil
        guard !q.isEmpty else { items = []; return }

        let local = localItems(for: q)
        items = local + items.filter { $0.kind == .search && $0.title.lowercased().hasPrefix(q.lowercased()) }

        task = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 90_000_000) // wait for a pause in typing
            guard !Task.isCancelled else { return }
            // Addresses and pasted links (which can carry private tokens) never go to the search engine.
            let isAddress = URLResolver.looksLikeAddress(q) || q.contains("://") || q.lowercased().hasPrefix("file:")
            let remote = Prefs.bool(Prefs.searchSuggestions) && !isAddress ? await Self.fetchSuggestions(q) : []
            guard !Task.isCancelled else { return }
            guard let self, self.query == q, self.active else { return }
            let localTexts = Set(local.map { $0.text.lowercased() })
            let searches = remote
                .filter { !localTexts.contains($0.lowercased()) }
                .prefix(max(3, 8 - local.count))
                .map { Suggestion(kind: .search, title: $0, text: $0) }
            // Keep the highlight on the suggestion you picked (its position may have changed);
            // otherwise Return could open a different one.
            let picked = self.selected?.text
            self.items = local + searches
            self.selectedIndex = picked.flatMap { text in self.items.firstIndex { $0.text == text } }
        }
    }

    private func localItems(for q: String) -> [Suggestion] {
        var result: [Suggestion] = []
        if URLResolver.looksLikeAddress(q) {
            result.append(Suggestion(kind: .website, title: q, detail: "Go to website", text: q))
        }
        let lower = q.lowercased()
        // The same page counts once, however it was written (www, trailing slash, http/https).
        var seen = Set<String>()
        func key(_ url: URL) -> String {
            (url.host?.lowercased().strippingWWW ?? "") + url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + (url.query ?? "")
        }
        let marks = (browser?.bookmarks ?? .shared).items.filter {
            $0.title.lowercased().contains(lower) || $0.url.absoluteString.lowercased().contains(lower)
        }
        for mark in marks.prefix(3) where seen.insert(key(mark.url)).inserted {
            result.append(Suggestion(kind: .bookmark, title: mark.title,
                                     detail: mark.url.host?.strippingWWW, text: mark.url.absoluteString))
        }
        // Pages you've visited before, best match first.
        let taken = Set(result.map { $0.text })
        for entry in (browser?.history ?? .shared).search(q, limit: 8) where !taken.contains(entry.url.absoluteString) && seen.insert(key(entry.url)).inserted {
            guard result.count < 5 else { break }
            result.append(Suggestion(kind: .history, title: entry.title.isEmpty ? (entry.url.host ?? "") : entry.title,
                                     detail: entry.url.host?.strippingWWW, text: entry.url.absoluteString))
        }
        return result
    }

    /// Suggestions go without cookies or a cache, so the search engine can't tie your typing to you.
    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        config.urlCache = nil
        return URLSession(configuration: config)
    }()

    /// The chosen search engine's public suggestion endpoint.
    private static func fetchSuggestions(_ q: String) async -> [String] {
        guard let url = SearchEngine.current.suggestionURL(q) else { return [] }
        var request = URLRequest(url: url)
        request.timeoutInterval = 3
        guard let (data, _) = try? await session.data(for: request),
              let json = try? JSONSerialization.jsonObject(with: data) as? [Any],
              json.count > 1, let list = json[1] as? [String] else { return [] }
        return list
    }
}

/// The floating panel of suggestions under the address bar.
struct SuggestionList: View {
    @ObservedObject var suggestions: SuggestionsModel
    let onChoose: (Suggestion) -> Void

    var body: some View {
        VStack(spacing: 2) {
            ForEach(Array(suggestions.items.enumerated()), id: \.element.id) { index, item in
                SuggestionRow(item: item, query: suggestions.query,
                              isSelected: index == suggestions.selectedIndex)
                    .onTapGesture { onChoose(item) }
            }
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.regularMaterial)
        )
        // The page underneath mustn't get clicks, scrolling or hover through the list.
        .background(ClickBlocker())
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.1))
        )
        .shadow(color: .black.opacity(0.22), radius: 24, y: 12)
    }
}

private struct SuggestionRow: View {
    let item: Suggestion
    let query: String
    let isSelected: Bool
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            icon
                .frame(width: 22, height: 22)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isSelected ? Color.white.opacity(0.18) : Color.primary.opacity(0.06)))
            highlighted
                .lineLimit(1)
                .layoutPriority(1)
            if let detail = item.detail {
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(isSelected ? Color.white.opacity(0.75) : Color.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if let badge {
                Image(systemName: badge)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.white.opacity(0.8) : Color.secondary.opacity(0.7))
                    .help(item.kind == .bookmark ? "Bookmark" : "From your history")
            }
            if isSelected {
                Image(systemName: "return")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.8))
            }
        }
        .font(.system(size: 13))
        .padding(.horizontal, 8)
        .frame(height: 34)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(isSelected ? Color.accentColor : Color.primary.opacity(hovering ? 0.06 : 0))
        )
        .foregroundStyle(isSelected ? Color.white : Color.primary)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }

    private var badge: String? {
        switch item.kind {
        case .bookmark: return "star.fill"
        case .history: return "clock"
        default: return nil
        }
    }

    @ViewBuilder private var icon: some View {
        switch item.kind {
        case .search:
            Image(systemName: "magnifyingglass")
                .foregroundStyle(isSelected ? Color.white : Color.secondary)
        case .website:
            Image(systemName: "globe")
                .foregroundStyle(isSelected ? Color.white : Color.secondary)
        case .bookmark, .history:
            Favicon(url: URL(string: item.text), size: 16)
        }
    }

    /// The part you typed in normal weight, Google's completion in bold — like a search box.
    private var highlighted: Text {
        let title = item.title
        guard item.kind == .search, title.lowercased().hasPrefix(query.lowercased()), !query.isEmpty else {
            return Text(title)
        }
        let typed = String(title.prefix(query.count))
        let rest = String(title.dropFirst(query.count))
        return Text(typed) + Text(rest).fontWeight(.semibold)
    }
}
