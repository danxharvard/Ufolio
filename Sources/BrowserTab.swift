import SwiftUI
import WebKit
import Combine

/// One tab: a WKWebView plus the bits of its state the UI shows.
final class BrowserTab: NSObject, ObservableObject, Identifiable {
    let id = UUID()
    private(set) var webView: WKWebView
    weak var model: BrowserModel?

    @Published private(set) var title = ""
    @Published private(set) var url: URL?
    @Published private(set) var isLoading = false
    @Published private(set) var progress: Double = 0
    @Published private(set) var canGoBack = false
    @Published private(set) var canGoForward = false
    @Published private(set) var isSecure = false
    /// Ads and trackers blocked on the current page.
    @Published private(set) var blockedOnPage = 0
    /// Blocked things not yet shown (see scheduleBlockedFlush).
    private var pendingBlocked = 0, pendingAds = 0, pendingTrackers = 0
    private var pendingSites: [String: Int] = [:]
    private var flushScheduled = false

    private func resetBlockedCounts() {
        pendingBlocked = 0; pendingAds = 0; pendingTrackers = 0; pendingSites = [:]
        if blockedOnPage != 0 { blockedOnPage = 0 }
        if adsOnPage != 0 { adsOnPage = 0 }
        if trackersOnPage != 0 { trackersOnPage = 0 }
        if !blockedSites.isEmpty { blockedSites = [:] }
    }

    private func scheduleBlockedFlush() {
        guard !flushScheduled else { return }
        flushScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self else { return }
            self.flushScheduled = false
            guard self.pendingBlocked > 0 else { return }
            self.blockedOnPage += self.pendingBlocked
            self.adsOnPage += self.pendingAds
            self.trackersOnPage += self.pendingTrackers
            for (site, n) in self.pendingSites { self.blockedSites[site, default: 0] += n }
            self.pendingBlocked = 0; self.pendingAds = 0; self.pendingTrackers = 0; self.pendingSites = [:]
        }
    }
    @Published private(set) var adsOnPage = 0
    @Published private(set) var trackersOnPage = 0
    /// What was blocked on this page: blocked site → requests (for the Hush Guard panel).
    @Published private(set) var blockedSites: [String: Int] = [:]
    /// Set when a page was stopped because it looks like a fake copy of a site you use.
    @Published var lookalike: (match: Lookalike.Match, url: URL)?
    /// This tab's video was popped out into Picture in Picture when you switched away.
    var autoPictureInPicture = false

    /// Heavy page warning: this page has used a lot of processor (and so energy) for a while.
    @Published var isHeavy = false
    /// Frozen from the warning's "Pause Page" (until Resume, or the next page).
    @Published private(set) var isPagePaused = false
    /// Dismissed for this page.
    var heavyDismissed = false

    func pausePage(_ pause: Bool) {
        WebKitExtras.setPageSuspended(pause, webView)
        isPagePaused = pause
        if pause { isHeavy = false }
    }

    /// A link from the other Split View pane is being dragged over this one.
    @Published private(set) var isDropTarget = false
    /// Torrent site mode, on this page: pop-ups and redirects stopped, and traps marked.
    @Published private(set) var torrentPopupsBlocked = 0
    @Published private(set) var torrentTrapsMarked = 0
    /// Pages committed in this tab, and the one whose follow-up has run.
    private var commitCount = 0
    /// Pages committed so far (a page that changes address with its own code commits none).
    var pageCommits: Int { commitCount }
    private var finishedCommit: Int?
    /// When you last clicked a link to another site on a torrent site (its redirects may follow).
    private var torrentOutboundClick = Date.distantPast
    /// Quick translation: the page's language when it isn't yours, and where translation is up to.
    @Published private(set) var translation: TranslationState = .none
    @Published private(set) var pageLanguage: Locale.Language?
    /// Sound: whether the page is playing any, and whether you muted the tab.
    @Published fileprivate(set) var isPlayingAudio = false
    @Published private(set) var isMuted = false
    /// Pinned tabs sit at the left as small icons and come back next launch.
    @Published var isPinned = false
    /// The Space this tab belongs to (only that Space's tabs show in the tab bar).
    var spaceID: UUID?

    /// The profile of this tab's Orbit (nil = the default profile): where its visits are recorded.
    var profileID: UUID? { isPrivate ? nil : SpaceStore.shared.space(spaceID)?.profile }

    /// Fixed when the tab is made: a Stealth tab stays private even in the moment its window is
    /// going away (it used to count as not private then, and could write to history).
    let isPrivate: Bool

    /// Set when the page's process crashed: the tab shows a friendly Reload screen.
    @Published private(set) var crashed = false

    /// See webViewWebContentProcessDidTerminate.
    var crashedWhileHidden = false

    /// Why the last page couldn't load (no connection, no such server, a bad certificate…).
    /// Before, a failed load showed nothing at all.
    @Published var loadError: (url: URL?, message: String, insecure: URL?)?
    /// The last http:// address this tab was sent to (which HTTPS upgrade turns into https://):
    /// if the site turns out to have no https, the error page offers the insecure version.
    private var requestedHTTP: URL?

    func recoverFromCrash() {
        crashedWhileHidden = false
        crashed = false
        if let url { webView.load(URLRequest(url: url)) } else { webView.reload() }
    }

    /// JavaScript switched off for just this tab (right-click the tab).
    @Published private(set) var javaScriptOff = false

    func toggleJavaScript() {
        javaScriptOff.toggle()
        if url != nil { webView.reload() }
    }

    /// Reader: whether the page has an article, and the article while Reader is showing.
    @Published private(set) var readerAvailable = false
    @Published private(set) var reader: ReaderArticle?
    /// Whether the page has a video that can float in Picture in Picture.
    @Published private(set) var canPictureInPicture = false

    func setReaderAvailable(_ available: Bool) { if readerAvailable != available { readerAvailable = available } }
    func showReader(_ article: ReaderArticle) { reader = article }
    func toggleReader() {
        FeatureUsage.mark(.reader)
        if reader != nil { reader = nil } else if url != nil { ReaderMode.open(self) }
    }

    func toggleMute() {
        isMuted.toggle()
        WebKitExtras.setMuted(isMuted, webView)
    }

    /// The tab you're looking at never stays with its sound and video held paused (Ufolio pauses
    /// them in tabs you can't see; if a way back ever missed releasing them, a video in front
    /// wouldn't play until Ufolio restarted). Checked when you click in the page (when you'd
    /// press play) and when its window comes to the front: never on a timer, so it costs nothing
    /// while you're not using Ufolio.
    func ensureMediaRunning() {
        guard !isAsleep, !isPagePaused else { return }
        webView.requestMediaPlaybackState { [weak self] state in
            guard let self, state == .suspended, !self.isPagePaused,
                  let model = self.model, model.selectedTab === self || (model.splitPair?.contains(self.id) ?? false && model.splitPair?.contains(model.selectedID) ?? false)
            else { return }
            self.webView.setAllMediaPlaybackSuspended(false)
        }
    }

    func checkAudio() {
        guard !isAsleep else { if isPlayingAudio { isPlayingAudio = false }; return }
        let playing = WebKitExtras.isPlayingAudio(webView)
        if playing != isPlayingAudio { isPlayingAudio = playing }
        let pip = WebKitExtras.canPictureInPicture(webView)
        if pip != canPictureInPicture { canPictureInPicture = pip }
    }

    /// The website's colour, for Magic Theme (nil on the start page or while asleep).
    @Published private(set) var siteColor: NSColor?

    fileprivate func updateSiteColor() {
        guard url != nil, !isAsleep else { if siteColor != nil { siteColor = nil }; return }
        let color = (webView.themeColor ?? webView.underPageBackgroundColor)?.usingColorSpace(.sRGB)
        // Ignore see-through colours: they'd show the frame, not the site.
        let usable = (color?.alphaComponent ?? 0) > 0.9 ? color : nil
        if usable != siteColor { siteColor = usable }
    }

    func setTranslation(_ state: TranslationState, language: Locale.Language?) {
        if translation != state { translation = state }
        if pageLanguage != language { pageLanguage = language }
    }
    /// The last address loaded by the user (typed, bookmark…), as opposed to by a page.
    private var userLoadedURL: URL?
    /// JavaScript dialogs shown on this page, and whether the user silenced them.
    private var dialogsShown = 0
    private var dialogsSilenced = false

    private var observers: Set<AnyCancellable> = []

    static func makeConfiguration(privately: Bool = false, store: WKWebsiteDataStore? = nil) -> WKWebViewConfiguration {
        let config = WKWebViewConfiguration()
        // Safari's speed settings: a page process kept ready, and recent sites' processes reused.
        config.processPool = Speed.pool
        // Private windows keep cookies and site data in memory only, apart from everything else.
        config.websiteDataStore = store ?? .default()
        config.userContentController = WKUserContentController()
        config.applicationNameForUserAgent = "Version/18.0 Safari/605.1.15"
        config.preferences.isElementFullscreenEnabled = true
        config.preferences.isFraudulentWebsiteWarningEnabled = Prefs.bool(Prefs.fraudWarning)
        config.preferences.javaScriptCanOpenWindowsAutomatically = !Prefs.bool(Prefs.blockPopups)
        config.defaultWebpagePreferences.preferredContentMode = .desktop
        config.mediaTypesRequiringUserActionForPlayback = PerformanceCenter.shared.autoplayMediaTypes
        PerformanceCenter.shared.configure(config.preferences)   // Performance / Balanced / Power Saver
        if !privately { ExtensionEvents.attach(config) }   // extensions don't run in private windows
        return config
    }

    /// Re-applies the settings that live in a page's preferences (power mode, pop-ups, fraud
    /// warnings) to every open tab. They used to apply only to tabs opened after a change, so
    /// unplugging into Battery Saver, say, didn't reach the pages already open.
    static func applyLivePreferences() {
        for model in BrowserModel.all.allObjects {
            for tab in model.tabs where !tab.isAsleep {
                let preferences = tab.webView.configuration.preferences
                preferences.javaScriptCanOpenWindowsAutomatically = !Prefs.bool(Prefs.blockPopups)
                preferences.isFraudulentWebsiteWarningEnabled = Prefs.bool(Prefs.fraudWarning)
                PerformanceCenter.shared.configure(preferences)
            }
        }
    }

    deinit { LiveCount.change(\.tabs, by: -1) }

    init(model: BrowserModel, configuration: WKWebViewConfiguration? = nil, store: WKWebsiteDataStore? = nil) {
        LiveCount.change(\.tabs, by: 1)
        self.model = model
        isPrivate = model.isPrivate
        webView = HushWebView(frame: .zero, configuration: configuration
            ?? BrowserTab.makeConfiguration(privately: model.isPrivate, store: store ?? model.dataStore))
        super.init()
        setUp(webView)
    }

    /// Connects a web view to this tab: delegates, blocking, AutoFill and the state the UI shows.
    private func setUp(_ view: WKWebView) {
        view.allowsBackForwardNavigationGestures = true
        view.allowsMagnification = true
        view.navigationDelegate = self
        view.uiDelegate = self
        let zoom = Prefs.double(Prefs.defaultZoom)
        view.pageZoom = zoom > 0 ? zoom : 1
        // A muted tab's new page (after sleeping, say) is muted from the start, not once it has
        // finished loading (sound could start playing first).
        if isMuted { WebKitExtras.setMuted(true, view) }
        ContentBlocker.shared.attach(view.configuration.userContentController)
        Speed.Handler.shared.register(view.configuration.userContentController)
        AutofillCenter.shared.register(self)
        ElementZapper.shared.register(self)
        (view as? HushWebView)?.onHideElements = { [weak self] in
            guard let self else { return }
            ElementZapper.shared.start(in: self)
        }
        (view as? HushWebView)?.onSplitDrag = { [weak self] phase, info in
            self?.handleSplitDrag(phase, info) ?? false
        }
        (view as? HushWebView)?.onHistoryStep = { [weak self] back in
            if back { self?.goBack() } else { self?.goForward() }
        }
        (view as? HushWebView)?.onClick = { [weak self] in self?.ensureMediaRunning() }
        (view as? HushWebView)?.onFocus = { [weak self] in
            guard let self, let model = self.model, model.isInSplit(self), model.selectedID != self.id else { return }
            model.selectedID = self.id
        }

        observers.removeAll()
        func bind<T>(_ keyPath: KeyPath<WKWebView, T>, _ apply: @escaping (BrowserTab, T) -> Void) {
            view.publisher(for: keyPath)
                .receive(on: RunLoop.main)
                .sink { [weak self] value in if let self { apply(self, value) } }
                .store(in: &observers)
        }
        bind(\.title) { tab, title in
            // A sleeping or lazily restored tab's empty web view has no title yet; keep the saved one.
            if (tab.waking || tab.isAsleep) && (title ?? "").isEmpty { return }
            if tab.title != (title ?? "") { tab.title = title ?? "" }
            if !tab.isPrivate, let url = tab.url, let title, !title.isEmpty { HistoryStore.store(for: tab.profileID).updateTitle(url, title: title) }
        }
        bind(\.url) { tab, url in
            // While waking from sleep the new web view briefly has no address; keep the old one.
            // The same goes for a tab restored from last time, which hasn't loaded yet.
            if (tab.waking || tab.isAsleep) && url == nil { return }
            if url != nil { tab.waking = false }
            guard tab.url != url else { return }
            let previous = tab.url
            tab.url = url
            // Pages that change without reloading (YouTube videos, web apps) never "finish
            // loading", so they're added to history here. Only a real change of page counts:
            // sites that update just the "#section" as you scroll would otherwise add a visit each time.
            func page(_ u: URL?) -> String? {
                guard let u, var c = URLComponents(url: u, resolvingAgainstBaseURL: false) else { return nil }
                c.fragment = nil
                return c.string
            }
            // (Not while a page's follow-up is still to come, which records it: a page swapped in
            // by Instant pages was counted twice.)
            if !tab.isLoading, tab.finishedCommit != nil, !tab.isPrivate, let url, page(url) != page(previous),
               ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
                HistoryStore.store(for: tab.profileID).record(url, title: tab.webView.title ?? "")
            }
            tab.updateSiteColor()
            tab.model?.scheduleSessionSave()
            ExtensionEvents.changed(tab)
        }
        bind(\.isLoading) { tab, value in if tab.isLoading != value { tab.isLoading = value } }
        // Progress arrives many times a second; only noticeable steps are passed on, so the tab
        // bar, address bar and toolbar aren't redrawn for every tiny change.
        bind(\.estimatedProgress) { tab, value in
            if value == 0 || value >= 1 || abs(value - tab.progress) >= 0.08 { tab.progress = value }
        }
        bind(\.canGoBack) { tab, value in
            let back = value || tab.hasParkedBack
            if !tab.waking && tab.canGoBack != back { tab.canGoBack = back }
        }
        bind(\.canGoForward) { tab, value in
            let forward = value || tab.hasParkedForward
            if !tab.waking && tab.canGoForward != forward { tab.canGoForward = forward }
        }
        // A published value announces a change even when set to the same thing, so each one is
        // only set when it really changes; otherwise every observer redraws for nothing.
        bind(\.hasOnlySecureContent) { tab, value in if tab.isSecure != value { tab.isSecure = value } }
        // Magic Theme: the site's own colour (its theme-color, or else its page background).
        bind(\.themeColor) { tab, _ in tab.updateSiteColor() }
        bind(\.underPageBackgroundColor) { tab, _ in tab.updateSiteColor() }
    }

    // MARK: Tab Sleep

    /// Sleeping tabs keep a picture of the page and its full state (including back/forward
    /// history) but release the web page itself, freeing its memory and processor time.
    @Published private(set) var isAsleep = false
    /// A small, compressed picture of a sleeping tab (about 150 KB instead of a full-size bitmap).
    @Published private(set) var snapshotData: Data? { didSet { decodedSnapshot = nil } }

    /// A small picture of the page for the preview shown when you hover its tab: taken as you
    /// switch away from it (one snapshot, nothing kept running), JPEG, about 20 KB.
    private(set) var previewData: Data?
    private(set) var previewTaken: Date?

    func capturePreview() {
        // Only with tab previews on (Settings › Appearance): it was taken on every tab switch anyway.
        guard Prefs.bool(Prefs.tabPreviews), !isAsleep, url != nil, webView.window != nil, webView.bounds.width > 50 else { return }
        let config = WKSnapshotConfiguration()
        config.snapshotWidth = 340
        webView.takeSnapshot(with: config) { [weak self] image, _ in
            guard let self, let image, let data = Self.compressed(image) else { return }
            self.previewData = data
            self.previewTaken = Date()
        }
    }

    /// Whether there's a picture for a preview (without decoding it).
    var hasPreview: Bool { previewData != nil || snapshotData != nil }

    /// The best picture there is for a preview: the latest taken, or the one from when it slept.
    var previewImage: NSImage? {
        (previewData ?? snapshotData).flatMap(NSImage.init(data:))
    }
    /// Decoded once (the page area redraws many times while a tab wakes up).
    private var decodedSnapshot: NSImage?
    var snapshot: NSImage? {
        if let decodedSnapshot { return decodedSnapshot }
        decodedSnapshot = snapshotData.flatMap(NSImage.init(data:))
        return decodedSnapshot
    }
    var lastActive = Date()
    private var sleepState: Any?
    /// The page's zoom when it went to sleep (a woken tab used to come back at the default size).
    private var zoomBeforeSleep: CGFloat?
    private var waking = false

    /// Puts even the tab you're looking at to sleep (from the heavy page warning); clicking its
    /// picture wakes it.
    func forceSleep() { sleep(force: true) }

    func sleep(force: Bool = false) {
        guard !isAsleep, url != nil, force || (!isLoading && model?.selectedTab !== self) else { return }
        let config = WKSnapshotConfiguration()
        config.snapshotWidth = NSNumber(value: min(Double(webView.bounds.width), 900))
        webView.takeSnapshot(with: config) { [weak self] image, _ in
            guard let self, !self.isAsleep, force || self.model?.selectedTab !== self else { return }
            // Unfrozen before its page process is let go (see tearDown).
            if self.isPagePaused { WebKitExtras.setPageSuspended(false, self.webView) }
            self.dropParkedPages()
            // The page that wakes is a fresh one: not paused, and not (yet) heavy.
            if self.isPagePaused { self.isPagePaused = false }
            if self.isHeavy { self.isHeavy = false }
            self.snapshotData = image.flatMap(Self.compressed)
            self.sleepState = self.webView.interactionState
            self.zoomBeforeSleep = self.webView.pageZoom   // the woken page gets it back
            self.observers.removeAll()
            let old = self.webView
            old.stopLoading()
            old.navigationDelegate = nil
            old.uiDelegate = nil
            old.removeFromSuperview()
            WebKitExtras.close(old)   // ends its web process now, so the memory really comes back
            // An empty web view starts no web process until it loads something.
            self.webView = HushWebView(frame: .zero, configuration: BrowserTab.makeConfiguration(
                privately: self.isPrivate, store: old.configuration.websiteDataStore))
            self.isAsleep = true
        }
    }

    /// JPEG at medium quality: plenty for the moment a tab takes to wake.
    private static func compressed(_ image: NSImage) -> Data? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        return NSBitmapImageRep(cgImage: cg).representation(using: .jpeg, properties: [.compressionFactor: 0.5])
    }

    /// A tab restored from last time: shows its address and title but loads nothing until
    /// you switch to it.
    func restoreLazily(_ address: URL) {
        url = address
        title = address.host?.strippingWWW ?? ""
        sleepState = nil
        isAsleep = true
    }

    /// Extensions attach when a page view is made, so a tab opened before an extension was added
    /// gets a fresh page view (keeping its place and history) to run it. Sleeping tabs pick it up
    /// when they wake.
    func adoptExtensions() {
        guard !isAsleep, !isPrivate else {
            if isAsleep { webView = HushWebView(frame: .zero, configuration: BrowserTab.makeConfiguration(
                privately: isPrivate, store: webView.configuration.websiteDataStore)) }
            return
        }
        let state = url != nil ? webView.interactionState : nil
        let address = url
        let zoom = webView.pageZoom   // kept for the rebuilt page
        observers.removeAll()
        let old = webView
        old.stopLoading()
        old.navigationDelegate = nil
        old.uiDelegate = nil
        old.removeFromSuperview()
        WebKitExtras.close(old)
        webView = HushWebView(frame: .zero, configuration: BrowserTab.makeConfiguration(
            privately: isPrivate, store: old.configuration.websiteDataStore))
        setUp(webView)
        webView.pageZoom = zoom
        if let state { webView.interactionState = state } else if let address { webView.load(URLRequest(url: address)) }
        objectWillChange.send()
    }

    func wakeIfNeeded(loading: Bool = true) {
        guard isAsleep else { return }
        waking = true
        // A fresh page: a crash before it slept no longer applies (the crashed screen used to
        // stay over the woken page).
        if crashed { crashed = false; crashedWhileHidden = false }
        // Settings may have changed while it slept (power mode, pop-ups…).
        let preferences = webView.configuration.preferences
        preferences.javaScriptCanOpenWindowsAutomatically = !Prefs.bool(Prefs.blockPopups)
        preferences.isFraudulentWebsiteWarningEnabled = Prefs.bool(Prefs.fraudWarning)
        PerformanceCenter.shared.configure(preferences)
        setUp(webView)
        if let state = sleepState {
            webView.interactionState = state
        } else if loading, let url {
            webView.load(URLRequest(url: url))
        }
        sleepState = nil
        if let zoom = zoomBeforeSleep { webView.pageZoom = zoom; zoomBeforeSleep = nil }
        isAsleep = false
        lastActive = Date()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self, !self.isAsleep else { return }
            self.waking = false
            self.snapshotData = nil
        }
    }

    var displayTitle: String {
        if !title.isEmpty { return title }
        if let host = url?.host, !host.isEmpty { return AddressBar.readableHost(host).strippingWWW }   // "münchen.de", not "xn--…"
        // A local file (or other address with no host) shows its name, not "New Tab".
        if let url, url.isFileURL, !url.lastPathComponent.isEmpty, url.lastPathComponent != "/" { return url.lastPathComponent }
        return "New Tab"
    }

    /// True for a fresh tab that hasn't loaded anything yet: show the start page.
    var isBlank: Bool { url == nil && !isLoading }

    var host: String? { url?.host }
    /// The site this tab last finished loading, to tell arriving at a site from moving around in it.
    private var lastFinishedHost: String?
    private var lastAppPrompt = Date.distantPast
    /// The last address Clean Links reloaded without tracking tags (see decidePolicyFor).
    private var lastCleaned: (url: URL, date: Date)?

    func load(_ url: URL) {
        // Already loaded in the background (Instant pages): swap it in, no wait at all.
        if !isAsleep, let ready = Preloader.take(url, for: self) {
            adopt(ready, for: url)
            return
        }
        // A sleeping tab's page isn't connected yet (no blocking, no delegates): wake it first,
        // going straight to the new address rather than restoring the old page.
        if isAsleep { sleepState = nil; wakeIfNeeded(loading: false) }
        lookalike = nil
        userLoadedURL = url
        dropParked(&parkedForwardStack)   // a new page: Forward no longer leads anywhere
        refreshNavigation()
        webView.load(URLRequest(url: url))
    }

    // MARK: Split View drops

    /// A link, address or picture dragged from the other pane opens here (replacing this page), or
    /// in a new tab with ⌥ held. Only web addresses: never javascript:, file: or data:.
    private func handleSplitDrag(_ phase: HushWebView.SplitDrag, _ info: NSDraggingInfo) -> Bool {
        // The drag must come from the other pane's page (WebKit may report the page view itself,
        // or a view inside it, as where the drag began).
        let source = info.draggingSource as? NSView
        guard let model, let other = model.otherPane(of: self), let source,
              source === other.webView || source.isDescendant(of: other.webView),
              let url = Self.webAddress(in: info.draggingPasteboard) else {
            if isDropTarget { isDropTarget = false }
            return false
        }
        switch phase {
        case .entered, .updated:
            if !isDropTarget { isDropTarget = true }
        case .exited:
            if isDropTarget { isDropTarget = false }
        case .drop:
            isDropTarget = false
            if NSEvent.modifierFlags.contains(.option) {
                model.newTab(url: url, select: false)
            } else {
                load(url)
                model.selectedID = id
            }
        }
        return true
    }

    /// The first http(s) address on a drag: a link, a picture's address or dragged text.
    static func webAddress(in pasteboard: NSPasteboard) -> URL? {
        var candidates = (pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL]) ?? []
        if let text = pasteboard.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !text.contains(" "), let url = URL(string: text) { candidates.append(url) }
        return candidates.first { url in
            guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return false }
            return url.host?.isEmpty == false
        }
    }

    // MARK: Instant pages

    /// A preloaded page has its own (empty) history, so the pages you came from are kept to one
    /// side: Back swaps them back in, and Forward the other way. Only the latest each way stays
    /// live (a whole page in memory, so Back to it is instant); older ones are kept as WebKit's
    /// own record of the page (its address, history and scroll position, a few kilobytes) and
    /// restored from that. Each tab used to keep up to six live pages, 50 to 200 MB apiece.
    private enum Parked {
        case live(WKWebView)
        case saved(state: Any?, url: URL?)
    }
    private var parkedBackStack: [Parked] = []
    private var parkedForwardStack: [Parked] = []
    private static let savedLimit = 20
    var hasParkedBack: Bool { !parkedBackStack.isEmpty }
    var hasParkedForward: Bool { !parkedForwardStack.isEmpty }
    /// Whether this tab keeps a whole page in memory for Back or Forward.
    var hasParkedPages: Bool { (parkedBackStack + parkedForwardStack).contains { if case .live = $0 { return true } else { return false } } }

    private func close(parked view: WKWebView) {
        view.navigationDelegate = nil
        view.uiDelegate = nil
        view.stopLoading()
        WebKitExtras.close(view)
    }

    /// A live kept page becomes a saved one: its memory goes, Back to it still works.
    private func demote(_ entry: Parked) -> Parked {
        guard case .live(let view) = entry else { return entry }
        let saved = Parked.saved(state: view.interactionState, url: view.url)
        close(parked: view)
        return saved
    }

    private func dropParked(_ stack: inout [Parked]) {
        let entries = stack
        stack.removeAll()
        for case .live(let view) in entries { close(parked: view) }
    }

    private func park(_ view: WKWebView, on stack: inout [Parked]) {
        stack = stack.map(demote) + [.live(view)]
        if stack.count > Self.savedLimit { stack.removeFirst(stack.count - Self.savedLimit) }
    }

    /// Lets the kept pages' memory go (memory running short, a tab idle in the background, or
    /// going to sleep), keeping Back and Forward working. `forget` drops them altogether (the
    /// tab is closing).
    func dropParkedPages(forget: Bool = false) {
        if forget {
            dropParked(&parkedBackStack)
            dropParked(&parkedForwardStack)
        } else {
            parkedBackStack = parkedBackStack.map(demote)
            parkedForwardStack = parkedForwardStack.map(demote)
        }
        refreshNavigation()
    }

    /// Forget This Site: that site's kept pages go from this tab's Back and Forward.
    func forgetParkedPages(site: String) {
        func keep(_ entry: Parked) -> Bool {
            switch entry {
            case .live(let view):
                guard Domains.site(view.url?.host ?? "") == site else { return true }
                close(parked: view)
                return false
            case .saved(_, let url):
                return Domains.site(url?.host ?? "") != site
            }
        }
        parkedBackStack = parkedBackStack.filter(keep)
        parkedForwardStack = parkedForwardStack.filter(keep)
        refreshNavigation()
    }

    /// A kept page ready to show: the live one, or a fresh one restored from its record.
    private func unpark(_ entry: Parked) -> (view: WKWebView, restore: Parked?) {
        switch entry {
        case .live(let view):
            return (view, nil)
        case .saved:
            let view = HushWebView(frame: .zero, configuration: BrowserTab.makeConfiguration(
                privately: isPrivate, store: webView.configuration.websiteDataStore))
            return (view, entry)
        }
    }

    /// Loads a restored page once it's connected to this tab (so blocking and the rest are on).
    private func restore(_ entry: Parked?, into view: WKWebView) {
        guard case .saved(let state, let url) = entry else { return }
        if let state { view.interactionState = state } else if let url { view.load(URLRequest(url: url)) }
    }

    private func refreshNavigation() {
        let back = webView.canGoBack || hasParkedBack
        let forward = webView.canGoForward || hasParkedForward
        if canGoBack != back { canGoBack = back }
        if canGoForward != forward { canGoForward = forward }
    }

    /// Shows another page view in this tab; returns the one it replaced (now inactive).
    private func show(_ view: WKWebView) -> WKWebView {
        let old = webView
        let zoom = view.pageZoom
        observers.removeAll()
        old.navigationDelegate = nil
        old.uiDelegate = nil
        // The page set aside stops playing (its video or podcast used to carry on, out of sight);
        // the one coming in picks up again.
        // Its floating video goes back in first (it used to stay up, frozen, after the page was set aside).
        if WebKitExtras.isPictureInPictureActive(old) { WebKitExtras.togglePictureInPicture(old) }
        if autoPictureInPicture { autoPictureInPicture = false }
        old.setAllMediaPlaybackSuspended(true)
        view.setAllMediaPlaybackSuspended(false)
        objectWillChange.send()
        webView = view
        // The new page view's own state: a crash or error screen from the old one mustn't stay
        // on top of it.
        if crashed { crashed = false; crashedWhileHidden = false }
        if loadError != nil { loadError = nil }
        if reader != nil { reader = nil }
        // A heavy page you paused belongs to the old view: it's resumed as it's set aside (it
        // used to stay frozen, with the Paused bar showing over the page swapped in instead).
        if isPagePaused { WebKitExtras.setPageSuspended(false, old); isPagePaused = false }
        if isHeavy { isHeavy = false }
        if translation != .none { setTranslation(.none, language: nil) }
        if readerAvailable { readerAvailable = false }
        if lookalike != nil { lookalike = nil }
        resetBlockedCounts()   // the counts were the old page's
        setUp(view)
        view.pageZoom = zoom
        if isMuted { WebKitExtras.setMuted(true, view) }
        return old
    }

    private func adopt(_ view: WKWebView, for url: URL) {
        lookalike = nil
        userLoadedURL = url
        let previous = show(view)
        // A new page for this tab. Without this, one handed over partway through loading (after it
        // had started showing, before it finished) counted as the page already finished, so it
        // never got its follow-up: no history entry, Reader or translation.
        commitCount &+= 1
        finishedCommit = nil
        // What Force Field blocked while it loaded in the background counts for this page (the
        // counter used to keep showing the previous page's number).
        for (identifier, blockedURL) in Preloader.takeBlocked() { noteBlocked(identifier, url: blockedURL, in: view) }
        dropParked(&parkedForwardStack)   // a new page: Forward no longer leads anywhere
        // A new tab's empty start page isn't somewhere to go Back to (Back used to lead to it).
        if previous.url != nil { park(previous, on: &parkedBackStack) } else { close(parked: previous) }
        refreshNavigation()
        // It finished loading before it was handed over, so its follow-up (history, Reader) runs now.
        if !view.isLoading { DispatchQueue.main.async { [weak self] in self?.pageFinished() } }
    }

    func goBack() {
        if webView.canGoBack { webView.goBack(); return }
        guard let entry = parkedBackStack.popLast() else { return }
        let (previous, restoring) = unpark(entry)
        let current = show(previous)
        restore(restoring, into: previous)
        park(current, on: &parkedForwardStack)
        refreshNavigation()
        redetectKeptPage()
    }

    func goForward() {
        if webView.canGoForward { webView.goForward(); return }
        guard let entry = parkedForwardStack.popLast() else { return }
        let (next, restoring) = unpark(entry)
        let current = show(next)
        restore(restoring, into: next)
        park(current, on: &parkedBackStack)
        refreshNavigation()
        redetectKeptPage()
    }

    /// A kept page swapped back in: whether it can be translated or read in Reader is its own
    /// (the page you left's answers used to stay).
    private func redetectKeptPage() {
        guard !webView.isLoading, webView.url != nil else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            PageTranslator.shared.detect(in: self)
            ReaderMode.detect(in: self)
        }
    }

    func reload() {
        if isLoading { webView.stopLoading() } else { webView.reload() }
    }

    func zoom(by delta: CGFloat) {
        webView.pageZoom = min(3, max(0.3, webView.pageZoom + delta))
    }

    func resetZoom() {
        let zoom = Prefs.double(Prefs.defaultZoom)
        webView.pageZoom = zoom > 0 ? zoom : 1
        // Trackpad pinch-zoom too: Actual Size left a pinched page magnified.
        if webView.magnification != 1 { webView.setMagnification(1, centeredAt: .zero) }
    }

    /// Print (⌘P): the page as you see it, fitted to the paper's width.
    func printPage() {
        guard let window = webView.window, url != nil else { return }
        let info = (NSPrintInfo.shared.copy() as? NSPrintInfo) ?? NSPrintInfo.shared
        info.horizontalPagination = .fit
        info.isVerticallyCentered = false
        let operation = webView.printOperation(with: info)
        operation.view?.frame = webView.bounds
        operation.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
    }

    /// Save Page As (⌘S): the whole page, images included, as a web archive.
    func savePage() {
        guard let window = webView.window, let url else { return }
        // A PDF is saved as the PDF itself (a web archive of it was no use outside Safari).
        if url.pathExtension.lowercased() == "pdf" {
            webView.startDownload(using: URLRequest(url: url)) { download in download.delegate = Downloads.shared }
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.webArchive]
        panel.nameFieldStringValue = Downloads.safeFilename(displayTitle) + ".webarchive"
        panel.directoryURL = Downloads.folder
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let destination = panel.url, let self else { return }
            self.webView.createWebArchiveData { result in
                // Written in the background: a big page's archive can be tens of megabytes.
                if case .success(let data) = result {
                    DispatchQueue.global(qos: .userInitiated).async { try? data.write(to: destination, options: .atomic) }
                }
            }
        }
    }

    func tearDown() {
        // A floating video goes first, so WebKit isn't left with a window for a page that's gone.
        if !isAsleep, WebKitExtras.isPictureInPictureActive(webView) { WebKitExtras.togglePictureInPicture(webView) }
        // A paused page is unfrozen before it closes: its page process can be kept for a moment and
        // reused for the next visit to that site, which then loaded frozen (a YouTube video that
        // wouldn't play until Ufolio restarted).
        if isPagePaused { WebKitExtras.setPageSuspended(false, webView); isPagePaused = false }
        dropParkedPages(forget: true)
        Preloader.discard(forTab: id)
        observers.removeAll()
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        webView.removeFromSuperview()
        // End the page now, and let go of the sleeping picture and saved page state, so a
        // closed tab costs (almost) nothing, even if a view somewhere still refers to it.
        WebKitExtras.close(webView)
        snapshotData = nil
        sleepState = nil
    }
}

extension BrowserTab: WKNavigationDelegate {
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 preferences: WKWebpagePreferences,
                 decisionHandler: @escaping (WKNavigationActionPolicy, WKWebpagePreferences) -> Void) {
        // ⌘-click opens the link in a new background tab.
        // Only web addresses: anything else goes through the checks below.
        // (A middle-click does the same, as in every other browser, instead of replacing this page.)
        if action.navigationType == .linkActivated, action.modifierFlags.contains(.command) || action.buttonNumber == 2,
           let url = action.request.url, ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
            model?.newTab(url: url, select: false)
            decisionHandler(.cancel, preferences)
            return
        }
        // Split View, "Open links in the other pane": a plain click opens on the other side.
        if action.navigationType == .linkActivated, action.targetFrame?.isMainFrame ?? false,
           let model, model.splitLinksAcross, let other = model.otherPane(of: self),
           let url = action.request.url, ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
            decisionHandler(.cancel, preferences)
            other.load(url)
            return
        }
        // A link you clicked that was already loading in the background (pressed a moment ago):
        // swap it in instead of starting again. Also when the page itself goes there straight
        // after your click (sites whose links are buttons that set the address in a script).
        let justClicked = Date().timeIntervalSince((webView as? HushWebView)?.lastInteraction ?? .distantPast) < 2
        if action.navigationType == .linkActivated || (action.navigationType == .other && justClicked),
           action.targetFrame?.isMainFrame ?? false,
           (action.request.httpMethod ?? "GET") == "GET", let url = action.request.url,
           let ready = Preloader.take(url, for: self) {
            decisionHandler(.cancel, preferences)
            adopt(ready, for: url)
            return
        }
        if let url = action.request.url, let scheme = url.scheme?.lowercased() {
            // Pages may not send you to data:/javascript: addresses (a phishing trick); you still can.
            if ["data", "javascript"].contains(scheme), action.targetFrame?.isMainFrame ?? true, url != userLoadedURL {
                decisionHandler(.cancel, preferences)
                return
            }
            // Websites may never open files on your Mac (file:// addresses); only you can.
            // (sourceFrame can really be missing for loads you start, despite what Swift says.)
            // Clicked links and forms only: dropping a file from Finder onto a page also comes "from"
            // that page, and must still open (WebKit itself refuses file:// loads made by scripts).
            if scheme == "file", [.linkActivated, .formSubmitted, .formResubmitted].contains(action.navigationType),
               let source = action.sourceFrame as WKFrameInfo?,
               ["http", "https"].contains(source.securityOrigin.protocol.lowercased()) {
                decisionHandler(.cancel, preferences)
                return
            }
            // Torrent tools: a magnet link shows what it is, then goes to your torrent app.
            if scheme == "magnet", TorrentTools.on {
                decisionHandler(.cancel, preferences)
                if action.targetFrame?.isMainFrame ?? true, Date().timeIntervalSince(lastAppPrompt) > 1 {
                    lastAppPrompt = Date()
                    TorrentTools.showMagnetCard(url, from: host, in: webView.window)
                }
                return
            }
            // Torrent site mode: no redirects to ad networks, and no pages swapped for another
            // site by a script while you're on a torrent site.
            if TorrentTools.siteModeOn, action.targetFrame?.isMainFrame ?? true, ["http", "https"].contains(scheme),
               TorrentTools.isIndexSite(webView.url?.host), url != userLoadedURL {
                let current = Domains.site(webView.url?.host ?? "")
                let target = Domains.site(url.host ?? "")
                if TorrentTools.isAdNetwork(url.host) {
                    torrentPopupsBlocked += 1
                    decisionHandler(.cancel, preferences)
                    return
                }
                if target != current, !TorrentTools.isIndexSite(url.host), url.pathExtension.lowercased() != "torrent" {
                    if action.navigationType == .linkActivated {
                        torrentOutboundClick = Date()   // a link you chose: its redirects may follow
                    } else if action.navigationType == .other, Date().timeIntervalSince(torrentOutboundClick) > 4 {
                        torrentPopupsBlocked += 1
                        decisionHandler(.cancel, preferences)
                        return
                    }
                }
            }
            // Links to other apps (mailto:, zoommtg:, facetime:…) open only after you say so.
            if !["http", "https", "about", "blob", "data", "file", "javascript"].contains(scheme) {
                decisionHandler(.cancel, preferences)
                confirmOpeningApp(for: url)
                return
            }
        }
        if action.targetFrame?.isMainFrame ?? true, let url = action.request.url,
           let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" {
            // Debouncing and De-AMP: skip tracking redirects and AMP copies, straight to the real page.
            if action.navigationType != .backForward, let real = CleanLinks.skipRedirect(url) {
                decisionHandler(.cancel, preferences)
                webView.load(URLRequest(url: real))
                return
            }
            // Clean Links: reload the same page without tracking tags.
            // (Not twice in a row for the same page: a server that redirects straight back to the
            // tagged address would otherwise loop forever.)
            if CleanLinks.isEnabled, action.request.httpMethod ?? "GET" == "GET", let clean = CleanLinks.cleaned(url),
               !(lastCleaned?.url == clean && Date().timeIntervalSince(lastCleaned?.date ?? .distantPast) < 5) {
                lastCleaned = (clean, Date())
                decisionHandler(.cancel, preferences)
                webView.load(URLRequest(url: clean))
                return
            }
            // Look-alike sites: stop before anything loads and explain.
            if action.navigationType != .backForward, let host = url.host, let match = Lookalike.check(host: host) {
                decisionHandler(.cancel, preferences)
                lookalike = (match, url)
                return
            }
        }
        if action.targetFrame?.isMainFrame ?? true {
            if let url = action.request.url, url.scheme?.lowercased() == "http" { requestedHTTP = url }
            // Per-site shields must be in place before the page starts loading.
            ContentBlocker.shared.update(webView.configuration.userContentController,
                                         forHost: action.request.url?.host)
        }
        // Script blocking: the site's Hush Guard setting (Block all turns JavaScript off for it).
        let scriptHost = (action.targetFrame?.isMainFrame ?? true) ? action.request.url?.host : host
        let siteOn = !(scriptHost.map(ContentBlocker.shared.isShieldsDown) ?? false)
        let scriptsBlocked = siteOn && ShieldSettings.shared.effective(for: scriptHost).scripts == .blockAll
        preferences.allowsContentJavaScript = Prefs.bool(Prefs.javaScript) && !javaScriptOff && !scriptsBlocked
        // Auto-play, as Safari does it (see WebKitExtras.setAutoplay). Eco keeps everything stopped.
        if action.targetFrame?.isMainFrame ?? true {
            let rules = PerformanceCenter.shared.isEco ? (policy: 3, quirks: 0) : AutoplayPolicy.current.webKitPolicy
            WebKitExtras.setAutoplay(policy: rules.policy, quirks: rules.quirks, preferences)
        }
        decisionHandler(action.shouldPerformDownload ? .download : .allow, preferences)
    }

    func webView(_ webView: WKWebView, decidePolicyFor response: WKNavigationResponse,
                 decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        // A server marking the file as an attachment wants it downloaded, even if WebKit could
        // show it (a site's Download button for a PDF or picture used to open it in the tab).
        let disposition = (response.response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Disposition")?
            .trimmingCharacters(in: .whitespaces).lowercased() ?? ""
        let attachment = response.isForMainFrame && disposition.hasPrefix("attachment")
        let wantsDownload = !response.canShowMIMEType || attachment
        // A frame inside the page (an ad, say) may only start a download just after you clicked or
        // typed in the page: files used to arrive from frames with no click at all.
        if wantsDownload, !response.isForMainFrame,
           Date().timeIntervalSince((webView as? HushWebView)?.lastInteraction ?? .distantPast) > 10 {
            decisionHandler(.cancel)
            return
        }
        decisionHandler(wantsDownload ? .download : .allow)
    }

    /// A load that failed before anything arrived. If Ufolio guessed the address from what you
    /// typed (like "node.js") and there's no such server, search for it instead, as other
    /// browsers do; otherwise nothing at all used to happen.
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        let failed = (error as NSError).userInfo[NSURLErrorFailingURLErrorKey] as? URL
        if (error as? URLError)?.code == .cannotFindHost, let guess = URLResolver.lastGuess,
           failed?.host == guess.url.host, let search = URLResolver.searchURL(for: guess.text) {
            URLResolver.lastGuess = nil
            load(search)
            return
        }
        // Stopped on purpose (Stop, a new address, a download): nothing to explain.
        let ns = error as NSError
        if ns.code == NSURLErrorCancelled || (ns.domain == "WebKitErrorDomain" && [102, 204].contains(ns.code)) { return }
        loadError = (failed, Self.explain(error), insecureVersion(of: failed, error: error))
    }

    /// The plain http:// address to offer when a secure one failed because the site seems to
    /// have no https: one you (or a link) asked for as http:// that HTTPS upgrade changed, or an
    /// address you typed without http(s)://. Only ever opened if you click it.
    private func insecureVersion(of failed: URL?, error: Error) -> URL? {
        guard Prefs.bool(Prefs.httpsUpgrade) || URLResolver.lastGuess != nil,
              let failed, failed.scheme?.lowercased() == "https", let host = failed.host?.lowercased() else { return nil }
        let noHTTPS: [URLError.Code] = [.secureConnectionFailed, .cannotConnectToHost, .timedOut, .serverCertificateUntrusted,
                                        .serverCertificateHasBadDate, .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid]
        guard let code = (error as? URLError)?.code, noHTTPS.contains(code) else { return nil }
        let askedHTTP = requestedHTTP?.host?.lowercased() == host
        let typed = URLResolver.lastGuess.map { $0.url.host?.lowercased() == host && !$0.text.contains("://") } ?? false
        guard askedHTTP || typed, var parts = URLComponents(url: failed, resolvingAgainstBaseURL: false) else { return nil }
        parts.scheme = "http"
        if parts.port == 443 { parts.port = nil }
        return parts.url
    }

    /// Opens the insecure version of a site with no https, after you chose to (for this site,
    /// until Ufolio quits).
    func openInsecure(_ url: URL) {
        guard let host = url.host else { return }
        ContentBlocker.shared.allowInsecure(host)
        loadError = nil
        load(url)
    }

    private static func explain(_ error: Error) -> String {
        let ns = error as NSError
        if ns.domain == "WebKitErrorDomain" && ns.code == 104 {
            return "Force Field blocked this page because it’s on a blocking list. If you trust it, turn Force Field off for this site in the shield menu."
        }
        switch (error as? URLError)?.code {
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
            return "Your Mac isn’t connected to the internet."
        case .cannotFindHost, .dnsLookupFailed:
            return "Ufolio couldn’t find that website. Check the address for typos."
        case .timedOut:
            return "The website took too long to answer."
        case .cannotConnectToHost:
            return "The website isn’t accepting connections right now."
        case .serverCertificateUntrusted, .serverCertificateHasBadDate, .serverCertificateHasUnknownRoot,
             .serverCertificateNotYetValid, .clientCertificateRejected, .secureConnectionFailed:
            return "This website’s security certificate isn’t valid, so Ufolio didn’t open it. Someone may be trying to impersonate it."
        default:
            return error.localizedDescription
        }
    }

    /// Sites that ask for a username and password the old way (routers, NAS boxes, staging
    /// sites): Ufolio never answered, so they just showed an error. Now it asks you, on this
    /// window, and the answer is kept only until Ufolio quits.
    func webView(_ webView: WKWebView, didReceive challenge: URLAuthenticationChallenge,
                 completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        let method = challenge.protectionSpace.authenticationMethod
        guard [NSURLAuthenticationMethodHTTPBasic, NSURLAuthenticationMethodHTTPDigest, NSURLAuthenticationMethodNTLM].contains(method),
              challenge.previousFailureCount < 3, let window = webView.window else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        let space = challenge.protectionSpace
        // One sign-in box per site and realm: a page asking several times at once used to stack
        // up identical boxes. Later requests wait and get the same answer.
        let key = "\(space.host):\(space.port)|\(space.realm ?? "")"
        if Self.waitingSignIns[key] != nil { Self.waitingSignIns[key]?.append(completionHandler); return }
        Self.waitingSignIns[key] = []
        let finish: (URLSession.AuthChallengeDisposition, URLCredential?) -> Void = { disposition, credential in
            completionHandler(disposition, credential)
            for waiting in Self.waitingSignIns.removeValue(forKey: key) ?? [] { waiting(disposition, credential) }
        }
        let alert = NSAlert()
        alert.messageText = "Sign in to \(space.host)"
        var info = space.realm.map { "The site says: “\(String($0.prefix(120)))”" } ?? "This site needs a username and password."
        if space.receivesCredentialSecurely == false { info += "\n\nYour password will be sent without encryption." }
        if challenge.previousFailureCount > 0 { info = "That didn’t work. Try again.\n\n" + info }
        alert.informativeText = info
        let user = NSTextField(frame: NSRect(x: 0, y: 30, width: 260, height: 24))
        user.placeholderString = "Username"
        user.stringValue = challenge.proposedCredential?.user ?? ""
        let password = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        password.placeholderString = "Password"
        let fields = NSView(frame: NSRect(x: 0, y: 0, width: 260, height: 54))
        fields.addSubview(user)
        fields.addSubview(password)
        alert.accessoryView = fields
        alert.addButton(withTitle: "Sign In")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = user.stringValue.isEmpty ? user : password
        alert.beginSheetModal(for: window) { response in
            guard response == .alertFirstButtonReturn else { finish(.cancelAuthenticationChallenge, nil); return }
            finish(.useCredential, URLCredential(user: user.stringValue, password: password.stringValue, persistence: .forSession))
        }
    }
    private static var waitingSignIns: [String: [(URLSession.AuthChallengeDisposition, URLCredential?) -> Void]] = [:]

    /// The page's web process crashed or was stopped by macOS.
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        guard webView === self.webView, !isAsleep else { return }
        // Ended while out of sight (usually macOS freeing memory): it reloads by itself when you
        // come back to it, as in Safari, instead of showing the crashed page.
        crashedWhileHidden = model?.selectedTab !== self
        crashed = true
        isPlayingAudio = false
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        CookieCleaner.lastActivity = Date()   // browsing: the cleaner waits for a quiet spell
        if isHeavy { isHeavy = false }
        heavyDismissed = false
        // A page you paused from the heavy page warning: the tab is unfrozen for the next page too.
        // (Only the Paused bar used to go: the next page, YouTube say, loaded frozen and its video
        // wouldn't play until Ufolio restarted.)
        if isPagePaused { WebKitExtras.setPageSuspended(false, webView); isPagePaused = false }
        if crashed { crashed = false }
        if loadError != nil { loadError = nil }
        // Going back (or anywhere else) from a look-alike warning takes the warning away too.
        if lookalike != nil { lookalike = nil }
        resetBlockedCounts()
        if translation != .none { setTranslation(.none, language: nil) }
        if reader != nil { reader = nil }
        if readerAvailable { readerAvailable = false }
        dialogsShown = 0
        dialogsSilenced = false
        if torrentPopupsBlocked != 0 { torrentPopupsBlocked = 0 }
        if torrentTrapsMarked != 0 { torrentTrapsMarked = 0 }
    }

    /// Asks before a page opens another app, the way Safari does.
    private func confirmOpeningApp(for url: URL) {
        // One question at a time, and no more than one every few seconds: a page can't bury you in them.
        guard let app = NSWorkspace.shared.urlForApplication(toOpen: url), let window = webView.window,
              !DialogHost.isBusy(window), Date().timeIntervalSince(lastAppPrompt) > 3 else { return }
        lastAppPrompt = Date()
        let name = FileManager.default.displayName(atPath: app.path).replacingOccurrences(of: ".app", with: "")
        DialogHost.show(HushDialog(
            art: .image(NSWorkspace.shared.icon(forFile: app.path)), badge: "arrow.up.forward", theme: .caution, motion: .pulse,
            title: "Open this link in “\(name)”?",
            message: "\(host?.strippingWWW ?? "This page") wants to open another app on your Mac.",
            choices: [.init(title: "Cancel", role: .cancel), .init(title: "Open", role: .primary)],
            completion: { choice, _ in if choice == 1 { NSWorkspace.shared.open(url) } }), in: window)
    }

    /// Torrent tools: recognises torrent index sites and marks their traps.
    private func checkTorrentSite() {
        guard TorrentTools.on, TorrentTools.siteModeOn || TorrentTools.fakeWarningsOn,
              let url = webView.url, ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return }
        let known = TorrentTools.isIndexSite(url.host)
        let script = TorrentTools.fakeWarningsOn ? TorrentSiteGuard.script
            : "return { isIndex: document.querySelectorAll('a[href^=\"magnet:\"]').length >= 3, marked: 0 };"
        webView.callAsyncJavaScript(script, arguments: ["known": known], in: nil, in: .defaultClient) { [weak self] result in
            guard let self, case .success(let value) = result, let info = value as? [String: Any] else { return }
            if (info["isIndex"] as? Bool) == true { TorrentTools.recognise(url.host) }
            let marked = (info["marked"] as? Int) ?? (info["marked"] as? NSNumber)?.intValue ?? 0
            if marked > 0, self.webView.url == url { self.torrentTrapsMarked = marked }
        }
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        if SpeedBenchmark.active { NotificationCenter.default.post(name: SpeedBenchmark.committed, object: self) }
        commitCount &+= 1
        finishedCommit = nil
        // A page shown instantly from the back/forward cache never reports "finished", so its
        // follow-up (title, history, Reader, translation) is done here once it's settled.
        let commit = commitCount
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.commitCount == commit, self.finishedCommit != commit, !self.webView.isLoading else { return }
                self.pageFinished()
            }
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if SpeedBenchmark.active { NotificationCenter.default.post(name: SpeedBenchmark.finished, object: self) }
        guard finishedCommit != commitCount else { return }
        pageFinished()
    }

    /// What happens once a page has loaded (or been restored from the back/forward cache).
    @MainActor private func pageFinished() {
        finishedCommit = commitCount
        checkTorrentSite()
        // The guessed address worked: forget the guess (a later hiccup on that site mustn't turn
        // into a search for something typed long ago).
        if let guess = URLResolver.lastGuess, webView.url?.host == guess.url.host { URLResolver.lastGuess = nil }
        if let url = webView.url {
            PageTranslator.shared.detect(in: self)
            ReaderMode.detect(in: self)
            if isMuted { WebKitExtras.setMuted(true, webView) }
            // Private windows leave no trace: no history, suggestions or report entries.
            guard !isPrivate else { return }
            HistoryStore.store(for: profileID).record(url, title: webView.title ?? "")
            CookieCleaner.noteVisit(url.host)
            // (Only in the default profile: other profiles keep their browsing fully separate.)
            if profileID == nil { BookmarkOffer.shared.record(url, previousHost: lastFinishedHost) }
            lastFinishedHost = url.host
            if let host = url.host, url.scheme?.hasPrefix("http") == true { PrivacyReport.shared.recordVisit(site: host) }
        }
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        download.delegate = Downloads.shared
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        download.delegate = Downloads.shared
    }

    /// WebKit asks for the WebCrypto key here (part of its private delegate API); answering
    /// means it never goes to the keychain, so no permission prompt can freeze the window.
    @objc(_webCryptoMasterKeyForWebView:)
    func hush_webCryptoMasterKey(_ webView: WKWebView) -> Data? {
        WebCryptoKey.key(privately: !webView.configuration.websiteDataStore.isPersistent)
    }

    @objc(_webCryptoMasterKeyForWebView:completionHandler:)
    func hush_webCryptoMasterKey(_ webView: WKWebView, completionHandler: @escaping (Data?) -> Void) {
        completionHandler(WebCryptoKey.key(privately: !webView.configuration.websiteDataStore.isPersistent))
    }

    /// WebKit reports each blocked request here. This is part of WebKit's
    /// private navigation-delegate API (the one Safari uses for its counts);
    /// if a future WebKit drops it, blocking still works and only the counter stops.
    @objc(_webView:contentRuleListWithIdentifier:performedAction:forURL:)
    func hush_webView(_ webView: WKWebView, contentRuleListWithIdentifier identifier: String,
                      performedAction action: NSObject, forURL url: URL) {
        guard action.responds(to: NSSelectorFromString("blockedLoad")),
              (action.value(forKey: "blockedLoad") as? Bool) == true else { return }
        noteBlocked(identifier, url: url, in: webView)
    }

    /// One blocked request on this tab's page (also those blocked while it was being preloaded).
    func noteBlocked(_ identifier: String, url: URL, in webView: WKWebView) {
        let category = BuiltInRules.category(of: identifier)
        guard category != .other else { return }
        DispatchQueue.main.async {
            // Busy pages block dozens of things a second: counts are gathered and shown at most
            // four times a second, so the window isn't redrawn for every single one.
            self.pendingBlocked += 1
            if category == .trackers { self.pendingTrackers += 1 } else { self.pendingAds += 1 }
            if let host = url.host {
                let site = Domains.site(host)
                if self.blockedSites.count + self.pendingSites.count < 300
                    || self.blockedSites[site] != nil || self.pendingSites[site] != nil {
                    self.pendingSites[site, default: 0] += 1
                }
            }
            self.scheduleBlockedFlush()
            BlockStats.shared.record(identifier)
            if !self.isPrivate, category == .trackers || category == .ads || category == .lists {
                PrivacyReport.shared.recordBlocked(tracker: url, on: self.host)
            }
            // Tell the page's ad-space collapser that ads really were blocked here.
            // (Again at the 5th and 20th, in case the first came before the page's script was ready.)
            if [1, 5, 20].contains(self.blockedOnPage + self.pendingBlocked) && Prefs.bool(Prefs.collapseAdSpace) {
                webView.evaluateJavaScript("window.__hushAdsBlocked = true; window.__hushSweep && window.__hushSweep();",
                                           in: nil, in: .defaultClient) { _ in }
            }
        }
    }
}

extension BrowserTab: WKUIDelegate {
    // Links and scripts that open a new window get a new tab instead.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard let model else { return nil }
        // Split View, "Open links in the other pane": links meant for a new window go there too.
        if model.splitLinksAcross, action.navigationType == .linkActivated, let other = model.otherPane(of: self),
           let url = action.request.url, ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
            other.load(url)
            return nil
        }
        // Torrent site mode: only a real click on a link to the same site may open a new tab.
        // Scripts opening pop-unders, and links to ad networks, are stopped.
        if TorrentTools.siteModeOn, TorrentTools.isIndexSite(webView.url?.host) {
            let target = action.request.url
            let sameSite = target?.host.map { Domains.site($0) == Domains.site(webView.url?.host ?? "") } ?? false
            let torrentLink = target?.scheme?.lowercased() == "magnet" || target?.pathExtension.lowercased() == "torrent"
            if TorrentTools.isAdNetwork(target?.host) || !(action.navigationType == .linkActivated && (sameSite || torrentLink)) {
                torrentPopupsBlocked += 1
                return nil
            }
        }
        // Its own set of blocking rules and scripts: sharing the opener's meant a pop-up on a
        // site with Force Field off switched blocking off for the original page too.
        configuration.userContentController = WKUserContentController()
        // "Open Link in Background Tab" from the right-click menu.
        let background = (webView as? HushWebView)?.openNextInBackground ?? false
        (webView as? HushWebView)?.openNextInBackground = false
        return model.newTab(configuration: configuration, select: !background).webView
    }

    func webViewDidClose(_ webView: WKWebView) {
        model?.close(self)
    }

    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping ([URL]?) -> Void) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.canChooseDirectories = parameters.allowsDirectories
        panel.begin { completionHandler($0 == .OK ? panel.urls : nil) }
    }

    /// A page's alert/confirm, shown as a sheet on this window only, titled with the
    /// origin WebKit reports. After two, the user can silence the page.
    private func pageDialog(_ message: String, frame: WKFrameInfo, confirm: Bool,
                            completion: @escaping (Bool) -> Void) {
        guard !dialogsSilenced, let window = webView.window, !DialogHost.isBusy(window) else { completion(false); return }
        dialogsShown += 1
        let origin = frame.securityOrigin.host
        let choices: [HushDialog.Choice] = confirm
            ? [.init(title: "Cancel", role: .cancel), .init(title: "OK", role: .primary)]
            : [.init(title: "OK", role: .primary)]
        DialogHost.show(HushDialog(
            art: .site(url), badge: "text.bubble.fill", theme: .hush, motion: .pulse,
            title: origin.isEmpty ? "This page says" : "\(origin.strippingWWW) says",
            message: String(message.prefix(2_000)),
            checkbox: dialogsShown > 1 ? "Don’t show more messages from this page" : nil,
            choices: choices,
            completion: { [weak self] choice, checked in
                if checked { self?.dialogsSilenced = true }
                completion(confirm ? choice == 1 : true)
            }), in: window)
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        pageDialog(message, frame: frame, confirm: false) { _ in completionHandler() }
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        pageDialog(message, frame: frame, confirm: true, completion: completionHandler)
    }

    // Camera and microphone (public WebKit API, macOS 12+).
    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                 initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType,
                 decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        let kinds: [PermissionKind]
        switch type {
        case .camera: kinds = [.camera]
        case .microphone: kinds = [.microphone]
        default: kinds = [.camera, .microphone]
        }
        SitePermissions.shared.request(kinds, host: origin.host, window: webView.window, privately: isPrivate) {
            decisionHandler($0 ? .grant : .deny)
        }
    }

    // Location. WebKit on macOS only offers this through its private UI-delegate
    // API; without it, every site's location request is silently refused.
    @objc(_webView:requestGeolocationPermissionForOrigin:initiatedByFrame:decisionHandler:)
    func hush_requestLocation(_ webView: WKWebView, origin: WKSecurityOrigin, frame: WKFrameInfo,
                              decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        SitePermissions.shared.request([.location], host: origin.host, window: webView.window, privately: isPrivate) {
            decisionHandler($0 ? .grant : .deny)
        }
    }

    @objc(_webView:requestGeolocationPermissionForFrame:decisionHandler:)
    func hush_requestLocationLegacy(_ webView: WKWebView, frame: WKFrameInfo,
                                    decisionHandler: @escaping (Bool) -> Void) {
        SitePermissions.shared.request([.location], host: frame.securityOrigin.host, window: webView.window,
                                       privately: isPrivate, completion: decisionHandler)
    }
}

/// Hush's web view: adds "Hide Elements on This Page…" to the page's right-click menu.
final class HushWebView: WKWebView {
    // MARK: Dropping links from the other Split View pane

    enum SplitDrag { case entered, updated, exited, drop }
    /// Answers whether this pane takes the drag (only one from the other pane, with a web address).
    var onSplitDrag: ((SplitDrag, NSDraggingInfo) -> Bool)?

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        if onSplitDrag?(.entered, sender) == true { return .copy }
        return super.draggingEntered(sender)
    }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        if onSplitDrag?(.updated, sender) == true { return .copy }
        return super.draggingUpdated(sender)
    }
    override func draggingExited(_ sender: NSDraggingInfo?) {
        if let sender { _ = onSplitDrag?(.exited, sender) }
        super.draggingExited(sender)
    }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        if onSplitDrag?(.drop, sender) == true { return true }
        return super.performDragOperation(sender)
    }
    /// A drag that ends any way at all (dropped elsewhere, or cancelled with Esc while over this
    /// pane) clears the highlight; it could otherwise stay on.
    override func draggingEnded(_ sender: NSDraggingInfo) {
        _ = onSplitDrag?(.exited, sender)
        super.draggingEnded(sender)
    }

    override init(frame: CGRect, configuration: WKWebViewConfiguration) {
        super.init(frame: frame, configuration: configuration)
        LiveCount.change(\.webViews, by: 1)
    }
    required init?(coder: NSCoder) { super.init(coder: coder) }
    deinit { LiveCount.change(\.webViews, by: -1) }

    var onHideElements: (() -> Void)?
    var onFocus: (() -> Void)?

    // MARK: Nothing gets through a dialog, guide or other card on top of the page
    //
    // A click, scroll, hover or cursor change under one of Ufolio's cards (dialogs, the setup
    // guide, the palette, Reader, warnings) used to be able to reach the page underneath: macOS
    // sends pointer movement straight to the page, whatever's drawn over it. The page now
    // checks for a card over the pointer and ignores the event.

    private func covered(_ point: NSPoint) -> Bool {
        guard let window else { return false }
        return ClickBlocker.BlockingView.covers(point, in: window)
    }
    private func covered(_ event: NSEvent) -> Bool { event.window === window && covered(event.locationInWindow) }

    override func hitTest(_ point: NSPoint) -> NSView? {
        if let superview, covered(superview.convert(point, to: nil)) { return nil }
        return super.hitTest(point)
    }
    override func mouseDown(with event: NSEvent) {
        if !covered(event) { lastInteraction = Date(); onClick?(); super.mouseDown(with: event) }
    }
    var onClick: (() -> Void)?
    override func keyDown(with event: NSEvent) { lastInteraction = Date(); super.keyDown(with: event) }
    /// When you last clicked or typed in this page (frames may only start a download just after).
    var lastInteraction = Date.distantPast
    override func mouseUp(with event: NSEvent) { if !covered(event) { super.mouseUp(with: event) } }
    override func mouseDragged(with event: NSEvent) { if !covered(event) { super.mouseDragged(with: event) } }
    override func rightMouseDown(with event: NSEvent) { if !covered(event) { super.rightMouseDown(with: event) } }
    override func rightMouseUp(with event: NSEvent) { if !covered(event) { super.rightMouseUp(with: event) } }
    override func otherMouseDown(with event: NSEvent) { if !covered(event) { super.otherMouseDown(with: event) } }
    override func otherMouseUp(with event: NSEvent) {
        guard !covered(event) else { return }
        super.otherMouseUp(with: event)
        // A mouse's side buttons: Back (button 4) and Forward (button 5), as in other browsers.
        guard event.buttonNumber == 3 || event.buttonNumber == 4 else { return }
        stepIfUnhandled(back: event.buttonNumber == 3)
    }

    /// A three-finger (or Magic Mouse) swipe between pages.
    override func swipe(with event: NSEvent) {
        guard !covered(event) else { return }
        super.swipe(with: event)
        guard event.deltaX != 0 else { return }
        stepIfUnhandled(back: event.deltaX > 0)
    }

    /// Goes Back or Forward (through the tab, which also knows pages opened instantly), unless
    /// the page or WebKit already did: checked a moment later, so it never goes two steps.
    private func stepIfUnhandled(back: Bool) {
        let before = backForwardList.currentItem
        let page = url, wasLoading = isLoading
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self, self.backForwardList.currentItem === before, self.url == page,
                  wasLoading || !self.isLoading else { return }
            self.onHistoryStep?(back)
        }
    }
    /// Back (true) or Forward (false) asked for by a mouse button or swipe (the tab decides how).
    var onHistoryStep: ((Bool) -> Void)?
    override func scrollWheel(with event: NSEvent) { if !covered(event) { super.scrollWheel(with: event) } }
    override func mouseMoved(with event: NSEvent) { if !covered(event) { super.mouseMoved(with: event) } }
    override func mouseEntered(with event: NSEvent) { if !covered(event) { super.mouseEntered(with: event) } }
    override func cursorUpdate(with event: NSEvent) {
        if covered(event) { NSCursor.arrow.set() } else { super.cursorUpdate(with: event) }
    }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { onFocus?() }
        return accepted
    }

    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        super.willOpenMenu(menu, with: event)
        // Right-click on a link: Open Link in New Tab (WebKit's "New Window" item, which in Ufolio
        // has always opened a tab, now says so) and Open Link in Background Tab.
        if let index = menu.items.firstIndex(where: { $0.identifier?.rawValue == "WKMenuItemIdentifierOpenLinkInNewWindow" }) {
            let original = menu.items[index]
            original.title = "Open Link in New Tab"
            let background = NSMenuItem(title: "Open Link in Background Tab", action: #selector(openLinkInBackground(_:)), keyEquivalent: "")
            background.target = self
            background.representedObject = original
            menu.insertItem(background, at: index + 1)
        }
        guard onHideElements != nil, url != nil else { return }
        menu.addItem(.separator())
        if WebKitExtras.canPictureInPicture(self) {
            let pip = NSMenuItem(title: "Picture in Picture", action: #selector(pictureInPicture), keyEquivalent: "")
            pip.target = self
            pip.image = NSImage(systemSymbolName: "pip.enter", accessibilityDescription: nil)
            menu.addItem(pip)
        }
        let item = NSMenuItem(title: "Hide Elements on This Page…", action: #selector(hideElements), keyEquivalent: "")
        item.target = self
        item.image = NSImage(systemSymbolName: "eye.slash", accessibilityDescription: nil)
        menu.addItem(item)
    }

    /// The next tab this page opens stays in the background (set just before WebKit opens it).
    var openNextInBackground = false

    @objc private func openLinkInBackground(_ sender: NSMenuItem) {
        guard let original = sender.representedObject as? NSMenuItem, let action = original.action else { return }
        openNextInBackground = true
        NSApp.sendAction(action, to: original.target, from: original)
        // WebKit asks for the new tab straight away; never let the flag linger for a later one.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.openNextInBackground = false }
    }

    @objc private func hideElements() { onHideElements?() }
    @objc private func pictureInPicture() { WebKitExtras.togglePictureInPicture(self) }
}

extension String {
    var strippingWWW: String { hasPrefix("www.") ? String(dropFirst(4)) : self }
}
