import AppKit
import WebKit
import IOKit.ps
import Darwin

/// How Hush balances speed against battery life.
enum PowerMode: String, CaseIterable, Identifiable {
    case automatic, performance, balanced, batterySaver, eco
    var id: String { rawValue }

    var label: String {
        switch self {
        case .automatic: return "Automatic"
        case .performance: return "Performance"
        case .balanced: return "Balanced"
        case .batterySaver: return "Battery Saver"
        case .eco: return "Eco"
        }
    }

    var detail: String {
        switch self {
        case .automatic: return "Balanced when plugged in, Battery Saver on battery."
        case .performance: return "Smoothest scrolling and the quickest page loads."
        case .balanced: return "Fast and efficient. Ufolio’s everyday setting."
        case .batterySaver: return "Longer battery life and a cooler, quieter Mac."
        case .eco: return "Uses the least energy and data, for a smaller carbon footprint."
        }
    }

    var symbol: String {
        switch self {
        case .automatic: return "wand.and.stars"
        case .performance: return "hare.fill"
        case .balanced: return "gauge.with.dots.needle.50percent"
        case .batterySaver: return "battery.100percent.bolt"
        case .eco: return "leaf.fill"
        }
    }

    var colors: [Color] {
        switch self {
        case .automatic: return [Color(red: 0.58, green: 0.44, blue: 1.0), Color(red: 0.38, green: 0.26, blue: 0.86)]
        case .performance: return [Color(red: 1.0, green: 0.45, blue: 0.35), Color(red: 0.90, green: 0.25, blue: 0.30)]
        case .balanced: return [Color(red: 0.30, green: 0.60, blue: 1.0), Color(red: 0.15, green: 0.40, blue: 0.95)]
        case .batterySaver: return [Color(red: 1.0, green: 0.75, blue: 0.2), Color(red: 0.95, green: 0.55, blue: 0.1)]
        case .eco: return [Color(red: 0.30, green: 0.78, blue: 0.45), Color(red: 0.15, green: 0.58, blue: 0.30)]
        }
    }
}

import SwiftUI

/// Applies the power mode, watches the battery, Low Power Mode and memory pressure, and
/// measures how much memory Hush and its tabs use.
final class PerformanceCenter: ObservableObject {
    static let shared = PerformanceCenter()

    /// The mode in effect right now (Automatic resolved to Balanced or Power Saver).
    @Published private(set) var effectiveMode: PowerMode = .balanced
    @Published private(set) var onBattery = false
    @Published private(set) var lowPowerMode = false
    /// Automatic Power Mode: when a tab genuinely needs more (it's heavy, or playing video or
    /// sound, or using the camera), Ufolio lets it have the memory, then drops back to its
    /// low-memory default a few minutes after. nil = not active.
    @Published private(set) var powerBoost: PowerBoost?

    struct PowerBoost: Equatable {
        let reason: String
        let limit: UInt64
    }

    private var pressureSource: DispatchSourceMemoryPressure?
    private var timer: Timer?
    private var defaultsObserver: NSObjectProtocol?

    private init() {}

    var chosenMode: PowerMode { PowerMode(rawValue: Prefs.string(Prefs.powerMode)) ?? .automatic }
    /// Battery Saver and Eco both go easy on the Mac.
    var isPowerSaving: Bool { effectiveMode == .batterySaver || effectiveMode == .eco }
    var isEco: Bool { effectiveMode == .eco }

    /// Eco stops all autoplay; otherwise your Privacy & Security choice applies.
    var autoplayMediaTypes: WKAudiovisualMediaTypes { isEco ? .all : AutoplayPolicy.current.mediaTypes }

    /// Whether tabs you switch away from have their sound and video paused.
    var pausesBackgroundMedia: Bool { isEco || Prefs.bool(Prefs.pauseBackgroundMedia) }

    /// Starts watching. Called once at launch.
    func start() {
        refresh()
        NotificationCenter.default.addObserver(forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { [weak self] _ in
            self?.refresh()
        }
        defaultsObserver = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self, self.resolve() != self.effectiveMode else { return }
            self.refresh()
        }
        // Plugging in or unplugging: checked twice a minute (cheap) rather than hooking IOKit run loops.
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.refresh()
            self?.keepWithinMemoryLimit()
        }
        timer?.tolerance = 10

        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)
        source.setEventHandler { [weak self, weak source] in
            // Pictures kept in memory can always be fetched again.
            Task { await FaviconCache.shared.purgeMemory(); await NewsImages.shared.purgeMemory() }
            MainActor.assumeIsolated {
                SettingsWindow.releaseNow()          // rebuilt next time you open Settings
                BackgroundStore.shared.purgeIfHidden()   // the start page picture, if no start page shows
            }
            guard Prefs.bool(Prefs.freeMemoryAutomatically), let event = source?.data else { return }
            self?.sleepBackgroundTabs(idleFor: event.contains(.critical) ? 0 : 120)
        }
        source.resume()
        pressureSource = source
    }

    private func refresh() {
        let battery = Self.isOnBattery()
        let lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        if battery != onBattery { onBattery = battery }
        if lowPower != lowPowerMode { lowPowerMode = lowPower }
        let mode = resolve()
        if mode != effectiveMode { effectiveMode = mode }
    }

    /// Uses the battery state from the last check (refreshed every 30 seconds), so settings
    /// changes don't each ask IOKit again.
    private func resolve() -> PowerMode {
        let lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        switch chosenMode {
        case .automatic: return (onBattery || lowPower) ? .batterySaver : .balanced
        // Low Power Mode is the Mac asking every app to go easy: Performance steps down to Balanced.
        case .performance: return lowPower ? .balanced : .performance
        default: return chosenMode
        }
    }

    private static func isOnBattery() -> Bool {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let type = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() else { return false }
        return (type as String) == kIOPSBatteryPowerValue
    }

    // MARK: Tab Sleep

    /// Minutes before an inactive tab sleeps (0 = never). Battery Saver and Eco sleep tabs sooner.
    var sleepMinutes: Double {
        let chosen = Prefs.double(Prefs.tabSleepMinutes)
        guard chosen > 0 else { return 0 }
        return isPowerSaving ? min(chosen, 5) : chosen
    }

    /// Puts background tabs to sleep, skipping ones playing media or using the camera or microphone.
    func sleepBackgroundTabs(idleFor seconds: TimeInterval) {
        for model in BrowserModel.all.allObjects {
            model.sleepBackgroundTabs(idleFor: seconds)
        }
    }

    // MARK: Memory Saver

    static var memorySaverOn: Bool { Prefs.bool(Prefs.memorySaver) }

    /// The usual most memory Ufolio should use: your choice, or a quarter of this Mac's memory.
    static var baseMemoryLimit: UInt64 {
        let chosen = Prefs.double(Prefs.memoryLimitGB)
        if chosen > 0 { return UInt64(chosen * 1_073_741_824) }
        return max(1_073_741_824, ProcessInfo.processInfo.physicalMemory / 4)
    }

    /// The limit right now: higher while Power Mode is on.
    static var memoryLimit: UInt64 { shared.powerBoost?.limit ?? baseMemoryLimit }

    // MARK: Power Mode

    /// A tab using more than this is "heavy" (a big web app, a map, a 4K video…).
    static let heavyTabBytes: UInt64 = 250 * 1_048_576
    /// How long after the heavy work stops before Ufolio drops back to its usual limit.
    private static let powerCooldown: TimeInterval = 180
    private var lastNeededPower = Date.distantPast
    private var recentlyHeavy: [UUID: Date] = [:]

    /// Works out whether any tab needs more right now, and raises or lowers the limit to suit.
    func evaluatePowerMode(_ usage: Usage? = nil) {
        guard Prefs.bool(Prefs.autoPowerMode) else { if powerBoost != nil { powerBoost = nil }; return }
        let usage = usage ?? measure()
        var reason: String?
        for model in BrowserModel.all.allObjects {
            for tab in model.tabs where !tab.isAsleep {
                let bytes = usage.tabs.first { $0.id == tab.id }?.bytes ?? 0
                if bytes >= Self.heavyTabBytes { recentlyHeavy[tab.id] = Date() }
                let inFront = tab === model.selectedTab
                let capturing = tab.webView.cameraCaptureState != .none || tab.webView.microphoneCaptureState != .none
                if capturing { reason = reason ?? "“\(tab.displayTitle)” is using the camera or microphone" }
                else if tab.isPlayingAudio { reason = reason ?? "“\(tab.displayTitle)” is playing" }
                else if inFront && bytes >= Self.heavyTabBytes { reason = reason ?? "“\(tab.displayTitle)” is a heavy page" }
            }
        }
        recentlyHeavy = recentlyHeavy.filter { Date().timeIntervalSince($0.value) < Self.powerCooldown }
        if reason != nil { lastNeededPower = Date() }
        let stillCooling = Date().timeIntervalSince(lastNeededPower) < Self.powerCooldown
        guard reason != nil || (stillCooling && powerBoost != nil) else {
            if powerBoost != nil { powerBoost = nil }
            return
        }
        let base = Self.baseMemoryLimit
        // Up to 60% more, but never more than 45% of the Mac's memory (and never below the usual).
        let boosted = max(base, min(base + base * 3 / 5, ProcessInfo.processInfo.physicalMemory * 45 / 100))
        let next = PowerBoost(reason: reason ?? powerBoost?.reason ?? "A heavy page", limit: boosted)
        if next != powerBoost { powerBoost = next }
    }

    /// Heavy tabs you used in the last few minutes are kept awake while Power Mode is on.
    func isProtectedHeavy(_ tab: BrowserTab) -> Bool {
        powerBoost != nil && recentlyHeavy[tab.id] != nil && Date().timeIntervalSince(tab.lastActive) < Self.powerCooldown
    }

    /// Called when you switch tabs: a moment later, check whether the new tab needs more.
    func tabSwitched() {
        powerCheck?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.evaluatePowerMode() }
        powerCheck = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: work)
    }
    private var powerCheck: DispatchWorkItem?

    /// When Hush is over its limit, the tabs you used least recently go to sleep, never the one
    /// you're looking at, either side of Split View, or tabs playing sound or using the camera.
    func keepWithinMemoryLimit() {
        let usage = measure()
        evaluatePowerMode(usage)
        guard Self.memorySaverOn else { return }
        var over = Int64(usage.total) - Int64(Self.memoryLimit)
        guard over > 0 else { return }
        var candidates: [(tab: BrowserTab, bytes: UInt64)] = []
        for model in BrowserModel.all.allObjects {
            let visibleSplit = model.splitPair.flatMap { $0.contains(model.selectedID) ? $0 : nil }
            for tab in model.tabs where tab !== model.selectedTab && !tab.isAsleep && !tab.isLoading && !tab.isPlayingAudio
                && !(visibleSplit?.contains(tab.id) ?? false)
                && tab.webView.cameraCaptureState == .none && tab.webView.microphoneCaptureState == .none
                && !isProtectedHeavy(tab) {
                candidates.append((tab, usage.tabs.first { $0.id == tab.id }?.bytes ?? 0))
            }
        }
        // The biggest, longest-idle tabs first: one sleeping web app frees more than five articles.
        func cost(_ c: (tab: BrowserTab, bytes: UInt64)) -> Double {
            Date().timeIntervalSince(c.tab.lastActive) * (Double(c.bytes) / 1_048_576 + 50)
        }
        for candidate in candidates.sorted(by: { cost($0) > cost($1) }) where over > 0 {
            candidate.tab.sleep()
            over -= Int64(candidate.bytes)
        }
    }

    // MARK: Web page settings

    /// Applies the power mode to a new web view's settings (WebKit's own feature switches,
    /// the same ones Safari's Develop menu exposes).
    func configure(_ preferences: WKPreferences) {
        let mode = effectiveMode
        // Up to 120 Hz on ProMotion displays instead of WebKit's usual 60.
        Self.setFeature("PreferPageRenderingUpdatesNear60FPSEnabled", mode != .performance, in: preferences)
        // Look up the addresses of links on a page before you click them.
        Self.setFeature("DNSPrefetchingEnabled", mode == .performance, in: preferences)
        // Memory Saver: don't keep whole pages alive in memory just to make Back instant.
        Self.setFeature("UsesBackForwardCache", !Self.memorySaverOn || mode == .performance, in: preferences)
        // 3D graphics on the energy-saving graphics chip, where a Mac has two.
        Self.setFeature("ForceWebGLUsesLowPower", isPowerSaving, in: preferences)
        // Background tabs' timers slow down further the longer they're hidden.
        Self.setFeature("HiddenPageDOMTimerThrottlingAutoIncreases", isPowerSaving, in: preferences)
    }

    private static let features: [String: NSObject] = {
        let selector = NSSelectorFromString("_features")
        guard WKPreferences.responds(to: selector),
              let list = WKPreferences.perform(selector)?.takeUnretainedValue() as? [NSObject] else { return [:] }
        var byKey: [String: NSObject] = [:]
        for feature in list where feature.responds(to: NSSelectorFromString("key")) {
            if let key = feature.value(forKey: "key") as? String { byKey[key] = feature }
        }
        return byKey
    }()

    private static func setFeature(_ key: String, _ enabled: Bool, in preferences: WKPreferences) {
        let selector = NSSelectorFromString("_setEnabled:forFeature:")
        guard let feature = features[key], preferences.responds(to: selector) else { return }
        typealias Setter = @convention(c) (AnyObject, Selector, Bool, AnyObject) -> Void
        unsafeBitCast(preferences.method(for: selector), to: Setter.self)(preferences, selector, enabled, feature)
    }

    // MARK: Memory

    struct TabUsage: Identifiable {
        let id: UUID
        let title: String
        let bytes: UInt64
        let isAsleep: Bool
        let isSelected: Bool
        weak var tab: BrowserTab?
    }

    struct Usage {
        var total: UInt64 = 0
        var tabCount = 0
        var asleepCount = 0
        var tabs: [TabUsage] = []
    }

    /// Memory used by Hush itself, its graphics process and each tab's web page.
    func measure() -> Usage {
        var usage = Usage()
        var counted = Set<pid_t>()
        func add(_ pid: pid_t) -> UInt64 {
            guard pid > 0, !counted.contains(pid), let bytes = Self.footprint(of: pid) else { return 0 }
            counted.insert(pid)
            usage.total += bytes
            return bytes
        }
        _ = add(getpid())
        for model in BrowserModel.all.allObjects {
            for tab in model.tabs {
                usage.tabCount += 1
                if tab.isAsleep { usage.asleepCount += 1 }
                let pid = tab.isAsleep ? 0 : Self.processID(of: tab.webView, "_webProcessIdentifier")
                // Tabs that share a web process are only counted once.
                let bytes = Self.footprint(of: pid) ?? 0
                _ = add(pid)
                if !tab.isAsleep { _ = add(Self.processID(of: tab.webView, "_gpuProcessIdentifier")) }
                usage.tabs.append(TabUsage(id: tab.id, title: tab.displayTitle, bytes: bytes,
                                           isAsleep: tab.isAsleep, isSelected: model.selectedTab === tab, tab: tab))
            }
        }
        usage.tabs.sort { $0.bytes > $1.bytes }
        return usage
    }

    private static func processID(of webView: WKWebView, _ name: String) -> pid_t {
        let selector = NSSelectorFromString(name)
        guard webView.responds(to: selector) else { return 0 }
        typealias Getter = @convention(c) (AnyObject, Selector) -> pid_t
        return unsafeBitCast(webView.method(for: selector), to: Getter.self)(webView, selector)
    }

    private static func footprint(of pid: pid_t) -> UInt64? {
        guard pid > 0 else { return nil }
        var info = rusage_info_v2()
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V2, $0) }
        }
        return result == 0 ? info.ri_phys_footprint : nil
    }

    /// Downloads Hush Guard spared you in the last 30 days: a rough estimate, using an
    /// average of 20 KB per blocked ad or tracker request.
    var dataSavedThisMonth: UInt64 { UInt64(max(0, PrivacyReport.shared.summary.blocked)) * 20_000 }

    static func format(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .memory)
    }
}
