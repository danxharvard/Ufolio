import SwiftUI
import WebKit

enum SettingsTab: String, CaseIterable, Identifiable {
    case general, appearance, adBlocker, extensions, privacy, passwords, location, updates
    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .appearance: return "Appearance"
        case .adBlocker: return "Hush Guard"
        case .extensions: return "Extensions"
        case .privacy: return "Privacy & Security"
        case .passwords: return "Passwords & AutoFill"
        case .location: return "Location"
        case .updates: return "Software Update"
        }
    }

    var symbol: String {
        switch self {
        case .general: return "gearshape.fill"
        case .appearance: return "paintbrush.fill"
        case .adBlocker: return "hush"
        case .extensions: return "puzzlepiece.extension.fill"
        case .privacy: return "hand.raised.fill"
        case .passwords: return "key.fill"
        case .location: return "location.fill"
        case .updates: return "arrow.down.circle.fill"
        }
    }

    /// The tile colours, picked to match the System Settings palette.
    var colors: [Color] {
        switch self {
        case .general: return [Color(white: 0.62), Color(white: 0.45)]
        case .appearance: return [Color(red: 0.30, green: 0.55, blue: 1.0), Color(red: 0.42, green: 0.32, blue: 0.95)]
        case .adBlocker: return [Color(red: 0.55, green: 0.40, blue: 1.0), Color(red: 0.36, green: 0.26, blue: 0.86)]
        case .extensions: return [Color(red: 1.0, green: 0.62, blue: 0.25), Color(red: 0.95, green: 0.42, blue: 0.18)]
        case .privacy: return [Color(red: 0.25, green: 0.60, blue: 1.0), Color(red: 0.10, green: 0.42, blue: 0.95)]
        case .passwords: return [Color(red: 0.60, green: 0.62, blue: 0.66), Color(red: 0.40, green: 0.42, blue: 0.46)]
        case .location: return [Color(red: 0.25, green: 0.75, blue: 1.0), Color(red: 0.10, green: 0.50, blue: 0.95)]
        case .updates: return [Color(red: 0.62, green: 0.62, blue: 0.65), Color(red: 0.44, green: 0.44, blue: 0.48)]
        }
    }
}

enum SettingsOpener {
    /// Opens Hush Settings (⌘,), optionally on a particular section.
    static func open(tab: SettingsTab? = nil) {
        if let tab { UserDefaults.standard.set(tab.rawValue, forKey: "settingsTab") }
        NSApp.activate(ignoringOtherApps: true)
        // Since macOS 14 the old "showSettingsWindow:" action is ignored, so use the app
        // menu's own Settings… item (⌘,), which always works. Close any open popover first.
        DispatchQueue.main.async {
            let appMenu = NSApp.mainMenu?.items.first?.submenu
            if let menu = appMenu,
               let index = menu.items.firstIndex(where: { $0.keyEquivalent == "," && $0.keyEquivalentModifierMask == .command }) {
                menu.performActionForItem(at: index)
            } else {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }
        }
    }
}

/// Hush Settings, laid out like macOS System Settings: a sidebar of coloured
/// icon tiles, and each section in Apple's grouped style.
struct SettingsView: View {
    @AppStorage("settingsTab") private var selection = SettingsTab.general.rawValue
    @AppStorage(Prefs.accent) private var accent = AccentChoice.system.rawValue

    private var current: Binding<SettingsTab?> {
        Binding(get: { SettingsTab(rawValue: selection) ?? .general },
                set: { if let tab = $0 { selection = tab.rawValue } })
    }

    var body: some View {
        NavigationSplitView {
            List(SettingsTab.allCases, selection: current) { tab in
                HStack(spacing: 10) {
                    IconTile(symbol: tab.symbol, colors: tab.colors, size: 22)
                    Text(tab.title)
                }
                .padding(.vertical, 2)
                .padding(.leading, 2)
                .tag(tab)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 200, ideal: 215, max: 240)
        } detail: {
            let tab = current.wrappedValue ?? .general
            Group {
                switch tab {
                case .general: GeneralSettings()
                case .appearance: AppearanceSettings()
                case .adBlocker: AdBlockerSettings()
                case .extensions: ExtensionSettings()
                case .privacy: PrivacySettings()
                case .passwords: PasswordSettings()
                case .location: LocationSettings()
                case .updates: UpdateSettings()
                }
            }
            .navigationTitle(tab.title)
            .id(tab)
        }
        .frame(width: 880, height: 660)
        .accentColor(AccentChoice(rawValue: accent)?.color)
    }
}

// MARK: - Shared pieces

/// A System Settings–style rounded icon tile.
struct IconTile: View {
    let symbol: String
    let colors: [Color]
    var size: CGFloat = 22

    var body: some View {
        Group {
            if symbol == "hush" {
                // Hush Guard uses the Hush mark itself.
                HushMark(showStars: false).padding(size * 0.16)
            } else {
                Image(systemName: symbol)
                    .font(.system(size: size * 0.52, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                    .fill(LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom))
                    .shadow(color: .black.opacity(0.12), radius: 0.5, y: 0.5)
            )
    }
}

/// The large tile, title and description at the top of a settings section.
private struct SettingsHeader: View {
    let tab: SettingsTab
    let subtitle: String

    var body: some View {
        HStack(spacing: 14) {
            IconTile(symbol: tab.symbol, colors: tab.colors, size: 48)
                .shadow(color: (tab.colors.last ?? .clear).opacity(0.3), radius: 6, y: 3)
            VStack(alignment: .leading, spacing: 3) {
                Text(tab.title).font(.system(size: 15, weight: .semibold))
                Text(subtitle).font(.system(size: 12)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }
}

/// A toggle with a grey explanation underneath.
private struct DescribedToggle: View {
    let title: String
    let detail: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Grey explanatory text under a section.
private struct Footnote: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.system(size: 11)).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Sites you've answered, with a menu to change each answer.
private struct RememberedPermissions: View {
    let kinds: [PermissionKind]
    @ObservedObject private var permissions = SitePermissions.shared

    private var rows: [(host: String, kind: PermissionKind, allowed: Bool)] {
        permissions.decisions.keys.sorted().flatMap { host in
            kinds.compactMap { kind in permissions.decisions[host]?[kind.rawValue].map { (host, kind, $0) } }
        }
    }

    var body: some View {
        if rows.isEmpty {
            Text("No websites yet. When you choose Always Allow, the site appears here.")
                .foregroundStyle(.secondary)
        } else {
            ForEach(rows, id: \.host) { row in
                HStack(spacing: 10) {
                    Favicon(url: URL(string: "https://\(row.host)"), size: 16)
                    Text(row.host)
                    if kinds.count > 1 {
                        Image(systemName: row.kind.symbol).foregroundStyle(.secondary).font(.system(size: 11))
                    }
                    Spacer()
                    Menu {
                        Button("Always Allow") { permissions.set(true, for: row.host, [row.kind]) }
                        Button("Don’t Allow") { permissions.set(false, for: row.host, [row.kind]) }
                        Divider()
                        Button("Ask Next Time") { permissions.forget(row.host, kinds: [row.kind]) }
                    } label: {
                        Text(row.allowed ? "Always Allow" : "Don’t Allow")
                    }
                    .fixedSize()
                }
            }
        }
    }
}

// MARK: - General

private struct GeneralSettings: View {
    @AppStorage(Prefs.searchEngine) private var engine = SearchEngine.google.rawValue
    @AppStorage(Prefs.searchSuggestions) private var suggestions = true
    @AppStorage(Prefs.launchBehavior) private var launch = LaunchBehavior.startPage.rawValue
    @AppStorage(Prefs.newWindowPage) private var newWindowPage = NewTabPage.startPage.rawValue
    @AppStorage(Prefs.newTabPage) private var newTabPage = NewTabPage.startPage.rawValue
    @AppStorage(Prefs.homepage) private var homepage = ""
    @AppStorage(Prefs.historyRetention) private var historyRetention = HistoryRetention.year.rawValue
    @AppStorage(Prefs.downloadFolder) private var downloadFolder = ""
    @AppStorage(Prefs.downloadRetention) private var downloadRetention = DownloadRetention.oneDay.rawValue
    @AppStorage(Prefs.askWhereToSave) private var askWhereToSave = false
    @AppStorage(Prefs.openSafeFiles) private var openSafeFiles = false
    @AppStorage(Prefs.askDefaultBrowser) private var askDefault = true
    @AppStorage(Prefs.tabSleepMinutes) private var tabSleep = 15.0
    @State private var isDefaultBrowser = DefaultBrowser.isDefault
    @State private var confirmClearHistory = false
    @State private var importStatus: String?
    @State private var importing = false

    private var engineName: String { (SearchEngine(rawValue: engine) ?? .google).name }

    var body: some View {
        Form {
            Section {
                SettingsHeader(tab: .general, subtitle: "How Hush starts, searches, remembers and downloads.")
            }

            Section {
                HStack(spacing: 10) {
                    Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 28, height: 28)
                    Text(isDefaultBrowser ? "Hush is your default web browser." : "Hush isn’t your default web browser.")
                    Spacer()
                    if isDefaultBrowser {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.green)
                    } else {
                        Button("Set Default…") { DefaultBrowser.makeDefault { isDefaultBrowser = $0 } }
                    }
                }
                if !isDefaultBrowser {
                    Toggle("Ask when Hush opens", isOn: $askDefault)
                }
            } header: { Text("Default browser") }

            Section {
                Picker("Hush opens with", selection: $launch) {
                    ForEach(LaunchBehavior.allCases) { Text($0.label).tag($0.rawValue) }
                }
                Picker("New windows open with", selection: $newWindowPage) {
                    ForEach(NewTabPage.allCases) { Text($0.label).tag($0.rawValue) }
                }
                Picker("New tabs open with", selection: $newTabPage) {
                    ForEach(NewTabPage.allCases) { Text($0.label).tag($0.rawValue) }
                }
                LabeledContent("Homepage") {
                    HStack {
                        TextField("", text: $homepage, prompt: Text("example.com"))
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 260)
                        Button("Set to Current Page") {
                            if let url = BrowserModel.frontmost?.selectedTab?.url { homepage = url.absoluteString }
                        }
                        .disabled(BrowserModel.frontmost?.selectedTab?.url == nil)
                    }
                }
            } header: { Text("Startup") }

            Section {
                Picker("Search engine", selection: $engine) {
                    ForEach(SearchEngine.allCases) { Text($0.name).tag($0.rawValue) }
                }
                DescribedToggle(title: "Show search suggestions",
                                detail: "What you type in the address bar is sent to \(engineName) to suggest searches.",
                                isOn: $suggestions)
            } header: { Text("Search") }

            Section {
                Picker("Remove history items", selection: $historyRetention) {
                    ForEach(HistoryRetention.allCases) { Text($0.label).tag($0.rawValue) }
                }
                HStack {
                    Menu("Import from Another Browser") {
                        ForEach(BrowserImporter.available()) { source in
                            Button(source.name) { runImport(source) }
                        }
                    }
                    .fixedSize()
                    .disabled(importing)
                    if importing { ProgressView().controlSize(.small) }
                    if let importStatus { Text(importStatus).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2) }
                    Spacer()
                    Button("Clear History…") { confirmClearHistory = true }
                }
            } header: { Text("History") } footer: {
                Footnote("History stays on this Mac. It powers Frequently Visited and address-bar suggestions.")
            }

            Section {
                LabeledContent("File download location") {
                    HStack(spacing: 8) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: Downloads.folder.path))
                            .resizable().frame(width: 16, height: 16)
                        Text(FileManager.default.displayName(atPath: Downloads.folder.path))
                        Button("Change…", action: chooseFolder)
                    }
                }
                Picker("Remove download list items", selection: $downloadRetention) {
                    ForEach(DownloadRetention.allCases) { Text($0.label).tag($0.rawValue) }
                }
                Toggle("Ask where to save each download", isOn: $askWhereToSave)
                DescribedToggle(title: "Open “safe” files after downloading",
                                detail: "“Safe” files include movies, pictures, sounds, PDFs, text documents and archives.",
                                isOn: $openSafeFiles)
            } header: { Text("Downloads") }

            Section {
                Picker("Sleep inactive tabs", selection: $tabSleep) {
                    Text("Never").tag(0.0)
                    Text("After 5 minutes").tag(5.0)
                    Text("After 15 minutes").tag(15.0)
                    Text("After 30 minutes").tag(30.0)
                    Text("After 1 hour").tag(60.0)
                }
            } header: { Text("Performance") } footer: {
                Footnote("Sleeping tabs free their memory and wake instantly with the page as you left it. Tabs playing sound or video never sleep.")
            }
        }
        .formStyle(.grouped)
        .onAppear { isDefaultBrowser = DefaultBrowser.isDefault }
        .alert("Clear all history?", isPresented: $confirmClearHistory) {
            Button("Clear History", role: .destructive) {
                HistoryStore.shared.clear()
                RecentlyClosed.shared.clear()
                PrivacyReport.shared.reset()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes every page Hush remembers, including Suggestions, Recently Closed Tabs and the Privacy Report. It can’t be undone.")
        }
    }

    private func runImport(_ source: BrowserImporter.Source) {
        importing = true
        importStatus = nil
        DispatchQueue.global(qos: .userInitiated).async {
            let message: String
            do {
                let count = try BrowserImporter.importTopSites(from: source)
                message = "Imported \(count) pages from \(source.name)."
            } catch {
                message = error.localizedDescription
            }
            DispatchQueue.main.async { importing = false; importStatus = message }
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.directoryURL = Downloads.folder
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url { downloadFolder = url.path }
    }
}

// MARK: - Appearance

private struct AppearanceSettings: View {
    @AppStorage(Prefs.appearance) private var appearance = AppearanceMode.system.rawValue
    @AppStorage(Prefs.accent) private var accent = AccentChoice.system.rawValue
    @AppStorage(Prefs.startBackground) private var background = StartBackground.twilight.rawValue
    @AppStorage(Prefs.startGreeting) private var greeting = true
    @AppStorage(Prefs.startBookmarks) private var startBookmarks = true
    @AppStorage(Prefs.startFrequent) private var startFrequent = true
    @AppStorage(Prefs.startRecentlyClosed) private var startClosed = true
    @AppStorage(Prefs.startPrivacyReport) private var startPrivacy = true
    @AppStorage(Prefs.startTranslucent) private var startTranslucent = true
    @AppStorage(Prefs.showBookmarkBar) private var bookmarkBar = true
    @AppStorage(Prefs.alwaysShowTabBar) private var alwaysTabBar = false
    @AppStorage(Prefs.showFullAddress) private var fullAddress = false
    @AppStorage(Prefs.reduceMotion) private var reduceMotion = false
    @AppStorage(Prefs.defaultZoom) private var zoom = 1.0

    private let zoomLevels: [Double] = [0.75, 0.85, 0.9, 1.0, 1.1, 1.25, 1.5, 1.75]

    var body: some View {
        Form {
            Section {
                SettingsHeader(tab: .appearance, subtitle: "Make Hush look and feel the way you like.")
            }
            Section {
                HStack(spacing: 18) {
                    ForEach(AppearanceMode.allCases) { mode in
                        ThemeCard(mode: mode, selected: appearance == mode.rawValue) { appearance = mode.rawValue }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                LabeledContent("Accent colour") {
                    HStack(spacing: 9) {
                        ForEach(AccentChoice.allCases) { choice in
                            AccentDot(choice: choice, selected: accent == choice.rawValue) { accent = choice.rawValue }
                        }
                    }
                }
            } header: { Text("Theme") }

            Section {
                Picker("Background", selection: $background) {
                    ForEach(StartBackground.allCases) { Text($0.label).tag($0.rawValue) }
                }
                .pickerStyle(.segmented)
                DescribedToggle(title: "Translucent background",
                                detail: "Lets your desktop show softly through the start page, like frosted glass.",
                                isOn: $startTranslucent)
                Toggle("Show greeting", isOn: $greeting)
                Toggle("Show Recently Closed Tabs", isOn: $startClosed)
                Toggle("Show Favourites", isOn: $startBookmarks)
                Toggle("Show Suggestions", isOn: $startFrequent)
                Toggle("Show Privacy Report", isOn: $startPrivacy)
            } header: { Text("Start page") }

            Section {
                Toggle("Show bookmarks bar", isOn: $bookmarkBar)
                Toggle("Always show the tab bar", isOn: $alwaysTabBar)
                Toggle("Show full website address", isOn: $fullAddress)
            } header: { Text("Toolbar and tabs") }

            Section {
                DescribedToggle(title: "Reduce motion",
                                detail: "Turns off Hush’s animations, for a calmer, snappier feel.",
                                isOn: $reduceMotion)
                Picker("Default page zoom", selection: $zoom) {
                    ForEach(zoomLevels, id: \.self) { Text("\(Int(($0 * 100).rounded()))%").tag($0) }
                }
            } header: { Text("Motion and zoom") }
        }
        .formStyle(.grouped)
    }
}

/// A small picture of a browser window in each theme.
private struct ThemeCard: View {
    let mode: AppearanceMode
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                ZStack {
                    switch mode {
                    case .light: miniWindow(dark: false)
                    case .dark: miniWindow(dark: true)
                    case .system:
                        ZStack {
                            miniWindow(dark: false)
                            miniWindow(dark: true).mask(
                                GeometryReader { geo in
                                    Path { p in
                                        p.move(to: CGPoint(x: geo.size.width, y: 0))
                                        p.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height))
                                        p.addLine(to: CGPoint(x: 0, y: geo.size.height))
                                        p.closeSubpath()
                                    }
                                })
                        }
                    }
                }
                .frame(width: 104, height: 66)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.12),
                                      lineWidth: selected ? 2.5 : 1)
                )
                .shadow(color: .black.opacity(0.1), radius: 3, y: 1)
                Text(mode.label)
                    .font(.system(size: 11.5, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? .primary : .secondary)
            }
        }
        .buttonStyle(.plain)
    }

    private func miniWindow(dark: Bool) -> some View {
        let bg = dark ? Color(red: 0.11, green: 0.11, blue: 0.15) : Color(red: 0.97, green: 0.97, blue: 0.99)
        let bar = dark ? Color(red: 0.2, green: 0.2, blue: 0.24) : Color(red: 0.88, green: 0.88, blue: 0.91)
        let field = dark ? Color.white.opacity(0.12) : Color.black.opacity(0.07)
        return ZStack(alignment: .top) {
            bg
            VStack(spacing: 0) {
                HStack(spacing: 3) {
                    ForEach([Color.red, Color.yellow, Color.green], id: \.self) {
                        Circle().fill($0.opacity(0.85)).frame(width: 4.5, height: 4.5)
                    }
                    RoundedRectangle(cornerRadius: 2.5).fill(field).frame(height: 7).padding(.leading, 8)
                }
                .padding(.horizontal, 7)
                .frame(height: 15)
                .background(bar)
                Spacer()
                Text("Hush")
                    .font(.system(size: 11, weight: .thin, design: .rounded))
                    .foregroundStyle(dark ? Color.white.opacity(0.85) : Color.black.opacity(0.7))
                Spacer()
            }
        }
    }
}

private struct AccentDot: View {
    let choice: AccentChoice
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                if let color = choice.color {
                    Circle().fill(color)
                } else {
                    Circle().fill(AngularGradient(colors: [.red, .orange, .yellow, .green, .blue, .purple, .red],
                                                  center: .center))
                }
                if selected {
                    Circle().fill(.white).frame(width: 6, height: 6)
                }
            }
            .frame(width: 18, height: 18)
            .overlay(Circle().strokeBorder(Color.black.opacity(0.12)))
            .padding(2)
            .overlay(Circle().strokeBorder(selected ? (choice.color ?? .accentColor).opacity(0.5) : .clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .help(choice.label)
    }
}

// MARK: - Privacy

private struct PrivacySettings: View {
    @AppStorage(Prefs.blockThirdPartyCookies) private var thirdPartyCookies = true
    @AppStorage(Prefs.httpsUpgrade) private var https = true
    @AppStorage(Prefs.globalPrivacyControl) private var gpc = true
    @AppStorage(Prefs.cleanLinks) private var cleanLinks = true
    @AppStorage(Prefs.lookalikeWarning) private var lookalike = true
    @AppStorage(Prefs.fraudWarning) private var fraud = true
    @AppStorage(Prefs.cameraPolicy) private var camera = PermissionPolicy.ask.rawValue
    @AppStorage(Prefs.blockPopups) private var popups = true
    @AppStorage(Prefs.autoplay) private var autoplay = AutoplayPolicy.stopSound.rawValue
    @AppStorage(Prefs.javaScript) private var javaScript = true
    @State private var siteCount: Int?
    @State private var confirmClear = false

    var body: some View {
        Form {
            Section {
                SettingsHeader(tab: .privacy, subtitle: "Hush keeps what you do on one site from following you to the next.")
            }

            Section {
                DescribedToggle(title: "Block third-party cookies",
                                detail: "Stops companies embedded in websites from recognising you across sites.",
                                isOn: $thirdPartyCookies)
                DescribedToggle(title: "Upgrade connections to HTTPS",
                                detail: "Loads the secure version of a site whenever it exists.",
                                isOn: $https)
                DescribedToggle(title: "Clean tracking from links",
                                detail: "Removes tags like utm_source and fbclid that follow you between sites.",
                                isOn: $cleanLinks)
                DescribedToggle(title: "Warn about look-alike websites",
                                detail: "Stops fake copies of sites you use, like paypa1.com, before they load.",
                                isOn: $lookalike)
                DescribedToggle(title: "Ask websites not to sell or share my data",
                                detail: "Sends the Global Privacy Control signal, which some laws require sites to honour.",
                                isOn: $gpc)
                DescribedToggle(title: "Warn when visiting a fraudulent website",
                                detail: "Uses the same Safe Browsing check as Safari.",
                                isOn: $fraud)
            } header: { Text("Tracking protection") }

            Section {
                Picker("Camera and microphone", selection: $camera) {
                    ForEach(PermissionPolicy.allCases) { Text($0.label).tag($0.rawValue) }
                }
                Picker("Auto-play", selection: $autoplay) {
                    ForEach(AutoplayPolicy.allCases) { Text($0.label).tag($0.rawValue) }
                }
                Toggle("Block pop-up windows", isOn: $popups)
                Toggle("Allow JavaScript", isOn: $javaScript)
            } header: { Text("Websites") } footer: {
                Text("Auto-play, pop-up and fraud-warning changes apply to tabs you open afterwards.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section {
                RememberedPermissions(kinds: [.camera, .microphone])
            } header: { Text("Camera and microphone decisions") }

            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Cookies and website data")
                        Text(siteCount.map { "Stored by \($0) website\($0 == 1 ? "" : "s")" } ?? "Checking…")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Clear All…") { confirmClear = true }
                        .disabled(siteCount == 0)
                }
            } header: { Text("Website data") }
        }
        .formStyle(.grouped)
        .onAppear(perform: countSites)
        .alert("Clear all website data?", isPresented: $confirmClear) {
            Button("Clear", role: .destructive, action: clearData)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You’ll be signed out of websites and they’ll forget your preferences. This can’t be undone.")
        }
    }

    private func countSites() {
        WKWebsiteDataStore.default().fetchDataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes()) { records in
            siteCount = records.count
        }
    }

    private func clearData() {
        WKWebsiteDataStore.default().removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
                                                modifiedSince: .distantPast) {
            countSites()
        }
    }
}

// MARK: - Ad blocker

private struct AdBlockerSettings: View {
    @ObservedObject private var blocker = ContentBlocker.shared
    @ObservedObject private var stats = BlockStats.shared
    @ObservedObject private var zapper = ElementZapper.shared
    @AppStorage(Prefs.adBlockEnabled) private var ads = true
    @AppStorage(Prefs.trackerBlockEnabled) private var trackers = true
    @AppStorage(Prefs.hideCookieBanners) private var cookieBanners = true
    @AppStorage(Prefs.collapseAdSpace) private var collapse = true
    @AppStorage(Prefs.autoRejectCookies) private var autoReject = true
    @State private var showWebSheet = false
    @State private var confirmReset = false

    var body: some View {
        Form {
            Section {
                StatsCard(stats: stats) { confirmReset = true }
            }

            Section {
                Toggle("Block ads", isOn: $ads)
                Toggle("Block trackers", isOn: $trackers)
                DescribedToggle(title: "Collapse empty ad spaces",
                                detail: "Closes the gaps and “Advertisement” labels blocked ads leave behind.",
                                isOn: $collapse)
                DescribedToggle(title: "Reject cookie banners automatically",
                                detail: "Clicks “Reject all” on cookie pop-ups for you.",
                                isOn: $autoReject)
                DescribedToggle(title: "Hide cookie banners",
                                detail: "Hides common “accept cookies” pop-ups without accepting anything.",
                                isOn: $cookieBanners)
            } header: { Text("Built-in protection") }

            Section {
                if blocker.lists.isEmpty {
                    Text("Add EasyList, a hosts file or any Adblock Plus–style list to block even more.")
                        .foregroundStyle(.secondary)
                }
                ForEach(blocker.lists) { list in
                    FilterListRow(list: list)
                }
                HStack {
                    Button("Import from File…", action: importFile)
                    Button("Add from the Web…") { showWebSheet = true }
                    Spacer()
                    if blocker.isWorking { ProgressView().controlSize(.small) }
                }
                .disabled(blocker.isWorking)
                if let status = blocker.status {
                    Label(status, systemImage: blocker.isWorking ? "hourglass"
                          : blocker.statusIsError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .font(.system(size: 11.5))
                        .foregroundStyle(blocker.statusIsError ? Color.orange : Color.secondary)
                }
            } header: { Text("Your filter lists") } footer: {
                Text("Works with Adblock Plus and uBlock Origin lists, hosts files and Safari content-blocker JSON. Advanced rules WebKit can’t run are skipped.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section {
                if blocker.shieldsDown.isEmpty {
                    Text("None. Use the shield in the toolbar to turn Hush Guard off for a site that doesn’t work properly.")
                        .foregroundStyle(.secondary)
                }
                ForEach(blocker.shieldsDown, id: \.self) { host in
                    HStack(spacing: 10) {
                        Favicon(url: URL(string: "https://\(host)"), size: 16)
                        Text(host)
                        Spacer()
                        Button("Turn Hush Guard Back On") { blocker.setShields(true, for: host) }
                            .controlSize(.small)
                    }
                }
            } header: { Text("Sites with Hush Guard off") }

            Section {
                if zapper.hidden.isEmpty {
                    Text("None yet. Right-click a page and choose “Hide Elements on This Page…”, then click anything you don’t want to see.")
                        .foregroundStyle(.secondary)
                }
                ForEach(zapper.hidden.keys.sorted(), id: \.self) { site in
                    HStack(spacing: 10) {
                        Favicon(url: URL(string: "https://\(site)"), size: 16)
                        Text(site)
                        Text("\(zapper.hidden[site]?.count ?? 0) hidden").foregroundStyle(.secondary).font(.system(size: 11.5))
                        Spacer()
                        Button("Show Again") { zapper.showAgain(site) }.controlSize(.small)
                    }
                }
            } header: { Text("Hidden elements") }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showWebSheet) { AddListSheet() }
        .alert("Reset the counter?", isPresented: $confirmReset) {
            Button("Reset", role: .destructive) { stats.reset() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The blocked ads and trackers count starts again from zero.")
        }
    }

    private func importFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choose a filter list (.txt), hosts file or content-blocker .json"
        panel.prompt = "Import"
        if panel.runModal() == .OK, let url = panel.url {
            blocker.importFile(url)
        }
    }
}

private struct StatsCard: View {
    @ObservedObject var stats: BlockStats
    let onReset: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 14) {
                HushLogoTile(size: 50)
                VStack(alignment: .leading, spacing: 2) {
                    Text(stats.total.formatted())
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        
                    Text("ads and trackers blocked since \(stats.since.formatted(date: .abbreviated, time: .omitted))")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Reset…", action: onReset)
                    .controlSize(.small)
            }
            HStack(spacing: 10) {
                StatPill(label: "Ads", value: stats.ads, color: Color(red: 0.95, green: 0.45, blue: 0.4))
                StatPill(label: "Trackers", value: stats.trackers, color: Color(red: 0.3, green: 0.6, blue: 1))
                StatPill(label: "Your lists", value: stats.fromLists, color: Color(red: 0.55, green: 0.45, blue: 0.95))
            }
        }
        .padding(.vertical, 6)
        .animation(.easeOut(duration: 0.3), value: stats.total)
    }
}

private struct StatPill: View {
    let label: String
    let value: Int
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Circle().fill(color).frame(width: 7, height: 7)
                Text(label).font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(value.formatted())
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(color.opacity(0.1))
        )
    }
}

private struct FilterListRow: View {
    let list: FilterList
    @ObservedObject private var blocker = ContentBlocker.shared

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: list.sourceURL == nil ? "doc.text" : "globe")
                .foregroundStyle(.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(list.name).lineLimit(1)
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Menu {
                if list.sourceURL != nil {
                    Button("Update Now") { blocker.update(list) }
                }
                Button("Remove", role: .destructive) { blocker.remove(list) }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            Toggle("", isOn: Binding(get: { list.enabled }, set: { blocker.setEnabled(list, $0) }))
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.small)
        }
    }

    private var detail: String {
        var parts = ["\(list.ruleCount.formatted()) rules"]
        if list.skippedCount > 0 { parts.append("\(list.skippedCount.formatted()) skipped") }
        parts.append("updated \(list.updatedAt.formatted(.relative(presentation: .named)))")
        return parts.joined(separator: " · ")
    }
}

/// Add a list by web address, with a few well-known lists one click away.
private struct AddListSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var address = ""

    private let popular: [(name: String, detail: String, url: String)] = [
        ("EasyList", "The most widely used ad-blocking list", "https://easylist.to/easylist/easylist.txt"),
        ("EasyPrivacy", "Blocks tracking and analytics", "https://easylist.to/easylist/easyprivacy.txt"),
        ("Peter Lowe’s list", "Compact list of ad and tracking servers",
         "https://pgl.yoyo.org/adservers/serverlist.php?hostformat=hosts&showintro=0&mimetype=plaintext"),
        ("Fanboy’s Annoyances", "Cookie notices, pop-ups and social widgets",
         "https://secure.fanboy.co.nz/fanboy-annoyance.txt"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add a Filter List").font(.system(size: 15, weight: .semibold))
            Text("Paste the address of any Adblock Plus–style list or hosts file.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
            TextField("https://…", text: $address)
                .textFieldStyle(.roundedBorder)
                .onSubmit(add)

            VStack(alignment: .leading, spacing: 8) {
                Text("Popular lists").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                ForEach(popular, id: \.url) { item in
                    Button {
                        address = item.url
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.name).font(.system(size: 12.5, weight: .medium))
                                Text(item.detail).font(.system(size: 11)).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if address == item.url {
                                Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                            }
                        }
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color.primary.opacity(address == item.url ? 0.08 : 0.04)))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Add List", action: add)
                    .keyboardShortcut(.defaultAction)
                    .disabled(URL(string: address)?.scheme?.hasPrefix("http") != true)
            }
        }
        .padding(20)
        .frame(width: 440)
    }

    private func add() {
        guard let url = URL(string: address.trimmingCharacters(in: .whitespaces)),
              url.scheme?.hasPrefix("http") == true else { return }
        let name = popular.first { $0.url == url.absoluteString }?.name
        ContentBlocker.shared.importFromWeb(url, name: name)
        dismiss()
    }
}

// MARK: - Location

private struct LocationSettings: View {
    @AppStorage(Prefs.startPageWeather) private var weatherOn = false
    @AppStorage(Prefs.locationPolicy) private var policy = PermissionPolicy.ask.rawValue
    @ObservedObject private var weather = LocalWeather.shared

    var body: some View {
        Form {
            Section {
                SettingsHeader(tab: .location, subtitle: "Let Hush use your approximate location for a more personal browser. Nothing is shared without your say.")
            }

            Section {
                DescribedToggle(title: "Personalise the start page",
                                detail: "Shows your town and the local weather under the greeting.",
                                isOn: $weatherOn)
                if weatherOn {
                    HStack(spacing: 8) {
                        Image(systemName: weather.isAuthorized ? "location.fill" : "location.slash")
                            .foregroundStyle(weather.isAuthorized ? Color.accentColor : Color.orange)
                        Text(weather.statusText)
                            .font(.system(size: 12))
                        Spacer()
                        if weather.authorization == .denied || weather.authorization == .restricted {
                            Button("Open System Settings…") { LocalWeather.openSystemLocationSettings() }
                                .controlSize(.small)
                        } else if let temperature = weather.temperature {
                            Image(systemName: weather.symbol).symbolRenderingMode(.multicolor)
                            Text("\(temperature)° \(weather.summary)").font(.system(size: 12))
                        }
                    }
                }
            } header: { Text("Hush") } footer: {
                Text("Your position is rounded to about 1 km before it leaves your Mac. It goes to Open-Meteo for the weather and to Apple to find your town’s name.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section {
                Picker("When a website asks for your location", selection: $policy) {
                    ForEach(PermissionPolicy.allCases) { Text($0.label).tag($0.rawValue) }
                }
            } header: { Text("Websites") } footer: {
                Text("Maps, delivery and weather sites can use your location to show nearby results. Hush asks you first and remembers your answer.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section {
                RememberedPermissions(kinds: [.location])
            } header: { Text("Your answers") }
        }
        .formStyle(.grouped)
        .onChange(of: weatherOn) { on in
            if on { weather.request() } else { weather.clear() }
        }
    }
}

// MARK: - Updates

private struct UpdateSettings: View {
    @ObservedObject private var updater = Updater.shared
    @AppStorage(Prefs.autoCheckUpdates) private var autoCheck = true
    @AppStorage(Prefs.autoInstallUpdates) private var autoInstall = true

    var body: some View {
        Form {
            Section {
                HStack(spacing: 16) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 64, height: 64)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Hush Browser \(updater.currentVersion)")
                            .font(.system(size: 17, weight: .semibold))
                        statusLine
                    }
                    Spacer()
                    actionButton
                }
                .padding(.vertical, 6)

                if case .downloading(_, let progress) = updater.state {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                }
            }

            if let notes = updater.releaseNotes, isShowingRelease {
                Section {
                    ScrollView {
                        Text(notes)
                            .font(.system(size: 12))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(maxHeight: 160)
                    if let page = updater.releasePage {
                        Link("View on GitHub", destination: page)
                            .font(.system(size: 12))
                    }
                } header: { Text("What’s new") }
            }

            Section {
                Toggle("Check for updates automatically", isOn: $autoCheck)
                DescribedToggle(title: "Download and install updates automatically",
                                detail: "New versions download in the background and install the next time you quit Hush.",
                                isOn: $autoInstall)
                    .disabled(!autoCheck)
            } header: { Text("Automatic updates") } footer: {
                Text("Updates come from github.com/\(Updater.repo). Each download is checked against GitHub’s fingerprint before it’s installed.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
    }

    private var isShowingRelease: Bool {
        switch updater.state {
        case .available, .downloading, .ready: return true
        default: return false
        }
    }

    @ViewBuilder private var statusLine: some View {
        switch updater.state {
        case .idle:
            Text(lastCheckedText).foregroundStyle(.secondary)
        case .checking:
            Text("Checking for updates…").foregroundStyle(.secondary)
        case .upToDate:
            Label("You’re up to date", systemImage: "checkmark.circle.fill")
                .foregroundStyle(Color.green)
        case .available(let version):
            Label("Version \(version) is available", systemImage: "sparkles")
                .foregroundStyle(Color.accentColor)
        case .downloading(let version, let progress):
            Text("Downloading \(version)… \(Int(progress * 100))%").foregroundStyle(.secondary)
        case .ready(let version):
            Label("Version \(version) is ready to install", systemImage: "arrow.down.circle.fill")
                .foregroundStyle(Color.accentColor)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.orange)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder private var actionButton: some View {
        switch updater.state {
        case .checking, .downloading:
            ProgressView().controlSize(.small)
        case .available:
            Button("Download and Install") { Task { await updater.download() } }
                .controlSize(.large)
        case .ready:
            Button("Restart to Update") { updater.restartToUpdate() }
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
        default:
            Button("Check for Updates") { Task { await updater.check(userInitiated: true) } }
                .controlSize(.large)
        }
    }

    private var lastCheckedText: String {
        guard let date = updater.lastChecked else { return "Not checked yet" }
        return "Last checked \(date.formatted(.relative(presentation: .named)))"
    }
}

// MARK: - Passwords & AutoFill

private struct PasswordSettings: View {
    @AppStorage(Prefs.autofillContact) private var contact = true
    @AppStorage(Prefs.autofillPasswords) private var passwords = true
    @AppStorage(Prefs.autofillCards) private var cards = true
    @State private var unlocked = false
    @State private var logins: [SavedLogin] = []
    @State private var cardList: [CardVault.Summary] = []
    @State private var revealed: [String: String] = [:]
    @State private var search = ""
    @State private var neverSave = PasswordVault.neverSave
    @State private var showAddCard = false
    @State private var myName = MyCard.status == .authorized ? MyCard.displayName : nil
    @State private var copiedID: String?

    private var filtered: [SavedLogin] {
        let q = search.lowercased()
        return q.isEmpty ? logins : logins.filter { $0.host.contains(q) || $0.account.lowercased().contains(q) }
    }

    var body: some View {
        Form {
            Section {
                SettingsHeader(tab: .passwords,
                               subtitle: "Kept in your Mac’s keychain and filled in only after Touch ID or your Mac’s password.")
            }

            Section {
                AutofillToggleRow(title: "Using information from my contact card",
                                  detail: myName.map { "Fills in forms as \($0)." } ?? "Fills in names, emails, phone numbers and addresses.",
                                  isOn: $contact, button: "Edit…") {
                    if MyCard.status == .notDetermined {
                        MyCard.requestAccess { _ in myName = MyCard.displayName }
                    } else {
                        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Contacts.app"))
                    }
                }
                AutofillToggleRow(title: "Usernames and passwords",
                                  detail: "Offers to save passwords when you sign in, and fills them in next time.",
                                  isOn: $passwords, button: unlocked ? nil : "Edit…") { unlock() }
                AutofillToggleRow(title: "Credit cards",
                                  detail: "Fills in card details on checkout pages. Security codes are never stored.",
                                  isOn: $cards, button: "Add Card…") { showAddCard = true }
            } header: { Text("AutoFill web forms") } footer: {
                Footnote("AutoFill only works on secure (https) pages, and only fills a password on the exact site it was saved for.")
            }

            Section {
                if !unlocked {
                    HStack {
                        Image(systemName: "lock.fill").foregroundStyle(.secondary)
                        Text("Your passwords are locked.")
                        Spacer()
                        Button("Unlock…", action: unlock)
                            .keyboardShortcut(.defaultAction)
                    }
                } else if logins.isEmpty {
                    Text("No saved passwords yet. Hush offers to save one when you sign in to a website.")
                        .foregroundStyle(.secondary)
                } else {
                    TextField("Search", text: $search, prompt: Text("Search passwords"))
                        .textFieldStyle(.roundedBorder)
                    ForEach(filtered) { login in
                        HStack(spacing: 10) {
                            Favicon(url: URL(string: "https://\(login.host)"), size: 20)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(login.host).font(.system(size: 12.5, weight: .medium))
                                Text(login.account.isEmpty ? "(no username)" : login.account)
                                    .font(.system(size: 11)).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(revealed[login.id] ?? "••••••••")
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                                .lineLimit(1)
                            Button {
                                if revealed[login.id] != nil { revealed[login.id] = nil }
                                else { revealed[login.id] = PasswordVault.password(for: login) ?? "" }
                            } label: { Image(systemName: revealed[login.id] == nil ? "eye" : "eye.slash") }
                                .buttonStyle(.borderless).help("Show password")
                            Button { copy(login) } label: {
                                Image(systemName: copiedID == login.id ? "checkmark" : "doc.on.doc")
                            }
                            .buttonStyle(.borderless).help("Copy password (cleared from the clipboard after 90 seconds)")
                            Button {
                                PasswordVault.delete(login)
                                logins.removeAll { $0.id == login.id }
                            } label: { Image(systemName: "trash") }
                                .buttonStyle(.borderless).help("Delete")
                        }
                    }
                }
            } header: {
                HStack {
                    Text("Passwords")
                    Spacer()
                    if unlocked {
                        Button("Lock") { lock() }.buttonStyle(.link).font(.system(size: 11))
                    }
                }
            }

            Section {
                if cardList.isEmpty {
                    Text("No cards saved.").foregroundStyle(.secondary)
                }
                ForEach(cardList) { card in
                    HStack(spacing: 10) {
                        Image(systemName: "creditcard.fill").foregroundStyle(Color.accentColor)
                        Text(card.label)
                        Spacer()
                        Button {
                            CardVault.delete(card.id)
                            cardList = CardVault.list()
                        } label: { Image(systemName: "trash") }
                            .buttonStyle(.borderless).help("Delete")
                    }
                }
            } header: { Text("Credit cards") }

            if !neverSave.isEmpty {
                Section {
                    ForEach(neverSave, id: \.self) { host in
                        HStack {
                            Favicon(url: URL(string: "https://\(host)"), size: 16)
                            Text(host)
                            Spacer()
                            Button("Remove") {
                                PasswordVault.neverSave = PasswordVault.neverSave.filter { $0 != host }
                                neverSave = PasswordVault.neverSave
                            }
                            .controlSize(.small)
                        }
                    }
                } header: { Text("Never save passwords for") }
            }
        }
        .formStyle(.grouped)
        .onAppear { cardList = CardVault.list() }
        .onDisappear { lock() }
        .sheet(isPresented: $showAddCard) {
            AddCardSheet { cardList = CardVault.list() }
        }
    }

    private func unlock() {
        UserAuth.confirm("show your saved passwords") { ok in
            guard ok else { return }
            logins = PasswordVault.logins()
            unlocked = true
        }
    }

    private func lock() {
        unlocked = false
        revealed = [:]
        logins = []
    }

    /// Copies a password and clears it from the clipboard 90 s later (if it's still there).
    private func copy(_ login: SavedLogin) {
        guard let password = PasswordVault.password(for: login) else { return }
        let board = NSPasteboard.general
        board.clearContents()
        board.setString(password, forType: .string)
        let change = board.changeCount
        copiedID = login.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { if copiedID == login.id { copiedID = nil } }
        DispatchQueue.main.asyncAfter(deadline: .now() + 90) {
            if board.changeCount == change { board.clearContents() }
        }
    }
}

private struct AutofillToggleRow: View {
    let title: String
    let detail: String
    @Binding var isOn: Bool
    let button: String?
    let action: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Toggle("", isOn: $isOn).toggleStyle(.checkbox).labelsHidden()
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if let button {
                Button(button, action: action).disabled(!isOn)
            }
        }
    }
}

private struct AddCardSheet: View {
    let onSave: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var number = ""
    @State private var name = ""
    @State private var month = Calendar.current.component(.month, from: Date())
    @State private var year = Calendar.current.component(.year, from: Date()) + 2
    @State private var error: String?

    private var thisYear: Int { Calendar.current.component(.year, from: Date()) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                IconTile(symbol: "creditcard.fill", colors: SettingsTab.passwords.colors, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Add a Card").font(.system(size: 15, weight: .semibold))
                    Text("Saved in your Mac’s keychain. Hush never stores the security code.")
                        .font(.system(size: 11.5)).foregroundStyle(.secondary)
                }
            }
            Form {
                TextField("Card number", text: $number)
                TextField("Name on card", text: $name)
                LabeledContent("Expires") {
                    HStack {
                        Picker("", selection: $month) {
                            ForEach(1...12, id: \.self) { Text(String(format: "%02d", $0)).tag($0) }
                        }
                        .labelsHidden().frame(width: 70)
                        Picker("", selection: $year) {
                            ForEach(thisYear...(thisYear + 15), id: \.self) { Text(String($0)).tag($0) }
                        }
                        .labelsHidden().frame(width: 90)
                    }
                }
            }
            .formStyle(.grouped)
            .frame(height: 170)
            if let error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11.5)).foregroundStyle(Color.orange)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Add Card", action: save).keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    private func save() {
        let digits = number.filter(\.isNumber)
        guard (12...19).contains(digits.count), Self.luhn(digits) else {
            error = "That card number doesn’t look right."
            return
        }
        let card = SavedCard(name: name.trimmingCharacters(in: .whitespaces), number: digits, expMonth: month, expYear: year)
        guard CardVault.save(card) else {
            error = "The card couldn’t be saved to your keychain."
            return
        }
        onSave()
        dismiss()
    }

    /// The standard check-digit test every real card number passes.
    static func luhn(_ digits: String) -> Bool {
        var sum = 0
        for (i, ch) in digits.reversed().enumerated() {
            guard var d = ch.wholeNumberValue else { return false }
            if i % 2 == 1 { d *= 2; if d > 9 { d -= 9 } }
            sum += d
        }
        return sum % 10 == 0
    }
}

// MARK: - Extensions

private struct ExtensionSettings: View {
    @ObservedObject private var store = ExtensionStore.shared
    @State private var link = ""

    var body: some View {
        Form {
            Section {
                SettingsHeader(tab: .extensions,
                               subtitle: "Add Chrome extensions from the Chrome Web Store. Most work in Hush; a few that rely on Chrome-only features may not.")
            }

            if !ExtensionStore.isSupported {
                Section {
                    Label("Extensions need macOS 15.4 or later. Update macOS in System Settings › General › Software Update to use them.",
                          systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Section {
                    HStack {
                        TextField("", text: $link, prompt: Text("Paste a Chrome Web Store link"))
                            .textFieldStyle(.roundedBorder)
                            .onSubmit(add)
                        Button("Add", action: add)
                            .keyboardShortcut(.defaultAction)
                            .disabled(link.isEmpty || store.isWorking)
                    }
                    HStack {
                        Button("Open the Chrome Web Store") {
                            BrowserModel.frontmost?.newTab(url: URL(string: "https://chromewebstore.google.com/")!)
                        }
                        Button("Load Unpacked…", action: loadFolder)
                        Spacer()
                        if store.isWorking { ProgressView().controlSize(.small) }
                    }
                    if let status = store.status {
                        Label(status, systemImage: store.statusIsError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                            .font(.system(size: 11.5))
                            .foregroundStyle(store.statusIsError ? Color.orange : Color.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } header: { Text("Add an extension") } footer: {
                    Footnote("Find an extension in the Chrome Web Store, copy the address of its page and paste it here. Hush shows what it can access before adding it.")
                }

                Section {
                    if store.installed.isEmpty {
                        Text("No extensions yet.").foregroundStyle(.secondary)
                    }
                    ForEach(store.installed) { ext in
                        ExtensionRow(ext: ext)
                    }
                } header: { Text("Installed") }
            }
        }
        .formStyle(.grouped)
    }

    private func add() {
        let text = link
        Task { @MainActor in
            await store.install(fromWebStore: text)
            if !store.statusIsError { link = "" }
        }
    }

    private func loadFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.prompt = "Load Extension"
        panel.message = "Choose an unpacked extension folder (the one containing manifest.json)."
        if panel.runModal() == .OK, let url = panel.url {
            Task { @MainActor in await store.install(fromFolder: url) }
        }
    }
}

private struct ExtensionRow: View {
    let ext: InstalledExtension
    @ObservedObject private var store = ExtensionStore.shared
    @State private var icon: NSImage?

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let icon { Image(nsImage: icon).resizable() } else { Image(systemName: "puzzlepiece.extension.fill").foregroundStyle(.secondary) }
            }
            .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(ext.name).font(.system(size: 13, weight: .medium))
                Text(ext.version.isEmpty ? "Extension" : "Version \(ext.version)").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            Menu {
                if let source = ext.source, let url = URL(string: source) {
                    Button("Open in Chrome Web Store") { BrowserModel.frontmost?.newTab(url: url) }
                }
                Divider()
                Button("Remove", role: .destructive) { store.remove(ext) }
            } label: { Image(systemName: "ellipsis.circle") }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            Toggle("", isOn: Binding(get: { ext.enabled }, set: { store.setEnabled(ext, $0) }))
                .toggleStyle(.switch).labelsHidden().controlSize(.small)
        }
        .task {
            let folder = store.directory(for: ext)
            if #available(macOS 15.4, *), let loaded = try? await WKWebExtension(resourceBaseURL: folder) {
                icon = loaded.icon(for: CGSize(width: 28, height: 28))
            }
        }
    }
}
