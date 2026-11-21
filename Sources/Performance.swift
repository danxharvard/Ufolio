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
        case .balanced: return "Fast and efficient. Hush’s everyday setting."
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
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in self?.refresh() }
        timer?.tolerance = 10

        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)
        source.setEventHandler { [weak self, weak source] in
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

    // MARK: Web page settings

    /// Applies the power mode to a new web view's settings (WebKit's own feature switches,
    /// the same ones Safari's Develop menu exposes).
    func configure(_ preferences: WKPreferences) {
        let mode = effectiveMode
        // Up to 120 Hz on ProMotion displays instead of WebKit's usual 60.
        Self.setFeature("PreferPageRenderingUpdatesNear60FPSEnabled", mode != .performance, in: preferences)
        // Look up the addresses of links on a page before you click them.
        Self.setFeature("DNSPrefetchingEnabled", mode == .performance, in: preferences)
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
