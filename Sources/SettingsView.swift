import SwiftUI
import WebKit

enum SettingsTab: String, CaseIterable, Identifiable {
    case general, appearance, spaces, performance, adBlocker, extensions, privacy, passwords, location, keyboard, updates
    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .appearance: return "Appearance"
        case .spaces: return "Orbits & Profiles"
        case .performance: return "Performance"
        case .adBlocker: return "Force Field"
        case .extensions: return "Extensions"
        case .privacy: return "Privacy & Security"
        case .passwords: return "Passwords & AutoFill"
        case .location: return "Location"
        case .keyboard: return "Keyboard"
        case .updates: return "Software Update"
        }
    }

    /// Words that find this section in the Settings search.
    var keywords: String {
        switch self {
        case .general: return "default browser homepage startup new tab window search engine suggestions history import downloads safe files favourites"
        case .appearance: return "tabs vertical side sidebar layout theme dark light night day accent colour color start page background wallpaper photo picture daily desktop motion animation zoom bookmarks bar tab bar address magic theme colours site colour"
        case .spaces: return "spaces profiles workspaces work personal accounts sign in cookies separate containers"
        case .performance: return "performance speed fast power battery saver eco carbon energy green memory ram tab sleep graphics 120hz smooth frame rate video pause"
        case .adBlocker: return "blocking mode strict standard off ads ad blocker trackers block filter list easylist cookie banners collapse zapper hidden elements counter statistics"
        case .extensions: return "chrome extension extensions web store add-on plugin dark reader"
        case .privacy: return "torrent torrents magnet bittorrent transmission qbittorrent fingerprinting farbling redirects debounce amp cookies https tracking gpc fraud phishing look-alike clean links camera microphone pop-ups autoplay javascript website data clear"
        case .passwords: return "autofill passwords credit cards contact card keychain vault touch id lock ask"
        case .location: return "location weather town postcode personalise start page permission maps"
        case .keyboard: return "keyboard shortcuts keys hotkeys customise command"
        case .updates: return "update updates version changelog what's new release notes"
        }
    }

    var symbol: String {
        switch self {
        case .general: return "gearshape.fill"
        case .appearance: return "paintbrush.fill"
        case .spaces: return "square.stack.3d.up.fill"
        case .performance: return "speedometer"
        case .adBlocker: return "hush"
        case .extensions: return "puzzlepiece.extension.fill"
        case .privacy: return "hand.raised.fill"
        case .passwords: return "key.fill"
        case .location: return "location.fill"
        case .keyboard: return "keyboard.fill"
        case .updates: return "arrow.down.circle.fill"
        }
    }

    /// The tile colours, picked to match the System Settings palette.
    var colors: [Color] {
        switch self {
        case .general: return [Color(white: 0.62), Color(white: 0.45)]
        case .appearance: return [Color(red: 0.30, green: 0.55, blue: 1.0), Color(red: 0.42, green: 0.32, blue: 0.95)]
        case .spaces: return [Color(red: 0.20, green: 0.78, blue: 0.65), Color(red: 0.10, green: 0.55, blue: 0.55)]
        case .performance: return [Color(red: 1.0, green: 0.45, blue: 0.35), Color(red: 0.90, green: 0.25, blue: 0.30)]
        case .adBlocker: return [Color(red: 0.55, green: 0.40, blue: 1.0), Color(red: 0.36, green: 0.26, blue: 0.86)]
        case .extensions: return [Color(red: 1.0, green: 0.62, blue: 0.25), Color(red: 0.95, green: 0.42, blue: 0.18)]
        case .privacy: return [Color(red: 0.25, green: 0.60, blue: 1.0), Color(red: 0.10, green: 0.42, blue: 0.95)]
        case .passwords: return [Color(red: 0.60, green: 0.62, blue: 0.66), Color(red: 0.40, green: 0.42, blue: 0.46)]
        case .location: return [Color(red: 0.25, green: 0.75, blue: 1.0), Color(red: 0.10, green: 0.50, blue: 0.95)]
        case .keyboard: return [Color(white: 0.55), Color(white: 0.38)]
        case .updates: return [Color(red: 0.62, green: 0.62, blue: 0.65), Color(red: 0.44, green: 0.44, blue: 0.48)]
        }
    }
}

enum SettingsOpener {
    /// Opens Hush Settings (⌘,), optionally on a particular section.
    static func open(tab: SettingsTab? = nil) {
        if let tab { UserDefaults.standard.set(tab.rawValue, forKey: "settingsTab") }
        // After any open popover or menu has closed.
        DispatchQueue.main.async { MainActor.assumeIsolated { SettingsWindow.show() } }
    }
}

/// Hush Settings, laid out like macOS System Settings: a sidebar of coloured
/// icon tiles, and each section in Apple's grouped style.
struct SettingsView: View {
    @AppStorage("settingsTab") private var selection = SettingsTab.general.rawValue
    @AppStorage(Prefs.accent) private var accent = AccentChoice.system.rawValue
    @AppStorage(Prefs.theme) private var theme = "classic"
    @State private var query = ""

    private var current: Binding<SettingsTab?> {
        Binding(get: { SettingsTab(rawValue: selection) ?? .general },
                set: { if let tab = $0 { selection = tab.rawValue } })
    }

    private var visibleTabs: [SettingsTab] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return SettingsTab.allCases }
        return SettingsTab.allCases.filter { $0.title.lowercased().contains(q) || $0.keywords.contains(q) }
    }

    var body: some View {
        NavigationSplitView {
            List(selection: current) {
                SidebarCard { selection = SettingsTab.updates.rawValue }
                    .padding(.horizontal, -7)   // line up exactly with the search field above
                    .listRowInsets(EdgeInsets(top: 12, leading: 0, bottom: 10, trailing: 0))
                ForEach(visibleTabs) { tab in
                    HStack(spacing: 10) {
                        IconTile(symbol: tab.symbol, colors: tab.colors, size: 22)
                        Text(tab.title)
                    }
                    .padding(.vertical, 2)
                    .padding(.leading, 2)
                    .tag(tab)
                }
            }
            .listStyle(.sidebar)
            .searchable(text: $query, placement: .sidebar, prompt: "Search settings")
            .navigationSplitViewColumnWidth(min: 220, ideal: 235, max: 260)
        } detail: {
            let tab = current.wrappedValue ?? .general
            ZStack {
                Group {
                    switch tab {
                    case .general: GeneralSettings()
                    case .appearance: AppearanceSettings()
                    case .adBlocker: AdBlockerSettings()
                    case .extensions: ExtensionSettings()
                    case .privacy: PrivacySettings()
                    case .passwords: PasswordSettings()
                    case .performance: PerformanceSettings()
                    case .spaces: SpacesSettings()
                    case .location: LocationSettings()
                    case .keyboard: KeyboardSettings()
                    case .updates: UpdateSettings()
                    }
                }
                .id(tab)
                .transition(.opacity.combined(with: .offset(y: 6)))
            }
            .animation(.easeOut(duration: 0.18), value: tab)
            // Frosted glass behind every section, like the browser window.
            .background(VisualEffect(material: .underWindowBackground, blending: .behindWindow).ignoresSafeArea())
        }
        // The section's name, centred in the title bar. It belongs to the whole window (not the
        // changing section), so SwiftUI keeps one copy instead of leaving old ones on the left.
        .toolbar(removing: .title)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text((current.wrappedValue ?? .general).title).font(.system(size: 13, weight: .semibold))
            }
        }
        // A slim, compact title bar (keeps the window's close/minimise/zoom buttons).
        .background(WindowReader { window in
            window?.toolbarStyle = .unifiedCompact
            window?.titlebarSeparatorStyle = .none
            window?.titleVisibility = .hidden   // the centred title above replaces the left-hand one
        })
        .frame(width: 900, height: 680)
        .accentColor(AlienTheme.isActive(theme) ? AlienTheme.accent : AccentChoice(rawValue: accent)?.color)
        .onChange(of: query) { _, q in
            // Searching jumps straight to the first matching section.
            if !q.isEmpty, let first = visibleTabs.first { selection = first.rawValue }
        }
    }
}

/// The card at the top of the sidebar: Hush, its version and whether it's up to date.
private struct SidebarCard: View {
    let action: () -> Void
    @ObservedObject private var updater = Updater.shared
    @State private var hovering = false

    private var status: String {
        switch updater.state {
        case .available(let v), .downloading(let v, _), .ready(let v): return "Update available: \(v)"
        case .upToDate: return "Up to date"
        case .checking: return "Checking for updates…"
        default: return "Version \(updater.currentVersion)"
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                HushLogoTile(size: 38)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ufolio Browser").font(.system(size: 13, weight: .semibold))
                    Text(status).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.primary.opacity(hovering ? 0.09 : 0.05)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.snappy(duration: 0.16), value: hovering)
    }
}

// MARK: - Shared pieces

/// Hush's settings layout: one centred column, labels on the left, controls on the right,
/// no boxes or divider lines.
struct SafariFormStyle: FormStyle {
    func makeBody(configuration: Configuration) -> some View {
        ScrollView {
            // Lazy: only the sections on screen are built, so a long page opens straight away.
            LazyVStack(alignment: .leading, spacing: 6) {
                // Each section is a rounded card (like System Settings), with its title above
                // and any note below. The page header and "bare" sections are drawn as they are.
                Group(sections: configuration.content) { sections in
                    ForEach(Array(sections.enumerated()), id: \.element.id) { index, section in
                        if index == 0 && section.header.isEmpty || section.containerValues.bareSection {
                            section.header
                            section.content
                            section.footer
                        } else {
                            if !section.header.isEmpty {
                                section.header.padding(.leading, 4)
                            }
                            SettingsCard { section.content }
                            if !section.footer.isEmpty {
                                section.footer.padding(.horizontal, 6).padding(.top, 2).padding(.bottom, 6)
                            }
                        }
                    }
                }
            }
            .toggleStyle(SettingsSwitchStyle())
            .labeledContentStyle(SafariLabeledStyle())
            .padding(.horizontal, 32)
            .padding(.top, 8)
            .padding(.bottom, 36)
            .frame(maxWidth: 680, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .scrollContentBackground(.hidden)
    }
}

/// Settings toggles: the label on the left and a small switch on the right, like System Settings.
struct SettingsSwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .center, spacing: 12) {
            configuration.label
            Spacer(minLength: 16)
            Toggle("", isOn: configuration.$isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
    }
}

private struct BareSectionKey: ContainerValueKey { static let defaultValue = false }

extension ContainerValues {
    /// A Settings section drawn without a card (for content that has its own cards).
    var bareSection: Bool {
        get { self[BareSectionKey.self] }
        set { self[BareSectionKey.self] = newValue }
    }
}

extension View {
    /// Draws this Settings section without a card around it.
    func bareSection() -> some View { containerValue(\.bareSection, true) }
}

enum SettingsColors {
    /// The cards: frosted, a soft veil over the window's see-through backdrop.
    static let card = Color(nsColor: NSColor(name: nil) { a in
        a.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(white: 1, alpha: 0.05) : NSColor(white: 1, alpha: 0.42)
    })
    static let stroke = Color(nsColor: NSColor(name: nil) { a in
        a.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(white: 1, alpha: 0.06) : NSColor(white: 0, alpha: 0.07)
    })
}

/// A rounded group of rows with hairlines between them.
struct SettingsCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Group(subviews: content) { rows in
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    if index > 0 {
                        Rectangle().fill(SettingsColors.stroke).frame(height: 1).padding(.leading, 12)
                    }
                    row
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .background(SettingsColors.card, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(SettingsColors.stroke))
    }
}

/// The label on the left, the control on the right of the row.
struct SafariLabeledStyle: LabeledContentStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            configuration.label
            Spacer(minLength: 16)
            configuration.content
        }
    }
}

/// A section title with space above it, so sections breathe.
struct SectionTitle: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.primary.opacity(0.85))
            .padding(.top, 16)
            .padding(.bottom, 1)
    }
}


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
struct SettingsHeader: View {
    let tab: SettingsTab
    let subtitle: String

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            IconTile(symbol: tab.symbol, colors: tab.colors, size: 54)
                // A tight, soft halo close to the icon.
                .shadow(color: (tab.colors.first ?? .clear).opacity(0.4), radius: 5)
                .shadow(color: .black.opacity(0.18), radius: 3, y: 2)
            VStack(alignment: .leading, spacing: 4) {
                Text(tab.title).font(.system(size: 20, weight: .bold))
                Text(subtitle)
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 14)
        .padding(.bottom, 4)
    }
}

/// A toggle with a small coloured icon and a grey explanation underneath.
struct DescribedToggle: View {
    let title: String
    let detail: String
    @Binding var isOn: Bool

    private static let blue = [Color(red: 0.30, green: 0.60, blue: 1.0), Color(red: 0.15, green: 0.42, blue: 0.95)]
    private static let green = [Color(red: 0.30, green: 0.78, blue: 0.45), Color(red: 0.15, green: 0.58, blue: 0.30)]
    private static let orange = [Color(red: 1.0, green: 0.65, blue: 0.25), Color(red: 0.95, green: 0.45, blue: 0.15)]
    private static let purple = [Color(red: 0.62, green: 0.48, blue: 1.0), Color(red: 0.42, green: 0.30, blue: 0.88)]
    private static let pink = [Color(red: 1.0, green: 0.42, blue: 0.62), Color(red: 0.85, green: 0.22, blue: 0.45)]
    private static let red = [Color(red: 1.0, green: 0.42, blue: 0.36), Color(red: 0.86, green: 0.22, blue: 0.20)]
    private static let teal = [Color(red: 0.25, green: 0.78, blue: 0.82), Color(red: 0.10, green: 0.55, blue: 0.62)]
    private static let grey = [Color(white: 0.62), Color(white: 0.44)]

    private static let icons: [String: (String, [Color])] = [
        "Show search suggestions": ("magnifyingglass", blue),
        "Suggest favourites": ("star.fill", orange),
        "Block annoyances": ("bell.slash.fill", orange),
        "Block chat widgets": ("bubble.left.and.bubble.right.fill", blue),
        "Keep lists up to date": ("arrow.triangle.2.circlepath", green),
        "Fingerprinting protection": ("touchid", purple),
        "Skip tracking redirects": ("arrow.uturn.right", teal),
        "Open original pages instead of AMP": ("bolt.slash.fill", orange),
        "Magic Theme": ("wand.and.stars", pink),
        "Show News": ("newspaper.fill", purple),
        "Pause sound and video in background tabs": ("pause.circle.fill", green),
        "Free up memory automatically": ("memorychip.fill", blue),
        "Open “safe” files after downloading": ("arrow.down.doc.fill", teal),
        "Translucent background": ("square.on.square.squareshape.controlhandles", purple),
        "Reduce motion": ("figure.walk.motion", grey),
        "Block third-party cookies": ("hand.raised.fill", blue),
        "Upgrade connections to HTTPS": ("lock.fill", green),
        "Clean tracking from links": ("link", teal),
        "Warn about look-alike websites": ("exclamationmark.triangle.fill", orange),
        "Ask websites not to sell or share my data": ("person.crop.circle.badge.xmark", purple),
        "Warn when visiting a fraudulent website": ("shield.lefthalf.filled.trianglebadge.exclamationmark", red),
        "Collapse empty ad spaces": ("rectangle.compress.vertical", purple),
        "Reject cookie banners automatically": ("xmark.seal.fill", pink),
        "Hide cookie banners": ("eye.slash.fill", grey),
        "Personalise the start page": ("cloud.sun.fill", blue),
        "Download and install updates automatically": ("arrow.down.circle.fill", green),
    ]

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: 11) {
                if let icon = Self.icons[title] {
                    IconTile(symbol: icon.0, colors: icon.1, size: 26)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

/// Grey explanatory text under a section.
struct Footnote: View {
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

    private struct Row { let host: String; let kind: PermissionKind; let allowed: Bool; var id: String { host + "|" + kind.rawValue } }
    private var rows: [Row] {
        permissions.decisions.keys.sorted().flatMap { host in
            kinds.compactMap { kind in permissions.decisions[host]?[kind.rawValue].map { Row(host: host, kind: kind, allowed: $0) } }
        }
    }

    var body: some View {
        if rows.isEmpty {
            Text("No websites yet. When you choose Always Allow, the site appears here.")
                .foregroundStyle(.secondary)
        } else {
            // Site and kind together: a site with camera and microphone answers has two rows,
            // and identical IDs made SwiftUI mix them up (the menu could change the wrong one).
            ForEach(rows, id: \.id) { row in
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
    @AppStorage(Prefs.offerBookmarks) private var offerBookmarks = true
    @AppStorage(Prefs.downloadFolder) private var downloadFolder = ""
    @AppStorage(Prefs.downloadRetention) private var downloadRetention = DownloadRetention.oneDay.rawValue
    @AppStorage(Prefs.askWhereToSave) private var askWhereToSave = false
    @AppStorage(Prefs.sortDownloads) private var sortDownloads = false
    @AppStorage(Prefs.openSafeFiles) private var openSafeFiles = false
    @AppStorage(Prefs.askDefaultBrowser) private var askDefault = true
    @State private var isDefaultBrowser = false   // checked when the pane appears (asking macOS isn't free)
    /// Other browsers to import from, found when the pane appears (not on every redraw).
    @State private var importSources: [BrowserImporter.Source] = []
    @State private var importStatus: String?
    @State private var importing = false

    private var engineName: String { (SearchEngine(rawValue: engine) ?? .google).name }

    var body: some View {
        Form {
            Section {
                SettingsHeader(tab: .general, subtitle: "How Ufolio starts, searches, remembers and downloads.")
            }

            Section {
                HStack(spacing: 10) {
                    Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 28, height: 28)
                    Text(isDefaultBrowser ? "Ufolio is your default web browser." : "Ufolio isn’t your default web browser.")
                    Spacer()
                    if isDefaultBrowser {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.green)
                    } else {
                        Button("Set Default…") { DefaultBrowser.makeDefault { isDefaultBrowser = $0 } }
                    }
                }
                if !isDefaultBrowser {
                    Toggle("Ask when Ufolio opens", isOn: $askDefault)
                }
            } header: { SectionTitle("Default browser") }

            Section {
                HStack(spacing: 10) {
                    IconTile(symbol: "sparkles", colors: [Color(red: 0.62, green: 0.48, blue: 1.0), Color(red: 0.42, green: 0.30, blue: 0.88)], size: 26)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Setup guide")
                        Text("Go through the first-run questions again: importing, search, Force Field, tabs and look.")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Run Again…") {
                        NotificationCenter.default.post(name: SetupGuide.showAgain, object: nil)
                        NSApp.keyWindow?.close()   // close Settings so the guide is in view
                    }
                }
            }

            Section {
                LabeledContent("Ufolio opens with") { Picker("", selection: $launch) {
                    ForEach(LaunchBehavior.allCases) { Text($0.label).tag($0.rawValue) }
                }.labelsHidden().fixedSize() }
                LabeledContent("New windows open with") { Picker("", selection: $newWindowPage) {
                    ForEach(NewTabPage.allCases) { Text($0.label).tag($0.rawValue) }
                }.labelsHidden().fixedSize() }
                LabeledContent("New tabs open with") { Picker("", selection: $newTabPage) {
                    ForEach(NewTabPage.allCases) { Text($0.label).tag($0.rawValue) }
                }.labelsHidden().fixedSize() }
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
            } header: { SectionTitle("Startup") }

            Section {
                LabeledContent("Search engine") { Picker("", selection: $engine) {
                    ForEach(SearchEngine.allCases) { Text($0.name).tag($0.rawValue) }
                }.labelsHidden().fixedSize() }
                DescribedToggle(title: "Show search suggestions",
                                detail: "What you type in the address bar is sent to \(engineName) to suggest searches.",
                                isOn: $suggestions)
            } header: { SectionTitle("Search") }

            Section {
                LabeledContent("Remove history items") { Picker("", selection: $historyRetention) {
                    ForEach(HistoryRetention.allCases) { Text($0.label).tag($0.rawValue) }
                }.labelsHidden().fixedSize() }
                // A shorter time takes effect straight away.
                .onChange(of: historyRetention) { _, _ in HistoryStore.all.forEach { $0.prune() } }
                HStack {
                    Menu("Import History and Bookmarks") {
                        ForEach(importSources) { source in
                            Button(source.name) { runImport(source) }
                        }
                    }
                    .fixedSize()
                    .disabled(importing)
                    if importing { ProgressView().controlSize(.small) }
                    if let importStatus { Text(importStatus).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2) }
                    Spacer()
                    Button("Clear History…") { HushDialogs.clearHistory(in: .settings) }
                }
                DescribedToggle(title: "Suggest favourites",
                                detail: "When you visit a site at least 6 times a day for 3 days in a row, Ufolio offers to add it to your Favourites.",
                                isOn: $offerBookmarks)
            } header: { SectionTitle("History") } footer: {
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
                LabeledContent("Remove download list items") { Picker("", selection: $downloadRetention) {
                    ForEach(DownloadRetention.allCases) { Text($0.label).tag($0.rawValue) }
                }.labelsHidden().fixedSize() }
                Toggle("Ask where to save each download", isOn: $askWhereToSave)
                Toggle("Sort downloads into folders by type (Images, Documents, Videos…)", isOn: $sortDownloads)
                DescribedToggle(title: "Open “safe” files after downloading",
                                detail: "“Safe” files include movies, pictures, sounds, PDFs, text documents and archives.",
                                isOn: $openSafeFiles)
            } header: { SectionTitle("Downloads") }

        }
        .formStyle(SafariFormStyle())
        .onAppear {
            isDefaultBrowser = DefaultBrowser.isDefault
            importSources = BrowserImporter.available()
        }
    }

    private func runImport(_ source: BrowserImporter.Source) {
        importing = true
        importStatus = nil
        DispatchQueue.global(qos: .userInitiated).async {
            let message: String
            do {
                let count = try BrowserImporter.importTopSites(from: source)
                let marks = (try? BrowserImporter.importBookmarks(from: source)) ?? 0
                message = "Imported \(count) pages and \(marks) bookmarks from \(source.name)."
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

struct AppearanceSettings: View {
    @AppStorage(Prefs.appearance) private var appearance = AppearanceMode.system.rawValue
    @AppStorage(Prefs.tabLayout) private var tabLayout = TabLayout.top.rawValue
    @AppStorage(Prefs.accent) private var accent = AccentChoice.system.rawValue
    @AppStorage(Prefs.startBackground) private var background = StartBackground.frosted.rawValue
    @AppStorage(Prefs.startGreeting) private var greeting = true
    @AppStorage(Prefs.startBookmarks) private var startBookmarks = true
    @AppStorage(Prefs.magicTheme) private var magicTheme = false
    @AppStorage(Prefs.startNews) private var startNews = false
    @AppStorage(Prefs.startFrequent) private var startFrequent = true
    @AppStorage(Prefs.startRecentlyClosed) private var startClosed = true
    @AppStorage(Prefs.startPrivacyReport) private var startPrivacy = true
    @AppStorage(Prefs.startShowAdult) private var startAdult = false
    @AppStorage(Prefs.showBookmarkBar) private var bookmarkBar = true
    @AppStorage(Prefs.tabPreviews) private var tabPreviews = true
    @AppStorage(Prefs.autoPictureInPicture) private var autoPiP = true
    @AppStorage(Prefs.showFullAddress) private var fullAddress = false
    @AppStorage(Prefs.reduceMotion) private var reduceMotion = false
    @AppStorage(Prefs.defaultZoom) private var zoom = 1.0
    @AppStorage(Prefs.launchSound) private var launchSound = true
    @AppStorage(Prefs.theme) private var alienTheme = "classic"
    @AppStorage(Prefs.funEffects) private var funEffects = true
    @AppStorage(Prefs.achievements) private var achievements = false

    private let zoomLevels: [Double] = [0.75, 0.85, 0.9, 1.0, 1.1, 1.25, 1.5, 1.75]

    var body: some View {
        Form {
            Section {
                SettingsHeader(tab: .appearance, subtitle: "Make Ufolio look and feel the way you like.")
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
                .disabled(alienTheme == "area51")
                DescribedToggle(title: "Area 51 alien theme",
                                detail: "Radioactive-green accents, green-tinted glass, a green aurora on the start page and a green saucer, in light and dark mode.",
                                isOn: Binding(get: { alienTheme == "area51" }, set: { alienTheme = $0 ? "area51" : "classic" }))
            } header: { SectionTitle("Theme") }

            Section {
                HStack(spacing: 18) {
                    ForEach(TabLayout.allCases) { option in
                        Button { withAnimation(.spring(response: 0.35, dampingFraction: 0.88)) { tabLayout = option.rawValue } } label: {
                            VStack(spacing: 7) {
                                LayoutPreview(side: option == .side)
                                    .scaleEffect(0.8)
                                    .frame(width: 144, height: 96)
                                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                                        .strokeBorder(tabLayout == option.rawValue ? Color.accentColor : Color.primary.opacity(0.1),
                                                      lineWidth: tabLayout == option.rawValue ? 2.5 : 1))
                                Text(option.label).font(.system(size: 12, weight: tabLayout == option.rawValue ? .semibold : .regular))
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
            } header: { SectionTitle("Tabs") } footer: {
                Footnote("Down the side, drag the column’s edge to resize it, or double-click the edge for icons only.")
            }

            Section {
                BackgroundPicker()
                Toggle("Show greeting", isOn: $greeting)
                Toggle("Show Recently Closed Tabs", isOn: $startClosed)
                Toggle("Show Favourites", isOn: $startBookmarks)
                Toggle("Show Suggestions", isOn: $startFrequent)
                Toggle("Show Privacy Report", isOn: $startPrivacy)
                Toggle("Show adult sites in Recently Closed and Suggestions", isOn: $startAdult)
                DescribedToggle(title: "Show News",
                                detail: "Headlines from publishers you choose, fetched privately by Ufolio. Customise topics from the start page.",
                                isOn: $startNews)
            } header: { SectionTitle("Start page") }

            Section {
                DescribedToggle(title: "Magic Theme",
                                detail: "The toolbar and tabs take on the colours of the website you’re on.",
                                isOn: $magicTheme)
                Toggle("Show bookmarks bar", isOn: $bookmarkBar)
                Toggle("Show a preview when you hover a tab", isOn: $tabPreviews)
                Toggle("Pop playing videos out into Picture in Picture when you switch tabs", isOn: $autoPiP)
                Toggle("Show full website address", isOn: $fullAddress)
            } header: { SectionTitle("Toolbar and tabs") }

            Section {
                HStack {
                    DescribedToggle(title: "Play the arrival sound when Ufolio opens",
                                    detail: "A short, retro sci-fi “ooo-weee-ooo” as the saucer lands.",
                                    isOn: $launchSound)
                    Button("Play") { UserDefaults.standard.set(true, forKey: Prefs.launchSound); LaunchSound.playIfWanted() }
                        .controlSize(.small)
                        .disabled(!launchSound)
                }
                DescribedToggle(title: "Effects",
                                detail: "The little touches: shooting stars, warp speed between Orbits, the Stealth shimmer and the download beam.",
                                isOn: $funEffects)
                DescribedToggle(title: "Achievements",
                                detail: "Badges on the weekly report card, such as First Contact at 1,000 ads blocked. Never any pop-ups.",
                                isOn: $achievements)
                DescribedToggle(title: "Reduce motion",
                                detail: "Turns off Ufolio’s animations, for an instant, snappier feel.",
                                isOn: $reduceMotion)
                LabeledContent("Default page zoom") { Picker("", selection: $zoom) {
                    ForEach(zoomLevels, id: \.self) { Text("\(Int(($0 * 100).rounded()))%").tag($0) }
                }.labelsHidden().fixedSize() }
                // Open pages still at the old default follow the new one (it used to apply only to
                // new tabs); pages you've zoomed yourself keep their zoom.
                .onChange(of: zoom) { old, new in
                    let previous = old > 0 ? old : 1
                    for model in BrowserModel.all.allObjects {
                        for tab in model.tabs where !tab.isAsleep && abs(tab.webView.pageZoom - previous) < 0.001 {
                            tab.webView.pageZoom = new
                        }
                    }
                }
            } header: { SectionTitle("Motion and zoom") }
        }
        .formStyle(SafariFormStyle())
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
                Text("Ufolio")
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
    @AppStorage(Prefs.httpsUpgrade) private var https = true
    @AppStorage(Prefs.globalPrivacyControl) private var gpc = true
    @AppStorage(Prefs.cleanLinks) private var cleanLinks = true
    @AppStorage(Prefs.debounceLinks) private var debounce = true
    @AppStorage(Prefs.deAMP) private var deAMP = true
    @AppStorage(Prefs.lookalikeWarning) private var lookalike = true
    @AppStorage(Prefs.fraudWarning) private var fraud = true
    @AppStorage(Prefs.cameraPolicy) private var camera = PermissionPolicy.ask.rawValue
    @AppStorage(Prefs.blockPopups) private var popups = true
    @AppStorage(Prefs.autoplay) private var autoplay = AutoplayPolicy.stopSound.rawValue
    @AppStorage(Prefs.javaScript) private var javaScript = true
    @State private var siteCount: Int?

    var body: some View {
        Form {
            Section {
                SettingsHeader(tab: .privacy, subtitle: "Ufolio keeps what you do on one site from following you to the next.")
            }

            Section {
                LabeledContent {
                    Button("Force Field Settings…") { UserDefaults.standard.set(SettingsTab.adBlocker.rawValue, forKey: "settingsTab") }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Cookies, scripts and fingerprinting")
                        Text("Set for every site, or one site at a time, in Force Field.")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
                DescribedToggle(title: "Upgrade connections to HTTPS",
                                detail: "Loads the secure version of a site whenever it exists.",
                                isOn: $https)
                DescribedToggle(title: "Clean tracking from links",
                                detail: "Removes tags like utm_source and fbclid that follow you between sites.",
                                isOn: $cleanLinks)
                DescribedToggle(title: "Skip tracking redirects",
                                detail: "Goes straight to the real page instead of through link trackers like l.facebook.com.",
                                isOn: $debounce)
                DescribedToggle(title: "Open original pages instead of AMP",
                                detail: "Swaps Google’s AMP copies of articles for the publisher’s real page.",
                                isOn: $deAMP)
                DescribedToggle(title: "Warn about look-alike websites",
                                detail: "Stops fake copies of sites you use, like paypa1.com, before they load.",
                                isOn: $lookalike)
                DescribedToggle(title: "Ask websites not to sell or share my data",
                                detail: "Sends the Global Privacy Control signal, which some laws require sites to honour.",
                                isOn: $gpc)
                DescribedToggle(title: "Warn when visiting a fraudulent website",
                                detail: "Uses the same Safe Browsing check as Safari.",
                                isOn: $fraud)
            } header: { SectionTitle("Tracking protection") }

            Section {
                LabeledContent("Camera and microphone") { Picker("", selection: $camera) {
                    ForEach(PermissionPolicy.allCases) { Text($0.label).tag($0.rawValue) }
                }.labelsHidden().fixedSize() }
                LabeledContent("Auto-play") { Picker("", selection: $autoplay) {
                    ForEach(AutoplayPolicy.allCases) { Text($0.label).tag($0.rawValue) }
                }.labelsHidden().fixedSize() }
                Toggle("Block pop-up windows", isOn: $popups)
                Toggle("Allow JavaScript", isOn: $javaScript)
            } header: { SectionTitle("Websites") } footer: {
                Text("Changes apply from the next page you open, in every tab. With “Stop media with sound”, a video on a page you open yourself still plays, as in Safari.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section {
                RememberedPermissions(kinds: [.camera, .microphone])
            } header: { SectionTitle("Camera and microphone decisions") }

            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Cookies and website data")
                        Text(siteCount.map { "Stored by \($0) website\($0 == 1 ? "" : "s")" } ?? "Checking…")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Clear All…") {
                        DialogHost.settings.present(HushDialog(
                            art: .symbol("externaldrive.fill"), badge: "trash.fill", theme: .danger, motion: .drift,
                            title: "Clear all website data?",
                            message: "You’ll be signed out of websites and they’ll forget your preferences. This can’t be undone.",
                            choices: [.init(title: "Cancel", role: .cancel), .init(title: "Clear All", role: .destructive)],
                            completion: { choice, _ in if choice == 1 { clearData() } }))
                    }
                        .disabled(siteCount == 0)
                }
            } header: { SectionTitle("Website data") }

            CookieCleanerSection()

            TorrentToolsSection()
        }
        .formStyle(SafariFormStyle())
        .onAppear(perform: countSites)
    }

    /// Counted across the default profile and every other profile.
    private func countSites() {
        let stores = SpaceStore.shared.allDataStores
        var sites = Set<String>()
        var remaining = stores.count
        for store in stores {
            store.fetchDataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes()) { records in
                records.forEach { sites.insert($0.displayName) }
                remaining -= 1
                if remaining == 0 { siteCount = sites.count }
            }
        }
    }

    private func clearData() {
        // What's held in memory goes too: a page loading ahead, pages kept for an instant Back,
        // and closed tabs' cached page processes (Back used to show a page still signed in).
        Preloader.discard()
        for model in BrowserModel.all.allObjects { model.tabs.forEach { $0.dropParkedPages(forget: true) } }
        Speed.releaseCachedProcesses()
        let stores = SpaceStore.shared.allDataStores
        var remaining = stores.count
        for store in stores {
            store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast) {
                remaining -= 1
                if remaining == 0 { countSites() }
            }
        }
    }
}

/// Settings › Privacy & Security › Torrent tools: one switch, with its options underneath.
private struct TorrentToolsSection: View {
    @AppStorage(Prefs.torrentTools) private var on = false
    @AppStorage(Prefs.torrentApp) private var app = ""
    @AppStorage(Prefs.torrentPreview) private var preview = true
    @AppStorage(Prefs.torrentSiteMode) private var siteMode = true
    @AppStorage(Prefs.torrentFakeWarnings) private var fakeWarnings = true
    @State private var apps: [URL] = []

    private var uniqueApps: [URL] {
        var seen = Set<String>()
        return apps.filter { url in
            guard let id = Bundle(url: url)?.bundleIdentifier, !id.isEmpty else { return false }
            return seen.insert(id).inserted
        }
    }

    var body: some View {
        Section {
            DescribedToggle(title: "Torrent tools",
                            detail: "See what a magnet link or .torrent file contains before your torrent app opens it, and stay safe on torrent sites. Ufolio never downloads or shares torrents itself.",
                            isOn: $on)
            if on {
                Picker("Torrent app", selection: $app) {
                    Text("Mac default").tag("")
                    // Apps without an ID (they'd share the "Mac default" choice) are left out, and each
                    // app is listed once even if macOS knows several copies of it.
                    ForEach(uniqueApps, id: \.self) { url in
                        Text(TorrentTools.appName(url)).tag(Bundle(url: url)?.bundleIdentifier ?? "")
                    }
                }
                DescribedToggle(title: "Preview .torrent files",
                                detail: "Lists the files and sizes when one finishes downloading, and warns about programs hidden in videos or names like movie.mp4.exe.",
                                isOn: $preview)
                DescribedToggle(title: "Torrent site mode",
                                detail: "On torrent sites, stops pop-ups, pop-unders and redirects to other sites.",
                                isOn: $siteMode)
                DescribedToggle(title: "Mark fake download buttons",
                                detail: "On torrent sites, outlines the real magnet links in green and marks fake “Download” ads and disguised programs in red.",
                                isOn: $fakeWarnings)
            }
        } header: { SectionTitle("Torrent tools") } footer: {
            if on && apps.isEmpty {
                Footnote("No torrent app found on this Mac. Magnet links can still be copied.")
            }
        }
        .onAppear { apps = TorrentTools.installedApps() }
    }
}

// MARK: - Ad blocker

extension BlockingMode {
    var symbol: String {
        switch self {
        case .standard: return "shield.lefthalf.filled"
        case .strict: return "shield.fill"
        case .off: return "shield.slash"
        }
    }
    var colors: [Color] {
        switch self {
        case .standard: return [Color(red: 0.55, green: 0.40, blue: 1.0), Color(red: 0.36, green: 0.26, blue: 0.86)]
        case .strict: return [Color(red: 1.0, green: 0.45, blue: 0.35), Color(red: 0.88, green: 0.24, blue: 0.30)]
        case .off: return [Color(white: 0.62), Color(white: 0.45)]
        }
    }
}

struct BlockingModeCard: View {
    let mode: BlockingMode
    let selected: Bool
    var compact = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    IconTile(symbol: mode.symbol, colors: mode.colors, size: compact ? 22 : 28)
                    Spacer()
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selected ? Color.accentColor : Color.secondary.opacity(0.5))
                }
                Text(mode.label).font(.system(size: compact ? 12 : 13, weight: .semibold))
                if !compact {
                    Text(mode.detail).font(.system(size: 11)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
            }
            .padding(compact ? 9 : 11)
            .frame(maxWidth: .infinity, minHeight: compact ? 0 : 108, maxHeight: .infinity, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(selected ? 0.08 : hovering ? 0.05 : 0.03)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(selected ? Color.accentColor.opacity(0.8) : Color.primary.opacity(0.07), lineWidth: selected ? 1.5 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

private struct AdBlockerSettings: View {
    @ObservedObject private var blocker = ContentBlocker.shared
    /// Not observed here: only the stats card redraws as the count goes up, not the whole pane.
    private let stats = BlockStats.shared
    @ObservedObject private var zapper = ElementZapper.shared
    @AppStorage(Prefs.adBlockEnabled) private var ads = true
    @AppStorage(Prefs.trackerBlockEnabled) private var trackers = true
    @AppStorage(Prefs.hideCookieBanners) private var cookieBanners = true
    @AppStorage(Prefs.collapseAdSpace) private var collapse = true
    @AppStorage(Prefs.autoRejectCookies) private var autoReject = true
    @AppStorage(Prefs.blockingMode) private var mode = BlockingMode.standard.rawValue
    @AppStorage(Prefs.blockAnnoyances) private var annoyances = true
    @AppStorage(Prefs.blockChatWidgets) private var chatWidgets = false
    @AppStorage(Prefs.autoUpdateLists) private var autoUpdateLists = true
    @ObservedObject private var siteShields = ShieldSettings.shared
    @State private var defaultsRevision = 0
    @State private var showWebSheet = false

    /// A picker binding for a default stored as text (with older on/off answers carried over).
    private func defaultBinding(_ key: String, _ current: String) -> Binding<String> {
        Binding(get: { _ = defaultsRevision; return current },
                set: { UserDefaults.standard.set($0, forKey: key); defaultsRevision += 1 })
    }

    var body: some View {
        Form {
            Section {
                StatsCard(stats: stats) {
                    DialogHost.settings.present(HushDialog(
                        art: .symbol("hush"), badge: "arrow.counterclockwise", theme: .hush, motion: .drift,
                        title: "Reset the counter?",
                        message: "The count of blocked ads and trackers starts again from zero.",
                        choices: [.init(title: "Cancel", role: .cancel), .init(title: "Reset", role: .destructive)],
                        completion: { choice, _ in if choice == 1 { BlockStats.shared.reset() } }))
                }
            }

            Section { HushlistCard() }

            Section {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(BlockingMode.allCases) { option in
                        BlockingModeCard(mode: option, selected: mode == option.rawValue) {
                            withAnimation(.easeOut(duration: 0.15)) { mode = option.rawValue }
                        }
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                LabeledContent("Scripts") {
                    Picker("", selection: defaultBinding(Prefs.scriptPolicy, ShieldSettings.defaults.scripts.rawValue)) {
                        ForEach(ScriptPolicy.allCases) { Text($0.label).tag($0.rawValue) }
                    }.labelsHidden().fixedSize()
                }
                LabeledContent("Fingerprinting protection") {
                    Picker("", selection: defaultBinding(Prefs.fingerprintMode, ShieldSettings.defaults.fingerprinting.rawValue)) {
                        ForEach(FingerprintLevel.allCases) { Text($0.label).tag($0.rawValue) }
                    }.labelsHidden().fixedSize()
                }
                LabeledContent("Cookies") {
                    Picker("", selection: defaultBinding(Prefs.cookiePolicy, ShieldSettings.defaults.cookies.rawValue)) {
                        ForEach(CookiePolicy.allCases) { Text($0.label).tag($0.rawValue) }
                    }.labelsHidden().fixedSize()
                }
            } header: { SectionTitle("Defaults for every site") } footer: {
                Footnote("Each site can be set differently from the Force Field panel in the toolbar. Blocking scripts or all cookies makes many sites stop working, so they’re best chosen for single sites.")
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
                DescribedToggle(title: "Block annoyances",
                                detail: "“Sign in with Google” pop-ups, push-notification prompts and newsletter pop-ups.",
                                isOn: $annoyances)
                DescribedToggle(title: "Block chat widgets",
                                detail: "Hides the support-chat bubbles many sites show in the corner.",
                                isOn: $chatWidgets)
            } header: { SectionTitle("Built-in protection") }

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
                DescribedToggle(title: "Keep lists up to date",
                                detail: "Refreshes lists added from the web once a week, quietly in the background.",
                                isOn: $autoUpdateLists)
            } header: { SectionTitle("Your filter lists") } footer: {
                Text("Works with Adblock Plus and uBlock Origin lists, hosts files and Safari content-blocker JSON. Advanced rules WebKit can’t run are skipped.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section {
                let custom = Set(siteShields.sites.keys).union(blocker.shieldsDown).sorted()
                if custom.isEmpty {
                    Text("None yet. Change a site’s settings from the Force Field panel in the toolbar.")
                        .foregroundStyle(.secondary)
                }
                ForEach(custom, id: \.self) { site in
                    let off = blocker.isShieldsDown(site)
                    HStack(spacing: 10) {
                        Favicon(url: URL(string: "https://\(site)"), size: 16)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(site)
                            Text(off ? "Force Field off" : siteShields.summary(for: site))
                                .font(.system(size: 11)).foregroundStyle(off ? Color.orange : .secondary)
                                .lineLimit(2)
                        }
                        Spacer()
                        Button("Reset") {
                            if off { blocker.setShields(true, for: site) }
                            siteShields.reset(site)
                        }
                        .controlSize(.small)   // (no tooltip: the row vanishes when clicked, see TabStrip)
                    }
                }
            } header: { SectionTitle("Site settings") }

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
            } header: { SectionTitle("Hidden elements") }
        }
        .formStyle(SafariFormStyle())
        .sheet(isPresented: $showWebSheet) { AddListSheet() }
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
    @AppStorage(Prefs.locationPolicy) private var policy = PermissionPolicy.ask.rawValue
    @ObservedObject private var weather = LocalWeather.shared
    @State private var editing = false

    var body: some View {
        Form {
            Section {
                SettingsHeader(tab: .location, subtitle: "Choose which websites can know where you are. Ufolio itself never uses your Mac’s location.")
            }

            Section {
                LabeledContent {
                    HStack(spacing: 8) {
                        if weather.isPersonalised {
                            Button("Remove") { weather.clear() }
                        }
                        Button(weather.isPersonalised ? "Change…" : "Personalise…") { editing = true }
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Your town for the start page")
                        if let place = weather.place {
                            HStack(spacing: 5) {
                                Text(place.detail.isEmpty ? place.name : "\(place.name), \(place.detail)")
                                if let t = weather.temperature {
                                    Image(systemName: weather.symbol).symbolRenderingMode(.multicolor)
                                    Text("\(t)° \(weather.summary)")
                                }
                            }
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                        } else {
                            Text("Not set: add a town or postcode to see your local weather")
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                    }
                }
            } header: { SectionTitle("Start page") } footer: {
                Text("What you type goes to Apple to find the place, and only its rough position goes to Open-Meteo for the weather.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section {
                LabeledContent("When a website asks for your location") { Picker("", selection: $policy) {
                    ForEach(PermissionPolicy.allCases) { Text($0.label).tag($0.rawValue) }
                }.labelsHidden().fixedSize() }
            } header: { SectionTitle("Websites") } footer: {
                Text("Maps, delivery and weather sites can use your location to show nearby results. Ufolio asks you first and remembers your answer.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section {
                RememberedPermissions(kinds: [.location])
            } header: { SectionTitle("Your answers") }
        }
        .formStyle(SafariFormStyle())
        .sheet(isPresented: $editing) {
            PersonaliseCard { editing = false }
        }
    }
}

// MARK: - Updates

private struct UpdateSettings: View {
    @ObservedObject private var updater = Updater.shared
    @State private var showAllVersions = false

    private var earlierVersions: [ReleaseNotes.Version] {
        ReleaseNotes.bundled.versions.filter { $0.version != updater.currentVersion }
    }
    @AppStorage(Prefs.autoCheckUpdates) private var autoCheck = true
    @AppStorage(Prefs.autoInstallUpdates) private var autoInstall = true
    @AppStorage(Prefs.betaUpdates) private var betaUpdates = false

    var body: some View {
        Form {
            Section {
                HStack(spacing: 16) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 64, height: 64)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Ufolio Browser \(updater.currentVersion)")
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

            if let installed = ReleaseNotes.bundled.notes(for: updater.currentVersion) {
                Section {
                    ReleaseNotesView(notes: installed)
                        .padding(.vertical, 6)
                } header: { SectionTitle("What’s in Ufolio \(installed.version)") }
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
                } header: { SectionTitle("What’s new") }
            }

            Section {
                Toggle("Check for updates automatically", isOn: $autoCheck)
                DescribedToggle(title: "Download and install updates automatically",
                                detail: "New versions download in the background and install the next time you quit Ufolio.",
                                isOn: $autoInstall)
                    .disabled(!autoCheck)
                DescribedToggle(title: "Get beta versions",
                                detail: "Try new versions early, before everyone else. They may have rough edges. They’re checked exactly like regular updates, and if one won’t start, Ufolio offers to go back.",
                                isOn: $betaUpdates)
            } header: { SectionTitle("Automatic updates") } footer: {
                Text("Updates come from github.com/\(Updater.repo). Each download is checked against GitHub’s fingerprint before it’s installed.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !earlierVersions.isEmpty {
                Section {
                    ForEach(showAllVersions ? earlierVersions : Array(earlierVersions.prefix(3))) { version in
                        DisclosureGroup("Ufolio \(version.version)") {
                            ReleaseNotesView(notes: version).padding(.vertical, 6)
                        }
                    }
                    if earlierVersions.count > 3 {
                        Button(showAllVersions ? "Show Less" : "Show More") {
                            withAnimation(.easeOut(duration: 0.2)) { showAllVersions.toggle() }
                        }
                        .buttonStyle(.link)
                    }
                } header: { SectionTitle("Earlier versions") }
            }
        }
        .formStyle(SafariFormStyle())
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
    @AppStorage(Prefs.passwordFillLock) private var fillLock = UserAuth.FillLock.never.rawValue
    @State private var moveMessage: String?
    @State private var unlocked = false
    @State private var logins: [SavedLogin] = []
    @State private var cardList: [CardVault.Summary] = []
    @State private var revealed: [String: String] = [:]
    @State private var search = ""
    @State private var neverSave = PasswordVault.neverSave
    @State private var showAddCard = false
    /// Loaded once when the pane appears. (As a starting value it was worked out again, with a
    /// Contacts lookup, every time Settings redrew this pane.)
    @State private var myName: String?
    @State private var copiedID: String?

    private var filtered: [SavedLogin] {
        let q = search.lowercased()
        return q.isEmpty ? logins : logins.filter { $0.host.contains(q) || $0.account.lowercased().contains(q) }
    }

    @State private var importMessage: String?

    var body: some View {
        Form {
            Section {
                SettingsHeader(tab: .passwords,
                               subtitle: "Kept encrypted in Ufolio’s own vault. Save a password once and it fills in from then on.")
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
            } header: { SectionTitle("AutoFill web forms") } footer: {
                Footnote("AutoFill only works on secure (https) pages, and only fills a password on the exact site it was saved for.")
            }

            Section {
                Picker("Ask for Touch ID or your Mac password before filling", selection: $fillLock) {
                    ForEach(UserAuth.FillLock.allCases) { Text($0.label).tag($0.rawValue) }
                }
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Passwords from older versions of Ufolio")
                        Text(moveMessage ?? "Still in your keychain, and listed here. Each moves into Ufolio the first time it’s used (macOS asks once for that password). Move All asks once for every one.")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Move All") {
                        moveMessage = "Moving…"
                        DispatchQueue.global(qos: .userInitiated).async {
                            let moved = Vault.moveFromKeychain()
                            DispatchQueue.main.async {
                                moveMessage = moved > 0 ? "Moved \(moved) item\(moved == 1 ? "" : "s")." : "Nothing to move."
                                cardList = CardVault.list()
                                if unlocked { logins = PasswordVault.logins() }
                            }
                        }
                    }
                }
            } header: { SectionTitle("Security") } footer: {
                Footnote("Seeing or copying a password here always asks. Your vault is encrypted on your Mac, and FileVault protects it while your Mac is locked or off.")
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
                    Text("No saved passwords yet. Ufolio offers to save one when you sign in to a website.")
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
                                else {
                                    // Read in the background: an older password still in the keychain makes
                                    // macOS ask once, and Ufolio used to freeze behind that question.
                                    DispatchQueue.global(qos: .userInitiated).async {
                                        let password = PasswordVault.password(for: login) ?? ""
                                        DispatchQueue.main.async { revealed[login.id] = password }
                                    }
                                }
                            } label: { Image(systemName: revealed[login.id] == nil ? "eye" : "eye.slash") }
                                .buttonStyle(.borderless).accessibilityLabel("Show password")
                            Button { copy(login) } label: {
                                Image(systemName: copiedID == login.id ? "checkmark" : "doc.on.doc")
                            }
                            .buttonStyle(.borderless).accessibilityLabel("Copy password (cleared from the clipboard after 90 seconds)")
                            Button {
                                // Asks first: one stray click used to delete a saved password for good.
                                DialogHost.settings.present(HushDialog(
                                    art: .symbol("key.fill"), theme: .danger, motion: .drift,
                                    title: "Delete the password for \(login.host)?",
                                    message: "\(login.account.isEmpty ? "This password" : "The password for \(login.account)") will be deleted from Ufolio. This can’t be undone.",
                                    choices: [.init(title: "Cancel", role: .cancel), .init(title: "Delete", role: .destructive)],
                                    completion: { choice, _ in
                                        guard choice == 1 else { return }
                                        PasswordVault.delete(login)
                                        logins.removeAll { $0.id == login.id }
                                    }))
                            } label: { Image(systemName: "trash") }
                                .buttonStyle(.borderless).accessibilityLabel("Delete")
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
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Import passwords from another browser")
                        if let importMessage {
                            Text(importMessage).font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Button("Choose File…") { PasswordImporter.run { importMessage = $0; if unlocked { logins = PasswordVault.logins() } } }
                }
            } header: { SectionTitle("Import") } footer: {
                Footnote("First export your passwords as a file. Chrome, Brave and Edge: Settings › Passwords › Export. Safari: File › Export › Passwords. Firefox: Passwords › ⋯ › Export Passwords.")
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
                            DialogHost.settings.present(HushDialog(
                                art: .symbol("creditcard.fill"), theme: .danger, motion: .drift,
                                title: "Delete “\(card.label)”?",
                                message: "This card will be deleted from Ufolio. This can’t be undone.",
                                choices: [.init(title: "Cancel", role: .cancel), .init(title: "Delete", role: .destructive)],
                                completion: { choice, _ in
                                    guard choice == 1 else { return }
                                    CardVault.delete(card.id)
                                    cardList = CardVault.list()
                                }))
                        } label: { Image(systemName: "trash") }
                            .buttonStyle(.borderless).accessibilityLabel("Delete")
                    }
                }
            } header: { SectionTitle("Credit cards") }

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
                } header: { SectionTitle("Never save passwords for") }
            }
        }
        .formStyle(SafariFormStyle())
        .onAppear {
            // Read in the background, so opening this pane never stalls.
            DispatchQueue.global(qos: .userInitiated).async {
                let cards = CardVault.list()
                DispatchQueue.main.async { cardList = cards }
            }
            if MyCard.status == .authorized {
                DispatchQueue.global(qos: .userInitiated).async {
                    let name = MyCard.displayName
                    DispatchQueue.main.async { myName = name }
                }
            }
        }
        .onDisappear { lock() }
        // Lock again as soon as you switch to another app.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in lock() }
        .sheet(isPresented: $showAddCard) {
            AddCardSheet { cardList = CardVault.list() }
        }
    }

    private func unlock() {
        UserAuth.confirm("show your saved passwords") { ok in
            guard ok else { return }
            DispatchQueue.global(qos: .userInitiated).async {
                let all = PasswordVault.logins()
                DispatchQueue.main.async { logins = all; unlocked = true }
            }
        }
    }

    private func lock() {
        unlocked = false
        revealed = [:]
        logins = []
    }

    /// Copies a password and clears it from the clipboard 90 s later (if it's still there).
    private func copy(_ login: SavedLogin) {
        DispatchQueue.global(qos: .userInitiated).async {
            guard let password = PasswordVault.password(for: login) else { return }
            DispatchQueue.main.async { putOnClipboard(password, for: login) }
        }
    }

    private func putOnClipboard(_ password: String, for login: SavedLogin) {
        let board = NSPasteboard.general
        board.clearContents()
        board.setString(password, forType: .string)
        // Tells clipboard-history apps not to keep it (the convention 1Password and others use).
        board.setString("", forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
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
                    Text("Saved encrypted in Ufolio’s own vault. Ufolio never stores the security code.")
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
            .formStyle(SafariFormStyle())
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
        // Plain 0–9 only: full-width digits (some keyboards, pasted text) passed the check but
        // were filled into checkout forms as characters sites reject.
        let digits = number.filter { $0.isASCII && $0.isNumber }
        guard (12...19).contains(digits.count), Self.luhn(digits) else {
            error = "That card number doesn’t look right."
            return
        }
        let card = SavedCard(name: name.trimmingCharacters(in: .whitespaces), number: digits, expMonth: month, expYear: year)
        guard CardVault.save(card) else {
            error = "The card couldn’t be saved."
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
    @State private var safariExtensions: [SafariExtensionInfo] = []

    var body: some View {
        Form {
            Section {
                SettingsHeader(tab: .extensions,
                               subtitle: "Add Chrome extensions from the Chrome Web Store. Most work in Ufolio; a few that rely on Chrome-only features may not.")
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
                } header: { SectionTitle("Add an extension") } footer: {
                    Footnote("Find an extension in the Chrome Web Store, copy the address of its page and paste it here. Ufolio shows what it can access before adding it.")
                }

                Section {
                    if safariExtensions.isEmpty {
                        Text("No Safari extensions found. They come inside apps, usually from the Mac App Store — install one and it appears here.")
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    ForEach(safariExtensions) { info in
                        SafariExtensionRow(info: info)
                    }
                } header: { SectionTitle("Safari extensions on this Mac") } footer: {
                    Footnote("Safari web extensions run in Ufolio straight from their app. Content blockers can share their rules with Force Field when the app includes them as a file.")
                }

                Section {
                    if store.installed.isEmpty {
                        Text("No extensions yet.").foregroundStyle(.secondary)
                    }
                    ForEach(store.installed) { ext in
                        ExtensionRow(ext: ext)
                    }
                } header: { SectionTitle("Installed") } footer: {
                    if store.installed.filter(\.enabled).count > 3 {
                        Footnote("The first three extensions that are turned on have a button next to Force Field. Choose Show in Toolbar from an extension’s ⋯ menu to give it one.")
                    }
                }
            }
        }
        .formStyle(SafariFormStyle())
        .onAppear(perform: refreshSafari)
    }

    private func refreshSafari() {
        DispatchQueue.global(qos: .userInitiated).async {
            let found = SafariExtensionFinder.find()
            DispatchQueue.main.async { safariExtensions = found }
        }
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
                if ext.enabled {
                    if #available(macOS 15.4, *) {
                        Button("Use on Current Page") { ExtensionManager.shared.performAction(ext.id) }
                    }
                    if !store.inToolbar(ext) {
                        Button("Show in Toolbar") { store.showInToolbar(ext) }
                    }
                    Divider()
                }
                if let source = ext.source, let url = URL(string: source), url.scheme == "https",
                   url.host == "chromewebstore.google.com" || url.host == "chrome.google.com" {
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
            if #available(macOS 15.4, *) {
                var loaded: WKWebExtension?
                if let appex = ext.safariBundleURL, let bundle = Bundle(url: appex) {
                    loaded = try? await WKWebExtension(appExtensionBundle: bundle)
                } else {
                    loaded = try? await WKWebExtension(resourceBaseURL: store.directory(for: ext))
                }
                icon = loaded?.icon(for: CGSize(width: 28, height: 28))
            }
        }
    }
}

/// A Safari extension found in an installed app, with Add (web extensions) or
/// Import Rules (content blockers that include their rules).
private struct SafariExtensionRow: View {
    let info: SafariExtensionInfo
    @ObservedObject private var store = ExtensionStore.shared
    @ObservedObject private var blocker = ContentBlocker.shared
    /// Looked up once (the row redraws whenever filter-list status changes).
    @State private var appIcon: NSImage?

    private var added: Bool {
        switch info.kind {
        case .webExtension: return store.installed.contains { $0.id == "safari-" + info.bundleID }
        case .contentBlocker: return blocker.lists.contains { $0.name == info.name }
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: appIcon ?? NSImage())
                .resizable().frame(width: 28, height: 28)
                .task(id: info.appURL) { appIcon = NSWorkspace.shared.icon(forFile: info.appURL.path) }
            VStack(alignment: .leading, spacing: 2) {
                Text(info.name).font(.system(size: 13, weight: .medium))
                Text(info.kind == .webExtension ? "Safari extension · \(info.appName)" : "Content blocker · \(info.appName)")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            if added {
                Label("Added", systemImage: "checkmark.circle.fill").foregroundStyle(Color.green).font(.system(size: 12))
            } else {
                switch info.kind {
                case .webExtension:
                    Button("Add") { Task { @MainActor in await store.install(safari: info) } }
                        .disabled(store.isWorking)
                case .contentBlocker:
                    if let rules = info.blockerList {
                        Button("Import Rules") { blocker.importFile(rules, name: info.name) }
                            .disabled(blocker.isWorking)
                    } else {
                        Text("Rules not shareable").font(.system(size: 11)).foregroundStyle(.secondary)
                            .help("This content blocker keeps its rules inside its own app, so Ufolio can’t read them.")
                    }
                }
            }
        }
    }
}
