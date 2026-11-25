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
        send(e.target && e.target.closest ? e.target.closest('a[href]') : null);
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
            guard message.frameInfo.isMainFrame, let text = message.body as? String, text.count < 300,
                  let url = URL(string: text) else { return }
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
            var rows: [String] = ["round,url,commit_ms,finish_ms,fcp_ms"]
            for round in ["first", "return"] {
                for url in urls {
                    guard let tab = model.selectedTab else { break }
                    let (commit, finish, fcp) = await measure(in: tab) { tab.load(url) }
                    rows.append("\(round),\(url.host ?? ""),\(commit),\(finish),\(fcp)")
                    try? rows.joined(separator: "\n").write(toFile: out, atomically: true, encoding: .utf8)
                }
            }
            // Back: from the last page to the one before it.
            if urls.count >= 2, let tab = model.selectedTab {
                for _ in 0..<3 {
                    let (commit, finish, _) = await measure(in: tab) { tab.webView.goBack() }
                    rows.append("back,\(tab.webView.url?.host ?? ""),\(commit),\(finish),\(gotFinish ? 1 : 0)")
                    try? rows.joined(separator: "\n").write(toFile: out, atomically: true, encoding: .utf8)
                    _ = await measure(in: tab) { tab.webView.goForward() }
                }
            }
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
        start()
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
