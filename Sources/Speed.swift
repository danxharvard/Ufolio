import WebKit
import SwiftUI

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
              let host = url.host?.lowercased(), !host.isEmpty, !TorrentTools.isAdNetwork(host),
              // Never to an ad or tracking server: pointing at an ad link used to open a connection to
              // it (telling it your IP address) before you'd clicked anything.
              !BuiltInRules.isBlocked(host) || !Prefs.bool(Prefs.adBlockEnabled) else { return }
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
                let tab = BrowserModel.all.allObjects.lazy.flatMap(\.tabs).first { $0.hasPageView && $0.webView === webView }
                // Sites that switch pages with their own code (YouTube, Twitch…) never navigate on
                // a click: loading the link ahead there only loaded a whole second copy of the site
                // alongside the video you'd just clicked.
                if let here = webView.url?.host, let there = url.host, Domains.site(here) == Domains.site(there),
                   Preloader.handlesOwnLinks(here) { return }
                Preloader.preload(url, for: tab, lifetime: 2, pressed: true)
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
            var rows: [String] = ["round,url,commit_ms,finish_ms,fcp_ms,video_ready_ms,video_play_ms"]
            for round in ["first", "return"] {
                for url in urls {
                    guard let tab = model.selectedTab else { break }
                    // UFOLIO_BENCH_PRELOAD: as if you'd paused on it first (Instant pages).
                    if ProcessInfo.processInfo.environment["UFOLIO_BENCH_PRELOAD"] != nil {
                        Preloader.preload(url, for: tab)
                        try? await Task.sleep(nanoseconds: 3_000_000_000)
                    }
                    // In front, as when you browse (a window behind others is slowed by macOS).
                    NSApp.activate(ignoringOtherApps: true)
                    model.window?.makeKeyAndOrderFront(nil)
                    benchTarget = url.host
                    // UFOLIO_BENCH_SIMCLICK: as when you click a video on YouTube: Ufolio also
                    // loads that link ahead in the background (what it did on every press).
                    if let other = ProcessInfo.processInfo.environment["UFOLIO_BENCH_SIMCLICK"].flatMap(URL.init(string:)) {
                        Preloader.preload(other, for: tab, lifetime: 2)
                    }
                    let (commit, finish, fcp) = await measure(in: tab) { tab.load(url) }
                    rows.append("\(round),\(url.host ?? ""),\(commit),\(finish),\(fcp),\(lastVideo.ready),\(lastVideo.play)")
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
            // UFOLIO_BENCH_BACKALL: Back through every page, noting where each step lands.
            if ProcessInfo.processInfo.environment["UFOLIO_BENCH_BACKALL"] != nil, let tab = model.selectedTab {
                for step in 1..<max(urls.count, 1) {
                    let begin = Date()
                    tab.goBack()
                    var waited = 0
                    while tab.webView.url == nil || (tab.webView.isLoading && waited < 1500) { try? await Task.sleep(nanoseconds: 10_000_000); waited += 1 }
                    rows.append("backall\(step),\(tab.webView.url?.absoluteString ?? "-"),\(Int(Date().timeIntervalSince(begin) * 1000)),live=\(tab.hasParkedPages)")
                    try? rows.joined(separator: "\n").write(toFile: out, atomically: true, encoding: .utf8)
                }
            }
            rows.append(LagMonitor.summary)
            try? rows.joined(separator: "\n").write(toFile: out, atomically: true, encoding: .utf8)
            NSApp.terminate(nil)
        }
    }

    @MainActor static var benchTarget: String?
    @MainActor static var lastVideo: (ready: Int, play: Int) = (-1, -1)
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
        // Video pages: when the first sizeable video had data to show, and when it started playing
        // (polled every 50 ms alongside the load, for up to 20 seconds).
        lastVideo = (-1, -1)
        let wanted = benchTarget ?? ""
        let videoWatch = Task { @MainActor in
            let check = "if (location.host !== target) return null; const v = Array.from(document.querySelectorAll('video')).find(v => v.offsetWidth > 150); return v ? [v.readyState, v.currentTime] : null;"
            var ready = -1, play = -1
            while !Task.isCancelled, Date().timeIntervalSince(begin) < 20, play < 0 {
                if let r = (try? await tab.webView.callAsyncJavaScript(check, arguments: ["target": wanted], in: nil, contentWorld: .defaultClient)) as? [NSNumber], r.count == 2 {
                    let now = Int(Date().timeIntervalSince(begin) * 1000)
                    if ready < 0, r[0].intValue >= 2 { ready = now }
                    if play < 0, r[1].doubleValue > 0.05 { play = now }
                }
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
            lastVideo = (ready, play)
        }
        defer { videoWatch.cancel() }
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
        if ProcessInfo.processInfo.environment["UFOLIO_BENCH_VIDEO"] != nil { _ = await videoWatch.value }
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
        /// Pressed on a link on this site (a press-ahead preload), if it was.
        var pressedOn: String?
        /// Requests Force Field blocked while preloading (shown on the tab's counter once opened).
        var blocked: [(String, URL)] = []
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
    static func preload(_ url: URL, for tab: BrowserTab?, lifetime: TimeInterval = 30, pressed: Bool = false) {
        guard enabled, let tab, !tab.isPrivate, !tab.isAsleep, !tab.javaScriptOff,
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https", let host = url.host else { return }
        if let here = tab.url, same(here, url) { return }
        if let entry = current, entry.tabID == tab.id, same(entry.url, url), !entry.failed { return }
        // Links that do something rather than show something (sign out, unsubscribe, delete) are
        // never loaded early: a press you drag away from, or a pause on one, used to sign you out.
        if hasSideEffects(url) { return }
        // Pages the tab would stop or change first (look-alikes, tracking redirects) aren't preloaded.
        if Lookalike.check(host: host) != nil || CleanLinks.skipRedirect(url) != nil
            || (CleanLinks.isEnabled && CleanLinks.cleaned(url) != nil) || TorrentTools.isAdNetwork(host)
            || BuiltInRules.isBlocked(host) { return }   // an ad or tracker's own page: never loaded ahead
        discard()
        let config = BrowserTab.makeConfiguration(privately: false, store: tab.webView.configuration.websiteDataStore)
        // Laid out at the tab's own size, so swapping it in needs no second layout (it was always
        // 1280 × 800, so most pages reflowed, and some jumped, as they appeared).
        let size = tab.webView.bounds.size
        let frame = size.width > 100 && size.height > 100 ? NSRect(origin: .zero, size: size) : NSRect(x: 0, y: 0, width: 1280, height: 800)
        let view = HushWebView(frame: frame, configuration: config)
        view.navigationDelegate = delegate
        view.uiDelegate = delegate
        ContentBlocker.shared.attach(config.userContentController)
        ContentBlocker.shared.update(config.userContentController, forHost: host)
        WebKitExtras.setMuted(true, view)
        // Videos wait too: a page loading in the background used to play them (muted, but still
        // decoding) for up to 30 seconds.
        view.setAllMediaPlaybackSuspended(true)
        view.pageZoom = tab.webView.pageZoom
        view.load(URLRequest(url: url))
        let entry = Entry(url: url, tabID: tab.id, view: view)
        if pressed, let here = tab.url?.host, Domains.site(here) == Domains.site(host) { entry.pressedOn = Domains.site(here) }
        current = entry
        let pageBefore = tab.url, commitsBefore = tab.pageCommits, viewBefore = tab.webView
        DispatchQueue.main.asyncAfter(deadline: .now() + lifetime) { [weak entry, weak tab] in
            guard let entry, current === entry else { return }
            // Pressed, never opened, and the tab moved to another address without loading a new
            // page: the site switches pages with its own code. Its own links aren't loaded ahead
            // from now on (this run only).
            if let site = entry.pressedOn, let tab, tab.webView === viewBefore, tab.pageCommits == commitsBefore,
               tab.url != pageBefore { ownLinkSites.insert(site) }
            discard()
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
              // Still the tab's own website data (its Orbit may have moved to another profile
              // since, and the page would have shown the other profile's sign-ins).
              sameStore(entry.view.configuration.websiteDataStore, tab.webView.configuration.websiteDataStore),
              same(entry.url, url) || (entry.view.url.map { same($0, url) } ?? false) else { return nil }
        current = nil
        taken = entry.blocked
        entry.view.navigationDelegate = nil
        entry.view.uiDelegate = nil
        WebKitExtras.setMuted(false, entry.view)
        entry.view.setAllMediaPlaybackSuspended(false)
        return entry.view
    }

    /// The same website data (the default, or the same profile's), however WebKit hands it back.
    private static func sameStore(_ a: WKWebsiteDataStore, _ b: WKWebsiteDataStore) -> Bool {
        a === b || (a.isPersistent && b.isPersistent && a.identifier == b.identifier)
    }

    private static var taken: [(String, URL)] = []

    /// What was blocked on the page just handed over (once).
    static func takeBlocked() -> [(String, URL)] {
        defer { taken = [] }
        return taken
    }

    fileprivate static func noteBlocked(_ identifier: String, url: URL, in view: WKWebView) {
        guard let entry = current, entry.view === view, entry.blocked.count < 1000 else { return }
        entry.blocked.append((identifier, url))
    }

    /// Sites seen switching pages with their own code (for this run of Ufolio only).
    private static var ownLinkSites: Set<String> = ["youtube.com", "twitch.tv"]   // known; others are learned
    static func handlesOwnLinks(_ host: String) -> Bool { ownLinkSites.contains(Domains.site(host)) }

    /// Words in an address that mean opening it does something (signs you out, unsubscribes…).
    static func hasSideEffects(_ url: URL) -> Bool {
        let text = (url.path + "?" + (url.query ?? "")).lowercased()
        let words = ["logout", "log-out", "log_out", "signout", "sign-out", "sign_out", "logoff", "log-off",
                     "unsubscribe", "delete", "remove", "cancel", "confirm", "action=", "token=", "/api/"]
        return words.contains { text.contains($0) }
    }

    /// Its tab closed: nothing to hand it to.
    static func discard(forTab id: UUID) {
        if current?.tabID == id { discard() }
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
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, preferences: WKWebpagePreferences,
                     decisionHandler: @escaping (WKNavigationActionPolicy, WKWebpagePreferences) -> Void) {
            let scheme = action.request.url?.scheme?.lowercased() ?? ""
            let ok = ["http", "https", "about", "blob", "data"].contains(scheme)
            if !ok, action.targetFrame?.isMainFrame ?? true { Preloader.fail(webView) }
            // JavaScript follows your settings exactly as in a tab (Settings, and a site set to block
            // all scripts in Force Field): a preloaded page used to run scripts regardless.
            let host = action.request.url?.host
            let siteOn = !(host.map(ContentBlocker.shared.isShieldsDown) ?? false)
            let blocked = siteOn && ShieldSettings.shared.effective(for: host).scripts == .blockAll
            preferences.allowsContentJavaScript = Prefs.bool(Prefs.javaScript) && !blocked
            // The same auto-play rules as a tab: its video buffers while held paused here, and
            // starts the moment you open the page.
            if action.targetFrame?.isMainFrame ?? true {
                let rules = PerformanceCenter.shared.isEco ? (policy: 3, quirks: 0) : AutoplayPolicy.current.webKitPolicy
                WebKitExtras.setAutoplay(policy: rules.policy, quirks: rules.quirks, preferences)
            }
            decisionHandler(ok ? .allow : .cancel, preferences)
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
        /// Blocked requests, kept for the tab's counter (WebKit's private delegate call, as in tabs).
        @objc(_webView:contentRuleListWithIdentifier:performedAction:forURL:)
        func blocked(_ webView: WKWebView, contentRuleListWithIdentifier identifier: String,
                     performedAction action: NSObject, forURL url: URL) {
            guard action.responds(to: NSSelectorFromString("blockedLoad")),
                  (action.value(forKey: "blockedLoad") as? Bool) == true else { return }
            DispatchQueue.main.async { Preloader.noteBlocked(identifier, url: url, in: webView) }
        }
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

// MARK: - Force Field panel picture

/// Testing only (UFOLIO_SHIELD_SNAPSHOT=<png>, UFOLIO_SHIELD_URL=<page>): loads the page, then
/// draws the Force Field panel for it into a picture, and quits.
enum ShieldSnapshot {
    static func startIfAsked(in model: BrowserModel) {
        let env = ProcessInfo.processInfo.environment
        guard let out = env["UFOLIO_SHIELD_SNAPSHOT"] else { return }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if let page = env["UFOLIO_SHIELD_URL"].flatMap(URL.init(string:)), let tab = model.selectedTab { tab.load(page) }
            try? await Task.sleep(nanoseconds: 9_000_000_000)
            guard let tab = model.selectedTab else { NSApp.terminate(nil); return }
            FileHandle.standardError.write("snapshot: \(tab.url?.absoluteString ?? "-") blocked \(tab.blockedOnPage) ads \(tab.adsOnPage) trackers \(tab.trackersOnPage) sites \(tab.blockedSites.count)\n".data(using: .utf8)!)
            // UFOLIO_SNAPSHOT_VIEW: another view instead (start, appearance, spaces), for checking layouts.
            let root: AnyView
            switch env["UFOLIO_SNAPSHOT_VIEW"] {
            case "start": root = AnyView(StartPage(model: model).frame(width: 1280, height: 800))
            case "appearance": root = AnyView(AppearanceSettings().frame(width: 700, height: 2400))
            case "spaces": root = AnyView(SpacesSettings().frame(width: 700, height: 900))
            default: root = AnyView(ShieldsPanel(tab: tab, shieldsUp: env["UFOLIO_SHIELD_OFF"] == nil))
            }
            let host = NSHostingView(rootView: root)
            let appearance = NSAppearance(named: env["UFOLIO_SHIELD_LIGHT"] != nil ? .aqua : .darkAqua)
            host.appearance = appearance
            let size = host.fittingSize
            host.frame = NSRect(origin: .zero, size: size)
            let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.appearance = appearance
            window.backgroundColor = .windowBackgroundColor
            host.wantsLayer = true
            host.layer?.backgroundColor = appearance?.name == .aqua ? NSColor(white: 0.96, alpha: 1).cgColor : NSColor(white: 0.16, alpha: 1).cgColor
            window.contentView = host
            window.orderFront(nil)
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            host.layoutSubtreeIfNeeded()
            if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
                host.cacheDisplay(in: host.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: out))
            }
            NSApp.terminate(nil)
        }
    }
}

/// Testing only (UFOLIO_BG_TEST=<url>): opens the page in a background tab, waits ten seconds,
/// notes whether its video is playing (and with sound), then switches to it and checks again.
enum BackgroundPlayTest {
    static func startIfAsked(in model: BrowserModel) {
        guard let text = ProcessInfo.processInfo.environment["UFOLIO_BG_TEST"], let url = URL(string: text) else { return }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            let tab = model.newTab(url: url, select: false)
            let check = "const v = Array.from(document.querySelectorAll('video')).find(v => v.offsetWidth > 0 || v.currentTime > 0); return v ? [v.currentTime, v.paused ? 1 : 0, v.muted ? 1 : 0] : null;"
            func report(_ label: String) async {
                let r = (try? await tab.webView.callAsyncJavaScript(check, contentWorld: .defaultClient)) as? [NSNumber]
                FileHandle.standardError.write("bgtest \(label): \(r.map { "time \($0[0]) paused \($0[1]) muted \($0[2])" } ?? "no video")\n".data(using: .utf8)!)
            }
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            await report("in background")
            model.selectedID = tab.id
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            await report("after switching to it")
            NSApp.terminate(nil)
        }
    }
}

/// Testing only (UFOLIO_EVAL_URL=<page>, UFOLIO_EVAL_JS=<script returning a value>): loads the
/// page, waits, prints what the script returns, and quits.
enum EvalTest {
    private static var started = false
    static func startIfAsked(in model: BrowserModel) {
        let env = ProcessInfo.processInfo.environment
        guard !started, let address = env["UFOLIO_EVAL_URL"], let js = env["UFOLIO_EVAL_JS"] else { return }
        started = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            // UFOLIO_EVAL_TAB=<n>: switch to the n-th tab first (a tab restored from last time, say).
            if let n = env["UFOLIO_EVAL_TAB"].flatMap(Int.init), model.tabs.indices.contains(n) { model.selectedID = model.tabs[n].id }
            guard let tab = model.selectedTab else { return }
            // "current": leave the tab as it is (a restored session, say).
            if address != "current", let url = URL(string: address) { tab.load(url) }
            // UFOLIO_EVAL_WAIT: seconds to wait before running the script (6 by default).
            let wait = env["UFOLIO_EVAL_WAIT"].flatMap(Double.init) ?? 6
            try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            let value = try? await tab.webView.callAsyncJavaScript(js, contentWorld: .page)
            FileHandle.standardError.write("eval: \(value.map { "\($0)" } ?? "nil")\n".data(using: .utf8)!)
            NSApp.terminate(nil)
        }
    }
}

/// Testing only (UFOLIO_LAUNCH_TIME set): prints how long after the process started its first
/// window appeared, and when the next frame was drawn.
enum LaunchTimer {
    private static var done = false
    static let on = ProcessInfo.processInfo.environment["UFOLIO_LAUNCH_TIME"] != nil
    /// A step of launching, with the time since the process started (testing only).
    static func mark(_ step: String) {
        guard on else { return }
        var info = kinfo_proc(), size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        sysctl(&mib, 4, &info, &size, nil, 0)
        let start = info.kp_proc.p_un.__p_starttime
        let started = Double(start.tv_sec) + Double(start.tv_usec) / 1e6
        FileHandle.standardError.write("launch: \(step) \(Int((Date().timeIntervalSince1970 - started) * 1000)) ms\n".data(using: .utf8)!)
    }
    static func windowAppeared() {
        guard !done, ProcessInfo.processInfo.environment["UFOLIO_LAUNCH_TIME"] != nil else { return }
        done = true
        var info = kinfo_proc(), size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        sysctl(&mib, 4, &info, &size, nil, 0)
        let start = info.kp_proc.p_un.__p_starttime
        let started = Double(start.tv_sec) + Double(start.tv_usec) / 1e6
        let ms = { Int((Date().timeIntervalSince1970 - started) * 1000) }
        FileHandle.standardError.write("launch: window \(ms()) ms\n".data(using: .utf8)!)
        DispatchQueue.main.async { FileHandle.standardError.write("launch: first frame \(ms()) ms\n".data(using: .utf8)!) }
    }
}
