import SwiftUI
import WebKit

/// One browser window: its tabs and which one is showing.
final class BrowserModel: ObservableObject {
    @Published private(set) var tabs: [BrowserTab] = []
    @Published var selectedID: UUID? {
        didSet {
            // The tab you leave starts its idle clock; the one you pick wakes if it was asleep.
            if let old = tabs.first(where: { $0.id == oldValue }) { old.lastActive = Date() }
            selectedTab?.wakeIfNeeded()
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

    private static let all = NSHashTable<BrowserModel>.weakObjects()

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

    /// True when a Hush browser window is showing.
    static var hasVisibleWindow: Bool {
        all.allObjects.contains { $0.window?.isVisible == true }
    }

    /// Tab Sleep: background tabs idle for longer than the chosen time are put to sleep,
    /// unless they're playing sound or video or using the camera or microphone.
    private func sleepIdleTabs() {
        let minutes = Prefs.double(Prefs.tabSleepMinutes)
        guard minutes > 0 else { return }
        for tab in tabs where tab !== selectedTab && !tab.isAsleep && !tab.isLoading
            && Date().timeIntervalSince(tab.lastActive) > minutes * 60
            && tab.webView.cameraCaptureState == .none && tab.webView.microphoneCaptureState == .none {
            tab.webView.requestMediaPlaybackState { state in
                if state == .none || state == .paused { tab.sleep() }
            }
        }
    }

    init() {
        BrowserModel.all.add(self)
        sleepTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in self?.sleepIdleTabs() }
        sleepTimer?.tolerance = 15
        // The first window after launch can bring back last time's tabs.
        if !Self.didRestoreSession,
           LaunchBehavior(rawValue: Prefs.string(Prefs.launchBehavior)) == .restore,
           let saved = UserDefaults.standard.stringArray(forKey: "lastSession"), !saved.isEmpty {
            Self.didRestoreSession = true
            for address in saved {
                if let url = URL(string: address) { newTab(url: url) }
            }
            selectedID = tabs.first?.id
        }
        Self.didRestoreSession = true
        if tabs.isEmpty {
            // A new window opens the homepage if Settings › General says so.
            if let home = NewTabPage.windowURL { newTab(url: home) } else { newTab(focus: true, usePreferredPage: false) }
        }
    }

    /// Remembers this window's open pages (for "Tabs from last time").
    func scheduleSessionSave() {
        sessionSave?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let urls = self.tabs.compactMap { $0.url?.absoluteString }
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
                select: Bool = true, focus: Bool = false, usePreferredPage: Bool = true) -> BrowserTab {
        let tab = BrowserTab(model: self, configuration: configuration)
        if let current = selectedTab, let index = tabs.firstIndex(where: { $0 === current }) {
            tabs.insert(tab, at: index + 1)
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

    func close(_ tab: BrowserTab) {
        guard let index = tabs.firstIndex(where: { $0 === tab }) else { return }
        let wasSelected = tab.id == selectedTab?.id
        if let url = tab.url { RecentlyClosed.shared.add(title: tab.title, url: url) }
        tab.tearDown()
        tabs.remove(at: index)
        scheduleSessionSave()
        if tabs.isEmpty {
            (window ?? NSApp.keyWindow)?.performClose(nil)
            return
        }
        if wasSelected {
            selectedID = tabs[min(index, tabs.count - 1)].id
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
