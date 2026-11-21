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
            let remote = Prefs.bool(Prefs.searchSuggestions) ? await Self.fetchSuggestions(q) : []
            guard !Task.isCancelled else { return }
            guard let self, self.query == q, self.active else { return }
            let localTexts = Set(local.map { $0.text.lowercased() })
            let searches = remote
                .filter { !localTexts.contains($0.lowercased()) }
                .prefix(max(3, 8 - local.count))
                .map { Suggestion(kind: .search, title: $0, text: $0) }
            self.items = local + searches
        }
    }

    private func localItems(for q: String) -> [Suggestion] {
        var result: [Suggestion] = []
        if URLResolver.looksLikeAddress(q) {
            result.append(Suggestion(kind: .website, title: q, detail: "Go to website", text: q))
        }
        let lower = q.lowercased()
        let marks = BookmarkStore.shared.items.filter {
            $0.title.lowercased().contains(lower) || $0.url.absoluteString.lowercased().contains(lower)
        }
        for mark in marks.prefix(3) {
            result.append(Suggestion(kind: .bookmark, title: mark.title,
                                     detail: mark.url.host?.strippingWWW, text: mark.url.absoluteString))
        }
        // Pages you've visited before, best match first.
        let taken = Set(result.map { $0.text })
        for entry in HistoryStore.shared.search(q, limit: 6) where !taken.contains(entry.url.absoluteString) {
            guard result.count < 5 else { break }
            result.append(Suggestion(kind: .history, title: entry.title.isEmpty ? (entry.url.host ?? "") : entry.title,
                                     detail: entry.url.host?.strippingWWW, text: entry.url.absoluteString))
        }
        return result
    }

    /// The chosen search engine's public suggestion endpoint.
    private static func fetchSuggestions(_ q: String) async -> [String] {
        guard let url = SearchEngine.current.suggestionURL(q) else { return [] }
        var request = URLRequest(url: url)
        request.timeoutInterval = 3
        guard let (data, _) = try? await URLSession.shared.data(for: request),
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
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08))
        )
        .shadow(color: .black.opacity(0.18), radius: 20, y: 10)
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
                .frame(width: 18)
            highlighted
                .lineLimit(1)
            if let detail = item.detail {
                Text("— \(detail)")
                    .foregroundStyle(isSelected ? Color.white.opacity(0.75) : Color.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if isSelected {
                Image(systemName: "return")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.8))
            }
        }
        .font(.system(size: 13))
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(isSelected ? Color.accentColor : Color.primary.opacity(hovering ? 0.06 : 0))
        )
        .foregroundStyle(isSelected ? Color.white : Color.primary)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
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
