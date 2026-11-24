import SwiftUI
import AppKit

/// ⌘K: one box to find anything — open tabs, every command, Spaces, bookmarks and history —
/// and do it with the keyboard. Results are worked out locally as you type; nothing is sent
/// anywhere until you choose "Search the web".
struct PaletteItem: Identifiable {
    enum Kind: Int { case website, tab, command, space, bookmark, history, search }
    let id: String
    let kind: Kind
    let title: String
    var subtitle: String? = nil
    var symbol: String = "command"
    var tint: Color? = nil
    var siteURL: URL? = nil
    var shortcut: String? = nil
    let run: @MainActor () -> Void
}

/// A command that can run from the palette.
private struct PaletteCommand {
    let title: String
    let symbol: String
    var keywords: String = ""
    var shortcut: ShortcutAction? = nil
    var available: (BrowserModel) -> Bool = { _ in true }
    let run: @MainActor (BrowserModel, OpenWindowAction) -> Void
}

enum PaletteSearch {
    /// How well `query` matches `text`: a word starting with it beats it appearing anywhere,
    /// which beats its letters appearing in order. 0 = no match.
    static func score(_ query: String, _ text: String) -> Int {
        let q = query.lowercased(), t = text.lowercased()
        guard !q.isEmpty else { return 1 }
        if t.hasPrefix(q) { return 100 }
        if t.contains(" " + q) || t.contains("." + q) || t.contains("/" + q) { return 80 }
        if t.contains(q) { return 60 }
        return initialsScore(q, t)
    }

    /// Only a whole word starting with the query counts (for long keyword lists, where loose
    /// matching would find almost anything).
    static func wordScore(_ query: String, _ text: String) -> Int {
        let q = query.lowercased(), t = text.lowercased()
        guard !q.isEmpty else { return 0 }
        return t.hasPrefix(q) || t.contains(" " + q) ? 50 : 0
    }

    /// Letters in order, starting at the start of a word and close together
    /// (e.g. "nwtb" → "New Tab", but not "cats" → "Check for Updates").
    private static func initialsScore(_ q: String, _ t: String) -> Int {
        let letters = Array(q.filter { $0 != " " }), chars = Array(t)
        guard letters.count >= 2, letters.count <= 12 else { return 0 }
        for start in chars.indices where chars[start] == letters[0] && (start == 0 || chars[start - 1] == " ") {
            var i = start + 1, matched = 1
            while i < chars.count, matched < letters.count, i - start < letters.count * 3 {
                if chars[i] == letters[matched] { matched += 1 }
                i += 1
            }
            if matched == letters.count { return 25 }
        }
        return 0
    }
}

final class PaletteModel: ObservableObject {
    @Published var query = "" { didSet { refresh() } }
    @Published private(set) var items: [PaletteItem] = []
    @Published var selection = 0
    private weak var browser: BrowserModel?
    private var openWindow: OpenWindowAction?

    func attach(_ browser: BrowserModel, openWindow: OpenWindowAction) {
        self.browser = browser
        self.openWindow = openWindow
        refresh()
    }

    func move(_ delta: Int) {
        guard !items.isEmpty else { return }
        selection = (selection + delta + items.count) % items.count
    }

    func runSelected() {
        guard items.indices.contains(selection) else { return }
        run(items[selection])
    }

    func run(_ item: PaletteItem) {
        browser?.paletteOpen = false
        // Let the palette close first, so whatever the command opens gets the focus.
        DispatchQueue.main.async { item.run() }
    }

    private func refresh() {
        guard let browser, let openWindow else { items = []; return }
        let q = query.trimmingCharacters(in: .whitespaces)
        var scored: [(Int, PaletteItem)] = []

        // A typed address goes straight there.
        if !q.isEmpty, URLResolver.looksLikeAddress(q), let url = URLResolver.resolve(q) {
            scored.append((1000, PaletteItem(id: "go", kind: .website, title: q, subtitle: "Go to website",
                                             symbol: "globe", siteURL: url) { [weak browser] in browser?.open(url) }))
        }

        // Open tabs, in every Space.
        let spaces = SpaceStore.shared
        let current = browser.selectedTab
        var tabCount = 0
        for tab in browser.tabs where tab !== current {
            let s = max(PaletteSearch.score(q, tab.displayTitle), PaletteSearch.score(q, tab.url?.host ?? ""))
            guard s > 0, tabCount < (q.isEmpty ? 6 : 5) else { continue }
            tabCount += 1
            let spaceName = browser.isPrivate || spaces.spaces.count < 2 || tab.spaceID == browser.spaceID
                ? nil : spaces.space(tab.spaceID)?.name
            let detail = [tab.url?.host?.strippingWWW, spaceName.map { "in \($0)" }].compactMap { $0 }.joined(separator: " · ")
            scored.append((s + 20, PaletteItem(id: "tab-\(tab.id)", kind: .tab, title: tab.displayTitle,
                                               subtitle: detail.isEmpty ? "Switch to tab" : detail,
                                               symbol: "square.on.square", siteURL: tab.url) { [weak browser, weak tab] in
                guard let browser, let tab else { return }
                if let space = tab.spaceID, space != browser.spaceID { browser.switchSpace(to: space) }
                browser.selectedID = tab.id
            }))
        }

        // Spaces.
        if !browser.isPrivate {
            for space in spaces.spaces where space.id != browser.spaceID {
                let s = max(PaletteSearch.score(q, space.name), PaletteSearch.score(q, "space " + space.name))
                guard s > 0, !q.isEmpty else { continue }
                scored.append((s + 10, PaletteItem(id: "space-\(space.id)", kind: .space, title: "Switch to \(space.name)",
                                                   subtitle: "Orbit", symbol: space.symbol,
                                                   tint: SpacePalette.color(space.color)) { [weak browser] in
                    browser?.switchSpace(to: space.id)
                }))
                if let tab = current, tab.url != nil {
                    let m = PaletteSearch.score(q, "move tab to " + space.name)
                    if m > 0 {
                        scored.append((m, PaletteItem(id: "move-\(space.id)", kind: .space, title: "Move Tab to \(space.name)",
                                                      subtitle: "Orbit", symbol: "arrow.right.square",
                                                      tint: SpacePalette.color(space.color)) { [weak browser, weak tab] in
                            if let browser, let tab { browser.move(tab, toSpace: space.id) }
                        }))
                    }
                }
            }
        }

        // Commands.
        var commandCount = 0
        for command in Self.commands where command.available(browser) {
            let s = max(PaletteSearch.score(q, command.title), PaletteSearch.wordScore(q, command.keywords))
            guard s > 0, commandCount < (q.isEmpty ? 6 : 8) else { continue }
            if q.isEmpty && !Self.suggested.contains(command.title) { continue }
            commandCount += 1
            scored.append((s, PaletteItem(id: "cmd-\(command.title)", kind: .command, title: command.title, subtitle: nil,
                                          symbol: command.symbol, shortcut: command.shortcut.flatMap { Shortcuts.combo($0)?.display }) { [weak browser] in
                if let browser { command.run(browser, openWindow) }
            }))
        }

        if !q.isEmpty && !browser.isPrivate {
            // Bookmarks, then pages from history.
            var seen = Set(scored.compactMap { $0.1.siteURL?.absoluteString })
            let marks = BookmarkStore.shared.items
                .map { (max(PaletteSearch.score(q, $0.title), PaletteSearch.score(q, $0.url.host ?? "")), $0) }
                .filter { $0.0 >= 60 }.sorted { $0.0 > $1.0 }.prefix(4)
            for (s, mark) in marks where !seen.contains(mark.url.absoluteString) {
                seen.insert(mark.url.absoluteString)
                scored.append((s - 5, PaletteItem(id: "bm-\(mark.id)", kind: .bookmark, title: mark.title,
                                                  subtitle: mark.url.host?.strippingWWW, symbol: "bookmark", siteURL: mark.url) { [weak browser] in
                    browser?.open(mark.url)
                }))
            }
            for entry in HistoryStore.shared.search(q, limit: 6) where !seen.contains(entry.url.absoluteString) {
                seen.insert(entry.url.absoluteString)
                let title = entry.title.isEmpty ? (entry.url.host ?? entry.url.absoluteString) : entry.title
                scored.append((40, PaletteItem(id: "h-\(entry.url.absoluteString)", kind: .history, title: title,
                                               subtitle: entry.url.host?.strippingWWW, symbol: "clock", siteURL: entry.url) { [weak browser] in
                    browser?.open(entry.url)
                }))
                if seen.count > 12 { break }
            }
        }

        if !q.isEmpty, let url = URLResolver.resolve(q), !URLResolver.looksLikeAddress(q) {
            scored.append((-1, PaletteItem(id: "search", kind: .search, title: q, subtitle: "Search with \(SearchEngine.current.name)",
                                           symbol: "magnifyingglass") { [weak browser] in browser?.open(url) }))
        }

        // Best first; on ties, tabs before commands before bookmarks and history.
        items = scored.enumerated().sorted {
            if $0.element.0 != $1.element.0 { return $0.element.0 > $1.element.0 }
            if $0.element.1.kind != $1.element.1.kind { return $0.element.1.kind.rawValue < $1.element.1.kind.rawValue }
            return $0.offset < $1.offset
        }.map(\.element.1).prefix(14).map { $0 }
        selection = 0
    }

    // MARK: Commands

    private static let suggested: Set<String> = ["New Tab", "Reopen Closed Tab", "Bookmark This Page", "Split View",
                                                 "Show Bookmarks & History Sidebar", "Open Settings"]

    private static let commands: [PaletteCommand] = {
        var list: [PaletteCommand] = [
            .init(title: "New Tab", symbol: "plus.square", shortcut: .newTab) { m, _ in m.newTab(focus: true) },
            .init(title: "New Stealth Window", symbol: "eyeglasses", keywords: "incognito", shortcut: .privateWindow) { _, open in open(id: "private") },
            .init(title: "Reopen Closed Tab", symbol: "arrow.uturn.backward", keywords: "undo restore", shortcut: .reopenTab) { m, _ in m.reopenClosedTab() },
            .init(title: "Close Tab", symbol: "xmark.square", shortcut: .closeTab) { m, _ in m.closeSelectedTab() },
            .init(title: "Close Other Tabs", symbol: "xmark.square.fill", available: { $0.visibleTabs.count > 1 }) { m, _ in
                for tab in m.visibleTabs where tab !== m.selectedTab { m.close(tab) }
            },
            .init(title: "Duplicate Tab", symbol: "plus.square.on.square", available: { $0.selectedTab?.url != nil }) { m, _ in
                if let url = m.selectedTab?.url { m.newTab(url: url) }
            },
            .init(title: "Pin Tab", symbol: "pin", keywords: "unpin", available: { $0.selectedTab?.isPinned == false }) { m, _ in
                if let tab = m.selectedTab { m.togglePin(tab) }
            },
            .init(title: "Unpin Tab", symbol: "pin.slash", available: { $0.selectedTab?.isPinned == true }) { m, _ in
                if let tab = m.selectedTab { m.togglePin(tab) }
            },
            .init(title: "Mute Tab", symbol: "speaker.slash", keywords: "sound audio unmute", shortcut: .muteTab) { m, _ in m.selectedTab?.toggleMute() },
            .init(title: "Sleep Other Tabs", symbol: "moon.zzz", keywords: "memory ram free up", available: { $0.visibleTabs.count > 1 }) { m, _ in
                m.sleepBackgroundTabs(idleFor: 0)
            },
            .init(title: "Reload Page", symbol: "arrow.clockwise", keywords: "refresh", shortcut: .reload) { m, _ in m.selectedTab?.reload() },
            .init(title: "Back", symbol: "chevron.left", shortcut: .back) { m, _ in m.selectedTab?.webView.goBack() },
            .init(title: "Forward", symbol: "chevron.right", shortcut: .forward) { m, _ in m.selectedTab?.webView.goForward() },
            .init(title: "Find on Page", symbol: "text.magnifyingglass", keywords: "search", shortcut: .find) { m, _ in m.find.show() },
            .init(title: "Copy Link", symbol: "link", keywords: "address url", available: { $0.selectedTab?.url != nil }) { m, _ in
                guard let url = m.selectedTab?.url else { return }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(url.absoluteString, forType: .string)
            },
            .init(title: "Copy Clean Link", symbol: "link.badge.plus", keywords: "tracking remove", shortcut: .copyCleanLink,
                  available: { $0.selectedTab?.url != nil }) { m, _ in
                guard let url = m.selectedTab?.url else { return }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(CleanLinks.clean(url).absoluteString, forType: .string)
            },
            .init(title: "Split View", symbol: "rectangle.split.2x1", keywords: "side by side", shortcut: .splitView) { m, _ in
                if m.splitPair != nil { m.closeSplit(keeping: m.selectedID) } else { m.openSplit() }
            },
            .init(title: "Reader", symbol: "doc.plaintext", keywords: "reading mode article", shortcut: .reader) { m, _ in m.selectedTab?.toggleReader() },
            .init(title: "Picture in Picture", symbol: "pip", keywords: "video pip", shortcut: .pictureInPicture) { m, _ in
                if let view = m.selectedTab?.webView { WebKitExtras.togglePictureInPicture(view) }
            },
            .init(title: "Translate Page", symbol: "translate", keywords: "language", shortcut: .translate) { m, _ in
                guard let tab = m.selectedTab else { return }
                if tab.translation == .translated { PageTranslator.shared.showOriginal(tab) } else { PageTranslator.shared.translate(tab) }
            },
            .init(title: "Turn Off JavaScript in This Tab", symbol: "curlybraces", keywords: "scripts disable",
                  available: { $0.selectedTab?.javaScriptOff == false }) { m, _ in m.selectedTab?.toggleJavaScript() },
            .init(title: "Turn On JavaScript in This Tab", symbol: "curlybraces", keywords: "scripts enable",
                  available: { $0.selectedTab?.javaScriptOff == true }) { m, _ in m.selectedTab?.toggleJavaScript() },
            .init(title: "Forget This Site", symbol: "eraser", keywords: "delete cookies data sign out",
                  available: { $0.selectedTab?.url != nil }) { m, _ in if let tab = m.selectedTab { SiteForgetter.confirmAndForget(tab) } },
            .init(title: "Zoom In", symbol: "plus.magnifyingglass", keywords: "bigger larger", shortcut: .zoomIn) { m, _ in m.selectedTab?.zoom(by: 0.1) },
            .init(title: "Zoom Out", symbol: "minus.magnifyingglass", keywords: "smaller", shortcut: .zoomOut) { m, _ in m.selectedTab?.zoom(by: -0.1) },
            .init(title: "Actual Size", symbol: "1.magnifyingglass", keywords: "reset zoom", shortcut: .actualSize) { m, _ in m.selectedTab?.resetZoom() },
            .init(title: "Print", symbol: "printer", shortcut: .print) { m, _ in m.selectedTab?.printPage() },
            .init(title: "Save Page As", symbol: "square.and.arrow.down", keywords: "download", shortcut: .savePage) { m, _ in m.selectedTab?.savePage() },
            .init(title: "Bookmark This Page", symbol: "bookmark", keywords: "favourite favorite save", shortcut: .bookmark,
                  available: { $0.selectedTab?.url != nil }) { m, _ in m.toggleBookmarkForSelectedTab() },
            .init(title: "Show Bookmarks & History Sidebar", symbol: "sidebar.left", keywords: "library", shortcut: .sidebar) { m, _ in m.sidebarOpen.toggle() },
            .init(title: "Show Bookmarks Bar", symbol: "menubar.rectangle", keywords: "hide toolbar", shortcut: .bookmarksBar) { _, _ in
                let key = Prefs.showBookmarkBar
                UserDefaults.standard.set(!(UserDefaults.standard.object(forKey: key) as? Bool ?? true), forKey: key)
            },
            .init(title: "Show Tabs Down the Side", symbol: "sidebar.left", keywords: "vertical layout",
                  available: { _ in Prefs.string(Prefs.tabLayout) != TabLayout.side.rawValue }) { _, _ in
                UserDefaults.standard.set(TabLayout.side.rawValue, forKey: Prefs.tabLayout)
            },
            .init(title: "Show Tabs Along the Top", symbol: "rectangle.topthird.inset.filled", keywords: "horizontal layout",
                  available: { _ in Prefs.string(Prefs.tabLayout) == TabLayout.side.rawValue }) { _, _ in
                UserDefaults.standard.set(TabLayout.top.rawValue, forKey: Prefs.tabLayout)
            },
            .init(title: "Show All History", symbol: "clock", shortcut: .history) { _, open in open(id: "history") },
            .init(title: "Import Bookmarks", symbol: "square.and.arrow.down.on.square", keywords: "html chrome safari firefox") { _, _ in
                _ = BookmarkStore.shared.importWithPanel()
            },
            .init(title: "Export Bookmarks", symbol: "square.and.arrow.up", keywords: "html backup") { _, _ in BookmarkStore.shared.exportWithPanel() },
            .init(title: "Next Orbit", symbol: "arrow.right.circle", shortcut: .nextSpace,
                  available: { !$0.isPrivate && SpaceStore.shared.spaces.count > 1 }) { m, _ in m.switchSpace(by: 1) },
            .init(title: "Previous Orbit", symbol: "arrow.left.circle", shortcut: .previousSpace,
                  available: { !$0.isPrivate && SpaceStore.shared.spaces.count > 1 }) { m, _ in m.switchSpace(by: -1) },
            .init(title: "New Orbit", symbol: "square.stack.3d.up", keywords: "workspace profile", available: { !$0.isPrivate }) { m, _ in
                let store = SpaceStore.shared
                if let space = store.addSpace(name: "", symbol: SpacePalette.symbols[store.spaces.count % SpacePalette.symbols.count],
                                              color: store.spaces.count % SpacePalette.colors.count) {
                    m.switchSpace(to: space.id)
                }
            },
            .init(title: "Check for Updates", symbol: "arrow.down.circle", keywords: "version") { _, _ in
                SettingsOpener.open(tab: .updates)
                Task { await Updater.shared.check(userInitiated: true) }
            },
            .init(title: "Open Settings", symbol: "gearshape", keywords: "preferences options") { _, _ in SettingsOpener.open() },
        ]
        // Each Settings section, e.g. "Settings: Force Field".
        for tab in SettingsTab.allCases {
            list.append(.init(title: "Settings: \(tab.title)", symbol: tab.symbol == "hush" ? "shield.lefthalf.filled" : tab.symbol,
                              keywords: tab.keywords) { _, _ in SettingsOpener.open(tab: tab) })
        }
        return list
    }()
}

// MARK: - The palette

struct CommandPaletteOverlay: View {
    @ObservedObject var model: BrowserModel

    var body: some View {
        ZStack(alignment: .top) {
            if model.paletteOpen {
                Color.black.opacity(0.12)
                    .contentShape(Rectangle())
                    .onTapGesture { model.paletteOpen = false }
                    .ignoresSafeArea()
                    .transition(.opacity)
                CommandPalette(model: model)
                    .padding(.top, 70)
                    .transition(.scale(scale: 0.96, anchor: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.26, dampingFraction: 0.9), value: model.paletteOpen)
    }
}

private struct CommandPalette: View {
    @ObservedObject var model: BrowserModel
    @StateObject private var palette = PaletteModel()
    @Environment(\.openWindow) private var openWindow
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.secondary)
                TextField("Search tabs, commands, bookmarks and history", text: $palette.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 17))
                    .focused($focused)
                    .onSubmit { palette.runSelected() }
                    .onKeyPress(.upArrow) { palette.move(-1); return .handled }
                    .onKeyPress(.downArrow) { palette.move(1); return .handled }
                    .onKeyPress(.escape) { model.paletteOpen = false; return .handled }
                    .onKeyPress(.tab) { palette.move(1); return .handled }
                Text("esc").font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.primary.opacity(0.15)))
            }
            .padding(.horizontal, 16)
            .frame(height: 52)

            if !palette.items.isEmpty {
                Divider().opacity(0.5)
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(Array(palette.items.enumerated()), id: \.element.id) { index, item in
                                PaletteRow(item: item, selected: index == palette.selection)
                                    .id(item.id)
                                    .onTapGesture { palette.run(item) }
                                    .onHover { if $0 { palette.selection = index } }
                            }
                        }
                        .padding(6)
                    }
                    .frame(maxHeight: 380)
                    .fixedSize(horizontal: false, vertical: true)
                    .onChange(of: palette.selection) { _, index in
                        guard palette.items.indices.contains(index) else { return }
                        proxy.scrollTo(palette.items[index].id)
                    }
                }
            }
        }
        .frame(width: 600)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.primary.opacity(0.1)))
        .shadow(color: .black.opacity(0.25), radius: 30, y: 12)
        .onAppear {
            palette.attach(model, openWindow: openWindow)
            focused = true
        }
    }
}

private struct PaletteRow: View {
    let item: PaletteItem
    let selected: Bool

    var body: some View {
        HStack(spacing: 11) {
            Group {
                if let url = item.siteURL, item.kind != .search {
                    Favicon(url: url, size: 16)
                } else {
                    Image(systemName: item.symbol)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(item.tint ?? (selected ? Color.accentColor : .secondary))
                }
            }
            .frame(width: 26, height: 26)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.primary.opacity(0.06)))
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title).font(.system(size: 13.5, weight: .medium)).lineLimit(1)
                if let subtitle = item.subtitle {
                    Text(subtitle).font(.system(size: 11.5)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if let shortcut = item.shortcut {
                Text(shortcut).font(.system(size: 11.5, design: .rounded)).foregroundStyle(.secondary)
            }
            if selected {
                Image(systemName: "return").font(.system(size: 11, weight: .semibold)).foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: item.subtitle == nil ? 38 : 44)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(selected ? Color.accentColor.opacity(0.16) : Color.clear))
        .contentShape(Rectangle())
    }
}
