import SwiftUI
import Security
import WebKit

/// Every setting's storage key and default. Views read them with @AppStorage;
/// browser code reads them with `Prefs.bool` / `Prefs.string`.
enum Prefs {
    // Appearance
    static let appearance = "appearance"
    static let accent = "accentColor"
    static let showBookmarkBar = "showBookmarkBar"
    static let showFullAddress = "showFullAddress"
    static let reduceMotion = "reduceMotion"
    static let launchSound = "launchSound"
    /// "classic" or "area51" (the alien theme).
    static let theme = "theme"
    /// The playful animations: the abducted-counter saucer, shooting stars, the cloaking shimmer,
    /// the tractor beam and the easter egg.
    static let funEffects = "funEffects"
    /// Opt-in badges on the weekly report card.
    static let achievements = "achievements"
    /// Torrent tools (off by default) and their options.
    /// Clears the page cache as Ufolio quits, so it takes almost no disk space between sessions.
    static let clearCacheOnQuit = "clearCacheOnQuit"
    /// Instant pages: load the page you're about to open in the background.
    static let preloadPages = "preloadPages"
    /// A small picture of the page when you hover a tab.
    static let tabPreviews = "tabPreviews"
    /// Downloads sorted into Images, Documents, Videos… folders (off by default).
    static let sortDownloads = "sortDownloads"
    /// Deletes old sites' cookies and data after 30 days unused (off by default).
    static let cookieCleaner = "cookieCleaner"
    /// A playing video pops out into Picture in Picture when you switch tabs (on by default).
    static let autoPictureInPicture = "autoPictureInPicture"
    /// When filling a saved login or card asks for Touch ID or your Mac password ("never" by default).
    static let passwordFillLock = "passwordFillLock"
    static let torrentTools = "torrentTools"
    static let torrentApp = "torrentApp"
    static let torrentPreview = "torrentPreview"
    static let torrentSiteMode = "torrentSiteMode"
    static let torrentFakeWarnings = "torrentFakeWarnings"
    static let startBackground = "startBackground"
    static let startGreeting = "startShowGreeting"
    static let startBookmarks = "startShowBookmarks"
    static let startFrequent = "startShowFrequent"
    static let startRecentlyClosed = "startShowRecentlyClosed"
    static let startPrivacyReport = "startShowPrivacyReport"
    static let startWallpaper = "startWallpaper"
    static let startPhoto = "startPhoto"
    static let startShowAdult = "startShowAdult"
    static let defaultZoom = "defaultZoom"
    // General
    static let searchEngine = "searchEngine"
    static let searchSuggestions = "searchSuggestions"
    static let launchBehavior = "launchBehavior"
    static let newTabPage = "newTabPage"
    static let newWindowPage = "newWindowPage"
    static let historyRetention = "historyRetention"
    static let downloadRetention = "downloadRetention"
    static let openSafeFiles = "openSafeFiles"
    static let askDefaultBrowser = "askDefaultBrowser"
    static let hasOnboarded = "hasOnboarded"
    static let tabLayout = "tabLayout"
    static let sideTabsWidth = "sideTabsWidth"
    // AutoFill
    static let autofillPasswords = "autofillPasswords"
    static let autofillCards = "autofillCards"
    static let autofillContact = "autofillContact"
    static let homepage = "homepage"
    static let downloadFolder = "downloadFolder"
    static let askWhereToSave = "askWhereToSave"
    // Ad blocker
    static let adBlockEnabled = "adBlockEnabled"
    static let trackerBlockEnabled = "trackerBlockEnabled"
    static let hideCookieBanners = "hideCookieBanners"
    static let collapseAdSpace = "collapseAdSpace"
    static let autoRejectCookies = "autoRejectCookies"
    static let cleanLinks = "cleanLinks"
    static let lookalikeWarning = "lookalikeWarning"
    static let tabSleepMinutes = "tabSleepMinutes"
    // Updates
    static let autoCheckUpdates = "autoCheckUpdates"
    static let autoInstallUpdates = "autoInstallUpdates"
    /// Early test builds (off by default). They pass exactly the same signature checks.
    static let betaUpdates = "betaUpdates"
    // Privacy
    static let blockThirdPartyCookies = "blockThirdPartyCookies"
    static let httpsUpgrade = "httpsUpgrade"
    static let globalPrivacyControl = "globalPrivacyControl"
    static let fraudWarning = "fraudWarning"
    static let javaScript = "javaScriptEnabled"
    static let blockPopups = "blockPopups"
    static let autoplay = "autoplay"
    static let cameraPolicy = "cameraPolicy"
    // Location
    static let locationPolicy = "locationPolicy"
    static let offerBookmarks = "offerBookmarks"
    static let powerMode = "powerMode"
    static let memorySaver = "memorySaver"
    static let autoPowerMode = "autoPowerMode"
    static let blockAnnoyances = "blockAnnoyances"
    static let blockChatWidgets = "blockChatWidgets"
    static let autoUpdateLists = "autoUpdateLists"
    static let memoryLimitGB = "memoryLimitGB"
    static let magicTheme = "magicTheme"
    static let fingerprintProtection = "fingerprintProtection"
    static let debounceLinks = "debounceLinks"
    static let deAMP = "deAMP"
    static let blockingMode = "blockingMode"
    static let startNews = "startNews"
    static let scriptPolicy = "scriptPolicy"
    static let fingerprintMode = "fingerprintMode"
    static let cookiePolicy = "cookiePolicy"
    static let pauseBackgroundMedia = "pauseBackgroundMedia"
    static let freeMemoryAutomatically = "freeMemoryAutomatically"

    static let defaults: [String: Any] = [
        appearance: AppearanceMode.system.rawValue,
        accent: AccentChoice.system.rawValue,
        showBookmarkBar: true,
        showFullAddress: false,
        reduceMotion: false,
        launchSound: true,
        theme: "classic",
        funEffects: true,
        achievements: false,
        clearCacheOnQuit: true,
        preloadPages: true,
        tabPreviews: true,
        sortDownloads: false,
        cookieCleaner: false,
        autoPictureInPicture: true,
        passwordFillLock: "never",
        torrentTools: false,
        torrentApp: "",
        torrentPreview: true,
        torrentSiteMode: true,
        torrentFakeWarnings: true,
        startBackground: StartBackground.frosted.rawValue,
        startGreeting: true,
        startBookmarks: true,
        startFrequent: true,
        startRecentlyClosed: true,
        startPrivacyReport: true,
        defaultZoom: 1.0,
        searchEngine: SearchEngine.google.rawValue,
        searchSuggestions: true,
        launchBehavior: LaunchBehavior.startPage.rawValue,
        newTabPage: NewTabPage.startPage.rawValue,
        newWindowPage: NewTabPage.startPage.rawValue,
        historyRetention: HistoryRetention.year.rawValue,
        downloadRetention: DownloadRetention.oneDay.rawValue,
        openSafeFiles: false,
        askDefaultBrowser: true,
        hasOnboarded: false,
        autofillPasswords: true,
        autofillCards: true,
        autofillContact: true,
        homepage: "",
        downloadFolder: "",
        askWhereToSave: false,
        adBlockEnabled: true,
        trackerBlockEnabled: true,
        hideCookieBanners: true,
        collapseAdSpace: true,
        autoRejectCookies: true,
        cleanLinks: true,
        lookalikeWarning: true,
        tabSleepMinutes: 15,
        autoCheckUpdates: true,
        autoInstallUpdates: true,
        betaUpdates: false,
        blockThirdPartyCookies: true,
        httpsUpgrade: true,
        globalPrivacyControl: true,
        fraudWarning: true,
        javaScript: true,
        blockPopups: true,
        autoplay: AutoplayPolicy.stopSound.rawValue,
        cameraPolicy: PermissionPolicy.ask.rawValue,
        locationPolicy: PermissionPolicy.ask.rawValue,
        offerBookmarks: true,
        powerMode: PowerMode.automatic.rawValue,
        memorySaver: true,
        autoPowerMode: true,
        blockAnnoyances: true,
        blockChatWidgets: false,
        autoUpdateLists: true,
        memoryLimitGB: 0.0,
        magicTheme: false,
        fingerprintProtection: true,
        debounceLinks: true,
        deAMP: true,
        blockingMode: BlockingMode.standard.rawValue,
        startNews: false,
        pauseBackgroundMedia: false,
        freeMemoryAutomatically: true,
    ]

    static func register() {
        UserDefaults.standard.register(defaults: defaults)
    }

    static func bool(_ key: String) -> Bool { UserDefaults.standard.bool(forKey: key) }
    static func string(_ key: String) -> String { UserDefaults.standard.string(forKey: key) ?? "" }
    static func double(_ key: String) -> Double { UserDefaults.standard.double(forKey: key) }
}

/// Tabs along the top of the window, or in a column down the side.
enum TabLayout: String, CaseIterable, Identifiable {
    case top, side
    var id: String { rawValue }
    var label: String { self == .top ? "Tabs along the top" : "Tabs down the side" }
    var detail: String {
        self == .top ? "The classic layout, like Safari." : "A tidy column with room for long titles, like Arc and Zen."
    }
}

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "Match System"
        case .light: return "Day"
        case .dark: return "Night"
        }
    }

    static func apply(_ raw: String) {
        switch AppearanceMode(rawValue: raw) ?? .system {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
}

enum AccentChoice: String, CaseIterable, Identifiable {
    case system, violet, blue, teal, green, amber, rose, graphite
    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "System"
        default: return rawValue.capitalized
        }
    }

    /// nil means "use the accent colour chosen in System Settings".
    var color: Color? {
        switch self {
        case .system: return nil
        case .violet: return Color(red: 0.49, green: 0.36, blue: 0.93)
        case .blue: return Color(red: 0.16, green: 0.47, blue: 0.96)
        case .teal: return Color(red: 0.10, green: 0.62, blue: 0.66)
        case .green: return Color(red: 0.23, green: 0.66, blue: 0.36)
        case .amber: return Color(red: 0.93, green: 0.58, blue: 0.13)
        case .rose: return Color(red: 0.91, green: 0.30, blue: 0.47)
        case .graphite: return Color(red: 0.45, green: 0.46, blue: 0.50)
        }
    }

    static var current: AccentChoice { AccentChoice(rawValue: Prefs.string(Prefs.accent)) ?? .system }
}

enum SearchEngine: String, CaseIterable, Identifiable {
    case google, duckduckgo, bing, brave, ecosia
    var id: String { rawValue }

    var name: String {
        switch self {
        case .google: return "Google"
        case .duckduckgo: return "DuckDuckGo"
        case .bing: return "Bing"
        case .brave: return "Brave Search"
        case .ecosia: return "Ecosia"
        }
    }

    static var current: SearchEngine { SearchEngine(rawValue: Prefs.string(Prefs.searchEngine)) ?? .google }

    func searchURL(_ query: String) -> URL? {
        let base: String
        switch self {
        case .google: base = "https://www.google.com/search"
        case .duckduckgo: base = "https://duckduckgo.com/"
        case .bing: base = "https://www.bing.com/search"
        case .brave: base = "https://search.brave.com/search"
        case .ecosia: base = "https://www.ecosia.org/search"
        }
        var components = URLComponents(string: base)
        components?.queryItems = [URLQueryItem(name: "q", value: query)]
        return components.flatMap(Self.encodingPlus)
    }

    /// URLComponents leaves "+" as it is, and search engines read a bare "+" as a space, so
    /// "c++" was searched as "c". Encoded here as %2B.
    private static func encodingPlus(_ components: URLComponents) -> URL? {
        var c = components
        c.percentEncodedQuery = c.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        return c.url
    }

    /// Each engine's public suggestion endpoint; all answer in the
    /// OpenSearch format: ["query", ["suggestion", …]].
    func suggestionURL(_ query: String) -> URL? {
        var components: URLComponents?
        switch self {
        case .google:
            components = URLComponents(string: "https://suggestqueries.google.com/complete/search")
            components?.queryItems = [.init(name: "client", value: "firefox"), .init(name: "q", value: query)]
        case .duckduckgo:
            components = URLComponents(string: "https://duckduckgo.com/ac/")
            components?.queryItems = [.init(name: "q", value: query), .init(name: "type", value: "list")]
        case .bing:
            components = URLComponents(string: "https://api.bing.com/osjson.aspx")
            components?.queryItems = [.init(name: "query", value: query)]
        case .brave:
            components = URLComponents(string: "https://search.brave.com/api/suggest")
            components?.queryItems = [.init(name: "q", value: query)]
        case .ecosia:
            components = URLComponents(string: "https://ac.ecosia.org/autocomplete")
            components?.queryItems = [.init(name: "q", value: query), .init(name: "type", value: "list")]
        }
        return components.flatMap(Self.encodingPlus)
    }
}

enum LaunchBehavior: String, CaseIterable, Identifiable {
    case startPage, restore
    var id: String { rawValue }
    var label: String { self == .startPage ? "The start page" : "Tabs from last time" }
}

enum NewTabPage: String, CaseIterable, Identifiable {
    case startPage, homepage
    var id: String { rawValue }
    var label: String { self == .startPage ? "Start page" : "Homepage" }

    /// The page a new tab should load, or nil for the start page.
    static var url: URL? { page(for: Prefs.newTabPage) }

    /// The page a new window should load, or nil for the start page.
    static var windowURL: URL? { page(for: Prefs.newWindowPage) }

    private static func page(for key: String) -> URL? {
        guard NewTabPage(rawValue: Prefs.string(key)) == .homepage else { return nil }
        return URLResolver.resolve(Prefs.string(Prefs.homepage))
    }
}

enum AutoplayPolicy: String, CaseIterable, Identifiable {
    case allow, stopSound, never
    var id: String { rawValue }

    var label: String {
        switch self {
        case .allow: return "Allow all auto-play"
        case .stopSound: return "Stop media with sound"
        case .never: return "Never auto-play"
        }
    }

    var mediaTypes: WKAudiovisualMediaTypes {
        switch self {
        case .allow: return []
        case .stopSound: return .audio
        case .never: return .all
        }
    }

    static var current: AutoplayPolicy { AutoplayPolicy(rawValue: Prefs.string(Prefs.autoplay)) ?? .stopSound }

    /// WebKit's per-page auto-play policy and quirks for this choice (as Safari sets them):
    /// "Stop media with sound" still lets a page you opened yourself play its video with sound
    /// (it inherits your click), which is what made YouTube links start at once in Safari.
    var webKitPolicy: (policy: Int, quirks: Int) {
        switch self {
        case .allow: return (1, 0)
        case .stopSound: return (2, 1 | 2 | 4 | 8)   // pause events, inherited and arbitrary gestures, per-document
        case .never: return (3, 0)
        }
    }
}

enum PermissionPolicy: String, CaseIterable, Identifiable {
    case ask, never
    var id: String { rawValue }
    var label: String { self == .ask ? "Ask each time" : "Never allow" }
}

enum HistoryRetention: String, CaseIterable, Identifiable {
    case day, week, twoWeeks, month, year, manually
    var id: String { rawValue }

    var label: String {
        switch self {
        case .day: return "After one day"
        case .week: return "After one week"
        case .twoWeeks: return "After two weeks"
        case .month: return "After one month"
        case .year: return "After one year"
        case .manually: return "Manually"
        }
    }

    var maxAge: TimeInterval? {
        let day: TimeInterval = 86_400
        switch self {
        case .day: return day
        case .week: return 7 * day
        case .twoWeeks: return 14 * day
        case .month: return 31 * day
        case .year: return 365 * day
        case .manually: return nil
        }
    }

    static var current: HistoryRetention { HistoryRetention(rawValue: Prefs.string(Prefs.historyRetention)) ?? .year }
}

enum DownloadRetention: String, CaseIterable, Identifiable {
    case oneDay, onQuit, onSuccess, manually
    var id: String { rawValue }

    var label: String {
        switch self {
        case .oneDay: return "After one day"
        case .onQuit: return "When Ufolio quits"
        case .onSuccess: return "Upon successful download"
        case .manually: return "Manually"
        }
    }

    static var current: DownloadRetention { DownloadRetention(rawValue: Prefs.string(Prefs.downloadRetention)) ?? .oneDay }
}

/// Where Hush keeps its files. Any copy with a different bundle ID (a test build)
/// gets its own folder, so it can never touch your real bookmarks, history or lists.
enum AppPaths {
    static let support: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let id = Bundle.main.bundleIdentifier ?? ""
        let name = id == "com.danxharvard.hushbrowser" || id.isEmpty ? "Hush Browser" : "Hush Browser (\(id))"
        let folder = base.appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }()

    /// Where a profile keeps its own history and bookmarks. The default profile (nil) uses the
    /// main folder exactly as before; others get Profiles/<id>/ inside it.
    static func folder(forProfile id: UUID?) -> URL {
        guard let id else { return support }
        let folder = support.appendingPathComponent("Profiles", isDirectory: true).appendingPathComponent(id.uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// Reads a saved JSON file. If it exists but can't be read, a copy is kept beside it before
    /// anything else is written there, so a damaged file never quietly costs you your data.
    static func load<T: Decodable>(_ type: T.Type, from file: URL) -> T? {
        guard let data = try? Data(contentsOf: file) else { return nil }
        if let value = try? JSONDecoder().decode(type, from: data) { return value }
        let backup = file.deletingPathExtension().appendingPathExtension("damaged-\(Int(Date().timeIntervalSince1970)).json")
        try? FileManager.default.copyItem(at: file, to: backup)
        NSLog("Ufolio: \(file.lastPathComponent) couldn't be read; a copy was kept at \(backup.path)")
        return nil
    }
}


/// How hard Hush Guard works: Standard for everyday browsing, Strict for more protection
/// (a few sites may need it turned down), or Off.
enum BlockingMode: String, CaseIterable, Identifiable {
    case standard, strict, off
    var id: String { rawValue }
    var label: String {
        switch self {
        case .standard: return "Standard"
        case .strict: return "Strict"
        case .off: return "Off"
        }
    }
    var detail: String {
        switch self {
        case .standard: return "Blocks ads and trackers without breaking sites."
        case .strict: return "Also blocks social widgets, fingerprinting services and tracking pings. A few sites may not work."
        case .off: return "No ad or tracker blocking. Not recommended."
        }
    }
    static var current: BlockingMode { BlockingMode(rawValue: Prefs.string(Prefs.blockingMode)) ?? .standard }
}


/// Tidies away what features removed from Hush left behind.
enum RemovedFeatures {
    /// Half-written save files left when Hush was force-quit mid-save (older than a day).
    static func tidyLeftovers() {
        let fm = FileManager.default
        let folder = AppPaths.support
        guard let files = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        for file in files where file.lastPathComponent.hasPrefix(".dat.nosync") {
            let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            if Date().timeIntervalSince(modified) > 86_400 { try? fm.removeItem(at: file) }
        }
    }

    static func cleanUp() {
        DispatchQueue.global(qos: .utility).async { tidyLeftovers() }
        let d = UserDefaults.standard
        // Galaxy ranks, the saucer pet and the planet of the week (removed in 0.52): their
        // settings, and the count of the days you browsed.
        // And the start page's solid-colour option: it's always frosted now.
        for key in ["galaxyDayCount", "galaxySeeded", "galaxyLastDay", "saucerPet", "planetOfWeek", "startTranslucent"] where d.object(forKey: key) != nil {
            d.removeObject(forKey: key)
        }
        // Ask Hush (0.25.0): its model list, and any API keys it kept in the keychain.
        guard d.object(forKey: "ai.models") != nil || d.object(forKey: "ai.selected") != nil else { return }
        d.removeObject(forKey: "ai.models")
        d.removeObject(forKey: "ai.selected")
        SecItemDelete([kSecClass as String: kSecClassGenericPassword,
                       kSecAttrService as String: "Hush Browser AI"] as CFDictionary)
    }
}
