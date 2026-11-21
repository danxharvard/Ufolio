import SwiftUI
import WebKit

/// Every setting's storage key and default. Views read them with @AppStorage;
/// browser code reads them with `Prefs.bool` / `Prefs.string`.
enum Prefs {
    // Appearance
    static let appearance = "appearance"
    static let accent = "accentColor"
    static let showBookmarkBar = "showBookmarkBar"
    static let alwaysShowTabBar = "alwaysShowTabBar"
    static let showFullAddress = "showFullAddress"
    static let reduceMotion = "reduceMotion"
    static let startBackground = "startBackground"
    static let startGreeting = "startShowGreeting"
    static let startBookmarks = "startShowBookmarks"
    static let startFrequent = "startShowFrequent"
    static let startRecentlyClosed = "startShowRecentlyClosed"
    static let startPrivacyReport = "startShowPrivacyReport"
    static let startTranslucent = "startTranslucent"
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

    static let defaults: [String: Any] = [
        appearance: AppearanceMode.system.rawValue,
        accent: AccentChoice.system.rawValue,
        showBookmarkBar: true,
        alwaysShowTabBar: false,
        showFullAddress: false,
        reduceMotion: false,
        startBackground: StartBackground.twilight.rawValue,
        startGreeting: true,
        startBookmarks: true,
        startFrequent: true,
        startRecentlyClosed: true,
        startPrivacyReport: true,
        startTranslucent: true,
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
    ]

    static func register() {
        UserDefaults.standard.register(defaults: defaults)
    }

    static func bool(_ key: String) -> Bool { UserDefaults.standard.bool(forKey: key) }
    static func string(_ key: String) -> String { UserDefaults.standard.string(forKey: key) ?? "" }
    static func double(_ key: String) -> Double { UserDefaults.standard.double(forKey: key) }
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

enum StartBackground: String, CaseIterable, Identifiable {
    case twilight, aurora, plain
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
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
        return components?.url
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
        return components?.url
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
        case .onQuit: return "When Hush quits"
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
}
