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

    /// Fixed when the tab is made: a Stealth tab stays private even in the moment its window is
    /// going away (it used to count as not private then, and could write to history).
    let isPrivate: Bool

    /// Set when the page's process crashed: the tab shows a friendly Reload screen.
    @Published private(set) var crashed = false

    func recoverFromCrash() {
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
        if reader != nil { reader = nil } else if url != nil { ReaderMode.open(self) }
    }

    func toggleMute() {
        isMuted.toggle()
        WebKitExtras.setMuted(isMuted, webView)
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

    init(model: BrowserModel, configuration: WKWebViewConfiguration? = nil, store: WKWebsiteDataStore? = nil) {
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
        ContentBlocker.shared.attach(view.configuration.userContentController)
        HushlistLink.shared.register(view.configuration.userContentController)
        AutofillCenter.shared.register(self)
        ElementZapper.shared.register(self)
        (view as? HushWebView)?.onHideElements = { [weak self] in
            guard let self else { return }
            ElementZapper.shared.start(in: self)
        }
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
            if !tab.isPrivate, let url = tab.url, let title, !title.isEmpty { HistoryStore.shared.updateTitle(url, title: title) }
        }
        bind(\.url) { tab, url in
            // While waking from sleep the new web view briefly has no address; keep the old one.
            // The same goes for a tab restored from last time, which hasn't loaded yet.
            if (tab.waking || tab.isAsleep) && url == nil { return }
            if url != nil { tab.waking = false }
            guard tab.url != url else { return }
            tab.url = url
            // Pages that change without reloading (YouTube videos, web apps) never "finish
            // loading", so they're added to history here.
            if !tab.isLoading, !tab.isPrivate, let url, ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
                HistoryStore.shared.record(url, title: tab.webView.title ?? "")
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
        bind(\.canGoBack) { tab, value in if !tab.waking && tab.canGoBack != value { tab.canGoBack = value } }
        bind(\.canGoForward) { tab, value in if !tab.waking && tab.canGoForward != value { tab.canGoForward = value } }
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
    @Published private(set) var snapshotData: Data?
    var snapshot: NSImage? { snapshotData.flatMap(NSImage.init(data:)) }
    var lastActive = Date()
    private var sleepState: Any?
    private var waking = false

    func sleep() {
        guard !isAsleep, url != nil, !isLoading, model?.selectedTab !== self else { return }
        let config = WKSnapshotConfiguration()
        config.snapshotWidth = NSNumber(value: min(Double(webView.bounds.width), 900))
        webView.takeSnapshot(with: config) { [weak self] image, _ in
            guard let self, !self.isAsleep, self.model?.selectedTab !== self else { return }
            self.snapshotData = image.flatMap(Self.compressed)
            self.sleepState = self.webView.interactionState
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
        if let state { webView.interactionState = state } else if let address { webView.load(URLRequest(url: address)) }
        objectWillChange.send()
    }

    func wakeIfNeeded(loading: Bool = true) {
        guard isAsleep else { return }
        waking = true
        setUp(webView)
        if let state = sleepState {
            webView.interactionState = state
        } else if loading, let url {
            webView.load(URLRequest(url: url))
        }
        sleepState = nil
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
        if let host = url?.host { return host.strippingWWW }
        return "New Tab"
    }

    /// True for a fresh tab that hasn't loaded anything yet: show the start page.
    var isBlank: Bool { url == nil && !isLoading }

    var host: String? { url?.host }
    /// The site this tab last finished loading, to tell arriving at a site from moving around in it.
    private var lastFinishedHost: String?
    private var lastAppPrompt = Date.distantPast

    func load(_ url: URL) {
        // A sleeping tab's page isn't connected yet (no blocking, no delegates): wake it first,
        // going straight to the new address rather than restoring the old page.
        if isAsleep { sleepState = nil; wakeIfNeeded(loading: false) }
        lookalike = nil
        userLoadedURL = url
        webView.load(URLRequest(url: url))
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
        guard let window = webView.window, url != nil else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.webArchive]
        panel.nameFieldStringValue = Downloads.safeFilename(displayTitle) + ".webarchive"
        panel.directoryURL = Downloads.folder
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let destination = panel.url, let self else { return }
            self.webView.createWebArchiveData { result in
                if case .success(let data) = result { try? data.write(to: destination, options: .atomic) }
            }
        }
    }

    func tearDown() {
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
        if action.navigationType == .linkActivated, action.modifierFlags.contains(.command),
           let url = action.request.url, ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
            model?.newTab(url: url, select: false)
            decisionHandler(.cancel, preferences)
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
            if scheme == "file", let source = action.sourceFrame as WKFrameInfo?,
               ["http", "https"].contains(source.securityOrigin.protocol.lowercased()) {
                decisionHandler(.cancel, preferences)
                return
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
            if CleanLinks.isEnabled, action.request.httpMethod ?? "GET" == "GET", let clean = CleanLinks.cleaned(url) {
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
            // Per-site shields must be in place before the page starts loading.
            ContentBlocker.shared.update(webView.configuration.userContentController,
                                         forHost: action.request.url?.host)
        }
        // Script blocking: the site's Hush Guard setting (Block all turns JavaScript off for it).
        let scriptHost = (action.targetFrame?.isMainFrame ?? true) ? action.request.url?.host : host
        let siteOn = !(scriptHost.map(ContentBlocker.shared.isShieldsDown) ?? false)
        let scriptsBlocked = siteOn && ShieldSettings.shared.effective(for: scriptHost).scripts == .blockAll
        preferences.allowsContentJavaScript = Prefs.bool(Prefs.javaScript) && !javaScriptOff && !scriptsBlocked
        decisionHandler(action.shouldPerformDownload ? .download : .allow, preferences)
    }

    func webView(_ webView: WKWebView, decidePolicyFor response: WKNavigationResponse,
                 decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        decisionHandler(response.canShowMIMEType ? .allow : .download)
    }

    /// The page's web process crashed or was stopped by macOS.
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        guard webView === self.webView, !isAsleep else { return }
        crashed = true
        isPlayingAudio = false
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        if crashed { crashed = false }
        // Going back (or anywhere else) from a look-alike warning takes the warning away too.
        if lookalike != nil { lookalike = nil }
        pendingBlocked = 0; pendingAds = 0; pendingTrackers = 0; pendingSites = [:]
        if blockedOnPage != 0 { blockedOnPage = 0 }
        if adsOnPage != 0 { adsOnPage = 0 }
        if trackersOnPage != 0 { trackersOnPage = 0 }
        if !blockedSites.isEmpty { blockedSites = [:] }
        if translation != .none { setTranslation(.none, language: nil) }
        if reader != nil { reader = nil }
        if readerAvailable { readerAvailable = false }
        dialogsShown = 0
        dialogsSilenced = false
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

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if let url = webView.url {
            PageTranslator.shared.detect(in: self)
            ReaderMode.detect(in: self)
            if isMuted { WebKitExtras.setMuted(true, webView) }
            // Private windows leave no trace: no history, suggestions or report entries.
            guard !isPrivate else { return }
            HistoryStore.shared.record(url, title: webView.title ?? "")
            BookmarkOffer.shared.record(url, previousHost: lastFinishedHost)
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
        return model.newTab(configuration: configuration).webView
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
        SitePermissions.shared.request(kinds, host: origin.host, window: webView.window) {
            decisionHandler($0 ? .grant : .deny)
        }
    }

    // Location. WebKit on macOS only offers this through its private UI-delegate
    // API; without it, every site's location request is silently refused.
    @objc(_webView:requestGeolocationPermissionForOrigin:initiatedByFrame:decisionHandler:)
    func hush_requestLocation(_ webView: WKWebView, origin: WKSecurityOrigin, frame: WKFrameInfo,
                              decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        SitePermissions.shared.request([.location], host: origin.host, window: webView.window) {
            decisionHandler($0 ? .grant : .deny)
        }
    }

    @objc(_webView:requestGeolocationPermissionForFrame:decisionHandler:)
    func hush_requestLocationLegacy(_ webView: WKWebView, frame: WKFrameInfo,
                                    decisionHandler: @escaping (Bool) -> Void) {
        SitePermissions.shared.request([.location], host: frame.securityOrigin.host, window: webView.window,
                                       completion: decisionHandler)
    }
}

/// Hush's web view: adds "Hide Elements on This Page…" to the page's right-click menu.
final class HushWebView: WKWebView {
    var onHideElements: (() -> Void)?
    var onFocus: (() -> Void)?

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { onFocus?() }
        return accepted
    }

    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        super.willOpenMenu(menu, with: event)
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

    @objc private func hideElements() { onHideElements?() }
    @objc private func pictureInPicture() { WebKitExtras.togglePictureInPicture(self) }
}

extension String {
    var strippingWWW: String { hasPrefix("www.") ? String(dropFirst(4)) : self }
}
