import SwiftUI
import WebKit
import Combine

/// One tab: a WKWebView plus the bits of its state the UI shows.
final class BrowserTab: NSObject, ObservableObject, Identifiable {
    let id = UUID()
    let webView: WKWebView
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
    /// The last address loaded by the user (typed, bookmark…), as opposed to by a page.
    private var userLoadedURL: URL?
    /// JavaScript dialogs shown on this page, and whether the user silenced them.
    private var dialogsShown = 0
    private var dialogsSilenced = false

    private var observers: Set<AnyCancellable> = []

    static func makeConfiguration() -> WKWebViewConfiguration {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.userContentController = WKUserContentController()
        config.applicationNameForUserAgent = "Version/18.0 Safari/605.1.15"
        config.preferences.isElementFullscreenEnabled = true
        config.preferences.isFraudulentWebsiteWarningEnabled = Prefs.bool(Prefs.fraudWarning)
        config.preferences.javaScriptCanOpenWindowsAutomatically = !Prefs.bool(Prefs.blockPopups)
        config.defaultWebpagePreferences.preferredContentMode = .desktop
        config.mediaTypesRequiringUserActionForPlayback = AutoplayPolicy.current.mediaTypes
        return config
    }

    init(model: BrowserModel, configuration: WKWebViewConfiguration? = nil) {
        self.model = model
        let config = configuration ?? BrowserTab.makeConfiguration()
        webView = WKWebView(frame: .zero, configuration: config)
        super.init()

        webView.allowsBackForwardNavigationGestures = true
        webView.allowsMagnification = true
        webView.navigationDelegate = self
        webView.uiDelegate = self
        let zoom = Prefs.double(Prefs.defaultZoom)
        webView.pageZoom = zoom > 0 ? zoom : 1
        ContentBlocker.shared.attach(webView.configuration.userContentController)
        AutofillCenter.shared.register(self)

        func bind<T>(_ keyPath: KeyPath<WKWebView, T>, _ apply: @escaping (BrowserTab, T) -> Void) {
            webView.publisher(for: keyPath)
                .receive(on: RunLoop.main)
                .sink { [weak self] value in if let self { apply(self, value) } }
                .store(in: &observers)
        }
        bind(\.title) { tab, title in
            tab.title = title ?? ""
            if let url = tab.url, let title, !title.isEmpty { HistoryStore.shared.updateTitle(url, title: title) }
        }
        bind(\.url) { tab, url in
            tab.url = url
            tab.model?.scheduleSessionSave()
        }
        bind(\.isLoading) { $0.isLoading = $1 }
        bind(\.estimatedProgress) { $0.progress = $1 }
        bind(\.canGoBack) { $0.canGoBack = $1 }
        bind(\.canGoForward) { $0.canGoForward = $1 }
        bind(\.hasOnlySecureContent) { $0.isSecure = $1 }
    }

    var displayTitle: String {
        if !title.isEmpty { return title }
        if let host = url?.host { return host.strippingWWW }
        return "New Tab"
    }

    /// True for a fresh tab that hasn't loaded anything yet: show the start page.
    var isBlank: Bool { url == nil && !isLoading }

    var host: String? { url?.host }

    func load(_ url: URL) {
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

    func tearDown() {
        observers.removeAll()
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        webView.removeFromSuperview()
    }
}

extension BrowserTab: WKNavigationDelegate {
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 preferences: WKWebpagePreferences,
                 decisionHandler: @escaping (WKNavigationActionPolicy, WKWebpagePreferences) -> Void) {
        // ⌘-click opens the link in a new background tab.
        if action.navigationType == .linkActivated, action.modifierFlags.contains(.command),
           let url = action.request.url {
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
            // Links to other apps (mailto:, zoommtg:, facetime:…) open only after you say so.
            if !["http", "https", "about", "blob", "data", "file", "javascript"].contains(scheme) {
                decisionHandler(.cancel, preferences)
                confirmOpeningApp(for: url)
                return
            }
        }
        if action.targetFrame?.isMainFrame ?? true {
            // Per-site shields must be in place before the page starts loading.
            ContentBlocker.shared.update(webView.configuration.userContentController,
                                         forHost: action.request.url?.host)
        }
        preferences.allowsContentJavaScript = Prefs.bool(Prefs.javaScript)
        decisionHandler(action.shouldPerformDownload ? .download : .allow, preferences)
    }

    func webView(_ webView: WKWebView, decidePolicyFor response: WKNavigationResponse,
                 decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        decisionHandler(response.canShowMIMEType ? .allow : .download)
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        blockedOnPage = 0
        dialogsShown = 0
        dialogsSilenced = false
    }

    /// Asks before a page opens another app, the way Safari does.
    private func confirmOpeningApp(for url: URL) {
        guard let app = NSWorkspace.shared.urlForApplication(toOpen: url), let window = webView.window else { return }
        let name = FileManager.default.displayName(atPath: app.path).replacingOccurrences(of: ".app", with: "")
        let alert = NSAlert()
        alert.messageText = "Open this link in “\(name)”?"
        alert.informativeText = "\(host?.strippingWWW ?? "This page") wants to open another app on your Mac."
        alert.addButton(withTitle: "Open")
        alert.addButton(withTitle: "Cancel")
        alert.icon = NSWorkspace.shared.icon(forFile: app.path)
        alert.beginSheetModal(for: window) { response in
            if response == .alertFirstButtonReturn { NSWorkspace.shared.open(url) }
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if let url = webView.url { HistoryStore.shared.record(url, title: webView.title ?? "") }
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        download.delegate = Downloads.shared
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        download.delegate = Downloads.shared
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
            self.blockedOnPage += 1
            BlockStats.shared.record(identifier)
            // Tell the page's ad-space collapser that ads really were blocked here.
            if self.blockedOnPage == 1 && Prefs.bool(Prefs.collapseAdSpace) {
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
        guard !dialogsSilenced, let window = webView.window else { completion(false); return }
        dialogsShown += 1
        let alert = NSAlert()
        let origin = frame.securityOrigin.host
        alert.messageText = origin.isEmpty ? "This page says" : "\(origin.strippingWWW) says"
        alert.informativeText = String(message.prefix(2_000))
        alert.addButton(withTitle: "OK")
        if confirm { alert.addButton(withTitle: "Cancel") }
        if dialogsShown > 1 {
            alert.showsSuppressionButton = true
            alert.suppressionButton?.title = "Don’t show more messages from this page"
        }
        alert.beginSheetModal(for: window) { [weak self] response in
            if alert.suppressionButton?.state == .on { self?.dialogsSilenced = true }
            completion(response == .alertFirstButtonReturn)
        }
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

extension String {
    var strippingWWW: String { hasPrefix("www.") ? String(dropFirst(4)) : self }
}
