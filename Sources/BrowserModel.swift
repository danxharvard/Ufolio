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
            old?.backCacheReleased = false   // a fresh idle spell starts
            // A link preview belongs to the page it was opened from.
            if preview != nil, selectedID != oldValue { closePreview() }
            // Pause sound and video in the tab you leave (Eco, or Settings › Performance),
            // unless it's still showing on the other side of Split View.
            let stillVisible = old.map { splitPair?.contains($0.id) == true && splitPair?.contains(selectedID) == true } ?? false
            // Its hover preview, while it's still on screen (one snapshot; nothing kept awake).
            // Not when it's still showing in Split View: clicking from one side to the other
            // took a snapshot every time.
            if let old, old !== selectedTab, !stillVisible { old.capturePreview() }
            selectedTab?.wakeIfNeeded()
            // Silent video and animations in a tab you can't see are always paused (they only cost
            // memory, graphics and battery); sound keeps playing unless you've asked otherwise.
            // A video playing in the tab you leave pops out into Picture in Picture (Settings ›
            // Appearance, on by default, with sites you've turned it off for left alone).
            if let old, old !== selectedTab, !old.isAsleep, !stillVisible, AutoPictureInPicture.wanted(for: old) {
                AutoPictureInPicture.popOut(old) { [weak self, weak old] poppedOut in
                    // Back on that tab already: leave it playing.
                    guard let self, let old, self.selectedTab !== old else { return }
                    if !poppedOut, PerformanceCenter.shared.pausesBackgroundMedia || !old.isPlayingAudio {
                        old.webView.setAllMediaPlaybackSuspended(true)
                    }
                }
            } else if let old, old !== selectedTab, !old.isAsleep, !stillVisible,
               // A video you've popped out into Picture in Picture is still on screen: it used to
               // freeze in its floating window as you switched tabs (silent ones always).
               !WebKitExtras.isPictureInPictureActive(old.webView),
               PerformanceCenter.shared.pausesBackgroundMedia || !old.isPlayingAudio {
                old.webView.setAllMediaPlaybackSuspended(true)
            }
            if let tab = selectedTab, !tab.isAsleep {
                tab.webView.setAllMediaPlaybackSuspended(false)
                AutoPictureInPicture.bringBack(tab)   // back to its tab when you return
            }
            // Split View: the other half goes out of sight with the tab you leave, and comes back
            // with the one you pick. Its silent video used to keep running behind another tab, and
            // stay paused once the pair was back on screen.
            if let pair = splitPair, let old, pair.contains(old.id), !pair.contains(selectedID),
               let partner = otherPane(of: old), partner !== selectedTab, !partner.isAsleep,
               !WebKitExtras.isPictureInPictureActive(partner.webView),
               PerformanceCenter.shared.pausesBackgroundMedia || !partner.isPlayingAudio {
                partner.webView.setAllMediaPlaybackSuspended(true)
            }
            if let pair = splitPair, let tab = selectedTab, pair.contains(tab.id), !(old.map { pair.contains($0.id) } ?? false),
               let partner = otherPane(of: tab), !partner.isAsleep {
                partner.webView.setAllMediaPlaybackSuspended(false)
            }
            if let tab = selectedTab, tab.crashed, tab.crashedWhileHidden { tab.recoverFromCrash() }
            // Keyboard focus follows to the new tab's page (Space and the arrow keys scrolled the old
            // page, or nothing), unless you're typing somewhere such as the address bar.
            if let tab = selectedTab, tab !== old, !tab.isBlank {
                DispatchQueue.main.async { [weak self, weak tab] in
                    guard let self, let tab, self.selectedTab === tab, let window = tab.webView.window else { return }
                    let current = window.firstResponder
                    if current == nil || current === window || current is WKWebView {
                        window.makeFirstResponder(tab.webView)
                    }
                }
            }
            if let tab = selectedTab, tab !== old { ExtensionEvents.activated(tab, previous: old) }
            if selectedTab !== old { PerformanceCenter.shared.tabSwitched(); scheduleSessionSave() }
        }
    }
    private var sleepTimer: Timer?
    /// A Stealth window's closed tabs, for Reopen Closed Tab: in memory only, gone with the window.
    private var privateClosed: [URL] = []
    /// The profile of the Orbit this window is showing (nil = the default profile). Its history
    /// and bookmarks are the ones this window shows and adds to.
    var profileID: UUID? { isPrivate ? nil : SpaceStore.shared.space(spaceID)?.profile }
    var history: HistoryStore { .store(for: profileID) }
    var bookmarks: BookmarkStore { .store(for: profileID) }

    /// The last tab opened in the background, and the tab it was opened from (see newTab).
    private var lastBackgroundTab: (opener: UUID, tab: UUID)?
    /// The Space this window is showing; only its tabs appear in the tab bar.
    @Published private(set) var spaceID: UUID = SpaceStore.shared.defaultSpace.id
    /// The tab you last had open in each Space, to go back to when you switch.
    private var lastSelected: [UUID: UUID] = [:]

    /// The tabs in the tab bar: this Space's (private windows have no Spaces).
    var visibleTabs: [BrowserTab] {
        isPrivate ? tabs : tabs.filter { $0.spaceID == spaceID }
    }

    /// Where new tabs in this window keep their cookies: the current Space's profile.
    var currentStore: WKWebsiteDataStore {
        isPrivate ? dataStore : SpaceStore.shared.dataStore(forSpace: spaceID)
    }

    /// Shows another Space: its tabs replace the tab bar, and the tab you last used there is selected.
    func switchSpace(to id: UUID) {
        guard !isPrivate, id != spaceID, SpaceStore.shared.space(id) != nil else { return }
        FeatureUsage.mark(.orbits)
        if let current = selectedID { lastSelected[spaceID] = current }
        closeSplit()   // (pauses the side that goes out of sight)
        spaceID = id
        releaseDocksFromOtherProfiles()
        let mine = visibleTabs
        if let remembered = lastSelected[id], mine.contains(where: { $0.id == remembered }) {
            selectedID = remembered
        } else if let first = mine.first(where: { !$0.isPinned }) ?? mine.first {
            selectedID = first.id
        } else {
            newTab(focus: true)
        }
        UserDefaults.standard.set(id.uuidString, forKey: "lastSpace")
        scheduleSessionSave()
    }

    func switchSpace(by offset: Int) {
        let spaces = SpaceStore.shared.spaces
        guard spaces.count > 1, let index = spaces.firstIndex(where: { $0.id == spaceID }) else { return }
        switchSpace(to: spaces[(index + offset + spaces.count) % spaces.count].id)
    }

    /// Moves a tab to another Space. If that Space uses a different profile, the page reopens
    /// there (a page can't change which cookies it uses while open).
    func move(_ tab: BrowserTab, toSpace id: UUID) {
        guard !isPrivate, tab.spaceID != id, SpaceStore.shared.space(id) != nil else { return }
        let target = SpaceStore.shared.dataStore(forSpace: id)
        if splitPair?.contains(tab.id) == true { splitPair = nil }
        if target === tab.webView.configuration.websiteDataStore {
            tab.spaceID = id
            if tab.id == selectedID { selectFallback(near: tab) }
            objectWillChange.send()
        } else {
            let copy = BrowserTab(model: self, store: target)
            copy.spaceID = id
            copy.isPinned = tab.isPinned
            if let url = tab.url { copy.restoreLazily(url) }
            if let index = tabs.firstIndex(where: { $0 === tab }) { tabs.insert(copy, at: index + 1) }
            ExtensionEvents.opened(copy)
            close(tab, remember: false)
        }
        scheduleSessionSave()
    }

    /// After a Space's profile changes, its open tabs reopen with the new profile's cookies.
    func spaceChangedProfile(_ id: UUID) {
        guard !isPrivate else { return }
        let target = SpaceStore.shared.dataStore(forSpace: id)
        for tab in tabs where tab.spaceID == id && (!tab.hasPageView || tab.webView.configuration.websiteDataStore !== target) {
            guard let index = tabs.firstIndex(where: { $0 === tab }) else { continue }
            let copy = BrowserTab(model: self, store: target)
            copy.spaceID = id
            copy.isPinned = tab.isPinned
            let wasSelected = tab.id == selectedID
            if splitPair?.contains(tab.id) == true { splitPair = nil }
            ExtensionEvents.closed(tab)
            tab.tearDown()
            tabs[index] = copy
            ExtensionEvents.opened(copy)
            if let url = tab.url { if wasSelected { copy.load(url) } else { copy.restoreLazily(url) } }
            if wasSelected { selectedID = copy.id }
        }
        releaseDocksFromOtherProfiles()
        scheduleSessionSave()
    }

    /// A removed Space's tabs join the first Space.
    func spaceRemoved(_ id: UUID) {
        let fallback = SpaceStore.shared.defaultSpace.id
        let target = SpaceStore.shared.dataStore(forSpace: fallback)
        let wasShowing = spaceID == id
        for tab in tabs where tab.spaceID == id {
            if tab.webView.configuration.websiteDataStore === target {
                tab.spaceID = fallback
            } else {
                tab.spaceID = id   // reopened below with the right cookies
            }
        }
        // Tabs from a profile the first Space doesn't use reopen there.
        for tab in tabs where tab.spaceID == id {
            guard let index = tabs.firstIndex(where: { $0 === tab }) else { continue }
            let copy = BrowserTab(model: self, store: target)
            copy.spaceID = fallback
            copy.isPinned = tab.isPinned   // pinned tabs stay pinned
            if let url = tab.url { copy.restoreLazily(url) }
            if splitPair?.contains(tab.id) == true { splitPair = nil }
            ExtensionEvents.closed(tab)
            tab.tearDown()
            tabs[index] = copy
            ExtensionEvents.opened(copy)
            if selectedID == tab.id { selectedID = copy.id }
        }
        if wasShowing {
            spaceID = fallback
            if !visibleTabs.contains(where: { $0.id == selectedID }) {
                if let first = visibleTabs.first { selectedID = first.id } else { newTab(focus: true) }
            }
            selectedTab?.wakeIfNeeded()
        }
        releaseDocksFromOtherProfiles()
        objectWillChange.send()
        scheduleSessionSave()
    }

    /// Picks the tab beside one that's leaving this Space.
    private func selectFallback(near tab: BrowserTab) {
        let mine = visibleTabs.filter { $0 !== tab }
        if let next = mine.first(where: { !$0.isPinned }) ?? mine.first { selectedID = next.id } else { newTab(focus: true) }
    }
    /// Whether the Command Palette (⌘K) is showing.
    @Published var paletteOpen = false
    /// Bumped to ask the address bar to take keyboard focus.
    @Published var addressFocusToken = 0
    /// The window showing this model (set by the view once it's on screen).
    weak var window: NSWindow?
    /// Set as its window closes (the model can linger a moment after): its tabs are no longer
    /// part of the session.
    var windowClosed = false

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
        // Pages kept for an instant Back (each a page held in memory) go once a tab has sat in
        // the background for five minutes, even with tab sleeping off: they were kept for good.
        for tab in tabs where tab !== selectedTab && !(splitPair?.contains(tab.id) ?? false)
            && tab.hasParkedPages && Date().timeIntervalSince(tab.lastActive) > 300 {
            tab.dropParkedPages()
        }
        // The same for the earlier pages WebKit itself keeps whole in each tab for an instant
        // Back: once a tab has been left alone for five minutes they go (once per idle spell).
        for tab in tabs where tab !== selectedTab && !(splitPair?.contains(tab.id) ?? false)
            && !tab.isAsleep && !tab.backCacheReleased && Date().timeIntervalSince(tab.lastActive) > 300 {
            tab.backCacheReleased = true
            WebKitExtras.clearBackForwardCache(tab.webView)
        }
        let minutes = PerformanceCenter.shared.sleepMinutes   // shorter in Power Saver
        guard minutes > 0 else { return }
        sleepBackgroundTabs(idleFor: minutes * 60)
        // Big pages (a web app, a map: 250 MB or more at the last measure) sleep after five idle
        // minutes whatever the chosen time: one of them frees as much as several articles, and
        // pointing at the tab wakes it again before you click.
        let heavy = PerformanceCenter.shared.heavyTabIDs
        if !heavy.isEmpty, minutes * 60 > 300 { sleepBackgroundTabs(idleFor: 300, only: heavy) }
    }

    /// Sleeps background tabs idle for at least `seconds`, unless they're playing media
    /// or using the camera or microphone.
    func sleepBackgroundTabs(idleFor seconds: TimeInterval, only: Set<UUID>? = nil) {
        // The other side of Split View is on screen too: never put it to sleep.
        let visible = splitPair.flatMap { $0.contains(selectedID) ? $0 : nil }
        for tab in tabs where tab !== selectedTab && !(visible?.contains(tab.id) ?? false) && !tab.isAsleep && !tab.isLoading
            && (only?.contains(tab.id) ?? true)
            && Date().timeIntervalSince(tab.lastActive) >= seconds
            && tab.webView.cameraCaptureState == .none && tab.webView.microphoneCaptureState == .none
            && !WebKitExtras.isPictureInPictureActive(tab.webView) {   // its floating video is still on screen
            tab.webView.requestMediaPlaybackState { [weak self, weak tab] state in
                // The answer comes a moment later: by then you may have switched to this tab (or
                // its Split View partner), which used to be put to sleep under you.
                guard let self, let tab, tab !== self.selectedTab, !tab.isAsleep,
                      !(self.splitPair.map { $0.contains(tab.id) && $0.contains(self.selectedID) } ?? false) else { return }
                // "Suspended" is the silent video Ufolio pauses in background tabs itself: those tabs
                // can sleep too (they never did). With background sound paused as well, a suspended
                // tab might be your podcast, so it's left alone.
                let suspendedSilently = state == .suspended && !PerformanceCenter.shared.pausesBackgroundMedia
                if state == .none || state == .paused || suspendedSilently { tab.sleep() }
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
    /// Whether the Bookmarks & History sidebar is showing.
    /// Whether the Bookmarks & History sidebar is out. It lives in its own small object so that
    /// opening or closing it only redraws the sidebar and its button, not the whole window.
    final class SidebarState: ObservableObject {
        @Published var open = UserDefaults.standard.bool(forKey: "sidebar.open") {
            didSet {
                if open != oldValue { UserDefaults.standard.set(open, forKey: "sidebar.open") }
                if open { FeatureUsage.mark(.sidebar) }
            }
        }
    }
    let sidebar = SidebarState()
    var sidebarOpen: Bool {
        get { sidebar.open }
        set { if sidebar.open != newValue { sidebar.open = newValue } }
    }
    /// Split View: the two tabs shown side by side, and how much room the left one gets.
    @Published var splitPair: SplitPair?
    /// Link preview: a page opened in a floating card over this one (⌥-click a link), not yet a tab.
    @Published private(set) var preview: BrowserTab?
    /// Docked sites: which panel is open, and the pages of those opened so far (kept loaded).
    @Published var dockOpen: UUID?
    var dockTabs: [UUID: BrowserTab] = [:]
    @Published var splitRatio: CGFloat = 0.5

    func isInSplit(_ tab: BrowserTab) -> Bool { splitPair?.contains(tab.id) ?? false }

    /// "Open links in the other pane" (off by default, from the split view controls): a link
    /// clicked on one side opens on the other, for a list on one side and reading on the other.
    @Published var splitLinksAcross = false

    /// The tab on the other side of Split View.
    func otherPane(of tab: BrowserTab) -> BrowserTab? {
        guard let pair = splitPair, pair.contains(tab.id) else { return nil }
        let other = pair.left == tab.id ? pair.right : pair.left
        return tabs.first { $0.id == other }
    }

    /// Shows a tab beside the current one. Splitting the current tab itself opens a new tab beside it.
    func openSplit(with tab: BrowserTab? = nil) {
        guard let current = selectedTab else { return }
        FeatureUsage.mark(.split)
        if let tab, tab !== current {
            splitPair = SplitPair(left: current.id, right: tab.id)
            tab.wakeIfNeeded()
            // It's on screen now: video paused when you left it plays again.
            if !tab.isAsleep { tab.webView.setAllMediaPlaybackSuspended(false) }
        } else {
            let fresh = newTab(select: false, usePreferredPage: true)
            splitPair = SplitPair(left: current.id, right: fresh.id)
            selectedID = fresh.id
            if fresh.url == nil { focusAddressBar() }
        }
    }

    /// Leaves Split View, showing the given tab (or the active one).
    func closeSplit(keeping id: UUID? = nil) {
        guard let pair = splitPair else { return }
        let shown = id ?? selectedID
        splitPair = nil
        splitLinksAcross = false
        if let id { selectedID = id }
        // The side that goes out of sight is treated as a tab you've left: its idle clock starts
        // and its silent video stops (it used to keep playing unseen, and could stay awake for
        // as long as it had sat in the pair).
        if let hidden = tabs.first(where: { $0.id == (pair.left == shown ? pair.right : pair.left) }),
           hidden !== selectedTab, !hidden.isAsleep {
            hidden.lastActive = Date()
            hidden.capturePreview()
            if !WebKitExtras.isPictureInPictureActive(hidden.webView),
               PerformanceCenter.shared.pausesBackgroundMedia || !hidden.isPlayingAudio {
                hidden.webView.setAllMediaPlaybackSuspended(true)
            }
        }
    }

    func swapSplit() {
        guard let pair = splitPair else { return }
        splitPair = SplitPair(left: pair.right, right: pair.left)
    }
    private var audioTimer: Timer?
    private var prewake: DispatchWorkItem?
    private var keyObserver: NSObjectProtocol?

    init(isPrivate: Bool = false) {
        LaunchTimer.mark("window model")
        defer { LaunchTimer.mark("window model done") }
        LiveCount.change(\.windows, by: 1)
        self.isPrivate = isPrivate
        dataStore = isPrivate ? .nonPersistent() : .default()
        super.init()
        BrowserModel.all.add(self)
        if isPrivate { FeatureUsage.mark(.stealth); StealthDays.recordToday() }
        // Which tabs are playing sound (for the speaker button on tabs).
        Self.watchMiddleClicks()   // middle-click on tabs, and the mouse's Back/Forward buttons
        // Coming back to the window: the tab in front (and its Split View partner) never stays with
        // its video held paused.
        keyObserver = NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { [weak self] note in
            guard let self, (note.object as? NSWindow) === self.window else { return }
            self.selectedTab?.ensureMediaRunning()
            if let tab = self.selectedTab, let other = self.otherPane(of: tab), self.splitPair?.contains(tab.id) == true { other.ensureMediaRunning() }
        }
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
            let savedSpaces = UserDefaults.standard.stringArray(forKey: "lastSessionSpaces") ?? []
            if let last = UserDefaults.standard.string(forKey: "lastSpace").flatMap(UUID.init(uuidString:)),
               SpaceStore.shared.space(last) != nil { spaceID = last }
            // Only web pages come back, and only the first loads now: the rest wait until you
            // click them, so launching with lots of tabs stays quick.
            // You come back to the tab you were on (it used to be the first tab every time).
            let wanted = UserDefaults.standard.object(forKey: "lastSessionSelected") as? Int
            var restored: [Int: BrowserTab] = [:]
            // Up to 500 (they wait unloaded): the limit used to be 200, so anyone with more lost
            // the rest at the next launch, and the next save made that permanent.
            for (index, text) in saved.prefix(500).enumerated() {
                guard let url = URL(string: text), ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { continue }
                let space = savedSpaces.indices.contains(index)
                    ? UUID(uuidString: savedSpaces[index]).flatMap { SpaceStore.shared.space($0)?.id } : nil
                restored[index] = addRestoredTab(url, space: space ?? SpaceStore.shared.defaultSpace.id)
            }
            // Only that tab loads now (selecting wakes it); the rest wait until you click them.
            if let wanted, let tab = restored[wanted], tab.spaceID == spaceID {
                selectedID = tab.id
            } else {
                selectedID = restored.sorted { $0.key < $1.key }.map(\.value).first { $0.spaceID == spaceID }?.id ?? visibleTabs.first?.id
            }
        }
        // Pinned tabs always come back, at the left, loading when you click them.
        // (Also when the window is closed and opened again: they used to be missing until Ufolio restarted.)
        if !isPrivate {
            let pinnedText = (UserDefaults.standard.stringArray(forKey: "pinnedTabs") ?? []).prefix(30)
            let pinnedSpaces = UserDefaults.standard.stringArray(forKey: "pinnedTabSpaces") ?? []
            var placed: [BrowserTab] = []
            for (index, text) in pinnedText.enumerated() {
                guard let url = URL(string: text), ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { continue }
                let space = (pinnedSpaces.indices.contains(index)
                    ? UUID(uuidString: pinnedSpaces[index]).flatMap { SpaceStore.shared.space($0)?.id } : nil)
                    ?? SpaceStore.shared.defaultSpace.id
                if let existing = tabs.first(where: { $0.url == url && !$0.isPinned && $0.spaceID == space }) {
                    existing.isPinned = true
                    placed.append(existing)
                } else {
                    let tab = addRestoredTab(url, space: space)
                    tab.isPinned = true
                    placed.append(tab)
                }
            }
            if !placed.isEmpty { tabs = placed + tabs.filter { !$0.isPinned } }
        }
        if !isPrivate, !Self.didRestoreSession { SpeedBenchmark.startIfAsked(in: self); LeakTest.startIfAsked(in: self); AutofillTest.startIfAsked(in: self); ShieldSnapshot.startIfAsked(in: self); BackgroundPlayTest.startIfAsked(in: self); EvalTest.startIfAsked(in: self) }
        if !isPrivate { EvalTest.startIfAsked(in: self); SwitchTest.startIfAsked(in: self); SpeedBenchmark.prefetchTestIfAsked(in: self); ChaosTest.startIfAsked(in: self) }   // (testing only; also after restoring tabs)
        if !isPrivate { Self.didRestoreSession = true }
        if visibleTabs.allSatisfy(\.isPinned) {
            // A new window opens the homepage if Settings › General says so.
            if let home = NewTabPage.windowURL { newTab(url: home) } else { newTab(focus: true, usePreferredPage: false) }
        }
    }

    /// A tab from last time, waiting to load until you click it.
    private func addRestoredTab(_ url: URL, space: UUID) -> BrowserTab {
        let tab = BrowserTab(model: self, store: SpaceStore.shared.dataStore(forSpace: space), waiting: true)
        tab.spaceID = space
        tab.restoreLazily(url)
        tabs.append(tab)
        ExtensionEvents.opened(tab)
        return tab
    }

    deinit {
        LiveCount.change(\.windows, by: -1)
        // The last Stealth window gone: its downloads leave the list too (the files stay in your
        // Downloads folder, as the Stealth page says; they used to stay listed until Ufolio quit).
        if isPrivate {
            DispatchQueue.main.async {
                // The last Stealth window gone: its downloads leave the list, and every answer given
                // in Stealth goes (they used to last until Ufolio quit): Force Field switched off for
                // a site, site settings, hidden elements, look-alike and permission answers.
                guard !BrowserModel.all.allObjects.contains(where: { $0.isPrivate }) else { return }
                Downloads.shared.forgetPrivateItems()
                ContentBlocker.shared.stealthEnded()
                ShieldSettings.shared.stealthEnded()
                ElementZapper.shared.stealthEnded()
                Lookalike.stealthEnded()
                SitePermissions.shared.stealthEnded()
            }
        }
        // A closed window's timers stop with it.
        sleepTimer?.invalidate()
        audioTimer?.invalidate()
        if let keyObserver { NotificationCenter.default.removeObserver(keyObserver) }
    }

    /// Remembers this window's open pages (for "Tabs from last time").
    /// Writes any waiting session save straight away (as Ufolio quits).
    func saveSessionNow() {
        guard let pending = sessionSave, !pending.isCancelled else { return }
        sessionSave = nil
        pending.perform()
        pending.cancel()   // so the scheduled copy doesn't run again
    }

    func scheduleSessionSave() {
        guard !isPrivate else { return }
        sessionSave?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let pinned = self.tabs.filter { $0.url != nil && $0.isPinned }
            // Every open window's tabs, this one's first: each window used to overwrite the
            // others', so with two windows open only one window's tabs came back next launch.
            // Minimised windows, and windows while Ufolio is hidden (⌘H), count too: they aren't
            // "visible", so their tabs used to be left out and were gone at the next launch.
            let others = BrowserModel.all.allObjects.filter { model in
                guard model !== self, !model.isPrivate, !model.windowClosed, let window = model.window else { return false }
                return window.isVisible || window.isMiniaturized || NSApp.isHidden
            }
            let saved = ([self] + others).flatMap { model in model.tabs.filter { $0.url != nil && !(model !== self && $0.isPinned) } }
            let d = UserDefaults.standard
            d.set(pinned.compactMap { $0.url?.absoluteString }, forKey: "pinnedTabs")
            d.set(pinned.map { $0.spaceID?.uuidString ?? "" }, forKey: "pinnedTabSpaces")
            // Closing the last tab closes the window; keep that window's pages for next launch.
            guard !saved.isEmpty else { return }
            d.set(saved.compactMap { $0.url?.absoluteString }, forKey: "lastSession")
            d.set(saved.map { $0.spaceID?.uuidString ?? "" }, forKey: "lastSessionSpaces")
            // The tab you were on, so it's the one you come back to.
            if let index = saved.firstIndex(where: { $0 === self.selectedTab }) { d.set(index, forKey: "lastSessionSelected") }
        }
        sessionSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work)
    }

    var selectedTab: BrowserTab? {
        tabs.first { $0.id == selectedID } ?? visibleTabs.first ?? tabs.first
    }

    @discardableResult
    func newTab(url: URL? = nil, configuration: WKWebViewConfiguration? = nil,
                select: Bool = true, focus: Bool = false, usePreferredPage: Bool = true, atEnd: Bool = false) -> BrowserTab {
        let tab = BrowserTab(model: self, configuration: configuration, store: currentStore)
        tab.spaceID = isPrivate ? nil : spaceID
        defer { ExtensionEvents.opened(tab) }
        if !atEnd, let current = selectedTab, let index = tabs.firstIndex(where: { $0 === current }) {
            // New tabs go after the current one, but never in among the pinned tabs. Several opened
            // in the background from the same tab line up in the order you opened them (each one
            // used to go straight after the current tab, so they came out backwards).
            var position = max(index + 1, tabs.filter(\.isPinned).count)
            if !select, let last = lastBackgroundTab, last.opener == current.id,
               let lastIndex = tabs.firstIndex(where: { $0.id == last.tab }) {
                position = max(position, lastIndex + 1)
            }
            tabs.insert(tab, at: min(position, tabs.count))
            lastBackgroundTab = select ? nil : (current.id, tab.id)
        } else {
            tabs.append(tab)
        }
        if select { selectedID = tab.id } else {
            // Opened in the background (⌘-click, Open Link in Background Tab, Open All): its sound
            // and video wait until you switch to it, as in Safari (a page you open counts as you
            // asking for its video, so it could otherwise start playing out of sight).
            if ProcessInfo.processInfo.environment["UFOLIO_BG_NOHOLD"] == nil { tab.webView.setAllMediaPlaybackSuspended(true) }
        }
        // A plain new tab opens the homepage if one is set in Settings.
        let page = url ?? (configuration == nil && usePreferredPage ? NewTabPage.url : nil)
        if let page { tab.load(page) }
        if focus && page == nil { focusAddressBar() }
        return tab
    }

    func close(_ tab: BrowserTab, remember: Bool = true) {
        guard let index = tabs.firstIndex(where: { $0 === tab }) else { return }
        let wasSelected = tab.id == selectedTab?.id
        let visibleIndex = visibleTabs.firstIndex(where: { $0 === tab }) ?? 0
        // Closing one side of Split View shows the other on its own.
        var partner: UUID?
        if let pair = splitPair, pair.contains(tab.id) {
            partner = pair.left == tab.id ? pair.right : pair.left
            splitPair = nil
        }
        if remember, !isPrivate, let url = tab.url { RecentlyClosed.shared.add(title: tab.title, url: url, profile: tab.profileID) }
        if remember, isPrivate, let url = tab.url { privateClosed.append(url); if privateClosed.count > 20 { privateClosed.removeFirst() } }
        ExtensionEvents.closed(tab)
        tab.tearDown()
        Speed.trimSoon()
        tabs.remove(at: index)
        scheduleSessionSave()
        if tabs.isEmpty {
            // Keep a fresh tab ready in case the window is shown again (it should never be empty).
            newTab(usePreferredPage: false)
            (window ?? NSApp.keyWindow)?.performClose(nil)
            return
        }
        if wasSelected {
            let mine = visibleTabs
            if let partner, tabs.contains(where: { $0.id == partner }) {
                selectedID = partner
            } else if !mine.isEmpty {
                selectedID = mine[min(visibleIndex, mine.count - 1)].id
            } else {
                // The last tab in this Space: start a fresh one here rather than closing the window.
                newTab(focus: true)
            }
        }
    }

    /// Brings back the most recently closed tab (or a chosen one).
    func reopenClosedTab(_ closed: ClosedTab? = nil) {
        // A Stealth window reopens its own closed tabs (it used to bring back one closed in a
        // normal window).
        if isPrivate, closed == nil {
            guard let url = privateClosed.popLast() else { return }
            if let current = selectedTab, current.isBlank { current.load(url) } else { newTab(url: url) }
            return
        }
        // Only this profile's closed tabs: a tab closed in another profile used to come back here,
        // without that profile's sign-ins.
        guard let tab = RecentlyClosed.shared.take(closed, profile: profileID) else { return }
        if let current = selectedTab, current.isBlank {
            current.load(tab.url)
        } else {
            newTab(url: tab.url)
        }
    }

    /// A window always has a tab in the Space it's showing; adds a new one if it somehow hasn't.
    func ensureTab() {
        if visibleTabs.isEmpty { newTab(focus: true) }
        else if !visibleTabs.contains(where: { $0.id == selectedID }) { selectedID = visibleTabs.first?.id }
    }

    // MARK: Middle-click to close

    /// The tab the pointer is over in the tab bar, if any (not published: nothing redraws for it).
    private(set) var tabUnderPointer: UUID?

    func pointerOverTab(_ tab: BrowserTab, _ inside: Bool) {
        if inside { tabUnderPointer = tab.id } else if tabUnderPointer == tab.id { tabUnderPointer = nil }
        Self.watchMiddleClicks()
        wakeWhenPointedAt(tab, inside)
    }

    /// A sleeping tab starts waking as soon as you rest the pointer on it, so it's ready (or
    /// nearly) by the time you click: tabs can sleep, and give their memory back, without you
    /// ever waiting for one. Only after a short pause on it (passing over tabs wakes nothing),
    /// never in Low Power Mode, and its sound and video stay paused until you switch to it.
    private func wakeWhenPointedAt(_ tab: BrowserTab, _ inside: Bool) {
        prewake?.cancel()
        prewake = nil
        guard inside, tab.isAsleep, tab.url != nil, tab !== selectedTab,
              !ProcessInfo.processInfo.isLowPowerModeEnabled else { return }
        let work = DispatchWorkItem { [weak self, weak tab] in
            guard let self, let tab, self.tabUnderPointer == tab.id, tab.isAsleep, tab !== self.selectedTab else { return }
            tab.wakeIfNeeded()
            if !tab.isAsleep, tab !== self.selectedTab { tab.webView.setAllMediaPlaybackSuspended(true) }
        }
        prewake = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: work)
    }

    /// A middle-click (the scroll wheel pressed) on a tab closes it, as in other browsers. One
    /// listener for the whole app; clicks anywhere but on a tab carry on as normal.
    private static var middleClickMonitor: Any?
    private static func watchMiddleClicks() {
        guard middleClickMonitor == nil else { return }
        middleClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.otherMouseDown, .otherMouseUp]) { event in
            // A mouse's Back and Forward buttons anywhere in a browser window (the tab bar, sidebar,
            // toolbar…), not just over the page, which handles them itself.
            if event.buttonNumber == 3 || event.buttonNumber == 4,
               let model = BrowserModel.all.allObjects.first(where: { $0.window === event.window }),
               let content = event.window?.contentView {
                let hit = content.hitTest(content.convert(event.locationInWindow, from: nil))
                var node = hit
                while let view = node, !(view is WKWebView) { node = view.superview }
                guard node == nil else { return event }   // over the page
                if event.type == .otherMouseUp {
                    if event.buttonNumber == 3 { model.selectedTab?.goBack() } else { model.selectedTab?.goForward() }
                }
                return nil
            }
            guard event.buttonNumber == 2,
                  let model = BrowserModel.all.allObjects.first(where: { $0.window === event.window }),
                  let id = model.tabUnderPointer, let tab = model.tabs.first(where: { $0.id == id }) else { return event }
            if event.type == .otherMouseUp {
                model.tabUnderPointer = nil
                if !tab.isPinned { model.close(tab) }
            }
            return nil
        }
    }

    func closeSelectedTab() {
        // A Link preview on top closes first (⌘W used to close the tab underneath it).
        if preview != nil { closePreview(); return }
        guard let tab = selectedTab else { return }
        // ⌘W on a pinned tab leaves it pinned and moves to a normal tab, as in Safari (a stray ⌘W
        // used to lose it; its right-click menu still closes it).
        if tab.isPinned {
            if let other = visibleTabs.first(where: { !$0.isPinned }) { selectedID = other.id } else { newTab(focus: true) }
            return
        }
        close(tab)
    }

    /// Moves a tab to a new position in the tab bar (drag to reorder).
    /// Positions are in the tab bar (this Space's tabs).
    func moveTab(from source: Int, to destination: Int) {
        let mine = visibleTabs
        guard mine.indices.contains(source), mine.indices.contains(destination), source != destination,
              mine[source].isPinned == mine[destination].isPinned,   // pinned tabs stay together
              let from = tabs.firstIndex(where: { $0 === mine[source] }),
              let to = tabs.firstIndex(where: { $0 === mine[destination] }) else { return }
        let tab = tabs.remove(at: from)
        tabs.insert(tab, at: to)
        ExtensionEvents.moved(tab, from: from, in: self)
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

    /// ⌘1–⌘8: that tab in the tab bar (this Orbit's), ⌘9 (number 0): the last one.
    func selectTab(number: Int) {
        let mine = visibleTabs
        guard !mine.isEmpty else { return }
        let tab = number == 0 ? mine[mine.count - 1] : (number <= mine.count ? mine[number - 1] : nil)
        if let tab, tab.id != selectedID { selectedID = tab.id }
    }

    func selectAdjacentTab(_ offset: Int) {
        let mine = visibleTabs
        guard mine.count > 1, let current = selectedTab,
              let index = mine.firstIndex(where: { $0 === current }) else { return }
        selectedID = mine[(index + offset + mine.count) % mine.count].id
    }

    /// The window's address field (set by the field itself), so focusing it is direct.
    weak var addressField: NSTextField?

    /// Puts the cursor in the address bar, ready to type. A brand-new tab's bar may still be
    /// settling, so it checks it really got the cursor and tries again for a moment if not.
    func focusAddressBar() {
        addressFocusToken += 1   // (tabs down the side, icons only: opens the Command Palette instead)
        func attempt(_ tries: Int) {
            DispatchQueue.main.asyncAfter(deadline: .now() + (tries == 0 ? 0 : 0.05)) { [weak self] in
                guard let self else { return }
                if let field = self.addressField, let window = field.window, field.currentEditor() == nil {
                    window.makeFirstResponder(field)
                }
                if self.addressField?.currentEditor() == nil, tries < 8 { attempt(tries + 1) }
            }
        }
        attempt(0)
    }

    /// Opens a URL in the current tab, or a new background tab when ⌘ is held.
    func open(_ url: URL, inNewTab: Bool = false) {
        if inNewTab || selectedTab == nil {
            newTab(url: url, select: !inNewTab)
        } else {
            selectedTab?.load(url)
        }
    }

    /// Opens several pages as tabs (Open All in Tabs): the first loads now, the rest wait until
    /// you click them, like tabs restored from last time. Opening a folder of hundreds used to
    /// start hundreds of pages loading at once.
    func openAll(_ urls: [URL]) {
        for (index, url) in urls.prefix(200).enumerated() {
            if index == 0 {
                newTab(url: url, select: false, atEnd: true)
            } else {
                let tab = newTab(select: false, usePreferredPage: false, atEnd: true)
                tab.restoreLazily(url)
            }
        }
    }

    // MARK: Link preview

    /// Opens a link in the floating preview (from the tab it was clicked in, with its sign-ins).
    func showPreview(_ url: URL, from source: BrowserTab?) {
        let store = source?.webView.configuration.websiteDataStore ?? currentStore
        let tab = BrowserTab(model: self, store: store)
        present(preview: tab, from: source)
        tab.load(url)
    }

    /// The preview for a link WebKit is opening itself (right-click › Preview Link).
    func showPreview(configuration: WKWebViewConfiguration, from source: BrowserTab?) -> BrowserTab {
        let tab = BrowserTab(model: self, configuration: configuration)
        present(preview: tab, from: source)
        return tab
    }

    private func present(preview tab: BrowserTab, from source: BrowserTab?) {
        closePreview()
        FeatureUsage.mark(.linkPreview)
        tab.spaceID = source?.spaceID ?? spaceID
        (tab.webView as? HushWebView)?.ignoresBlockers = true   // it sits on top of the page
        preview = tab
    }

    func closePreview() {
        guard let tab = preview else { return }
        preview = nil
        tab.tearDown()
    }

    /// The preview becomes a real tab beside the one it came from (or opens beside it in Split View).
    func expandPreview(split: Bool = false) {
        guard let tab = preview else { return }
        preview = nil
        (tab.webView as? HushWebView)?.ignoresBlockers = false
        let index = selectedTab.flatMap { current in tabs.firstIndex { $0 === current } }.map { $0 + 1 } ?? tabs.count
        tabs.insert(tab, at: min(index, tabs.count))
        ExtensionEvents.opened(tab)
        if split { openSplit(with: tab) } else { selectedID = tab.id }
        scheduleSessionSave()
    }

    /// ⌘D, the star and the menus: a page already bookmarked is removed straight away; a new
    /// one asks what to call it first (its title, ready to change).
    func toggleBookmarkForSelectedTab() {
        guard let tab = selectedTab, let url = tab.url else { return }
        let store = BookmarkStore.store(for: tab.profileID)
        if store.contains(url) { store.toggle(url: url, title: tab.displayTitle); return }
        guard !DialogHost.isBusy(window) else { return }
        let name = BookmarkName(tab.displayTitle)
        DialogHost.show(HushDialog(
            art: .site(url), theme: .save, motion: .rise,
            title: "Add Bookmark",
            detail: AnyView(BookmarkNameField(name: name)),
            choices: [.init(title: "Cancel", role: .cancel), .init(title: "Save", role: .primary)],
            completion: { choice, _ in if choice == 1 { store.add(url: url, title: name.text) } }), in: window)
    }
}

/// The name being typed for a new bookmark.
final class BookmarkName: ObservableObject {
    @Published var text: String
    init(_ text: String) { self.text = text }
}

/// The name field in the Add Bookmark card: filled with the page's title, selected and ready to type over.
struct BookmarkNameField: View {
    @ObservedObject var name: BookmarkName
    @FocusState private var focused: Bool

    var body: some View {
        TextField("Name", text: $name.text)
            .textFieldStyle(.roundedBorder)
            .focused($focused)
            .frame(maxWidth: .infinity)
            .padding(.top, 2)
            .onAppear { DispatchQueue.main.async { focused = true } }
    }
}
