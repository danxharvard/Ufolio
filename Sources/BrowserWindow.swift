import SwiftUI
import WebKit

/// The whole window: toolbar, tab strip, bookmarks bar and page.
struct BrowserWindow: View {
    @StateObject private var model: BrowserModel

    init(isPrivate: Bool = false) {
        _model = StateObject(wrappedValue: BrowserModel(isPrivate: isPrivate))
    }

    @StateObject private var suggestions = SuggestionsModel()
    @Environment(\.colorScheme) private var systemScheme
    @AppStorage(Prefs.showBookmarkBar) private var showBookmarkBar = true
    @State private var isFullScreen = false
    @AppStorage(Prefs.magicTheme) private var magicTheme = false
    @State private var siteColor: NSColor?
    private var tint: Chrome.Tint? {
        if model.isPrivate { return PrivateChrome.tint }
        return magicTheme ? Chrome.tint(for: siteColor) : nil
    }
    /// Where the address bar is, so its suggestions line up underneath it.
    @State private var addressFrame: CGRect = .zero
    @State private var showWelcome = false
    @State private var showDefaultBanner = false
    @State private var whatsNew: ReleaseNotes.Version?


    var body: some View {
        VStack(spacing: 0) {
            // Tabs in the title bar, beside the window buttons.
            VStack(spacing: 0) {
            WindowTabBar(model: model, toolbarColor: tint?.toolbar ?? Chrome.toolbar, leadingInset: isFullScreen ? 10 : 80)
                .background(tint?.frame ?? .clear)
            VStack(spacing: 0) {
                    toolbarRow
                    if showBookmarkBar {
                        BookmarkBar(model: model)
                    }
                    if showDefaultBanner {
                        Hairline()
                        DefaultBrowserBanner {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) { showDefaultBanner = false }
                        }
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    FindBarHost(model: model)
                }
            .background(tint?.toolbar ?? Chrome.toolbar)
            .overlay(alignment: .bottom) { Hairline() }
            }
            .environment(\.colorScheme, tint?.scheme ?? systemScheme)
            .animation(.easeInOut(duration: 0.35), value: siteColor)
            .background(SelectedTab(model: model) { tab in
                SiteColorReader(tab: tab) { color in if color != siteColor { siteColor = color } }
                    .id(tab.id)
            })

            TranslationHost()
            // "Add to Hush" on Chrome Web Store pages (takes no space anywhere else).
            SelectedTab(model: model) { tab in
                WebStoreBar(tab: tab).background(VisualEffect(material: .titlebar))
            }
            // "You visit this site a lot: add it to your Favourites?" (no space otherwise).
            SelectedTab(model: model) { tab in
                BookmarkOfferBar(tab: tab).background(VisualEffect(material: .titlebar))
            }

            HStack(spacing: 0) {
            // Bookmarks & History, beside the page (⇧⌘L).
            if model.sidebarOpen {
                LibrarySidebar(model: model)
                    .transition(.move(edge: .leading).combined(with: .opacity))
                Divider()
            }
            ZStack(alignment: .topLeading) {
                PageArea(model: model)
                if let tab = model.selectedTab {
                    ProgressLine(tab: tab)
                }
                if suggestions.isVisible {
                    SuggestionList(suggestions: suggestions) { choice in
                        go(choice.text)
                    }
                    .frame(width: max(260, addressFrame.width))
                    .offset(x: addressFrame.minX)
                    .padding(.top, 6)
                    .transition(.opacity.combined(with: .offset(y: -4)))
                }
            }
            .animation(.easeOut(duration: 0.12), value: suggestions.isVisible)
            }
            .animation(.spring(response: 0.32, dampingFraction: 0.9), value: model.sidebarOpen)
        }
        .ignoresSafeArea(.container, edges: .top)
        .background(VisualEffect(material: .titlebar, blending: .behindWindow).ignoresSafeArea())
        .coordinateSpace(name: "window")
        .onPreferenceChange(AddressFrameKey.self) { addressFrame = $0 }
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { model.windowWidth = geo.size.width }
                    .onChange(of: geo.size.width) { model.windowWidth = $0 }
            }
        )
        .background(WindowReader { window in
            // Remember the window's size and position between launches.
            if let window, model.window !== window, !model.isPrivate {
                window.setFrameUsingName("HushBrowserWindow")
                window.setFrameAutosaveName("HushBrowserWindow")
            }
            model.window = window
            TrafficLights.align(in: window)
        })
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResizeNotification)) { note in
            if (note.object as? NSWindow) === model.window { TrafficLights.align(in: model.window) }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification)) { note in
            if (note.object as? NSWindow) === model.window { isFullScreen = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { note in
            if (note.object as? NSWindow) === model.window {
                isFullScreen = false
                TrafficLights.align(in: model.window)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { note in
            if (note.object as? NSWindow) === model.window { TrafficLights.align(in: model.window) }
        }
        // The welcome screen and default-browser question are drawn inside the window,
        // over a dimmed backdrop (SwiftUI sheets could end up off-screen and lock the window).
        .overlay {
            if let notes = whatsNew {
                LaunchCardOverlay {
                    WhatsNewView(notes: notes) { whatsNew = nil }
                }
                .transition(.opacity)
            }
            if showWelcome {
                LaunchCardOverlay {
                    WelcomeView {
                        UserDefaults.standard.set(true, forKey: Prefs.hasOnboarded)
                        showWelcome = false
                        model.focusAddressBar()
                    }
                }
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.25), value: showWelcome)
        .animation(.easeOut(duration: 0.25), value: whatsNew?.version)
        // Links opened from other apps (when Hush is the default browser) arrive here.
        .handlesExternalEvents(preferring: ["*"], allowing: ["*"])
        .onOpenURL { url in
            guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return }
            if let tab = model.selectedTab, tab.isBlank {
                tab.load(url)
            } else {
                model.newTab(url: url)
            }
            // Give the page focus, not the (empty) address bar.
            if let tab = model.selectedTab { DispatchQueue.main.async { tab.webView.window?.makeFirstResponder(tab.webView) } }
            NSApp.activate(ignoringOtherApps: true)
        }
        .hushDialogs(model.dialogs)
        .onReceive(NotificationCenter.default.publisher(for: QuitHelper.closeSheets)) { _ in
            showWelcome = false
            showDefaultBanner = false
            whatsNew = nil
        }
        .onAppear {
            guard !model.isPrivate else { return }
            switch LaunchPrompts.next() {
            case .welcome:
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { showWelcome = true }
            case .whatsNew(let notes):
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { whatsNew = notes }
            case .defaultBrowser:
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { showDefaultBanner = true }
                }
            case nil:
                break
            }
        }
        .focusedSceneObject(model)
        .navigationTitle(model.selectedTab?.displayTitle ?? "Hush")
        .frame(minWidth: 640, minHeight: 420)
    }

    /// Back, forward and reload; the address bar across the middle; then the tools.
    private var toolbarRow: some View {
        HStack(spacing: 6) {
            SidebarButton(model: model)
            SelectedTab(model: model) { NavButtons(tab: $0) }
            SelectedTab(model: model) { tab in
                AddressBar(model: model, tab: tab, suggestions: suggestions, onGo: go)
                    .frame(maxWidth: .infinity)
                    .background(GeometryReader { geo in
                        Color.clear.preference(key: AddressFrameKey.self, value: geo.frame(in: .named("window")))
                    })
            }
            .padding(.horizontal, 4)
            HStack(spacing: 2) {
                DownloadsButton()
                if !model.isPrivate { ExtensionButtons() }   // up to three, right beside Hush Guard
                SelectedTab(model: model) { ShieldsButton(tab: $0) }
                PrivateWindowButton(isPrivate: model.isPrivate)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 44)
    }

    private func go(_ text: String) {
        suggestions.dismiss()
        guard let url = URLResolver.resolve(text) else { return }
        model.selectedTab?.load(url)
        if let tab = model.selectedTab {
            DispatchQueue.main.async { tab.webView.window?.makeFirstResponder(tab.webView) }
        }
    }
}

/// Shows the selected tab's page, or the start page for a fresh tab.
struct PageArea: View {
    @ObservedObject var model: BrowserModel

    var body: some View {
        if let tab = model.selectedTab {
            if let pair = model.splitPair, pair.contains(tab.id),
               let left = model.tabs.first(where: { $0.id == pair.left }), let right = model.tabs.first(where: { $0.id == pair.right }) {
                SplitPages(model: model, left: left, right: right)
            } else {
                TabPage(model: model, tab: tab).id(tab.id)
            }
        } else {
            Color.clear
        }
    }
}

/// One tab's page (used by Split View for each side).
struct TabPageContent: View {
    @ObservedObject var model: BrowserModel
    @ObservedObject var tab: BrowserTab
    var body: some View { TabPage(model: model, tab: tab) }
}

private struct TabPage: View {
    @ObservedObject var model: BrowserModel
    @ObservedObject var tab: BrowserTab

    var body: some View {
        ZStack {
            // A blank tab shows only the start page, so its translucent backdrop
            // isn't drawn over an empty white web view.
            if tab.isBlank {
                if model.isPrivate { PrivateStartPage() } else { StartPage(model: model) }
            } else if tab.isAsleep, let snapshot = tab.snapshot {
                Image(nsImage: snapshot).resizable().aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top).clipped()
            } else {
                // A woken tab has a new web view, so key the host on it.
                WebViewHost(webView: tab.webView).id(ObjectIdentifier(tab.webView))
            }
            if tab.crashed {
                CrashedPage { tab.recoverFromCrash() }
                    .transition(.opacity)
            }
            if let article = tab.reader {
                ReaderView(article: article) { tab.toggleReader() }
                    .transition(.opacity)
            }
            if let block = tab.lookalike {
                LookalikeWarning(match: block.match) {
                    tab.load(URL(string: "https://\(block.match.real)")!)
                } onContinue: {
                    Lookalike.allow(Domains.site(block.url.host ?? ""))
                    tab.load(block.url)
                }
                .transition(.opacity)
            }
        }
    }
}

struct WebViewHost: NSViewRepresentable {
    let webView: WKWebView
    func makeNSView(context: Context) -> WKWebView { webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}

private struct NavButtons: View {
    @ObservedObject var tab: BrowserTab

    var body: some View {
        HStack(spacing: 2) {
            ToolbarIconButton(symbol: "chevron.left", help: "Back (⌘[)") { tab.webView.goBack() }
                .disabled(!tab.canGoBack)
            ToolbarIconButton(symbol: "chevron.right", help: "Forward (⌘])") { tab.webView.goForward() }
                .disabled(!tab.canGoForward)
            ToolbarIconButton(symbol: tab.isLoading ? "xmark" : "arrow.clockwise",
                              help: tab.isLoading ? "Stop" : "Reload (⌘R)") { tab.reload() }
                .disabled(tab.isBlank)
        }
    }
}

struct ToolbarIconButton: View {
    let symbol: String
    let help: String
    var tint: Color? = nil
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(tint ?? Color.primary.opacity(isEnabled ? 0.75 : 0.25))
                .frame(width: 28, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.primary.opacity(hovering && isEnabled ? 0.08 : 0))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

/// Hush Guard in the toolbar: how much was blocked on this page, and per-site on/off.
private struct ShieldsButton: View {
    @ObservedObject var tab: BrowserTab
    @ObservedObject private var blocker = ContentBlocker.shared
    @AppStorage(Prefs.adBlockEnabled) private var adsOn = true
    @AppStorage(Prefs.trackerBlockEnabled) private var trackersOn = true
    @State private var showing = false

    @AppStorage(Prefs.blockingMode) private var blockingMode = BlockingMode.standard.rawValue

    private var shieldsUp: Bool {
        guard blockingMode != BlockingMode.off.rawValue, adsOn || trackersOn else { return false }
        guard let host = tab.host else { return true }
        return !blocker.isShieldsDown(host)
    }

    @State private var hovering = false
    @State private var pulse = false
    @State private var lastPulse = Date.distantPast
    @AppStorage(Prefs.reduceMotion) private var reduceMotion = false

    var body: some View {
        Button { showing.toggle() } label: {
            HushMark(color: shieldsUp ? .accentColor : Color.primary.opacity(0.5), showStars: false, outlined: !shieldsUp)
                .frame(width: 17, height: 17)
                .scaleEffect(pulse ? 1.18 : 1)
                .frame(width: 28, height: 26)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.primary.opacity(hovering ? 0.08 : 0)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(shieldsUp ? "Hush Guard is on" : "Hush Guard is off for this site")
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        // A tiny "hush" pulse when something is blocked (at most once a second).
        .onChange(of: tab.blockedOnPage) { count in
            guard count > 0, !reduceMotion, Date().timeIntervalSince(lastPulse) > 1 else { return }
            lastPulse = Date()
            withAnimation(.spring(response: 0.18, dampingFraction: 0.5)) { pulse = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { pulse = false }
            }
        }
        .overlay(alignment: .topTrailing) {
            if tab.blockedOnPage > 0 && shieldsUp {
                Text(tab.blockedOnPage > 99 ? "99+" : "\(tab.blockedOnPage)")
                    .font(.system(size: 8.5, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 3.5)
                    .frame(minWidth: 13, minHeight: 13)
                    .background(Capsule().fill(Color.accentColor))
                    .offset(x: 3, y: -1)
                    .allowsHitTesting(false)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: tab.blockedOnPage > 0)
        .popover(isPresented: $showing, arrowEdge: .bottom) {
            ShieldsPanel(tab: tab, shieldsUp: shieldsUp)
        }
    }
}

struct ShieldsPanel: View {
    @ObservedObject var tab: BrowserTab
    let shieldsUp: Bool
    @ObservedObject private var stats = BlockStats.shared
    @AppStorage(Prefs.blockingMode) private var mode = BlockingMode.standard.rawValue
    @ObservedObject private var siteShields = ShieldSettings.shared

    private var blockingMode: BlockingMode { BlockingMode(rawValue: mode) ?? .standard }
    private var shields: Shields { siteShields.effective(for: tab.host) }

    var body: some View {
        VStack(spacing: 0) {
            // The animated moon and stars, with this page's count beneath.
            GuardIllustration(on: shieldsUp, blocked: tab.blockedOnPage)
                .frame(height: 150)
            VStack(spacing: 1) {
                Text("\(tab.blockedOnPage)")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransitionIfAvailable()
                Text(shieldsUp ? (tab.blockedOnPage == 1 ? "thing hushed on this page" : "things hushed on this page")
                               : "Hush Guard is off for this site")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .padding(.top, -6)
            .padding(.bottom, 14)

            VStack(spacing: 10) {
                siteCard
                if shieldsUp {
                    HStack(spacing: 8) {
                        GuardStat(symbol: "rectangle.slash", label: "Ads", value: "\(tab.adsOnPage)", tint: Color(red: 0.95, green: 0.45, blue: 0.40))
                        GuardStat(symbol: "eye.slash.fill", label: "Trackers", value: "\(tab.trackersOnPage)", tint: Color(red: 0.36, green: 0.62, blue: 1.0))
                        GuardStat(symbol: "touchid", label: "Fingerprint",
                                  value: shields.fingerprinting == .off ? "Off" : (shields.fingerprinting == .strict ? "Strict" : "Masked"),
                                  tint: Color(red: 0.62, green: 0.48, blue: 1.0))
                    }
                }
                if shieldsUp, tab.host != nil { siteSettings }
                if tab.url != nil { tabActions }
            }
            .padding(.horizontal, 14)

            HStack {
                Text("\(stats.total.formatted()) hushed in total")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Settings…") { SettingsOpener.open(tab: .adBlocker) }
                    .buttonStyle(.link)
                    .font(.system(size: 11))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .frame(width: 340)
        // A solid backdrop so the panel stays readable over bright (white) pages.
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.97))
        .animation(.easeOut(duration: 0.2), value: shieldsUp)
    }

    /// This site, its status, and the on/off switch.
    private var siteCard: some View {
        HStack(spacing: 10) {
            Group {
                if tab.url == nil { HushLogoTile(size: 26) } else { Favicon(url: tab.url, size: 22) }
            }
            .frame(width: 28, height: 28)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.primary.opacity(0.05)))
            VStack(alignment: .leading, spacing: 3) {
                Text(tab.host?.strippingWWW ?? "New Tab")
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Circle().fill(shieldsUp ? Color.green : Color.orange).frame(width: 6, height: 6)
                    Text(shieldsUp ? "Protected" : (blockingMode == .off ? "Blocking is off everywhere" : "Off for this site"))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let host = tab.host, blockingMode != .off {
                Toggle("", isOn: Binding(
                    get: { !ContentBlocker.shared.isShieldsDown(host) },
                    set: { up in
                        ContentBlocker.shared.setShields(up, for: host)
                        tab.webView.reload()
                    }))
                .toggleStyle(.switch)
                .labelsHidden()
                .help("Turn Hush Guard off if this site doesn’t work properly")
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.045)))
    }

    /// This site's own settings: anything left on Default follows Settings › Hush Guard.
    private var siteSettings: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("THIS SITE").font(.system(size: 10, weight: .semibold)).tracking(0.8).foregroundStyle(.secondary)
                Spacer()
                if let host = tab.host, !siteShields.overrides(for: host).isEmpty {
                    Button("Use Defaults") { siteShields.reset(host); tab.webView.reload() }
                        .buttonStyle(.link).font(.system(size: 10.5))
                }
            }
            VStack(spacing: 0) {
                SiteSettingRow(symbol: "shield.lefthalf.filled", title: "Ads & trackers", tab: tab, keyPath: \.blocking,
                               options: BlockingMode.allCases.map { ($0.rawValue, $0.label) },
                               current: shields.blocking.label, defaultLabel: ShieldSettings.defaults.blocking.label)
                Divider().padding(.leading, 34)
                SiteSettingRow(symbol: "curlybraces", title: "Scripts", tab: tab, keyPath: \.scripts,
                               options: ScriptPolicy.allCases.map { ($0.rawValue, $0.label) },
                               current: shields.scripts.label, defaultLabel: ShieldSettings.defaults.scripts.label)
                Divider().padding(.leading, 34)
                SiteSettingRow(symbol: "touchid", title: "Fingerprinting", tab: tab, keyPath: \.fingerprinting,
                               options: FingerprintLevel.allCases.map { ($0.rawValue, $0.label) },
                               current: shields.fingerprinting.label, defaultLabel: ShieldSettings.defaults.fingerprinting.label)
                Divider().padding(.leading, 34)
                SiteSettingRow(symbol: "birthday.cake", title: "Cookies", tab: tab, keyPath: \.cookies,
                               options: CookiePolicy.allCases.map { ($0.rawValue, $0.label) },
                               current: shields.cookies.label, defaultLabel: ShieldSettings.defaults.cookies.label)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.045)))
        }
    }

    /// Quick actions for this tab.
    private var tabActions: some View {
        HStack(spacing: 6) {
            GuardAction(symbol: tab.javaScriptOff ? "curlybraces.square.fill" : "curlybraces.square",
                        label: tab.javaScriptOff ? "JS Off" : "JavaScript", active: tab.javaScriptOff) { tab.toggleJavaScript() }
                .help(tab.javaScriptOff ? "Turn JavaScript back on in this tab" : "Turn JavaScript off in this tab")
            GuardAction(symbol: "eye.slash", label: "Hide…", active: false) { ElementZapper.shared.start(in: tab) }
                .help("Click things on the page to hide them for good")
            GuardAction(symbol: "eraser", label: "Forget", active: false) { SiteForgetter.confirmAndForget(tab) }
                .help("Forget This Site: delete its cookies, data and history")
        }
    }
}

/// One of a site's settings in the Hush Guard panel: Default, or one of the choices.
private struct SiteSettingRow: View {
    let symbol: String
    let title: String
    @ObservedObject var tab: BrowserTab
    let keyPath: WritableKeyPath<SiteOverrides, String?>
    let options: [(String, String)]
    let current: String
    let defaultLabel: String
    @ObservedObject private var siteShields = ShieldSettings.shared

    var body: some View {
        let host = tab.host ?? ""
        let chosen = siteShields.overrides(for: host)[keyPath: keyPath]
        HStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(Color.accentColor).frame(width: 22)
            Text(title).font(.system(size: 12.5))
            Spacer()
            Menu {
                Button { set(nil) } label: {
                    if chosen == nil { Label("Default (\(defaultLabel))", systemImage: "checkmark") } else { Text("Default (\(defaultLabel))") }
                }
                Divider()
                ForEach(options, id: \.0) { value, label in
                    Button { set(value) } label: {
                        if chosen == value { Label(label, systemImage: "checkmark") } else { Text(label) }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    if chosen != nil { Circle().fill(Color.accentColor).frame(width: 5, height: 5) }
                    Text(current).font(.system(size: 12, weight: chosen != nil ? .semibold : .regular))
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help(chosen == nil ? "Following your default" : "Changed for this site")
        }
        .frame(height: 32)
    }

    private func set(_ value: String?) {
        guard let host = tab.host else { return }
        siteShields.update(host) { $0[keyPath: keyPath] = value }
        tab.webView.reload()
    }
}

private struct GuardStat: View {
    let symbol: String
    let label: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: symbol).font(.system(size: 12, weight: .semibold)).foregroundStyle(tint)
            Text(value).font(.system(size: 15, weight: .bold, design: .rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
            Text(label).font(.system(size: 10)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(tint.opacity(0.10)))
    }
}

private struct GuardAction: View {
    let symbol: String
    let label: String
    let active: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: symbol).font(.system(size: 13, weight: .medium))
                Text(label).font(.system(size: 10.5))
            }
            .foregroundStyle(active ? Color.accentColor : Color.primary.opacity(0.8))
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(hovering ? 0.08 : 0.045)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

private extension View {
    /// Rolling-number animation.
    func contentTransitionIfAvailable() -> some View {
        contentTransition(.numericText())
    }
}

/// The Hush Guard illustration: no background at all, just a lit, cut-out Hush moon with
/// stars drifting past and tracker beads vanishing into its curve. When Hush Guard is off
/// it turns silver-grey and the trackers roam free.
struct GuardIllustration: View {
    let on: Bool
    let blocked: Int
    @AppStorage(Prefs.reduceMotion) private var reduceMotion = false

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { context in
            let t = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
            GeometryReader { geo in
                GuardScene(on: on, blocked: blocked, t: t, size: geo.size)
            }
        }
        .animation(.easeInOut(duration: 0.5), value: on)
    }
}

private struct GuardScene: View {
    let on: Bool
    let blocked: Int
    let t: Double
    let size: CGSize

    var body: some View {
        let moonSize = size.height * 0.62
        let center = CGPoint(x: size.width * 0.5, y: size.height * 0.52)
        ZStack {
            GuardStars(on: on, t: t, size: size)
            GuardBeads(on: on, blocked: blocked, t: t, center: center, moonSize: moonSize)
            HushMoon(colors: on
                     ? [Color(red: 0.80, green: 0.72, blue: 1.0), Color(red: 0.40, green: 0.28, blue: 0.85)]
                     : [Color(white: 0.88), Color(white: 0.52)])
                .frame(width: moonSize, height: moonSize)
                .shadow(color: (on ? Color(red: 0.25, green: 0.15, blue: 0.65) : .black).opacity(0.35), radius: 12, y: 7)
                .position(center)
        }
    }
}

/// Stars that slowly drift across and twinkle.
struct GuardStars: View {
    let on: Bool
    let t: Double
    let size: CGSize
    private let seeds: [(x: Double, y: Double, r: Double, speed: Double)] = (0..<14).map { i in
        let d = Double(i)
        return (x: (d * 0.137).truncatingRemainder(dividingBy: 1), y: (d * 0.311 + 0.07).truncatingRemainder(dividingBy: 1),
                r: 0.8 + (d * 0.53).truncatingRemainder(dividingBy: 1.4), speed: 0.006 + (d * 0.0017).truncatingRemainder(dividingBy: 0.01))
    }

    var body: some View {
        ZStack {
            ForEach(0..<seeds.count, id: \.self) { i in
                star(i)
            }
        }
    }

    private func star(_ i: Int) -> some View {
        let seed = seeds[i]
        let x = (seed.x + t * seed.speed).truncatingRemainder(dividingBy: 1)
        let twinkle = 0.4 + 0.6 * (sin(t * (0.9 + Double(i) * 0.19) + Double(i)) + 1) / 2
        // Stars fade near the edges so they melt into the panel too.
        let edge = min(x, 1 - x, seed.y, 1 - seed.y) * 4
        return Circle()
            .fill(on ? Color(red: 0.62, green: 0.52, blue: 1.0) : Color.secondary)
            .frame(width: seed.r * 2, height: seed.r * 2)
            .opacity(twinkle * min(1, edge) * (on ? 0.95 : 0.5))
            .position(x: CGFloat(x) * size.width, y: CGFloat(seed.y) * size.height)
    }
}

/// Tracker beads drifting into the moon's curve and fading (on), or roaming free (off).
private struct GuardBeads: View {
    let on: Bool
    let blocked: Int
    let t: Double
    let center: CGPoint
    let moonSize: CGFloat

    var body: some View {
        ZStack {
            ForEach(0..<count, id: \.self) { i in
                bead(i)
            }
        }
    }

    private var count: Int { on ? min(max(blocked, 1), 6) : 4 }

    private func bead(_ i: Int) -> some View {
        let index = Double(i)
        let period: Double = on ? 3.4 : 10
        let phase = (t / period + index / 6).truncatingRemainder(dividingBy: 1)
        let angle = index * 1.1 - 0.4 + (on ? 0 : t * 0.22)
        let reach: Double = on ? (1 - phase) : 0.85 + 0.12 * sin(t * 0.7 + index)
        let target = CGPoint(x: center.x + moonSize * 0.18, y: center.y - moonSize * 0.14)
        let x = target.x + CGFloat(cos(angle) * reach) * moonSize * 0.95
        let y = target.y + CGFloat(sin(angle) * reach) * moonSize * 0.62
        let diameter: CGFloat = on ? 9 - CGFloat(phase) * 3 : 9
        let opacity: Double = on ? min(1, (1 - phase) * 2.2) : 0.95
        return TrackerBead(color: on ? Color(red: 0.72, green: 0.64, blue: 1.0) : Color(red: 1.0, green: 0.55, blue: 0.40),
                           size: diameter)
            .opacity(opacity)
            .position(x: x, y: y)
    }
}

/// A small glossy sphere.
private struct TrackerBead: View {
    let color: Color
    let size: CGFloat

    var body: some View {
        Circle()
            .fill(RadialGradient(colors: [.white.opacity(0.95), color, color.opacity(0.8)],
                                 center: .init(x: 0.35, y: 0.3), startRadius: 0, endRadius: size * 0.7))
            .frame(width: size, height: size)
            .shadow(color: color.opacity(0.5), radius: 3)
    }
}

/// Thin loading bar along the top of the page.
private struct ProgressLine: View {
    @ObservedObject var tab: BrowserTab

    var body: some View {
        GeometryReader { geo in
            Rectangle()
                .fill(LinearGradient(colors: [.accentColor.opacity(0.6), .accentColor],
                                     startPoint: .leading, endPoint: .trailing))
                .frame(width: geo.size.width * max(0.05, tab.progress), height: 2)
                .opacity(tab.isLoading ? 1 : 0)
                .animation(.easeOut(duration: 0.25), value: tab.progress)
                .animation(.easeOut(duration: 0.4), value: tab.isLoading)
        }
        .frame(height: 2)
        .allowsHitTesting(false)
    }
}

struct Hairline: View {
    var body: some View {
        Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1)
    }
}

struct VisualEffect: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blending: NSVisualEffectView.BlendingMode = .withinWindow
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blending
        view.state = .followsWindowActiveState
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
    }
}

/// Hands the view's NSWindow to SwiftUI code once it's on screen.
/// Shown when a page's process crashed, instead of a blank tab.
private struct CrashedPage: View {
    let onReload: () -> Void

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            VStack(spacing: 14) {
                ZStack {
                    Circle().fill(Color.primary.opacity(0.05)).frame(width: 110, height: 110)
                    HushMark(color: Color.secondary.opacity(0.7), showStars: false, outlined: true)
                        .frame(width: 58, height: 58)
                }
                Text("This page stopped working")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                Text("Something on the page made it crash. The rest of Hush is fine, and your other tabs weren’t affected.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
                Button(action: onReload) {
                    Label("Reload Page", systemImage: "arrow.clockwise")
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .padding(.top, 4)
            }
            .padding(40)
        }
    }
}

/// Shows the Find bar for the window's selected tab.
private struct FindBarHost: View {
    @ObservedObject var model: BrowserModel
    @ObservedObject private var find: FindModel

    init(model: BrowserModel) {
        self.model = model
        find = model.find
    }

    var body: some View {
        if find.isVisible {
            VStack(spacing: 0) {
                Hairline()
                FindBar(find: find, webView: model.selectedTab?.webView)
            }
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}

private struct AddressFrameKey: PreferenceKey {
    static let defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next != .zero { value = next }
    }
}

struct WindowReader: NSViewRepresentable {
    let onWindow: (NSWindow?) -> Void
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { onWindow(view.window) }
        return view
    }
    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async { onWindow(view.window) }
    }
}

/// A card floating over a dimmed window, scaled down if the window is too small for it.
struct LaunchCardOverlay<Card: View>: View {
    @ViewBuilder let card: Card
    @State private var size: CGSize = .zero
    @State private var appeared = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Rectangle()
                    .fill(Color.black.opacity(0.3))
                    .contentShape(Rectangle())
                    .onTapGesture {} // clicks outside the card do nothing
                card
                    .background(
                        GeometryReader { inner in
                            Color.clear.onAppear { size = inner.size }
                        }
                    )
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(.regularMaterial)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.08))
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .shadow(color: .black.opacity(0.35), radius: 40, y: 18)
                    .scaleEffect(scale(in: geo.size) * (appeared ? 1 : 0.96))
                    .opacity(appeared ? 1 : 0)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .onAppear {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) { appeared = true }
        }
    }

    private func scale(in space: CGSize) -> CGFloat {
        guard size.width > 0, size.height > 0 else { return 1 }
        return min(1, (space.width - 40) / size.width, (space.height - 40) / size.height)
    }
}

/// Shows content for the window's selected tab, and re-renders whenever the selection changes.
struct SelectedTab<Content: View>: View {
    @ObservedObject var model: BrowserModel
    @ViewBuilder let content: (BrowserTab) -> Content

    var body: some View {
        if let tab = model.selectedTab { content(tab) }
    }
}

/// Shown instead of a page that looks like a fake copy of a site you use.
struct LookalikeWarning: View {
    let match: Lookalike.Match
    let onGoToReal: () -> Void
    let onContinue: () -> Void

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.55, green: 0.10, blue: 0.12), Color(red: 0.32, green: 0.05, blue: 0.08)],
                           startPoint: .top, endPoint: .bottom)
            VStack(spacing: 22) {
                Image(systemName: "exclamationmark.shield.fill")
                    .font(.system(size: 64, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.white)
                VStack(spacing: 10) {
                    Text("This might be a fake website")
                        .font(.system(size: 28, weight: .bold))
                    Text("“\(match.visited)” looks very like “\(match.real)”, a site you use. Fake look-alike sites are made to steal passwords and card details.")
                        .font(.system(size: 15))
                        .multilineTextAlignment(.center)
                        .opacity(0.9)
                        .frame(maxWidth: 520)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button(action: onGoToReal) {
                    Text("Go to \(match.real)")
                        .font(.system(size: 14, weight: .semibold))
                        .padding(.horizontal, 22)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(Color.white))
                        .foregroundStyle(Color(red: 0.55, green: 0.10, blue: 0.12))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
                Button("I understand the risk — continue to \(match.visited)", action: onContinue)
                    .buttonStyle(.link)
                    .foregroundStyle(.white.opacity(0.75))
                    .font(.system(size: 12))
            }
            .foregroundStyle(.white)
            .padding(40)
        }
    }
}
