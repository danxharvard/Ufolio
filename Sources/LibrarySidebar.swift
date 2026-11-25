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
    @AppStorage(Prefs.theme) private var theme = "classic"
    @State private var query = ""

    private var section: Section { Section(rawValue: sectionName) ?? .bookmarks }

    var body: some View {
        VStack(spacing: 0) {
            header
            // While tucked away the lists aren't built at all, so visiting pages (which updates
            // history) and bookmarking never redraw a sidebar nobody can see.
            if active {
                switch section {
                case .bookmarks: BookmarksList(model: model, query: query)
                case .history: HistoryList(model: model, query: query)
                }
            } else {
                Spacer(minLength: 0)
            }
        }
        .frame(width: 275)
        .background {
            if active {
                VisualEffect(material: .sidebar)
                if AlienTheme.isActive(theme) { AlienTheme.glass }   // the Area 51 theme's green glass
            }
        }
    }

    @Namespace private var sectionSlide

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
                        .background {
                            if selected {
                                // A soft frosted highlight that slides between Bookmarks and History.
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(SideColors.selected)
                                    .matchedGeometryEffect(id: "librarySection", in: sectionSlide)
                            }
                        }
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
    /// The bookmarks of the current Orbit's profile.
    @ObservedObject private var store: BookmarkStore

    init(model: BrowserModel, query: String) {
        _model = ObservedObject(wrappedValue: model)
        self.query = query
        _store = ObservedObject(wrappedValue: model.bookmarks)
    }
    @State private var editing: (id: UUID, field: Field)?
    @State private var draft = ""
    @State private var dragging: UUID?
    @State private var collapsed: Set<String> = []
    @State private var newFolder: String?
    /// The bookmark waiting to go into the folder being made (Move to Folder › New Folder…).
    @State private var movingIntoNewFolder: Bookmark?
    @State private var renamingFolder: String?
    @State private var folderDraft = ""
    @State private var message: String?

    enum Field { case title, address }

    private var filtered: [Bookmark] {
        let q = query.lowercased()
        return store.items.filter { $0.title.lowercased().contains(q) || $0.url.absoluteString.lowercased().contains(q) }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    if let name = newFolder {
                        HStack(spacing: 8) {
                            Image(systemName: "folder.badge.plus").foregroundStyle(Color.accentColor)
                            TextField("Folder name", text: Binding(get: { name }, set: { newFolder = $0 }))
                                .textFieldStyle(.roundedBorder)
                                .onSubmit {
                                    store.makeFolder(name)
                                    let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
                                    if let moving = movingIntoNewFolder, !clean.isEmpty { store.setFolder(moving, clean) }
                                    movingIntoNewFolder = nil
                                    newFolder = nil
                                }
                                .onExitCommand { newFolder = nil; movingIntoNewFolder = nil }
                        }
                        .padding(.horizontal, 8).padding(.vertical, 4)
                    }
                    if !query.isEmpty {
                        ForEach(filtered) { row($0) }
                        if filtered.isEmpty { EmptyNote(symbol: "star", text: "No bookmarks match “\(query)”.") }
                    } else if store.items.isEmpty && store.folders.isEmpty {
                        EmptyNote(symbol: "star", text: "No bookmarks yet. Press ⌘D on any page to add one, or import them from another browser.")
                    } else {
                        ForEach(store.items(in: nil)) { row($0) }
                        ForEach(store.folders, id: \.self) { folder in
                            folderHeader(folder)
                            if !collapsed.contains(folder) {
                                ForEach(store.items(in: folder)) { row($0).padding(.leading, 14) }
                            }
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 6)
            }
            if let message {
                Text(message).font(.system(size: 11)).foregroundStyle(.secondary)
                    .padding(.horizontal, 14).padding(.bottom, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            footer
        }
    }

    @ViewBuilder private func row(_ bookmark: Bookmark) -> some View {
        if let editing, editing.id == bookmark.id {
            TextField(editing.field == .title ? "Name" : "Address", text: $draft)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    if editing.field == .title { store.rename(bookmark, to: draft) } else { store.setAddress(bookmark, draft) }
                    self.editing = nil
                }
                .onExitCommand { self.editing = nil }
                .padding(.vertical, 2)
        } else {
            LibraryRow(url: bookmark.url, title: bookmark.title, detail: bookmark.url.host?.strippingWWW ?? "",
                       current: model.selectedTab?.url.map { $0.host == bookmark.url.host && $0.path == bookmark.url.path } ?? false) {
                model.open(bookmark.url, inNewTab: NSEvent.modifierFlags.contains(.command))
            }
            .opacity(dragging == bookmark.id ? 0.4 : 1)
            .onDrag {
                dragging = bookmark.id
                return NSItemProvider(object: bookmark.url.absoluteString as NSString)
            }
            .onDrop(of: [.text], delegate: BookmarkDrop(store: store, target: bookmark, dragging: $dragging, enabled: query.isEmpty))
            .contextMenu {
                Button { model.open(bookmark.url, inNewTab: true) } label: { Label("Open in New Tab", systemImage: "plus.square.on.square") }
                Button { copy(bookmark.url) } label: { Label("Copy Address", systemImage: "doc.on.doc") }
                Divider()
                Button { draft = bookmark.title; editing = (bookmark.id, .title) } label: { Label("Rename…", systemImage: "pencil") }
                Button { draft = bookmark.url.absoluteString; editing = (bookmark.id, .address) } label: { Label("Edit Address…", systemImage: "pencil.line") }
                Menu("Move to Folder") {
                    Button { store.setFolder(bookmark, nil) } label: { Label("No Folder", systemImage: "tray") }.disabled(bookmark.folder == nil)
                    if !store.folders.isEmpty { Divider() }
                    ForEach(store.folders, id: \.self) { folder in
                        Button(folder) { store.setFolder(bookmark, folder) }.disabled(bookmark.folder == folder)
                    }
                    Divider()
                    Button { movingIntoNewFolder = bookmark; newFolder = "" } label: { Label("New Folder…", systemImage: "folder.badge.plus") }
                }
                Divider()
                Button("Remove", role: .destructive) { store.remove(bookmark) }
            }
        }
    }

    @ViewBuilder private func folderHeader(_ folder: String) -> some View {
        if renamingFolder == folder {
            HStack(spacing: 8) {
                Image(systemName: "folder.fill").font(.system(size: 12)).foregroundStyle(Color.accentColor)
                TextField("Folder name", text: $folderDraft)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        store.renameFolder(folder, to: folderDraft)
                        renamingFolder = nil
                    }
                    .onExitCommand { renamingFolder = nil }
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
        } else {
            folderButton(folder)
        }
    }

    private func folderButton(_ folder: String) -> some View {
        let open = !collapsed.contains(folder)
        return Button {
            withAnimation(.easeOut(duration: 0.15)) { if open { collapsed.insert(folder) } else { collapsed.remove(folder) } }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold)).foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(open ? 90 : 0))
                Image(systemName: open ? "folder.fill" : "folder").font(.system(size: 12)).foregroundStyle(Color.accentColor)
                Text(folder).font(.system(size: 12.5, weight: .medium)).lineLimit(1)
                Spacer()
                Text("\(store.items(in: folder).count)").font(.system(size: 10.5)).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            let marks = store.items(in: folder)
            Button { model.openAll(marks.map(\.url)) } label: { Label("Open All in Tabs", systemImage: "square.stack") }.disabled(marks.isEmpty)
            Divider()
            Button { folderDraft = folder; renamingFolder = folder } label: { Label("Rename Folder…", systemImage: "pencil") }
            Button { store.removeFolder(folder) } label: { Label("Remove Folder (Keep Bookmarks)", systemImage: "folder.badge.minus") }
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if let tab = model.selectedTab, let url = tab.url {
                let saved = store.contains(url)
                Button {
                    model.toggleBookmarkForSelectedTab()
                } label: {
                    Label(saved ? "Bookmarked" : "Bookmark This Page", systemImage: saved ? "star.fill" : "star")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(saved ? Color.yellow : Color.accentColor)
                        .padding(.horizontal, 10).frame(height: 24)
                        .background(Capsule().fill((saved ? Color.yellow : Color.accentColor).opacity(0.14)))
                }
                .buttonStyle(.plain)
            }
            Spacer()
            Menu {
                Button("New Folder") { movingIntoNewFolder = nil; newFolder = "" }
                Divider()
                Button("Import Bookmarks…") { message = store.importWithPanel() }
                Button("Export Bookmarks…") { store.exportWithPanel() }
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 26, height: 24)
                    .background(Capsule().fill(Color.primary.opacity(0.07)))
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .help("New folder, import and export")
        }
        .padding(.horizontal, 12).frame(height: 40)
        .overlay(alignment: .top) { Rectangle().fill(Color.primary.opacity(0.07)).frame(height: 1) }
    }
}

// MARK: - History

private struct HistoryList: View {
    let model: BrowserModel   // only used to open pages; the list doesn't redraw for tab changes
    let query: String
    /// The history of the current Orbit's profile.
    @ObservedObject private var history: HistoryStore
    @Environment(\.openWindow) private var openWindow

    init(model: BrowserModel, query: String) {
        self.model = model
        self.query = query
        _history = ObservedObject(wrappedValue: model.history)
    }

    private var days: [(day: Date, entries: [HistoryEntry])] {
        let q = query.lowercased()
        let matching = history.entries(matching: q)
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
                Label("Pages you visit in this Stealth window aren’t added to history.", systemImage: "eyeglasses")
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
                                    Button { model.open(entry.url, inNewTab: true) } label: { Label("Open in New Tab", systemImage: "plus.square.on.square") }
                                    Button { copy(entry.url) } label: { Label("Copy Address", systemImage: "doc.on.doc") }
                                    Divider()
                                    Button { history.remove(entry) } label: { Label("Remove from History", systemImage: "trash") }
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
    let store: BookmarkStore
    let target: Bookmark
    @Binding var dragging: UUID?
    let enabled: Bool

    func dropEntered(info: DropInfo) {
        guard enabled, let moving = dragging, moving != target.id else { return }
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
    let model: BrowserModel
    var body: some View { Inner(sidebar: model.sidebar) }

    private struct Inner: View {
        @ObservedObject var sidebar: BrowserModel.SidebarState
        var body: some View {
            ToolbarIconButton(symbol: "sidebar.left", help: "Show Bookmarks & History (⇧⌘L)",
                              tint: sidebar.open ? .accentColor : nil) {
                sidebar.open.toggle()
            }
        }
    }
}
