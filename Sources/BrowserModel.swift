import SwiftUI
import WebKit

/// One browser window: its tabs and which one is showing.
final class BrowserModel: ObservableObject {
    @Published private(set) var tabs: [BrowserTab] = []
    @Published var selectedID: UUID?
    /// Bumped to ask the address bar to take keyboard focus.
    @Published var addressFocusToken = 0
    /// The window showing this model (set by the view once it's on screen).
    weak var window: NSWindow?

    private static let all = NSHashTable<BrowserModel>.weakObjects()

    /// The browser in the frontmost Hush window, for menu commands.
    static var frontmost: BrowserModel? {
        let models = all.allObjects
        for window in NSApp.orderedWindows {
            if let model = models.first(where: { $0.window === window }) { return model }
        }
        return models.first
    }

    init() {
        BrowserModel.all.add(self)
        newTab(focus: true)
    }

    var selectedTab: BrowserTab? {
        tabs.first { $0.id == selectedID } ?? tabs.first
    }

    @discardableResult
    func newTab(url: URL? = nil, configuration: WKWebViewConfiguration? = nil,
                select: Bool = true, focus: Bool = false) -> BrowserTab {
        let tab = BrowserTab(model: self, configuration: configuration)
        if let current = selectedTab, let index = tabs.firstIndex(where: { $0 === current }) {
            tabs.insert(tab, at: index + 1)
        } else {
            tabs.append(tab)
        }
        if select { selectedID = tab.id }
        if let url { tab.load(url) }
        if focus { focusAddressBar() }
        return tab
    }

    func close(_ tab: BrowserTab) {
        guard let index = tabs.firstIndex(where: { $0 === tab }) else { return }
        let wasSelected = tab.id == selectedTab?.id
        tab.tearDown()
        tabs.remove(at: index)
        if tabs.isEmpty {
            (window ?? NSApp.keyWindow)?.performClose(nil)
            return
        }
        if wasSelected {
            selectedID = tabs[min(index, tabs.count - 1)].id
        }
    }

    func closeSelectedTab() {
        if let tab = selectedTab { close(tab) }
    }

    func selectAdjacentTab(_ offset: Int) {
        guard tabs.count > 1, let current = selectedTab,
              let index = tabs.firstIndex(where: { $0 === current }) else { return }
        selectedID = tabs[(index + offset + tabs.count) % tabs.count].id
    }

    func focusAddressBar() {
        addressFocusToken += 1
    }

    /// Opens a URL in the current tab, or a new background tab when ⌘ is held.
    func open(_ url: URL, inNewTab: Bool = false) {
        if inNewTab || selectedTab == nil {
            newTab(url: url, select: !inNewTab)
        } else {
            selectedTab?.load(url)
        }
    }

    func toggleBookmarkForSelectedTab() {
        guard let tab = selectedTab, let url = tab.url else { return }
        BookmarkStore.shared.toggle(url: url, title: tab.displayTitle)
    }
}
