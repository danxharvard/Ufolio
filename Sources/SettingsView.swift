import SwiftUI
import WebKit

enum SettingsTab: String {
    case general, appearance, privacy, adBlocker, location, updates
}

enum SettingsOpener {
    /// Opens Hush Settings (⌘,), optionally on a particular tab.
    static func open(tab: SettingsTab? = nil) {
        if let tab { UserDefaults.standard.set(tab.rawValue, forKey: "settingsTab") }
        NSApp.activate(ignoringOtherApps: true)
        if !NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) {
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
    }
}

/// Hush Settings: one place for every browser setting, in the native macOS style.
struct SettingsView: View {
    @AppStorage("settingsTab") private var selection = SettingsTab.general.rawValue
    @AppStorage(Prefs.accent) private var accent = AccentChoice.system.rawValue

    var body: some View {
        TabView(selection: $selection) {
            GeneralSettings()
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(SettingsTab.general.rawValue)
            AppearanceSettings()
                .tabItem { Label("Appearance", systemImage: "paintbrush") }
                .tag(SettingsTab.appearance.rawValue)
            PrivacySettings()
                .tabItem { Label("Privacy", systemImage: "hand.raised") }
                .tag(SettingsTab.privacy.rawValue)
            AdBlockerSettings()
                .tabItem { Label("Ad Blocker", systemImage: "shield.lefthalf.filled") }
                .tag(SettingsTab.adBlocker.rawValue)
            LocationSettings()
                .tabItem { Label("Location", systemImage: "location") }
                .tag(SettingsTab.location.rawValue)
            UpdateSettings()
                .tabItem { Label("Updates", systemImage: "arrow.down.circle") }
                .tag(SettingsTab.updates.rawValue)
        }
        .frame(width: 680, height: 600)
        .accentColor(AccentChoice(rawValue: accent)?.color)
    }
}

// MARK: - Shared pieces

/// The large icon, title and description at the top of a settings tab.
private struct SettingsHeader: View {
    let symbol: String
    let colors: [Color]
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 46, height: 46)
                .background(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                )
                .shadow(color: colors.last?.opacity(0.35) ?? .clear, radius: 6, y: 3)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 15, weight: .semibold))
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

/// Sites the user has allowed or refused, for the given permissions.
private struct RememberedPermissions: View {
    let kinds: [PermissionKind]
    @ObservedObject private var permissions = SitePermissions.shared

    private var rows: [(host: String, entries: [(PermissionKind, Bool)])] {
        permissions.decisions.keys.sorted().compactMap { host in
            let entries = kinds.compactMap { kind in
                permissions.decisions[host]?[kind.rawValue].map { (kind, $0) }
            }
            return entries.isEmpty ? nil : (host, entries)
        }
    }

    var body: some View {
        if rows.isEmpty {
            Text("No websites have asked yet.")
                .foregroundStyle(.secondary)
        } else {
            ForEach(rows, id: \.host) { row in
                HStack(spacing: 10) {
                    Favicon(url: URL(string: "https://\(row.host)"), size: 16)
                    Text(row.host)
                    Spacer()
                    ForEach(row.entries, id: \.0) { kind, allowed in
                        Label(allowed ? "Allowed" : "Denied", systemImage: kind.symbol)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(allowed ? Color.green : Color.secondary)
                    }
                    Button {
                        permissions.forget(row.host, kinds: kinds)
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .help("Forget this decision; the site will ask again")
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
    @AppStorage(Prefs.newTabPage) private var newTabPage = NewTabPage.startPage.rawValue
    @AppStorage(Prefs.homepage) private var homepage = ""
    @AppStorage(Prefs.downloadFolder) private var downloadFolder = ""
    @AppStorage(Prefs.askWhereToSave) private var askWhereToSave = false
    @State private var isDefaultBrowser = false

    private var engineName: String { (SearchEngine(rawValue: engine) ?? .google).name }

    var body: some View {
        Form {
            Section {
                Picker("Search engine", selection: $engine) {
                    ForEach(SearchEngine.allCases) { Text($0.name).tag($0.rawValue) }
                }
                DescribedToggle(title: "Show search suggestions",
                                detail: "What you type in the address bar is sent to \(engineName) to suggest searches.",
                                isOn: $suggestions)
            } header: { Text("Search") }

            Section {
                Picker("Hush opens with", selection: $launch) {
                    ForEach(LaunchBehavior.allCases) { Text($0.label).tag($0.rawValue) }
                }
                Picker("New tabs open with", selection: $newTabPage) {
                    ForEach(NewTabPage.allCases) { Text($0.label).tag($0.rawValue) }
                }
                if newTabPage == NewTabPage.homepage.rawValue {
                    HStack {
                        TextField("Homepage", text: $homepage, prompt: Text("example.com"))
                        Button("Use Current Page") {
                            if let url = BrowserModel.frontmost?.selectedTab?.url { homepage = url.absoluteString }
                        }
                    }
                }
            } header: { Text("Startup") }

            Section {
                LabeledContent("Save downloads to") {
                    HStack(spacing: 8) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: Downloads.folder.path))
                            .resizable().frame(width: 16, height: 16)
                        Text(FileManager.default.displayName(atPath: Downloads.folder.path))
                        Button("Change…", action: chooseFolder)
                    }
                }
                Toggle("Ask where to save each download", isOn: $askWhereToSave)
            } header: { Text("Downloads") }

            Section {
                HStack {
                    Image(systemName: isDefaultBrowser ? "checkmark.seal.fill" : "safari")
                        .foregroundStyle(isDefaultBrowser ? Color.green : Color.secondary)
                    Text(isDefaultBrowser ? "Hush is your default web browser" : "Hush isn’t your default web browser")
                    Spacer()
                    if !isDefaultBrowser {
                        Button("Make Default", action: makeDefault)
                    }
                }
            } header: { Text("Default browser") }
        }
        .formStyle(.grouped)
        .onAppear(perform: checkDefault)
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

    private func checkDefault() {
        let handler = NSWorkspace.shared.urlForApplication(toOpen: URL(string: "https://example.com")!)
        isDefaultBrowser = handler?.standardizedFileURL == Bundle.main.bundleURL.standardizedFileURL
    }

    private func makeDefault() {
        // macOS shows its own confirmation for this.
        for scheme in ["http", "https"] {
            NSWorkspace.shared.setDefaultApplication(at: Bundle.main.bundleURL, toOpenURLsWithScheme: scheme) { _ in
                DispatchQueue.main.async { checkDefault() }
            }
        }
    }
}

// MARK: - Appearance

private struct AppearanceSettings: View {
    @AppStorage(Prefs.appearance) private var appearance = AppearanceMode.system.rawValue
    @AppStorage(Prefs.accent) private var accent = AccentChoice.system.rawValue
    @AppStorage(Prefs.startBackground) private var background = StartBackground.twilight.rawValue
    @AppStorage(Prefs.startGreeting) private var greeting = true
    @AppStorage(Prefs.startBookmarks) private var startBookmarks = true
    @AppStorage(Prefs.showBookmarkBar) private var bookmarkBar = true
    @AppStorage(Prefs.alwaysShowTabBar) private var alwaysTabBar = false
    @AppStorage(Prefs.showFullAddress) private var fullAddress = false
    @AppStorage(Prefs.reduceMotion) private var reduceMotion = false
    @AppStorage(Prefs.defaultZoom) private var zoom = 1.0

    private let zoomLevels: [Double] = [0.75, 0.85, 0.9, 1.0, 1.1, 1.25, 1.5, 1.75]

    var body: some View {
        Form {
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
                Toggle("Show greeting", isOn: $greeting)
                Toggle("Show bookmarks", isOn: $startBookmarks)
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
                SettingsHeader(symbol: "hand.raised.fill",
                               colors: [Color(red: 0.25, green: 0.55, blue: 1), Color(red: 0.35, green: 0.3, blue: 0.95)],
                               title: "Privacy",
                               subtitle: "Hush keeps what you do on one site from following you to the next.")
            }

            Section {
                DescribedToggle(title: "Block third-party cookies",
                                detail: "Stops companies embedded in websites from recognising you across sites.",
                                isOn: $thirdPartyCookies)
                DescribedToggle(title: "Upgrade connections to HTTPS",
                                detail: "Loads the secure version of a site whenever it exists.",
                                isOn: $https)
                DescribedToggle(title: "Ask websites not to sell or share my data",
                                detail: "Sends the Global Privacy Control signal, which some laws require sites to honour.",
                                isOn: $gpc)
                DescribedToggle(title: "Warn about fraudulent websites",
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
    @AppStorage(Prefs.adBlockEnabled) private var ads = true
    @AppStorage(Prefs.trackerBlockEnabled) private var trackers = true
    @AppStorage(Prefs.hideCookieBanners) private var cookieBanners = true
    @AppStorage(Prefs.collapseAdSpace) private var collapse = true
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
                    Text("None. Use the shield in the toolbar to turn protection off for a site that doesn’t work properly.")
                        .foregroundStyle(.secondary)
                }
                ForEach(blocker.shieldsDown, id: \.self) { host in
                    HStack(spacing: 10) {
                        Favicon(url: URL(string: "https://\(host)"), size: 16)
                        Text(host)
                        Spacer()
                        Button("Turn Shields Back On") { blocker.setShields(true, for: host) }
                            .controlSize(.small)
                    }
                }
            } header: { Text("Sites with shields down") }
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
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 50, height: 50)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(LinearGradient(colors: [Color(red: 0.42, green: 0.32, blue: 0.95),
                                                          Color(red: 0.25, green: 0.55, blue: 1)],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing))
                    )
                    .shadow(color: Color(red: 0.3, green: 0.4, blue: 1).opacity(0.35), radius: 6, y: 3)
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
                SettingsHeader(symbol: "location.fill",
                               colors: [Color(red: 0.2, green: 0.75, blue: 0.95), Color(red: 0.15, green: 0.45, blue: 0.95)],
                               title: "Location",
                               subtitle: "Let Hush use your approximate location for a more personal browser. Nothing is shared without your say.")
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
            } header: { Text("Websites you’ve answered") }
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
