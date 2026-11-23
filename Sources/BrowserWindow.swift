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


    @AppStorage(Prefs.tabLayout) private var tabLayout = TabLayout.top.rawValue
    private var sideTabs: Bool { tabLayout == TabLayout.side.rawValue }

    var body: some View {
        Group {
            if sideTabs { sideLayout } else { topLayout }
        }
        .ignoresSafeArea(.container, edges: .top)
        .background(VisualEffect(material: .titlebar, blending: .behindWindow).ignoresSafeArea())
        .coordinateSpace(name: "window")
        // Address suggestions float over everything, lined up under the address bar wherever it is.
        .overlay(alignment: .topLeading) {
            if suggestions.isVisible {
                SuggestionList(suggestions: suggestions) { choice in go(choice.text) }
                    .frame(width: min(max(380, addressFrame.width), 680))
                    .offset(x: addressFrame.minX, y: addressFrame.maxY + 6)
                    .transition(.opacity.combined(with: .offset(y: -4)))
            }
        }
        .animation(.easeOut(duration: 0.12), value: suggestions.isVisible)
        .onPreferenceChange(AddressFrameKey.self) { addressFrame = $0 }
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
            if (note.object as? NSWindow) === model.window {
                TrafficLights.align(in: model.window)
                model.ensureTab()
            }
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
                SetupGuide {
                    showWelcome = false
                    model.focusAddressBar()
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
        .overlay { CommandPaletteOverlay(model: model) }
        .hushDialogs(model.dialogs)
        // Settings › General › Run Setup Guide Again.
        .onReceive(NotificationCenter.default.publisher(for: SetupGuide.showAgain)) { _ in
            guard !model.isPrivate, model.window?.isVisible == true, BrowserModel.frontmostNormal === model else { return }
            model.window?.makeKeyAndOrderFront(nil)
            showWelcome = true
        }
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
        .environment(\.isPrivateWindow, model.isPrivate)
        .focusedSceneObject(model)
        .navigationTitle(model.selectedTab?.displayTitle ?? "Hush")
        .frame(minWidth: 640, minHeight: 420)
    }

    /// Tabs along the top: the tab row in the title bar, the toolbar, then the page.
    private var topLayout: some View {
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
            SidebarSlot(model: model)
            // The page: a rounded card set into the frosted window.
            ZStack(alignment: .topLeading) {
                PageArea(model: model)
                if let tab = model.selectedTab {
                    ProgressLine(tab: tab)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
            .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
            }
            .padding([.horizontal, .bottom], 6)
            .padding(.top, 6)
        }
    }

    /// Tabs down the side: a frosted column with the window buttons, address bar, Spaces and
    /// tabs; the page sits beside it as a rounded card.
    private var sideLayout: some View {
        HStack(spacing: 0) {
            SideTabBar(model: model, suggestions: suggestions, onGo: go)
                .background(tint?.frame ?? .clear)
                .environment(\.colorScheme, tint?.scheme ?? systemScheme)
            VStack(spacing: 0) {
                if showBookmarkBar {
                    BookmarkBar(model: model)
                        .frame(height: 34)
                }
                if showDefaultBanner {
                    DefaultBrowserBanner {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) { showDefaultBanner = false }
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
                FindBarHost(model: model)
                TranslationHost()
                SelectedTab(model: model) { tab in WebStoreBar(tab: tab) }
                SelectedTab(model: model) { tab in BookmarkOfferBar(tab: tab) }
                HStack(spacing: 0) {
                    SidebarSlot(model: model)
                    ZStack(alignment: .topLeading) {
                        PageArea(model: model)
                        if let tab = model.selectedTab { ProgressLine(tab: tab) }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
                    .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
                }
                .padding(.top, showBookmarkBar ? 0 : 8)
                .padding(.trailing, 8)
                .padding(.bottom, 8)
            }
            .padding(.top, showBookmarkBar ? 4 : 0)
        }
        .background(SelectedTab(model: model) { tab in
            SiteColorReader(tab: tab) { color in if color != siteColor { siteColor = color } }
                .id(tab.id)
        })
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
                MoreMenuButton(model: model)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 40)
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

/// "⋯" at the end of the toolbar: the everyday commands, one click away.
struct MoreMenuButton: View {
    @ObservedObject var model: BrowserModel
    @Environment(\.openWindow) private var openWindow
    @AppStorage(Prefs.tabLayout) private var tabLayout = TabLayout.top.rawValue
    @AppStorage(Prefs.showBookmarkBar) private var showBookmarkBar = true
    @State private var hovering = false

    var body: some View {
        Menu {
            Button { model.newTab(focus: true) } label: { Label("New Tab", systemImage: "plus.square") }
            Button { openWindow(id: "private") } label: { Label("New Private Window", systemImage: "eyeglasses") }
            Button { model.paletteOpen = true } label: { Label("Command Palette…", systemImage: "command") }
            Divider()
            Button { model.find.show() } label: { Label("Find on Page…", systemImage: "text.magnifyingglass") }
            Button { model.selectedTab?.zoom(by: 0.1) } label: { Label("Zoom In", systemImage: "plus.magnifyingglass") }
            Button { model.selectedTab?.zoom(by: -0.1) } label: { Label("Zoom Out", systemImage: "minus.magnifyingglass") }
            Button { model.selectedTab?.printPage() } label: { Label("Print…", systemImage: "printer") }
            Divider()
            Button { model.sidebarOpen.toggle() } label: { Label("Bookmarks & History", systemImage: "sidebar.left") }
            Button { openWindow(id: "history") } label: { Label("Show All History", systemImage: "clock") }
            Toggle(isOn: $showBookmarkBar) { Label("Show Bookmarks Bar", systemImage: "menubar.rectangle") }
            Toggle(isOn: Binding(get: { tabLayout == TabLayout.side.rawValue },
                                 set: { tabLayout = ($0 ? TabLayout.side : TabLayout.top).rawValue })) {
                Label("Tabs Down the Side", systemImage: "sidebar.squares.left")
            }
            Divider()
            Button { SettingsOpener.open() } label: { Label("Settings…", systemImage: "gearshape") }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 26)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.primary.opacity(hovering ? 0.08 : 0)))
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .onHover { hovering = $0 }
        .help("More")
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

struct NavButtons: View {
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
struct ShieldsButton: View {
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
        .onChange(of: tab.blockedOnPage) { _, count in
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
    @State private var showBlocked = false

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
                if shieldsUp, !tab.blockedSites.isEmpty { blockedList }
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

    /// "What was blocked": the companies behind this page's blocked ads and trackers.
    private var blockedList: some View {
        let groups = TrackerCompanies.groups(tab.blockedSites)
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.88)) { showBlocked.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "building.2.fill").font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.accentColor).frame(width: 22)
                    Text("What was blocked").font(.system(size: 12.5))
                    Spacer()
                    Text(groups.count == 1 ? "1 company" : "\(groups.count) companies").font(.system(size: 11.5)).foregroundStyle(.secondary)
                    Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(showBlocked ? 90 : 0))
                }
                .frame(height: 32)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if showBlocked {
                VStack(spacing: 6) {
                    ForEach(groups.prefix(10)) { group in
                        HStack(alignment: .top, spacing: 9) {
                            Favicon(url: URL(string: "https://\(group.sites.first ?? "")"), size: 15)
                                .frame(width: 22, height: 18)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(group.company).font(.system(size: 12, weight: .medium)).lineLimit(1)
                                if group.company != group.sites.first || group.sites.count > 1 {
                                    Text(group.sites.prefix(3).joined(separator: ", ") + (group.sites.count > 3 ? " +\(group.sites.count - 3)" : ""))
                                        .font(.system(size: 10.5)).foregroundStyle(.secondary).lineLimit(1)
                                }
                            }
                            Spacer(minLength: 6)
                            Text("\(group.count)").font(.system(size: 11.5, weight: .semibold, design: .rounded)).monospacedDigit()
                                .padding(.horizontal, 7).padding(.vertical, 2)
                                .background(Capsule().fill(Color.primary.opacity(0.07)))
                        }
                    }
                    if groups.count > 10 {
                        Text("and \(groups.count - 10) more").font(.system(size: 11)).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 31)
                    }
                }
                .padding(.bottom, 10)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.045)))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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
            Image(systemName: symbol).font(.system(size: 11, weight: .semibold)).foregroundStyle(tint)
                .frame(width: 22, height: 22)
                .background(Circle().fill(tint.opacity(0.16)))
            Text(value).font(.system(size: 15, weight: .bold, design: .rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                .contentTransitionIfAvailable()
            Text(label).font(.system(size: 10)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(tint.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(tint.opacity(0.14)))
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
struct ProgressLine: View {
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
/// The sidebar is built once (shortly after launch) and kept, so opening it is instant. Only
/// the sidebar itself slides; the page takes its new width in a single step rather than being
/// re-laid out on every frame of the animation.
private struct SidebarSlot: View {
    @ObservedObject var model: BrowserModel
    @State private var built = false
    @State private var slotOpen = false
    @State private var slidIn = false
    private let width: CGFloat = 281

    var body: some View {
        Group {
            if built {
                HStack(spacing: 0) {
                    // While hidden, the sidebar draws nothing costly (no frosted glass), so it
                    // doesn't slow scrolling.
                    LibrarySidebar(model: model, active: slotOpen)
                    Divider()
                }
                .frame(width: width)
                .offset(x: slidIn ? 0 : -width)
                .animation(.spring(response: 0.3, dampingFraction: 0.9), value: slidIn)   // only the slide animates
                .frame(width: slotOpen ? width : 0, alignment: .leading)
                .clipped()
                .allowsHitTesting(slotOpen)
                .accessibilityHidden(!slotOpen)
            }
        }
        .onAppear {
            if model.sidebarOpen { open() } else {
                // Build it quietly while nothing else is happening.
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { built = true }
            }
        }
        .onChange(of: model.sidebarOpen) { _, isOpen in isOpen ? open() : close() }
    }

    private func open() {
        built = true
        slotOpen = true                          // the page makes room in one step
        DispatchQueue.main.async { slidIn = true }   // then the sidebar glides in
    }

    private func close() {
        slidIn = false                           // the sidebar glides out first
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
            if !model.sidebarOpen { slotOpen = false }   // then the page takes the space back
        }
    }
}

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

struct AddressFrameKey: PreferenceKey {
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
                    .ignoresSafeArea()   // dim the tab row too, so it matches the toolbar below
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
