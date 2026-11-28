import AppKit
import QuartzCore

/// Testing only (UFOLIO_FLUID_TEST=1): Project Fluid's smoothness meter. Opens Settings and, for
/// every section: how long switching to it takes, then a smooth scroll to the bottom and back
/// (as a trackpad would), counting frames that arrived late (each one a visible stutter).
/// UFOLIO_FLUID_TABS=general,appearance limits it to those sections.
@MainActor
enum FluidTest {
    private static var started = false

    static func startIfAsked() {
        guard !started, ProcessInfo.processInfo.environment["UFOLIO_FLUID_TEST"] != nil else { return }
        started = true
        let only = ProcessInfo.processInfo.environment["UFOLIO_FLUID_TABS"].map { Set($0.split(separator: ",").map(String.init)) }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            SettingsOpener.open(tab: .general)
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard let window = SettingsWindow.current, let view = window.contentView else { report("no settings window"); NSApp.terminate(nil); return }
            let meter = Meter(view: view)
            var lines: [String] = []
            var totalLate = 0, totalFrames = 0
            // UFOLIO_FLUID_PASSES=2: round every section twice (the second visit shows what's left
            // once each section has been built once); scrolling is measured on the last round.
            let passes = ProcessInfo.processInfo.environment["UFOLIO_FLUID_PASSES"].flatMap(Int.init) ?? 1
            for pass in 1...max(1, passes) {
            var switches: [String] = []
            for tab in SettingsTab.allCases where only?.contains(tab.rawValue) ?? true {
                // Switching section: from the click until the new section's first frame is drawn.
                meter.reset()
                let begin = CACurrentMediaTime()
                UserDefaults.standard.set(tab.rawValue, forKey: "settingsTab")
                await meter.nextFrame()
                let switchMs = Int((CACurrentMediaTime() - begin) * 1000)
                try? await Task.sleep(nanoseconds: 700_000_000)
                let settleLate = meter.late
                switches.append("\(tab.rawValue) \(switchMs)")
                if pass == passes {
                    // How many AppKit views the section is made of (each is laid out, tracked and
                    // searched under the pointer as you scroll).
                    var count = 0, kinds: [String: Int] = [:]
                    func walk(_ v: NSView) { count += 1; kinds[String(describing: type(of: v)).prefix(40).description, default: 0] += 1; v.subviews.forEach(walk) }
                    walk(view)
                    let top = kinds.sorted { $0.value > $1.value }.prefix(6).map { "\($0.key) \($0.value)" }.joined(separator: ", ")
                    lines.append("\(tab.rawValue): \(count) views (\(top))")
                }
                if pass < passes { continue }
                // Scrolling: down to the bottom and back up at a steady trackpad speed.
                guard let scroll = detailScrollView(in: view) else { lines.append("\(tab.rawValue): switch \(switchMs) ms, no scroll view"); continue }
                // UFOLIO_FLUID_POINTER=over|away: the pointer parked over the page, or off the window.
                if let where_ = ProcessInfo.processInfo.environment["UFOLIO_FLUID_POINTER"], let screen = window.screen {
                    let f = window.frame, h = screen.frame.height
                    let p = where_ == "away" ? CGPoint(x: 5, y: 5) : CGPoint(x: f.midX + 120, y: h - f.midY)
                    CGWarpMouseCursorPosition(p)
                    try? await Task.sleep(nanoseconds: 300_000_000)
                }
                meter.reset()
                await meter.scroll(scroll, speed: 1400)
                let frames = meter.frames, late = meter.late, worst = Int(meter.worst * 1000)
                totalLate += late; totalFrames += frames
                lines.append("\(tab.rawValue): switch \(switchMs) ms (late after: \(settleLate)), scroll \(frames) frames, \(late) late, worst \(worst) ms, height \(Int(scroll.documentView?.frame.height ?? 0))")
            }
            lines.append("pass \(pass) switches (ms): " + switches.joined(separator: ", "))
            }
            lines.append("TOTAL scroll: \(totalFrames) frames, \(totalLate) late (\(totalFrames > 0 ? totalLate * 1000 / totalFrames : 0)‰)")
            for line in lines { report(line) }
            NSApp.terminate(nil)
        }
    }

    /// Testing only (UFOLIO_FLUID_UI=1): the browser window's everyday moves, each timed from the
    /// action to its first frame, with late frames counted over the half second after (when its
    /// animation plays). Each is done several times and the median reported.
    static func browserIfAsked(in model: BrowserModel) {
        guard ProcessInfo.processInfo.environment["UFOLIO_FLUID_UI"] != nil, !started else { return }
        started = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard let window = model.window, let view = window.contentView else { report("no window"); NSApp.terminate(nil); return }
            NSApp.activate(ignoringOtherApps: true); window.makeKeyAndOrderFront(nil)
            // A few ordinary tabs to switch between.
            for url in ["https://en.wikipedia.org/wiki/Mars", "https://www.apple.com/", "https://news.ycombinator.com/"] {
                model.newTab(url: URL(string: url)!)
            }
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            let meter = Meter(view: view)
            @MainActor func measure(_ name: String, times: Int = 6, _ action: @escaping @MainActor () -> Void, undo: (@MainActor () -> Void)? = nil) async {
                var firsts: [Int] = [], lates: [Int] = [], worst = 0.0
                for _ in 0..<times {
                    meter.reset()
                    let begin = CACurrentMediaTime()
                    action()
                    await meter.nextFrame()
                    firsts.append(Int((CACurrentMediaTime() - begin) * 1000))
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    lates.append(meter.late); worst = max(worst, meter.worst)
                    if let undo { undo(); try? await Task.sleep(nanoseconds: 500_000_000) }
                }
                let median = firsts.sorted()[firsts.count / 2]
                await report("\(name): first frame \(median) ms (median), late frames \(lates.reduce(0, +)) over \(times), worst \(Int(worst * 1000)) ms")
            }
            // UFOLIO_FLUID_ONLY=switch|sidebar|palette|newtab, UFOLIO_FLUID_TIMES=n: one action, n times (to profile it).
            let only = ProcessInfo.processInfo.environment["UFOLIO_FLUID_ONLY"]
            let times = ProcessInfo.processInfo.environment["UFOLIO_FLUID_TIMES"].flatMap(Int.init) ?? 6
            if only == nil || only == "palette" { await measure("command palette", times: times, { model.paletteOpen = true }, undo: { model.paletteOpen = false }) }
            if only == nil || only == "sidebar" { await measure("sidebar", times: times, { model.sidebarOpen = true }, undo: { model.sidebarOpen = false }) }
            if only == nil || only == "switch" { await measure("switch tab", times: times, { model.selectAdjacentTab(1) }) }
            if only == nil || only == "newtab" { await measure("new tab", times: times, { model.newTab(focus: true) }, undo: { if let t = model.selectedTab { model.close(t) } }) }
            NSApp.terminate(nil)
        }
    }

    private static func report(_ text: String) { FileHandle.standardError.write("fluid: \(text)\n".data(using: .utf8)!) }

    /// The section's own scroll area: the widest scroll view in the window (the sidebar is narrower).
    private static func detailScrollView(in root: NSView) -> NSScrollView? {
        var found: [NSScrollView] = []
        func walk(_ v: NSView) { if let s = v as? NSScrollView { found.append(s) }; v.subviews.forEach(walk) }
        walk(root)
        // Only one that's actually showing (sections you've visited stay built, faded out).
        func visible(_ v: NSView) -> Bool {
            var view: NSView? = v
            while let current = view {
                if current.isHidden || current.alphaValue < 0.05 || (current.layer?.opacity ?? 1) < 0.05 { return false }
                view = current.superview
            }
            return true
        }
        return found.filter { ($0.documentView?.frame.height ?? 0) > $0.contentView.bounds.height + 20 && visible($0) }
            .max { $0.frame.width < $1.frame.width }
    }

    /// Counts frames from the display, noting any that came late.
    private final class Meter: NSObject {
        private var link: CADisplayLink?
        private var last: CFTimeInterval = 0
        private(set) var frames = 0
        private(set) var late = 0
        private(set) var worst: CFTimeInterval = 0
        private var waiters: [CheckedContinuation<Void, Never>] = []
        private var onTick: ((CFTimeInterval) -> Bool)?

        init(view: NSView) {
            super.init()
            link = view.displayLink(target: self, selector: #selector(tick(_:)))
            link?.add(to: .main, forMode: .common)
        }

        func reset() { frames = 0; late = 0; worst = 0; last = 0 }

        @objc private func tick(_ link: CADisplayLink) {
            let now = link.timestamp
            let expected = max(link.targetTimestamp - link.timestamp, 1.0 / 240)
            if last > 0 {
                let gap = now - last
                frames += 1
                worst = max(worst, gap)
                if gap > expected * 1.5 { late += 1 }
            }
            last = now
            let pending = waiters; waiters = []
            pending.forEach { $0.resume() }
            if let onTick, !onTick(now) { self.onTick = nil }
        }

        func nextFrame() async { await withCheckedContinuation { waiters.append($0) } }

        /// Scrolls to the bottom and back, a step every frame, `speed` points a second.
        func scroll(_ scroll: NSScrollView, speed: CGFloat) async {
            let clip = scroll.contentView
            let maxY = max(0, (scroll.documentView?.frame.height ?? 0) - clip.bounds.height)
            clip.scroll(to: .zero); scroll.reflectScrolledClipView(clip)
            var y: CGFloat = 0, down = true, previous: CFTimeInterval = 0
            await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
                onTick = { now in
                    let dt = previous > 0 ? now - previous : 1.0 / 60
                    previous = now
                    y += (down ? 1 : -1) * speed * CGFloat(dt)
                    if down, y >= maxY { y = maxY; down = false }
                    if !down, y <= 0 {
                        clip.scroll(to: .zero); scroll.reflectScrolledClipView(clip)
                        done.resume(); return false
                    }
                    // Flipped or not, the visible top moves through the document.
                    let origin = scroll.documentView?.isFlipped ?? true ? y : maxY - y
                    clip.scroll(to: NSPoint(x: 0, y: origin)); scroll.reflectScrolledClipView(clip)
                    return true
                }
            }
        }
    }
}
