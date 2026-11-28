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
                if pass < passes { continue }
                // Scrolling: down to the bottom and back up at a steady trackpad speed.
                guard let scroll = detailScrollView(in: view) else { lines.append("\(tab.rawValue): switch \(switchMs) ms, no scroll view"); continue }
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

    private static func report(_ text: String) { FileHandle.standardError.write("fluid: \(text)\n".data(using: .utf8)!) }

    /// The section's own scroll area: the widest scroll view in the window (the sidebar is narrower).
    private static func detailScrollView(in root: NSView) -> NSScrollView? {
        var found: [NSScrollView] = []
        func walk(_ v: NSView) { if let s = v as? NSScrollView { found.append(s) }; v.subviews.forEach(walk) }
        walk(root)
        return found.filter { ($0.documentView?.frame.height ?? 0) > $0.contentView.bounds.height + 20 }
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
