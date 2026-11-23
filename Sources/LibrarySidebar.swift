import SwiftUI

/// The sidebar (⇧⌘L): your bookmarks and your history, searchable, beside the page.
struct LibrarySidebar: View {
    enum Section: String, CaseIterable, Identifiable {
        case bookmarks, history
        var id: String { rawValue }
        var title: String { self == .bookmarks ? "Bookmarks" : "History" }
        var symbol: String { self == .bookmarks ? "star.fill" : "clock.fill" }
    }

    @ObservedObject var model: BrowserModel
    var active = true
    @AppStorage("sidebar.section") private var sectionName = Section.bookmarks.rawValue
    @State private var query = ""

    private var section: Section { Section(rawValue: sectionName) ?? .bookmarks }

    var body: some View {
        VStack(spacing: 0) {
            header
            switch section {
            case .bookmarks: BookmarksList(model: model, query: query)
            case .history: HistoryList(model: model, query: query)
            }
        }
        .frame(width: 280)
        .background { if active { VisualEffect(material: .sidebar) } }
    }

    private var header: some View {
        VStack(spacing: 10) {
            HStack(spacing: 4) {
                ForEach(Section.allCases) { option in
                    let selected = option == section
                    Button {
                        withAnimation(.easeOut(duration: 0.15)) { sectionName = option.rawValue }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: option.symbol).font(.system(size: 10.5, weight: .semibold))
                            Text(option.title).font(.system(size: 12, weight: selected ? .semibold : .medium))
                        }
                        .foregroundStyle(selected ? Color.primary : Color.secondary)
                        .frame(maxWidth: .infinity).frame(height: 28)
                        .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(selected ? Color(nsColor: .controlBackgroundColor) : Color.clear)
                            .shadow(color: .black.opacity(selected ? 0.12 : 0), radius: 1.5, y: 0.5))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.primary.opacity(0.07)))

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                TextField("Search \(section.title.lowercased())", text: $query).textFieldStyle(.plain).font(.system(size: 12.5))
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                        .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 9).frame(height: 28)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.06)))
        }
        .padding(12)
    }
}

// MARK: - Bookmarks

private struct BookmarksList: View {
    @ObservedObject var model: BrowserModel
    let query: String
    @ObservedObject private var store = BookmarkStore.shared
    @State private var renaming: UUID?
    @State private var newTitle = ""
    @State private var dragging: UUID?

    private var filtered: [Bookmark] {
        let q = query.lowercased()
        return q.isEmpty ? store.items : store.items.filter { $0.title.lowercased().contains(q) || $0.url.absoluteString.lowercased().contains(q) }
    }

    var body: some View {
        VStack(spacing: 0) {
            if filtered.isEmpty {
                EmptyNote(symbol: "star", text: query.isEmpty ? "No bookmarks yet. Press ⌘D on any page to add one." : "No bookmarks match “\(query)”.")
            } else {
                // A light scrolling stack (much quicker to open than a full list view), with
                // drag and drop to reorder.
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(filtered) { bookmark in
                            row(bookmark)
                                .opacity(dragging == bookmark.id ? 0.4 : 1)
                                .onDrag {
                                    dragging = bookmark.id
                                    return NSItemProvider(object: bookmark.url.absoluteString as NSString)
                                }
                                .onDrop(of: [.text], delegate: BookmarkDrop(target: bookmark, dragging: $dragging, enabled: query.isEmpty))
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 6)
                }
            }
            footer
        }
    }

    @ViewBuilder private func row(_ bookmark: Bookmark) -> some View {
        if renaming == bookmark.id {
            TextField("Name", text: $newTitle)
                .textFieldStyle(.roundedBorder)
                .onSubmit { store.rename(bookmark, to: newTitle); renaming = nil }
                .onExitCommand { renaming = nil }
        } else {
            LibraryRow(url: bookmark.url, title: bookmark.title, detail: bookmark.url.host?.strippingWWW ?? "",
                       current: model.selectedTab?.url.map { $0.host == bookmark.url.host && $0.path == bookmark.url.path } ?? false) {
                model.open(bookmark.url, inNewTab: NSEvent.modifierFlags.contains(.command))
            }
            .contextMenu {
                Button("Open in New Tab") { model.open(bookmark.url, inNewTab: true) }
                Button("Copy Address") { copy(bookmark.url) }
                Divider()
                Button("Rename…") { newTitle = bookmark.title; renaming = bookmark.id }
                Button("Remove", role: .destructive) { store.remove(bookmark) }
            }
        }
    }

    private var footer: some View {
        HStack {
            if let tab = model.selectedTab, let url = tab.url {
                let saved = store.contains(url)
                Button {
                    model.toggleBookmarkForSelectedTab()
                } label: {
                    Label(saved ? "Bookmarked" : "Bookmark This Page", systemImage: saved ? "star.fill" : "star")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(saved ? Color.yellow : Color.accentColor)
                }
                .buttonStyle(.plain)
            }
            Spacer()
            Text("\(store.items.count)").font(.system(size: 11)).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14).frame(height: 36)
        .overlay(alignment: .top) { Divider() }
    }
}

// MARK: - History

private struct HistoryList: View {
    @ObservedObject var model: BrowserModel
    let query: String
    @ObservedObject private var history = HistoryStore.shared
    @Environment(\.openWindow) private var openWindow

    private var days: [(day: Date, entries: [HistoryEntry])] {
        let q = query.lowercased()
        let matching = history.entries.values
            .filter { q.isEmpty || $0.title.lowercased().contains(q) || $0.url.absoluteString.lowercased().contains(q) }
            .sorted { $0.lastVisit > $1.lastVisit }
            .prefix(400)
        var groups: [Date: [HistoryEntry]] = [:]
        for entry in matching { groups[Calendar.current.startOfDay(for: entry.lastVisit), default: []].append(entry) }
        return groups.keys.sorted(by: >).map { ($0, groups[$0] ?? []) }
    }

    var body: some View {
        VStack(spacing: 0) {
            let groups = days
            if model.isPrivate {
                Label("Pages you visit in this Private window aren’t added to history.", systemImage: "eyeglasses")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .padding(.horizontal, 14).padding(.bottom, 6)
            }
            if groups.isEmpty {
                EmptyNote(symbol: "clock", text: query.isEmpty ? "No history yet." : "Nothing matches “\(query)”.")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1, pinnedViews: [.sectionHeaders]) {
                    ForEach(groups, id: \.day) { group in
                        SwiftUI.Section {
                            ForEach(group.entries) { entry in
                                LibraryRow(url: entry.url, title: entry.title.isEmpty ? (entry.url.host ?? "") : entry.title,
                                           detail: entry.lastVisit.formatted(date: .omitted, time: .shortened) + " · " + (entry.url.host?.strippingWWW ?? ""),
                                           current: false) {
                                    model.open(entry.url, inNewTab: NSEvent.modifierFlags.contains(.command))
                                }
                                .contextMenu {
                                    Button("Open in New Tab") { model.open(entry.url, inNewTab: true) }
                                    Button("Copy Address") { copy(entry.url) }
                                    Divider()
                                    Button("Remove from History") { history.remove(entry) }
                                }
                            }
                        } header: {
                            Text(HistoryWindowView.dayTitle(group.day))
                                .font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 8).padding(.top, 8).padding(.bottom, 3)
                                .background(Color(nsColor: .windowBackgroundColor).opacity(0.92))
                        }
                    }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 6)
                }
            }
            HStack {
                Button("Show All History") { openWindow(id: "history") }
                    .buttonStyle(.plain).font(.system(size: 11.5, weight: .medium)).foregroundStyle(Color.accentColor)
                Spacer()
                Button("Clear…") { HushDialogs.clearHistory(in: model.dialogs) }
                    .buttonStyle(.plain).font(.system(size: 11.5)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14).frame(height: 36)
            .overlay(alignment: .top) { Divider() }
        }
    }
}

/// Dropping one bookmark onto another moves it there.
private struct BookmarkDrop: DropDelegate {
    let target: Bookmark
    @Binding var dragging: UUID?
    let enabled: Bool

    func dropEntered(info: DropInfo) {
        guard enabled, let moving = dragging, moving != target.id else { return }
        let store = BookmarkStore.shared
        guard let from = store.items.firstIndex(where: { $0.id == moving }),
              let to = store.items.firstIndex(where: { $0.id == target.id }) else { return }
        withAnimation(.easeOut(duration: 0.15)) {
            store.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        dragging = nil
        return true
    }
}

// MARK: - Pieces

private struct LibraryRow: View {
    let url: URL
    let title: String
    let detail: String
    let current: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Favicon(url: url, size: 16)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 12.5, weight: current ? .semibold : .regular)).lineLimit(1)
                    Text(detail).font(.system(size: 10.5)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 8)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(current ? Color.accentColor.opacity(0.16) : Color.primary.opacity(hovering ? 0.07 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(url.absoluteString)
    }
}

private struct EmptyNote: View {
    let symbol: String
    let text: String
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 26, weight: .light)).foregroundStyle(.tertiary)
            Text(text).font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private func copy(_ url: URL) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(url.absoluteString, forType: .string)
}

/// The toolbar button that shows and hides the sidebar.
struct SidebarButton: View {
    @ObservedObject var model: BrowserModel
    var body: some View {
        ToolbarIconButton(symbol: "sidebar.left", help: "Show Bookmarks & History (⇧⌘L)",
                          tint: model.sidebarOpen ? .accentColor : nil) {
            model.sidebarOpen.toggle()
        }
    }
}
