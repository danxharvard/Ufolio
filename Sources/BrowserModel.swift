import SwiftUI
import WebKit

/// One browser window: its tabs and which one is showing.
final class BrowserModel: NSObject, ObservableObject {
    @Published private(set) var tabs: [BrowserTab] = []
    @Published var selectedID: UUID? {
        didSet {
            // The tab you leave starts its idle clock; the one you pick wakes if it was asleep.
            let old = tabs.first(where: { $0.id == oldValue })
            old?.lastActive = Date()
            selectedTab?.wakeIfNeeded()
            // Pause sound and video in the tab you leave (Eco, or Settings › Performance),
            // unless it's still showing on the other side of Split View.
            let stillVisible = old.map { splitPair?.contains($0.id) == true && splitPair?.contains(selectedID) == true } ?? false
            if let old, old !== selectedTab, !old.isAsleep, !stillVisible, PerformanceCenter.shared.pausesBackgroundMedia {
                old.webView.setAllMediaPlaybackSuspended(true)
            }
            if let tab = selectedTab, !tab.isAsleep { tab.webView.setAllMediaPlaybackSuspended(false) }
            if let tab = selectedTab, tab !== old { ExtensionEvents.activated(tab, previous: old) }
        }
    }
    private var sleepTimer: Timer?
    /// Bumped to ask the address bar to take keyboard focus.
    @Published var addressFocusToken = 0
    /// The window's width, which sizes the address bar.
    @Published var windowWidth: CGFloat = 1280
    var addressWidth: CGFloat { min(720, max(260, windowWidth - 420)) }
    /// The window showing this model (set by the view once it's on screen).
    weak var window: NSWindow?

    static let all = NSHashTable<BrowserModel>.weakObjects()

    /// The browser in the frontmost Hush window, for menu commands.
    static var frontmost: BrowserModel? {
        let models = all.allObjects
        for window in NSApp.orderedWindows {
            if let model = models.first(where: { $0.window === window }) { return model }
        }
        return models.first
    }

    private static var didRestoreSession = false
    private var sessionSave: DispatchWorkItem?

    /// The frontmost window that isn't private (extensions never see private windows).
    static var frontmostNormal: BrowserModel? {
        for window in NSApp.orderedWindows {
            if let model = all.allObjects.first(where: { $0.window === window && !$0.isPrivate }) { return model }
        }
        return all.allObjects.first { !$0.isPrivate }
    }

    /// True when a Hush browser window is showing.
    static var hasVisibleWindow: Bool {
        all.allObjects.contains { $0.window?.isVisible == true }
    }

    /// Tab Sleep: background tabs idle for longer than the chosen time are put to sleep,
    /// unless they're playing sound or video or using the camera or microphone.
    private func sleepIdleTabs() {
        let minutes = PerformanceCenter.shared.sleepMinutes   // shorter in Power Saver
        guard minutes > 0 else { return }
        sleepBackgroundTabs(idleFor: minutes * 60)
    }

    /// Sleeps background tabs idle for at least `seconds`, unless they're playing media
    /// or using the camera or microphone.
    func sleepBackgroundTabs(idleFor seconds: TimeInterval) {
        // The other side of Split View is on screen too: never put it to sleep.
        let visible = splitPair.flatMap { $0.contains(selectedID) ? $0 : nil }
        for tab in tabs where tab !== selectedTab && !(visible?.contains(tab.id) ?? false) && !tab.isAsleep && !tab.isLoading
            && Date().timeIntervalSince(tab.lastActive) >= seconds
            && tab.webView.cameraCaptureState == .none && tab.webView.microphoneCaptureState == .none {
            tab.webView.requestMediaPlaybackState { state in
                if state == .none || state == .paused { tab.sleep() }
            }
        }
    }

    /// Private windows: nothing is saved, and sites get a separate, in-memory set of cookies.
    let isPrivate: Bool
    let dataStore: WKWebsiteDataStore
    /// Find on Page (⌘F) for this window.
    let find = FindModel()
    /// Questions waiting to be shown over this window (one at a time).
    let dialogs = DialogHost()
    /// Split View: the two tabs shown side by side, and how much room the left one gets.
    @Published var splitPair: SplitPair?
    @Published var splitRatio: CGFloat = 0.5

    func isInSplit(_ tab: BrowserTab) -> Bool { splitPair?.contains(tab.id) ?? false }

    /// Shows a tab beside the current one. Splitting the current tab itself opens a new tab beside it.
    func openSplit(with tab: BrowserTab? = nil) {
        guard let current = selectedTab else { return }
        if let tab, tab !== current {
            splitPair = SplitPair(left: current.id, right: tab.id)
            tab.wakeIfNeeded()
        } else {
            let fresh = newTab(select: false, usePreferredPage: true)
            splitPair = SplitPair(left: current.id, right: fresh.id)
            selectedID = fresh.id
            if fresh.url == nil { focusAddressBar() }
        }
    }

    /// Leaves Split View, showing the given tab (or the active one).
    func closeSplit(keeping id: UUID? = nil) {
        guard splitPair != nil else { return }
        splitPair = nil
        if let id { selectedID = id }
    }

    func swapSplit() {
        guard let pair = splitPair else { return }
        splitPair = SplitPair(left: pair.right, right: pair.left)
    }
    private var audioTimer: Timer?

    init(isPrivate: Bool = false) {
        self.isPrivate = isPrivate
        dataStore = isPrivate ? .nonPersistent() : .default()
        super.init()
        BrowserModel.all.add(self)
        // Which tabs are playing sound (for the speaker button on tabs).
        audioTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            self?.tabs.forEach { $0.checkAudio() }
        }
        audioTimer?.tolerance = 0.5
        sleepTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in self?.sleepIdleTabs() }
        sleepTimer?.tolerance = 15
        // The first window after launch can bring back last time's tabs.
        if !isPrivate, !Self.didRestoreSession,
           LaunchBehavior(rawValue: Prefs.string(Prefs.launchBehavior)) == .restore,
           let saved = UserDefaults.standard.stringArray(forKey: "lastSession"), !saved.isEmpty {
            Self.didRestoreSession = true
            // Only web pages come back, and only the first loads now: the rest wait until you
            // click them, so launching with lots of tabs stays quick.
            let urls = saved.prefix(200).compactMap(URL.init(string:))
                .filter { ["http", "https"].contains($0.scheme?.lowercased() ?? "") }
            for (index, url) in urls.enumerated() {
                if index == 0 {
                    newTab(url: url)
                } else {
                    newTab(select: false, usePreferredPage: false, atEnd: true).restoreLazily(url)
                }
            }
            selectedID = tabs.first?.id
        }
        // Pinned tabs always come back, at the left, loading when you click them.
        if !isPrivate, !Self.didRestoreSession || tabs.count > 0 {
            let pinned = (UserDefaults.standard.stringArray(forKey: "pinnedTabs") ?? []).prefix(30)
                .compactMap(URL.init(string:)).filter { ["http", "https"].contains($0.scheme?.lowercased() ?? "") }
            var placed: [BrowserTab] = []
            for url in pinned {
                if let existing = tabs.first(where: { $0.url == url && !$0.isPinned }) {
                    existing.isPinned = true
                    placed.append(existing)
                } else {
                    let tab = newTab(select: false, usePreferredPage: false, atEnd: true)
                    tab.restoreLazily(url)
                    tab.isPinned = true
                    placed.append(tab)
                }
            }
            if !placed.isEmpty { tabs = placed + tabs.filter { !$0.isPinned } }
        }
        if !isPrivate { Self.didRestoreSession = true }
        if tabs.allSatisfy(\.isPinned) {
            // A new window opens the homepage if Settings › General says so.
            if let home = NewTabPage.windowURL { newTab(url: home) } else { newTab(focus: true, usePreferredPage: false) }
        }
    }

    /// Remembers this window's open pages (for "Tabs from last time").
    func scheduleSessionSave() {
        guard !isPrivate else { return }
        sessionSave?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let urls = self.tabs.compactMap { $0.url?.absoluteString }
            UserDefaults.standard.set(self.tabs.filter(\.isPinned).compactMap { $0.url?.absoluteString }, forKey: "pinnedTabs")
            // Closing the last tab closes the window; keep that window's pages for next launch.
            guard !urls.isEmpty else { return }
            UserDefaults.standard.set(urls, forKey: "lastSession")
        }
        sessionSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work)
    }

    var selectedTab: BrowserTab? {
        tabs.first { $0.id == selectedID } ?? tabs.first
    }

    @discardableResult
    func newTab(url: URL? = nil, configuration: WKWebViewConfiguration? = nil,
                select: Bool = true, focus: Bool = false, usePreferredPage: Bool = true, atEnd: Bool = false) -> BrowserTab {
        let tab = BrowserTab(model: self, configuration: configuration)
        defer { ExtensionEvents.opened(tab) }
        if !atEnd, let current = selectedTab, let index = tabs.firstIndex(where: { $0 === current }) {
            // New tabs go after the current one, but never in among the pinned tabs.
            tabs.insert(tab, at: max(index + 1, tabs.filter(\.isPinned).count))
        } else {
            tabs.append(tab)
        }
        if select { selectedID = tab.id }
        // A plain new tab opens the homepage if one is set in Settings.
        let page = url ?? (configuration == nil && usePreferredPage ? NewTabPage.url : nil)
        if let page { tab.load(page) }
        if focus && page == nil { focusAddressBar() }
        return tab
    }

    func close(_ tab: BrowserTab, remember: Bool = true) {
        guard let index = tabs.firstIndex(where: { $0 === tab }) else { return }
        let wasSelected = tab.id == selectedTab?.id
        // Closing one side of Split View shows the other on its own.
        var partner: UUID?
        if let pair = splitPair, pair.contains(tab.id) {
            partner = pair.left == tab.id ? pair.right : pair.left
            splitPair = nil
        }
        if remember, !isPrivate, let url = tab.url { RecentlyClosed.shared.add(title: tab.title, url: url) }
        ExtensionEvents.closed(tab)
        tab.tearDown()
        tabs.remove(at: index)
        scheduleSessionSave()
        if tabs.isEmpty {
            (window ?? NSApp.keyWindow)?.performClose(nil)
            return
        }
        if wasSelected {
            if let partner, tabs.contains(where: { $0.id == partner }) {
                selectedID = partner
            } else {
                selectedID = tabs[min(index, tabs.count - 1)].id
            }
        }
    }

    /// Brings back the most recently closed tab (or a chosen one).
    func reopenClosedTab(_ closed: ClosedTab? = nil) {
        guard let tab = RecentlyClosed.shared.take(closed) else { return }
        if let current = selectedTab, current.isBlank {
            current.load(tab.url)
        } else {
            newTab(url: tab.url)
        }
    }

    func closeSelectedTab() {
        if let tab = selectedTab { close(tab) }
    }

    /// Moves a tab to a new position in the tab bar (drag to reorder).
    func moveTab(from source: Int, to destination: Int) {
        guard tabs.indices.contains(source), tabs.indices.contains(destination), source != destination,
              tabs[source].isPinned == tabs[destination].isPinned else { return }   // pinned tabs stay together
        let tab = tabs.remove(at: source)
        tabs.insert(tab, at: destination)
        ExtensionEvents.moved(tab, from: source, in: self)
        scheduleSessionSave()
    }

    /// Pins a tab (moving it to the left with the other pinned tabs) or unpins it.
    func togglePin(_ tab: BrowserTab) {
        guard let index = tabs.firstIndex(where: { $0 === tab }) else { return }
        tab.isPinned.toggle()
        tabs.remove(at: index)
        let pinnedCount = tabs.filter(\.isPinned).count
        tabs.insert(tab, at: tab.isPinned ? pinnedCount : pinnedCount)
        scheduleSessionSave()
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
