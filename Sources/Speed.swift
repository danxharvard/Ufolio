import WebKit

/// Speed: the engine settings Safari uses to make pages appear near instantly, which WebKit
/// switches off for every other app, plus getting connections ready before you need them.
///
/// - One shared web-process pool that keeps a fresh page process ready (so a new tab or site
///   doesn't wait for one to start) and reuses recent sites' processes (so Back, and going
///   between sites, doesn't start from scratch).
/// - Preconnecting: as soon as it's likely you'll go somewhere (you hover a link, press on it, or
///   type into the address bar), the address is looked up and the secure connection opened,
///   which takes a tenth to half a second off the wait. Nothing is downloaded.
///
/// Every private call checks the method exists first: if a future macOS removes one, Ufolio
/// simply loses that speed-up instead of crashing.
enum Speed {
    /// Off only for measuring (UFOLIO_SPEED_OFF in the environment), to compare against.
    static let enabled = ProcessInfo.processInfo.environment["UFOLIO_SPEED_OFF"] == nil

    /// Every web view uses this pool.
    static let pool: WKProcessPool = (enabled ? makePool() : nil) ?? WKProcessPool()

    private static func makePool() -> WKProcessPool? {
        guard let configClass = NSClassFromString("_WKProcessPoolConfiguration") as? NSObject.Type else { return nil }
        let config = configClass.init()
        for key in ["usesWebProcessCache", "prewarmsProcessesAutomatically"] {
            let setter = NSSelectorFromString("set" + key.prefix(1).uppercased() + key.dropFirst() + ":")
            if config.responds(to: setter) { config.setValue(true, forKey: key) }
        }
        let initSelector = NSSelectorFromString("_initWithConfiguration:")
        let allocSelector = NSSelectorFromString("alloc")
        guard WKProcessPool.instancesRespond(to: initSelector),
              let initMethod = class_getInstanceMethod(WKProcessPool.self, initSelector) else { return nil }
        typealias Alloc = @convention(c) (AnyClass, Selector) -> Unmanaged<AnyObject>
        typealias Init = @convention(c) (AnyObject, Selector, AnyObject) -> Unmanaged<AnyObject>?
        let allocIMP = (WKProcessPool.self as AnyClass).method(for: allocSelector)
        let raw = unsafeBitCast(allocIMP, to: Alloc.self)(WKProcessPool.self, allocSelector)
        let initialise = unsafeBitCast(method_getImplementation(initMethod), to: Init.self)
        return initialise(raw.takeUnretainedValue(), initSelector, config)?.takeRetainedValue() as? WKProcessPool
    }

    /// Gives back the memory of cached page processes (when macOS is short of memory).
    static func releaseCachedProcesses() {
        trimWork?.cancel()
        trimWork = nil
        let selector = NSSelectorFromString("_clearWebProcessCache")
        if pool.responds(to: selector) { pool.perform(selector) }
    }

    private static var trimWork: DispatchWorkItem?

    /// After tabs close, their page processes are kept a little while (Reopen Closed Tab is then
    /// instant), then let go: measured with 30 tabs, the cache otherwise held on to about 2 GB.
    static func trimSoon() {
        trimWork?.cancel()
        let work = DispatchWorkItem { releaseCachedProcesses() }
        trimWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 30, execute: work)
    }

    // MARK: Preconnecting

    private static var recent: [String: Date] = [:]

    /// Opens a connection to the site's server ahead of time, through this web view (so with its
    /// profile's cookies, or a Stealth window's own). At most once every 30 seconds per site.
    static func preconnect(_ url: URL?, in webView: WKWebView?) {
        guard enabled, let url, let webView, let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = url.host?.lowercased(), !host.isEmpty, !TorrentTools.isAdNetwork(host) else { return }
        let origin = scheme + "://" + host + (url.port.map { ":\($0)" } ?? "")
        let now = Date()
        if let last = recent[origin], now.timeIntervalSince(last) < 30 { return }
        if recent.count > 300 { recent = recent.filter { now.timeIntervalSince($0.value) < 30 } }
        recent[origin] = now
        let selector = NSSelectorFromString("_preconnectToServer:")
        guard webView.responds(to: selector), let target = URL(string: origin) else { return }
        webView.perform(selector, with: target)
    }

    // MARK: Links on the page

    static let handlerName = "ufolioPreconnect"

    /// Watches the pointer over links (in Ufolio's own script world, out of the page's reach):
    /// a link held under the pointer for a moment, or pressed, gets its server connected.
    static let hoverScript = WKUserScript(source: """
    (function () {
      if (window.__ufolioPreconnect) return; window.__ufolioPreconnect = true;
      var sent = Object.create(null), count = 0, timer = null;
      function origin(a) {
        try {
          var u = new URL(a.href, location.href);
          if (u.protocol !== 'https:' && u.protocol !== 'http:') return null;
          return u.origin === location.origin ? null : u.origin;
        } catch (e) { return null; }
      }
      function send(a) {
        var o = a && origin(a);
        if (!o || sent[o] || count >= 40) return;
        sent[o] = true; count++;
        try { window.webkit.messageHandlers.\(handlerName).postMessage(o); } catch (e) {}
      }
      document.addEventListener('mouseover', function (e) {
        if (!e.isTrusted) return;
        var a = e.target && e.target.closest ? e.target.closest('a[href]') : null;
        clearTimeout(timer);
        if (a) timer = setTimeout(function () { send(a); }, 60);
      }, { capture: true, passive: true });
      document.addEventListener('mousedown', function (e) {
        if (!e.isTrusted) return;
        var a = e.target && e.target.closest ? e.target.closest('a[href]') : null;
        send(a);
        // Pressing on a plain link in this tab: start loading it now, a moment before the click
        // lands (only what the click itself would do; never on hover).
        if (!a || e.button !== 0 || e.metaKey || e.ctrlKey || e.shiftKey || e.altKey) return;
        if (a.hasAttribute('download') || (a.target && a.target !== '_self')) return;
        try {
          var u = new URL(a.href, location.href);
          if (u.protocol !== 'https:' && u.protocol !== 'http:') return;
          if (u.origin === location.origin && u.pathname === location.pathname && u.search === location.search) return;
          window.webkit.messageHandlers.\(handlerName).postMessage({ preload: u.href });
        } catch (err) {}
      }, { capture: true, passive: true });
    })();
    """, injectionTime: .atDocumentEnd, forMainFrameOnly: true, in: .defaultClient)

    final class Handler: NSObject, WKScriptMessageHandler {
        static let shared = Handler()
        private let registered = NSHashTable<WKUserContentController>.weakObjects()

        func register(_ controller: WKUserContentController) {
            guard !registered.contains(controller) else { return }
            registered.add(controller)
            controller.add(self, contentWorld: .defaultClient, name: Speed.handlerName)
        }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.frameInfo.isMainFrame else { return }
            if let body = message.body as? [String: Any], let text = body["preload"] as? String, text.count < 2000,
               let url = URL(string: text), let webView = message.webView {
                let tab = BrowserModel.all.allObjects.lazy.flatMap(\.tabs).first { $0.webView === webView }
                Preloader.preload(url, for: tab, lifetime: 2)
                return
            }
            guard let text = message.body as? String, text.count < 300, let url = URL(string: text) else { return }
            Speed.preconnect(url, in: message.webView)
        }
    }
}


// MARK: - Measuring

/// A page-load benchmark, run only when Ufolio is started with UFOLIO_BENCH set to a file of
/// addresses (one per line). It loads each one in turn, twice (a first visit, then a return
/// visit), then tests Back, writes the timings to UFOLIO_BENCH_OUT and quits.
enum SpeedBenchmark {
    static func startIfAsked(in model: BrowserModel) {
        let env = ProcessInfo.processInfo.environment
        guard let list = env["UFOLIO_BENCH"], let out = env["UFOLIO_BENCH_OUT"],
              let text = try? String(contentsOfFile: list, encoding: .utf8) else { return }
        let urls = text.split(whereSeparator: \.isNewline).compactMap { URL(string: String($0).trimmingCharacters(in: .whitespaces)) }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 4_000_000_000)   // let launch settle
            LagMonitor.start()
            var rows: [String] = ["round,url,commit_ms,finish_ms,fcp_ms"]
            for round in ["first", "return"] {
                for url in urls {
                    guard let tab = model.selectedTab else { break }
                    // UFOLIO_BENCH_PRELOAD: as if you'd paused on it first (Instant pages).
                    if ProcessInfo.processInfo.environment["UFOLIO_BENCH_PRELOAD"] != nil {
                        Preloader.preload(url, for: tab)
                        try? await Task.sleep(nanoseconds: 3_000_000_000)
                    }
                    let (commit, finish, fcp) = await measure(in: tab) { tab.load(url) }
                    rows.append("\(round),\(url.host ?? ""),\(commit),\(finish),\(fcp)")
                    try? rows.joined(separator: "\n").write(toFile: out, atomically: true, encoding: .utf8)
                }
            }
            // Back: from the last page to the one before it.
            if urls.count >= 2, let tab = model.selectedTab {
                for _ in 0..<3 {
                    let (commit, finish, _) = await measure(in: tab) { tab.goBack() }
                    rows.append("back,\(tab.webView.url?.host ?? ""),\(commit),\(finish),\(gotFinish ? 1 : 0)")
                    try? rows.joined(separator: "\n").write(toFile: out, atomically: true, encoding: .utf8)
                    _ = await measure(in: tab) { tab.goForward() }
                }
            }
            rows.append(LagMonitor.summary)
            try? rows.joined(separator: "\n").write(toFile: out, atomically: true, encoding: .utf8)
            NSApp.terminate(nil)
        }
    }

    /// Whether the last measured load reported "finished" itself.
    @MainActor static var gotFinish = true
    static let active = ProcessInfo.processInfo.environment["UFOLIO_BENCH"] != nil
    static let committed = Notification.Name("UfolioBenchCommitted")
    static let finished = Notification.Name("UfolioBenchFinished")

    /// Time from starting a load until WebKit says the new page is showing (committed) and
    /// until it has finished loading, and the page's own first-contentful-paint time.
    @MainActor private static func measure(in tab: BrowserTab, _ start: () -> Void) async -> (Int, Int, Int) {
        var commitAt: Date?
        var finishAt: Date?
        let a = NotificationCenter.default.addObserver(forName: committed, object: tab, queue: .main) { _ in if commitAt == nil { commitAt = Date() } }
        let b = NotificationCenter.default.addObserver(forName: finished, object: tab, queue: .main) { _ in if finishAt == nil { finishAt = Date() } }
        defer { NotificationCenter.default.removeObserver(a); NotificationCenter.default.removeObserver(b) }
        let begin = Date()
        let before = tab.webView
        start()
        // A page swapped in ready-made (Instant pages, or a kept page on Back) shows at once.
        if tab.webView !== before, !tab.webView.isLoading {
            commitAt = Date()
            finishAt = commitAt
        }
        // A page restored from the back/forward cache may not report "finished": committed and
        // no longer loading counts as done.
        while finishAt == nil, !(commitAt != nil && !tab.webView.isLoading), Date().timeIntervalSince(begin) < 30 {
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
        if finishAt == nil, commitAt != nil { finishAt = Date(); gotFinish = false } else { gotFinish = true }
        let finish = Int(((finishAt ?? Date()).timeIntervalSince(begin)) * 1000)
        let commit = commitAt.map { Int($0.timeIntervalSince(begin) * 1000) } ?? -1
        let script = "const p = performance.getEntriesByName('first-contentful-paint')[0]; return p ? Math.round(p.startTime) : -1;"
        let fcp = ((try? await tab.webView.callAsyncJavaScript(script, contentWorld: .defaultClient)) as? NSNumber)?.intValue ?? -1
        try? await Task.sleep(nanoseconds: 500_000_000)
        return (commit, finish, fcp)
    }
}


// MARK: - Leak checking

/// How many tabs, web views and windows are alive (for the leak test; costs nothing otherwise).
struct LiveCount {
    var tabs = 0
    var webViews = 0
    var windows = 0
    private static var counts = LiveCount()
    private static let lock = NSLock()
    static func change(_ field: WritableKeyPath<LiveCount, Int>, by delta: Int) {
        lock.lock(); counts[keyPath: field] += delta; lock.unlock()
    }
    static var now: LiveCount { lock.lock(); defer { lock.unlock() }; return counts }
}

/// Run only when Ufolio is started with UFOLIO_LEAKTEST set to a file of addresses and
/// UFOLIO_LEAKTEST_DIR to a folder: opens 30 tabs, then closes them, noting what's still alive
/// at each stage (and writing a marker so a script can measure memory from outside).
enum LeakTest {
    static func startIfAsked(in model: BrowserModel) {
        let env = ProcessInfo.processInfo.environment
        guard let list = env["UFOLIO_LEAKTEST"], let dir = env["UFOLIO_LEAKTEST_DIR"],
              let text = try? String(contentsOfFile: list, encoding: .utf8) else { return }
        let urls = text.split(whereSeparator: \.isNewline).compactMap { URL(string: String($0).trimmingCharacters(in: .whitespaces)) }
        Task { @MainActor in
            var report: [String] = []
            func stage(_ name: String) async {
                let c = LiveCount.now
                report.append("\(name): tabs \(c.tabs), webViews \(c.webViews), windows \(c.windows)")
                try? report.joined(separator: "\n").write(toFile: dir + "/report.txt", atomically: true, encoding: .utf8)
                try? name.write(toFile: dir + "/stage", atomically: true, encoding: .utf8)
                try? await Task.sleep(nanoseconds: 12_000_000_000)   // the script measures memory now
            }
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            await stage("start")
            for round in 0..<3 {
                for url in urls {
                    model.newTab(url: url, select: true)
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                }
                _ = round
            }
            try? await Task.sleep(nanoseconds: 20_000_000_000)
            await stage("open")
            let keep = model.tabs.first
            for tab in model.tabs where tab !== keep { model.close(tab, remember: true) }
            try? await Task.sleep(nanoseconds: 15_000_000_000)
            await stage("closed")
            try? await Task.sleep(nanoseconds: 25_000_000_000)   // the cache trims itself 30 s after closing
            await stage("a minute later")
            try? "done".write(toFile: dir + "/stage", atomically: true, encoding: .utf8)
            NSApp.terminate(nil)
        }
    }
}


/// Measures how often the main thread (which draws the window and answers clicks and typing)
/// was too busy to respond: a tick every 10 ms that should arrive on time.
enum LagMonitor {
    private static var stalls: [Double] = []
    private static var timer: DispatchSourceTimer?

    static func start() {
        var expected = DispatchTime.now().uptimeNanoseconds + 10_000_000
        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(deadline: .now() + .milliseconds(10), repeating: .milliseconds(10), leeway: .milliseconds(1))
        t.setEventHandler {
            let now = DispatchTime.now().uptimeNanoseconds
            let late = Double(Int64(now) - Int64(expected)) / 1_000_000
            if late > 50 { stalls.append(late) }
            expected = now + 10_000_000
        }
        t.resume()
        timer = t
    }

    static var summary: String {
        let over100 = stalls.filter { $0 > 100 }.count
        let worst = Int(stalls.max() ?? 0)
        let total = Int(stalls.reduce(0, +))
        return "lag,stalls>50ms=\(stalls.count),stalls>100ms=\(over100),worst_ms=\(worst),total_ms=\(total)"
    }
}

// MARK: - Instant pages

/// Loads the page you're most likely about to open in a hidden view, so when you do open it,
/// it's already there: no wait at all. Chosen only when you've as good as decided (the top
/// address-bar suggestion is a page from your history or bookmarks, or you rest the pointer on a
/// favourite, suggestion or bookmark). One page at a time, muted, with Force Field and every
/// protection on; never in Stealth windows or Power Saver; thrown away after 30 seconds unused.
enum Preloader {
    private final class Entry {
        let url: URL
        let tabID: UUID
        let view: WKWebView
        let started = Date()
        var failed = false
        init(url: URL, tabID: UUID, view: WKWebView) { self.url = url; self.tabID = tabID; self.view = view }
    }
    private static var current: Entry?
    private static var pending: DispatchWorkItem?
    private static let delegate = Delegate()

    static var enabled: Bool {
        Speed.enabled && Prefs.bool(Prefs.preloadPages) && !PerformanceCenter.shared.isPowerSaving
    }

    /// The same page, however it was written (trailing slash, #section).
    static func same(_ a: URL, _ b: URL) -> Bool {
        // Only the scheme and host ignore case: paths don't (/wiki/Apple and /wiki/APPLE are
        // different pages, and used to count as the same, so the wrong one could be swapped in).
        func key(_ u: URL) -> String {
            guard var c = URLComponents(url: u, resolvingAgainstBaseURL: false) else { return u.absoluteString }
            c.fragment = nil
            c.scheme = c.scheme?.lowercased()
            c.host = c.host?.lowercased().strippingWWW
            var s = c.string ?? u.absoluteString
            if s.hasSuffix("/") { s.removeLast() }
            return s
        }
        return key(a) == key(b)
    }

    /// Starts loading `url` for `tab`, replacing any earlier preload. `lifetime`: how long it's
    /// kept if not opened (a press on a link that never became a click, say on a web app that
    /// handles its own links, is let go after 2 seconds rather than 30).
    static func preload(_ url: URL, for tab: BrowserTab?, lifetime: TimeInterval = 30) {
        guard enabled, let tab, !tab.isPrivate, !tab.isAsleep,
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https", let host = url.host else { return }
        if let here = tab.url, same(here, url) { return }
        if let entry = current, entry.tabID == tab.id, same(entry.url, url), !entry.failed { return }
        // Pages the tab would stop or change first (look-alikes, tracking redirects) aren't preloaded.
        if Lookalike.check(host: host) != nil || CleanLinks.skipRedirect(url) != nil
            || (CleanLinks.isEnabled && CleanLinks.cleaned(url) != nil) || TorrentTools.isAdNetwork(host) { return }
        discard()
        let config = BrowserTab.makeConfiguration(privately: false, store: tab.webView.configuration.websiteDataStore)
        let view = HushWebView(frame: NSRect(x: 0, y: 0, width: 1280, height: 800), configuration: config)
        view.navigationDelegate = delegate
        view.uiDelegate = delegate
        ContentBlocker.shared.attach(config.userContentController)
        ContentBlocker.shared.update(config.userContentController, forHost: host)
        WebKitExtras.setMuted(true, view)
        view.pageZoom = tab.webView.pageZoom
        view.load(URLRequest(url: url))
        let entry = Entry(url: url, tabID: tab.id, view: view)
        current = entry
        DispatchQueue.main.asyncAfter(deadline: .now() + lifetime) { [weak entry] in
            if let entry, current === entry { discard() }
        }
    }

    /// Preloads after the pointer has rested for a moment (cancelled if it moves away).
    static func preloadSoon(_ url: URL, for tab: BrowserTab?, delay: TimeInterval = 0.25) {
        pending?.cancel()
        let work = DispatchWorkItem { [weak tab] in preload(url, for: tab) }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    static func cancelSoon() {
        pending?.cancel()
        pending = nil
    }

    /// The preloaded page for this address and tab, if there is one: it's handed over and no
    /// longer the preloader's.
    static func take(_ url: URL, for tab: BrowserTab) -> WKWebView? {
        guard let entry = current, entry.tabID == tab.id, !entry.failed,
              Date().timeIntervalSince(entry.started) < 30,
              same(entry.url, url) || (entry.view.url.map { same($0, url) } ?? false) else { return nil }
        current = nil
        entry.view.navigationDelegate = nil
        entry.view.uiDelegate = nil
        WebKitExtras.setMuted(false, entry.view)
        return entry.view
    }

    static func discard() {
        guard let entry = current else { return }
        current = nil
        entry.view.navigationDelegate = nil
        entry.view.uiDelegate = nil
        entry.view.stopLoading()
        WebKitExtras.close(entry.view)
    }

    private static func fail(_ view: WKWebView) {
        if current?.view === view { current?.failed = true; discard() }
    }

    /// Keeps a preloading page in its place: no pop-ups, downloads, dialogs or other apps.
    private final class Delegate: NSObject, WKNavigationDelegate, WKUIDelegate {
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            let scheme = action.request.url?.scheme?.lowercased() ?? ""
            let ok = ["http", "https", "about", "blob", "data"].contains(scheme)
            if !ok, action.targetFrame?.isMainFrame ?? true { Preloader.fail(webView) }
            decisionHandler(ok ? .allow : .cancel)
        }
        func webView(_ webView: WKWebView, decidePolicyFor response: WKNavigationResponse,
                     decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
            if response.isForMainFrame, !response.canShowMIMEType {
                Preloader.fail(webView)   // a download: only ever started by you
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { Preloader.fail(webView) }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { Preloader.fail(webView) }
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { Preloader.fail(webView) }
        func webView(_ webView: WKWebView, didReceive challenge: URLAuthenticationChallenge,
                     completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
            // A page asking for a password needs you there: leave it for the real visit.
            if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodHTTPBasic
                || challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodHTTPDigest {
                Preloader.fail(webView)
                completionHandler(.cancelAuthenticationChallenge, nil)
            } else {
                completionHandler(.performDefaultHandling, nil)
            }
        }
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? { nil }
        func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                     initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) { completionHandler() }
        func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                     initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) { completionHandler(false) }
        func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?,
                     initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) { completionHandler(nil) }
        /// Never the keychain from a preload (it could ask permission while you're typing).
        @objc(_webCryptoMasterKeyForWebView:)
        func webCryptoKey(_ webView: WKWebView) -> Data? { WebCryptoKey.key(privately: false) }
        @objc(_webCryptoMasterKeyForWebView:completionHandler:)
        func webCryptoKey(_ webView: WKWebView, completionHandler: @escaping (Data?) -> Void) {
            completionHandler(WebCryptoKey.key(privately: false))
        }
    }
}


/// UFOLIO_AUTOFILL_TEST=<address of a sign-in page>: loads it, fills it in and sends it, so the
/// offer to save can be checked (testing only).
enum AutofillTest {
    static func startIfAsked(in model: BrowserModel) {
        guard let address = ProcessInfo.processInfo.environment["UFOLIO_AUTOFILL_TEST"], let url = URL(string: address) else { return }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard let tab = model.selectedTab else { return }
            tab.load(url)
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            let fill = """
            for (const [sel, v] of [['#user', 'dan@example.com'], ['#pw', 'hunter2-test']]) {
              const el = document.querySelector(sel); el.value = v;
              el.dispatchEvent(new Event('input', { bubbles: true }));
            }
            document.querySelector('#go').click(); return 1;
            """
            _ = try? await tab.webView.callAsyncJavaScript(fill, contentWorld: .page)
            AutofillCenter.note("test: filled and clicked")
        }
    }
}
