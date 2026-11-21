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

        func bind<T>(_ keyPath: KeyPath<WKWebView, T>, _ apply: @escaping (BrowserTab, T) -> Void) {
            webView.publisher(for: keyPath)
                .receive(on: RunLoop.main)
                .sink { [weak self] value in if let self { apply(self, value) } }
                .store(in: &observers)
        }
        bind(\.title) { $0.title = $1 ?? "" }
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
        // Hand non-web links (mailto:, facetime:, app links…) to macOS.
        if let url = action.request.url, let scheme = url.scheme?.lowercased(),
           !["http", "https", "about", "blob", "data", "file"].contains(scheme) {
            NSWorkspace.shared.open(url)
            decisionHandler(.cancel, preferences)
            return
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
                webView.evaluateJavaScript("window.__hushAdsBlocked = true; window.__hushSweep && window.__hushSweep();")
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

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let alert = NSAlert()
        alert.messageText = frame.request.url?.host ?? "This page says"
        alert.informativeText = message
        alert.runModal()
        completionHandler()
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        let alert = NSAlert()
        alert.messageText = frame.request.url?.host ?? "This page says"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        completionHandler(alert.runModal() == .alertFirstButtonReturn)
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

/// Saves downloads to the chosen folder (or asks where) and bounces the Downloads stack in the Dock.
final class Downloads: NSObject, WKDownloadDelegate {
    static let shared = Downloads()
    private var destinations: [ObjectIdentifier: URL] = [:]

    static var folder: URL {
        let saved = Prefs.string(Prefs.downloadFolder)
        if !saved.isEmpty { return URL(fileURLWithPath: saved, isDirectory: true) }
        return FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
    }

    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse,
                  suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
        if Prefs.bool(Prefs.askWhereToSave) {
            let panel = NSSavePanel()
            panel.nameFieldStringValue = suggestedFilename
            panel.directoryURL = Self.folder
            let finish: (NSApplication.ModalResponse) -> Void = { response in
                let url = response == .OK ? panel.url : nil
                if let url {
                    try? FileManager.default.removeItem(at: url) // the panel already confirmed replacing it
                    self.destinations[ObjectIdentifier(download)] = url
                }
                completionHandler(url)
            }
            if let window = download.webView?.window {
                panel.beginSheetModal(for: window, completionHandler: finish)
            } else {
                finish(panel.runModal())
            }
            return
        }

        let folder = Self.folder
        let base = (suggestedFilename as NSString).deletingPathExtension
        let ext = (suggestedFilename as NSString).pathExtension
        var candidate = folder.appendingPathComponent(suggestedFilename)
        var n = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent(ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)")
            n += 1
        }
        destinations[ObjectIdentifier(download)] = candidate
        completionHandler(candidate)
    }

    func downloadDidFinish(_ download: WKDownload) {
        guard let url = destinations.removeValue(forKey: ObjectIdentifier(download)) else { return }
        DistributedNotificationCenter.default().post(
            name: .init("com.apple.DownloadFileFinished"), object: url.path)
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        destinations.removeValue(forKey: ObjectIdentifier(download))
    }
}

extension String {
    var strippingWWW: String { hasPrefix("www.") ? String(dropFirst(4)) : self }
}
