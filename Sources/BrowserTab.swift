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

    private var observers: Set<AnyCancellable> = []

    static func makeConfiguration() -> WKWebViewConfiguration {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.applicationNameForUserAgent = "Version/18.0 Safari/605.1.15"
        config.preferences.isElementFullscreenEnabled = true
        config.defaultWebpagePreferences.preferredContentMode = .desktop
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
        AdBlocker.shared.attach(to: webView)

        func bind<T>(_ keyPath: KeyPath<WKWebView, T>, _ apply: @escaping (BrowserTab, T) -> Void) {
            webView.publisher(for: keyPath)
                .receive(on: RunLoop.main)
                .sink { [weak self] value in if let self { apply(self, value) } }
                .store(in: &observers)
        }
        bind(\.title) { $0.title = $1 ?? "" }
        bind(\.url) { $0.url = $1 }
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
        webView.pageZoom = 1
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
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        // ⌘-click opens the link in a new background tab.
        if action.navigationType == .linkActivated, action.modifierFlags.contains(.command),
           let url = action.request.url {
            model?.newTab(url: url, select: false)
            decisionHandler(.cancel)
            return
        }
        // Hand non-web links (mailto:, facetime:, app links…) to macOS.
        if let url = action.request.url, let scheme = url.scheme?.lowercased(),
           !["http", "https", "about", "blob", "data", "file"].contains(scheme) {
            NSWorkspace.shared.open(url)
            decisionHandler(.cancel)
            return
        }
        decisionHandler(action.shouldPerformDownload ? .download : .allow)
    }

    func webView(_ webView: WKWebView, decidePolicyFor response: WKNavigationResponse,
                 decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        decisionHandler(response.canShowMIMEType ? .allow : .download)
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        download.delegate = Downloads.shared
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        download.delegate = Downloads.shared
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
}

/// Saves downloads to ~/Downloads and bounces the Downloads stack in the Dock.
final class Downloads: NSObject, WKDownloadDelegate {
    static let shared = Downloads()
    private var destinations: [ObjectIdentifier: URL] = [:]

    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse,
                  suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
        let folder = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
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
