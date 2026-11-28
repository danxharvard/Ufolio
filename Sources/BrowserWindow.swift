import SwiftUI
import WebKit

/// The whole window: toolbar, tab strip, bookmarks bar and page.
struct BrowserWindow: View {
    @StateObject private var model: BrowserModel

    init(isPrivate: Bool = false) {
        _model = StateObject(wrappedValue: BrowserModel(isPrivate: isPrivate))
    }

    /// Held without being watched here: every keystroke changes the suggestions, and watching them
    /// in the window redrew the whole window per letter typed. SuggestionOverlay watches them.
    @State private var suggestions = SuggestionsModel()
    @Environment(\.colorScheme) private var systemScheme
    @AppStorage(Prefs.showBookmarkBar) private var showBookmarkBar = true
    @State private var isFullScreen = false
    private var tint: Chrome.Tint? { model.isPrivate ? PrivateChrome.tint : nil }
    /// Where the address bar is, so its suggestions line up underneath it.
    @State private var addressFrame: CGRect = .zero
    @State private var showWelcome = false
    @State private var showDefaultBanner = false
    @State private var whatsNew: ReleaseNotes.Version?


    @AppStorage(Prefs.tabLayout) private var tabLayout = TabLayout.top.rawValue
    @AppStorage(Prefs.theme) private var theme = "classic"
    /// Compact mode, and whether its hidden tabs/toolbar (top) or tab column (side) are showing.
    @AppStorage(Prefs.compactMode) private var compact = false
    @State private var revealTop = false
    @State private var revealSide = false
    @State private var leaderEgg = false
    private var sideTabs: Bool { tabLayout == TabLayout.side.rawValue }

    /// The window's frosted glass; the Area 51 theme tints it (and so the tab column) green.
    private var windowGlass: some View {
        ZStack {
            if model.isPrivate {
                // Stealth: the whole window is one dark frosted glass with a single purple tint.
                // The window itself is dark (set below), so the glass follows it natively: forcing
                // dark glass onto a light window made every hover redraw cost the Mac far more.
                VisualEffect(material: .titlebar, blending: .behindWindow)
                PrivateChrome.glassTint
            } else {
                VisualEffect(material: .titlebar, blending: .behindWindow)
                if AlienTheme.isActive(theme) { AlienTheme.glass }
            }
        }
        .ignoresSafeArea()
    }

    /// The easter egg. (Stealth's edge shimmer and the Orbit-switch starfield are gone: animated
    /// pictures cost the Mac work for no use.)
    private var funOverlays: some View {
        ZStack {
            if leaderEgg { LeaderEasterEgg { leaderEgg = false } }
        }
        .allowsHitTesting(false)
    }

    var body: some View {
        Group {
            if sideTabs { sideLayout } else { topLayout }
        }
        .ignoresSafeArea(.container, edges: .top)
        .background(windowGlass)
        .coordinateSpace(name: "window")
        // Address suggestions float over everything, lined up under the address bar wherever it is.
        .overlay(alignment: .topLeading) {
            SuggestionOverlay(suggestions: suggestions, anchor: addressFrame) { choice in go(choice.text) }
        }
        .onPreferenceChange(AddressFrameKey.self) { addressFrame = $0 }
        .background(WindowReader { window in
            // Remember the window's size and position between launches.
            if let window, model.window !== window, !model.isPrivate {
                window.setFrameUsingName("HushBrowserWindow")
                window.setFrameAutosaveName("HushBrowserWindow")
                WindowPlacement.keepOnScreen(window)
            }
            model.window = window
            // Stealth windows are dark through and through: the window's own appearance, so the
            // frosted glass, menus and scroll bars are drawn dark by macOS itself.
            if model.isPrivate, let window, window.appearance?.name != .darkAqua { window.appearance = NSAppearance(named: .darkAqua) }
            if window != nil { ExtensionEvents.windowOpened(model) }
            if compact, !(revealTop || revealSide) { CompactMode.showWindowButtons(false, in: window) }
            TrafficLights.align(in: window)
        })
        .onChange(of: tabLayout) { _, _ in
            DispatchQueue.main.async { TrafficLights.align(in: model.window) }
        }
        // Compact mode: ⌘L brings the address bar back; the window buttons show with the tabs.
        .onChange(of: model.addressFocusToken) { _, _ in
            guard compact else { return }
            if sideTabs { revealSide = true } else { revealTop = true }
        }
        .onChange(of: compact) { _, on in
            revealTop = false; revealSide = false
            CompactMode.showWindowButtons(!on, in: model.window)
            DispatchQueue.main.async { TrafficLights.align(in: model.window) }
        }
        .onChange(of: revealTop || revealSide) { _, showing in
            guard compact else { return }
            CompactMode.showWindowButtons(showing, in: model.window)
            DispatchQueue.main.async { TrafficLights.align(in: model.window) }
        }
        // Switching light/dark makes macOS lay out the title bar again, which can put the window
        // buttons back in their default spot, out of line with the tabs.
        .onChange(of: systemScheme) { _, _ in
            DispatchQueue.main.async { TrafficLights.align(in: model.window) }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResizeNotification)) { note in
            if (note.object as? NSWindow) === model.window { TrafficLights.align(in: model.window) }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { note in
            if (note.object as? NSWindow) === model.window {
                model.windowClosed = true
                ExtensionEvents.windowClosed(model)
                // Questions still waiting (a site asking for the camera, say) are answered "no" as the
                // window goes: nothing would ever answer them, and the page was left waiting.
                model.dialogs.cancelAll()
                // A link preview or docked site doesn't outlive its window.
                model.closePreview()
                model.releaseDocks()
            }
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
            UpdateGateOverlay()   // over everything: a version too old to keep using
        }
        .animation(.smooth(duration: 0.26), value: showWelcome)
        .animation(.smooth(duration: 0.26), value: whatsNew?.version)
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
        .overlay(funOverlays)
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
            suggestions.browser = model   // so it suggests from this window's profile
            LaunchTimer.windowAppeared()
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
        // The menu bar follows this window through a light reference that changes only with what
        // the menus show (Split View, and the profile whose bookmarks they list): with the whole
        // model, every change in the window (tabs, dialogs…) rebuilt the entire menu bar.
        .focusedSceneValue(\.browserWindow, BrowserWindowRef(model: model, splitOpen: model.splitPair != nil, profile: model.profileID))
        .navigationTitle(model.selectedTab?.displayTitle ?? "Ufolio")
        .frame(minWidth: 640, minHeight: 420)
    }

    /// The tab row (in the title bar, beside the window buttons) and the toolbar under it.
    private var topChrome: some View {
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
                    if !compact {
                        UpdateGateBanner()
                        FindBarHost(model: model)
                    }
                }
            .background(tint?.toolbar ?? Chrome.toolbar)
            .overlay(alignment: .bottom) { Hairline() }
        }
        .environment(\.colorScheme, tint?.scheme ?? systemScheme)
    }

    /// Typing in the address bar keeps Compact mode's chrome out while the pointer wanders.
    private var editingAddress: Bool { model.addressField?.currentEditor() != nil }

    /// Tabs along the top: the tab row in the title bar, the toolbar, then the page.
    private var topLayout: some View {
        VStack(spacing: 0) {
            if compact {
                UpdateGateBanner()
                FindBarHost(model: model)
            } else { topChrome }

            TranslationHost()
            // "Add to Ufolio" on Chrome Web Store pages (takes no space anywhere else).
            SelectedTab(model: model) { tab in
                WebStoreBar(tab: tab).background(VisualEffect(material: .titlebar))
            }
            // What torrent site mode stopped (only with Torrent tools on, on torrent sites).
            SelectedTab(model: model) { tab in
                TorrentGuardBar(tab: tab).background(VisualEffect(material: .titlebar))
            }
            SelectedTab(model: model) { tab in
                HeavyPageBar(tab: tab).background(VisualEffect(material: .titlebar))
            }
            // "You visit this site a lot: add it to your Favourites?" (no space otherwise).
            SelectedTab(model: model) { tab in
                BookmarkOfferBar(tab: tab).background(VisualEffect(material: .titlebar))
            }

            HStack(spacing: 0) {
            // The page: a rounded card set into the frosted window.
            ZStack(alignment: .topLeading) {
                PageArea(model: model)
                if let tab = model.selectedTab {
                    ProgressLine(tab: tab)
                }
            }
            // Rounded by the page itself (cheap even for video), with a hairline edge. No drop
            // shadow or clipping mask here: those make the Mac recompose a playing video every frame.
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.08)).allowsHitTesting(false))
            // Bookmarks & History (⇧⌘L) slides in over the page's edge, so the page never resizes.
            .overlay(alignment: .leading) { SidebarSlot(model: model) }
            .overlay { LinkPreviewOverlay(model: model) }
            .overlay { NoticeHost(center: model.notices) }   // little notices, in the page's corner
            DockArea(model: model)
            }
            .padding([.horizontal, .bottom], 6)
            .padding(.top, 6)
        }
        // Compact mode: the tabs and toolbar come back over the page from the top edge.
        .overlay(alignment: .top) {
            if compact {
                CompactReveal(edge: .top, revealed: $revealTop, keepOpen: { editingAddress || CompactMode.chromeInUse(model.window) }) {
                    topChrome
                        .background(windowGlass)
                        .shadow(color: .black.opacity(0.18), radius: 14, y: 5)
                }
            }
        }
    }

    /// Tabs down the side: a frosted column with the window buttons, address bar, Spaces and
    /// tabs; the page sits beside it as a rounded card.
    private var sideLayout: some View {
        HStack(spacing: 0) {
            if !compact { sideColumn }
            VStack(spacing: 0) {
                // The top row: bookmarks (if shown), and the ⋯ panel at the top right.
                HStack(spacing: 0) {
                    if showBookmarkBar { BookmarkBar(model: model) } else { Color.clear.contentShape(Rectangle()).gesture(WindowDragGesture()) }
                    HStack(spacing: 2) {
                        DownloadsButton()
                        if !model.isPrivate { ExtensionButtons() }
                        SelectedTab(model: model) { ShieldsButton(tab: $0) }
                        PrivateWindowButton(isPrivate: model.isPrivate)
                        MoreMenuButton(model: model)
                    }
                    .padding(.horizontal, 8)
                }
                .frame(height: 34)
                if showDefaultBanner {
                    DefaultBrowserBanner {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) { showDefaultBanner = false }
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
                UpdateGateBanner()
                FindBarHost(model: model)
                TranslationHost()
                SelectedTab(model: model) { tab in WebStoreBar(tab: tab) }
                SelectedTab(model: model) { tab in TorrentGuardBar(tab: tab) }
                SelectedTab(model: model) { tab in HeavyPageBar(tab: tab) }
                SelectedTab(model: model) { tab in BookmarkOfferBar(tab: tab) }
                HStack(spacing: 0) {
                    ZStack(alignment: .topLeading) {
                        PageArea(model: model)
                        if let tab = model.selectedTab { ProgressLine(tab: tab) }
                    }
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.08)).allowsHitTesting(false))
                    .overlay(alignment: .leading) { SidebarSlot(model: model) }
                    .overlay { LinkPreviewOverlay(model: model) }
                    .overlay { NoticeHost(center: model.notices) }   // little notices, in the page's corner
                    DockArea(model: model)
                }
                .padding(.trailing, 8)
                .padding(.bottom, 8)
            }
            .padding(.top, 4)
        }
        // Compact mode: the tab column comes back over the page from the left edge.
        .overlay(alignment: .leading) {
            if compact {
                CompactReveal(edge: .leading, revealed: $revealSide, keepOpen: { editingAddress || CompactMode.chromeInUse(model.window) }) {
                    sideColumn
                        .background(windowGlass)
                        .shadow(color: .black.opacity(0.18), radius: 14, x: 5)
                }
            }
        }
    }

    /// The tab column: window buttons, address bar, Orbits and tabs.
    private var sideColumn: some View {
        SideTabBar(model: model, suggestions: suggestions, onGo: go)
            .background(tint?.frame ?? .clear)
            .environment(\.colorScheme, tint?.scheme ?? systemScheme)
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
        // 👽
        let words = text.lowercased().filter { $0.isLetter || $0 == " " }.split(separator: " ").joined(separator: " ")
        if words == "take me to your leader" {
            leaderEgg = true
            return
        }
        guard let url = URLResolver.resolve(text) else { return }
        // ⌘-Return or ⌥-Return opens it in a new tab, as in Safari and Chrome (it used to replace
        // the page you were on whatever you held).
        let flags = NSApp.currentEvent?.modifierFlags ?? []
        if flags.contains(.command) || flags.contains(.option), model.selectedTab?.isBlank == false {
            let tab = model.newTab(url: url, select: true)
            DispatchQueue.main.async { tab.webView.window?.makeFirstResponder(tab.webView) }
            return
        }
        model.selectedTab?.load(url)
        if let tab = model.selectedTab {
            DispatchQueue.main.async { tab.webView.window?.makeFirstResponder(tab.webView) }
        }
    }
}

/// "⋯" at the end of the toolbar: a frosted panel with the everyday commands, their shortcuts
/// and a live zoom control.
struct MoreMenuButton: View {
    let model: BrowserModel   // only handed to the panel (which watches it while open)
    @State private var showing = false

    var body: some View {
        Button { showing.toggle() } label: {
            ToolbarTile(art: .more, pressed: showing)
        }
        .buttonStyle(.plain)
        .help("More: zoom, print, history, settings and more")
        .popover(isPresented: $showing, arrowEdge: .bottom) {
            MorePanel(model: model) { showing = false }
        }
    }
}

private struct MorePanel: View {
    @ObservedObject var model: BrowserModel
    let close: () -> Void
    @Environment(\.openWindow) private var openWindow
    @AppStorage(Prefs.tabLayout) private var tabLayout = TabLayout.top.rawValue
    @AppStorage(Prefs.compactMode) private var compactMode = false
    @State private var zoomRevision = 0

    var body: some View {
        VStack(spacing: 0) {
            group {
                row("plus.square", "New Tab", .newTab) { model.newTab(focus: true) }
                row("theatermasks", "New Stealth Window", .privateWindow) { openWindow(id: "private") }
            }
            divider
            group {
                row("clock.arrow.circlepath", "History", .history, chevron: true) { openWindow(id: "history") }
                row("book", "Bookmarks", .sidebar, chevron: true) { model.sidebarOpen = true }
                row("arrow.down.circle", "Downloads") { NSWorkspace.shared.open(Downloads.folder) }
                row("key", "Passwords") { SettingsOpener.open(tab: .passwords) }
                row("puzzlepiece.extension", "Extensions & Themes") { SettingsOpener.open(tab: .extensions) }
            }
            divider
            group {
                let hasPage = model.selectedTab?.url != nil
                row("printer", "Print…", .print, enabled: hasPage) { model.selectedTab?.printPage() }
                row("square.and.arrow.down", "Save Page As…", .savePage, enabled: hasPage) { model.selectedTab?.savePage() }
                row("iphone.and.arrow.forward", "Send to iPhone…", enabled: hasPage && !model.isPrivate) {
                    if let tab = model.selectedTab, let url = tab.url { Beam.show(url, title: tab.displayTitle, in: model.window) }
                }
                row("translate", "Translate Page…", .translate, enabled: hasPage) {
                    if let tab = model.selectedTab {
                        if tab.translation == .translated { PageTranslator.shared.showOriginal(tab) } else { PageTranslator.shared.translate(tab) }
                    }
                }
                row("text.magnifyingglass", "Find in Page…", .find, enabled: hasPage) { model.find.show() }
            }
            divider
            zoomRow
            divider
            group {
                row(tabLayout == TabLayout.side.rawValue ? "rectangle.topthird.inset.filled" : "sidebar.squares.left",
                    tabLayout == TabLayout.side.rawValue ? "Tabs Along the Top" : "Tabs Down the Side") {
                    tabLayout = (tabLayout == TabLayout.side.rawValue ? TabLayout.top : TabLayout.side).rawValue
                }
                row(compactMode ? "arrow.up.left.and.arrow.down.right" : "arrow.down.right.and.arrow.up.left",
                    compactMode ? "Leave Compact Mode" : "Compact Mode", .compactMode) { CompactMode.toggle() }
                row("gearshape", "Settings", shortcutText: "⌘,") { SettingsOpener.open() }
                row("questionmark.circle", "Help and Feedback", chevron: true) {
                    NSWorkspace.shared.open(URL(string: "https://github.com/danxharvard/Ufolio")!)
                }
            }
        }
        .padding(.vertical, 6)
        .frame(width: 300)
    }

    // MARK: Pieces

    private func group<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 1) { content() }.padding(.horizontal, 6)
    }

    private var divider: some View {
        Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1).padding(.horizontal, 14).padding(.vertical, 5)
    }

    private func row(_ symbol: String, _ title: String, _ shortcut: ShortcutAction? = nil, shortcutText: String? = nil,
                     chevron: Bool = false, enabled: Bool = true, action: @escaping () -> Void) -> some View {
        PanelRow(symbol: symbol, title: title,
                 trailing: chevron ? nil : (shortcutText ?? shortcut.flatMap { Shortcuts.combo($0)?.display }),
                 chevron: chevron, enabled: enabled) {
            close()
            DispatchQueue.main.async(execute: action)
        }
    }

    private var zoomRow: some View {
        let zoom = model.selectedTab?.webView.pageZoom ?? 1
        let _ = zoomRevision
        return HStack(spacing: 4) {
            Image(systemName: "plus.magnifyingglass").font(.system(size: 13)).foregroundStyle(.secondary).frame(width: 22)
            Text("Zoom").font(.system(size: 13))
            Spacer()
            ZoomButton(symbol: "minus") { model.selectedTab?.zoom(by: -0.1); zoomRevision += 1 }
            Button { model.selectedTab?.resetZoom(); zoomRevision += 1 } label: {
                Text("\(Int((zoom * 100).rounded()))%")
                    .font(.system(size: 12.5, weight: .medium, design: .rounded)).monospacedDigit()
                    .frame(width: 48)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Actual Size")
            ZoomButton(symbol: "plus") { model.selectedTab?.zoom(by: 0.1); zoomRevision += 1 }
            Rectangle().fill(Color.primary.opacity(0.12)).frame(width: 1, height: 18).padding(.horizontal, 4)
            ZoomButton(symbol: "arrow.up.left.and.arrow.down.right") { close(); model.window?.toggleFullScreen(nil) }
                .accessibilityLabel("Full Screen")
        }
        .padding(.horizontal, 16)
        .frame(height: 34)
        .disabled(model.selectedTab?.url == nil)
    }
}

private struct PanelRow: View {
    let symbol: String
    let title: String
    let trailing: String?
    let chevron: Bool
    let enabled: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol).font(.system(size: 13)).frame(width: 22)
                    .foregroundStyle(hovering ? Color.white : Color.secondary)
                Text(title).font(.system(size: 13))
                Spacer(minLength: 8)
                if let trailing {
                    Text(trailing).font(.system(size: 12, design: .rounded))
                        .foregroundStyle(hovering ? Color.white.opacity(0.85) : Color.secondary)
                }
                if chevron {
                    Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(hovering ? Color.white.opacity(0.85) : Color.secondary)
                }
            }
            .foregroundStyle(hovering ? Color.white : Color.primary)
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(hovering ? Color.accentColor : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
        .onHover { hovering = $0 && enabled }
    }
}

private struct ZoomButton: View {
    let symbol: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 12, weight: .semibold))
                .frame(width: 28, height: 24)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.primary.opacity(hovering ? 0.1 : 0)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
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
    let model: BrowserModel   // not observed: the page doesn't need redrawing when other tabs change
    @ObservedObject var tab: BrowserTab

    var body: some View {
        ZStack {
            // A blank tab shows only the start page, so its translucent backdrop
            // isn't drawn over an empty white web view.
            if tab.isBlank {
                Group { if model.isPrivate { PrivateStartPage() } else { StartPage(model: model) } }
                    .clipShape(PageCorners.shape)
            } else if tab.isAsleep, let snapshot = tab.snapshot {
                Image(nsImage: snapshot).resizable().aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top).clipShape(PageCorners.shape)
                    .contentShape(Rectangle())
                    .onTapGesture { tab.wakeIfNeeded() }   // a page put to sleep while showing
            } else {
                // A woken tab has a new web view, so key the host on it.
                WebViewHost(webView: tab.webView).id(ObjectIdentifier(tab.webView))
            }
            if tab.crashed {
                CrashedPage { tab.recoverFromCrash() }
                    .clipShape(PageCorners.shape)
                    .transition(.opacity)
            } else if let failure = tab.loadError {
                LoadErrorPage(url: failure.url, message: failure.message, insecure: failure.insecure,
                              onInsecure: { if let insecure = failure.insecure { tab.openInsecure(insecure) } }) {
                    if let url = failure.url ?? tab.url { tab.load(url) } else { tab.reload() }
                }
                .clipShape(PageCorners.shape)
                .transition(.opacity)
            }
            if let article = tab.reader {
                ReaderView(article: article) { tab.toggleReader() }
                    .clipShape(PageCorners.shape)
                    .transition(.opacity)
            }
            if let block = tab.lookalike {
                LookalikeWarning(match: block.match) {
                    // The real site comes from your own bookmarks and history: never assume it's a tidy address.
                    if let real = URL(string: "https://\(block.match.real)") { tab.load(real) } else { tab.lookalike = nil }
                } onContinue: {
                    Lookalike.allow(Domains.site(block.url.host ?? ""), remember: !tab.isPrivate)   // Stealth leaves no record
                    tab.load(block.url)
                }
                .clipShape(PageCorners.shape)
                .transition(.opacity)
            }
        }
    }
}

struct WebViewHost: NSViewRepresentable {
    let webView: WKWebView
    func makeNSView(context: Context) -> WKWebView { PageCorners.round(webView); return webView }
    func updateNSView(_ nsView: WKWebView, context: Context) { PageCorners.round(nsView) }
}

/// The page card's rounded corners. Web pages are rounded by their own layer, which Core
/// Animation does almost for free, rather than by a SwiftUI clipping mask (which forces the
/// whole page, video and all, to be recomposed every frame).
enum PageCorners {
    static let radius: CGFloat = 10
    static let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)

    static func round(_ view: NSView) {
        view.wantsLayer = true
        guard let layer = view.layer, layer.cornerRadius != radius else { return }
        layer.cornerRadius = radius
        layer.cornerCurve = .continuous
        layer.masksToBounds = true
    }
}

struct NavButtons: View {
    @ObservedObject var tab: BrowserTab

    var body: some View {
        HStack(spacing: 2) {
            ToolbarIconButton(symbol: "chevron.left", help: "Back (⌘[)") { tab.goBack() }
                .disabled(!tab.canGoBack)
            ToolbarIconButton(symbol: "chevron.right", help: "Forward (⌘])") { tab.goForward() }
                .disabled(!tab.canGoForward)
            ToolbarIconButton(symbol: tab.isLoading ? "xmark" : "arrow.clockwise",
                              help: tab.isLoading ? "Stop" : "Reload (⌘R)") { tab.reload() }
                .disabled(tab.isBlank)
        }
    }
}

/// One look for every icon in the toolbar: the same size, line weight and grey, so no icon
/// shouts louder than another. Colour only ever means "on" (Force Field, Stealth).
enum ToolbarIcon {
    static let font = Font.system(size: 15, weight: .regular)
    /// The shield draws narrower than round icons at the same size: one point up makes it
    /// measure the same as the alien and ⋯ (it looked noticeably smaller).
    static let shieldFont = Font.system(size: 16, weight: .regular)
    /// The square that drawn icons (not SF Symbols) fill, to match a 15 pt symbol.
    static let glyph: CGFloat = 16
    static let color = Color.primary.opacity(0.72)
    static let disabledColor = Color.primary.opacity(0.25)
    static let button = CGSize(width: 30, height: 26)
}

/// The top-right toolbar buttons, in the macOS "icon and text" style: an SF Symbol (drawn by
/// macOS as a vector, so it stays perfectly crisp) over a small word, all one size. The shield is
/// green while Force Field blocks, with its count; Downloads gets a ring as files arrive.
struct ToolbarTile: View {
    enum Art: String { case adblock, downloads, stealth, more }
    let art: Art
    /// Ad blocking switched off for this site: a slashed grey shield, "Allowed".
    var dimmed = false
    var pressed = false
    /// Downloads: something is downloading (the symbol takes the accent colour).
    var glowing = false
    /// Ad blocking: how many things it stopped on this page (shown on the shield).
    var count = 0
    /// A little bounce of the count when something new is blocked.
    var pulse = false
    @State private var hovering = false

    static let size = CGSize(width: 56, height: 32)

    private var symbol: String {
        switch art {
        case .adblock: return dimmed ? "shield.slash" : "shield.lefthalf.filled"
        case .downloads: return "arrow.down.circle"
        case .stealth: return "eye.slash"
        case .more: return "ellipsis.circle"
        }
    }
    private var word: String {
        switch art {
        case .adblock: return dimmed ? "Allowed" : "Blocking"
        case .downloads: return "Downloads"
        case .stealth: return "Stealth"
        case .more: return "More"
        }
    }
    private var tint: Color {
        if art == .adblock && !dimmed { return ForceFieldColor.on }
        if art == .downloads && glowing { return .accentColor }
        return Color.primary.opacity(dimmed ? 0.45 : 0.78)
    }

    var body: some View {
        VStack(spacing: 1) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .regular))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint)
                .frame(width: 22, height: 19)
                .overlay(alignment: .topTrailing) {
                    if count > 0 {
                        Text(count > 99 ? "99+" : "\(count)")
                            .font(.system(size: 8.5, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                            .padding(.horizontal, 3.5)
                            .frame(minWidth: 14, minHeight: 13)
                            // A deep green in both looks, so the white number reads clearly.
                            .background(Capsule().fill(Color(red: 0.13, green: 0.60, blue: 0.29)))
                            .overlay(Capsule().strokeBorder(Color.black.opacity(0.12), lineWidth: 0.5))
                            .scaleEffect(pulse ? 1.18 : 1)
                            .fixedSize()
                            .offset(x: 11, y: -5)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
            Text(word)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.primary.opacity(hovering || pressed ? 0.85 : 0.6))
                .lineLimit(1)
                .fixedSize()
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(Color.primary.opacity(pressed ? 0.11 : hovering ? 0.07 : 0)))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .animation(.snappy(duration: 0.16), value: hovering)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: count > 0)
        .animation(.easeOut(duration: 0.2), value: glowing)
        .accessibilityLabel(word)
    }
}

/// Force Field's green: the AD BLOCKING badge while it's protecting the page.
enum ForceFieldColor {
    static let on = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0.36, green: 0.85, blue: 0.48, alpha: 1)
            : NSColor(red: 0.13, green: 0.58, blue: 0.27, alpha: 1)
    })
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
                .font(ToolbarIcon.font)
                .foregroundStyle(tint ?? (isEnabled ? ToolbarIcon.color : ToolbarIcon.disabledColor))
                .frame(width: ToolbarIcon.button.width, height: ToolbarIcon.button.height)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.primary.opacity(hovering && isEnabled ? 0.08 : 0))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { hovering = $0 }
        .animation(.snappy(duration: 0.16), value: hovering)
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

    @State private var pulse = false
    @State private var lastPulse = Date.distantPast
    @AppStorage(Prefs.reduceMotion) private var reduceMotion = false

    var body: some View {
        Button { showing.toggle() } label: {
            // In colour while Force Field protects this site; greyed out when it's off for it.
            ToolbarTile(art: .adblock, dimmed: !shieldsUp, pressed: showing,
                        count: shieldsUp ? tab.blockedOnPage : 0, pulse: pulse)
        }
        .buttonStyle(.plain)
        .help(shieldsUp ? "Force Field: blocking ads and trackers on this site" : "Force Field is off for this site")
        // A tiny "hush" pulse when something is blocked (at most once a second).
        .onChange(of: tab.blockedOnPage) { _, count in
            guard count > 0, !reduceMotion, Date().timeIntervalSince(lastPulse) > 1 else { return }
            lastPulse = Date()
            withAnimation(.spring(response: 0.18, dampingFraction: 0.5)) { pulse = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { pulse = false }
            }
        }
        .popover(isPresented: $showing, arrowEdge: .bottom) {
            ShieldsPanel(tab: tab, shieldsUp: shieldsUp)
        }
    }
}

struct ShieldsPanel: View {
    @ObservedObject var tab: BrowserTab
    @Environment(\.colorScheme) private var scheme
    let shieldsUp: Bool
    @ObservedObject private var stats = BlockStats.shared
    @ObservedObject private var report = PrivacyReport.shared
    @AppStorage(Prefs.blockingMode) private var mode = BlockingMode.standard.rawValue
    @ObservedObject private var siteShields = ShieldSettings.shared
    @State private var showBlocked = false

    private var blockingMode: BlockingMode { BlockingMode(rawValue: mode) ?? .standard }
    private var shields: Shields { siteShields.effective(for: tab.host) }

    var body: some View {
        VStack(spacing: 12) {
            // The animation in its own flat, dark tile, with the status and this page's count.
            heroTile
            siteRow
            if shieldsUp { statsStrip }
            if shieldsUp, !tab.blockedSites.isEmpty { blockedList }
            if shieldsUp, tab.host != nil { siteSettings }
            if tab.url != nil { tabActions }
            footer
        }
        .padding(14)
        .frame(width: 352)
        .animation(.smooth(duration: 0.26), value: shieldsUp)
    }

    // MARK: The animation and the count

    private var heroTile: some View {
        VStack(spacing: 0) {
            // No box: the animation floats on the frosted panel, over a soft night glow that's
            // deepest behind the saucer and fades to nothing well before the edges.
            GuardIllustration(on: shieldsUp, blocked: tab.blockedOnPage)
                .frame(height: 160)
                .background {
                    ZStack {
                        // Night: a deep haze. Day: a soft dusk violet, so the panel stays light.
                        let haze = scheme == .dark ? GuardPalette.night : Color(red: 0.42, green: 0.38, blue: 0.70)
                        let depth = scheme == .dark ? (0.92, 0.6) : (0.62, 0.30)
                        EllipticalGradient(stops: [.init(color: haze.opacity(depth.0), location: 0),
                                                   .init(color: haze.opacity(depth.1), location: 0.45),
                                                   .init(color: haze.opacity(0), location: 1)],
                                           center: .center, startRadiusFraction: 0, endRadiusFraction: 0.5)
                        EllipticalGradient(colors: [GuardPalette.violet.opacity(shieldsUp ? 0.22 : 0.06), .clear],
                                           center: .init(x: 0.5, y: 0.38), startRadiusFraction: 0, endRadiusFraction: 0.42)
                    }
                    .padding(.horizontal, -20)
                    .padding(.vertical, -26)
                    .allowsHitTesting(false)
                }
            VStack(spacing: 3) {
                HStack(spacing: 6) {
                    Circle().fill(shieldsUp ? Color.green : Color.orange).frame(width: 6, height: 6)
                    Text(shieldsUp ? "Force Field Active" : (blockingMode == .off ? "Force Field Off Everywhere" : "Force Field Off for This Site"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                Text("\(tab.blockedOnPage)")
                    .font(.system(size: 44, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(shieldsUp ? Color.primary : Color.secondary)
                    .contentTransitionIfAvailable()
                Text(shieldsUp ? (tab.blockedOnPage == 1 ? "thing blocked on this page" : "things blocked on this page")
                               : "Ads and trackers load on this site")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 10)
            .padding(.bottom, 4)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Ads, trackers, fingerprint

    /// One strip with three readings and hairline dividers, as on hushlist.online.
    private var statsStrip: some View {
        let fingerprint = shields.fingerprinting == .off ? "Off" : (shields.fingerprinting == .strict ? "Strict" : "Masked")
        return HStack(spacing: 0) {
            GuardReading(label: "Ads", value: "\(tab.adsOnPage)")
            GuardDivider()
            GuardReading(label: "Trackers", value: "\(tab.trackersOnPage)")
            GuardDivider()
            GuardReading(label: "Fingerprint", value: fingerprint)
        }
        .padding(.vertical, 12)
        .guardCard()
    }

    // MARK: Footer

    private var footer: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text("\(stats.total.formatted()) blocked in total")
                    .font(.system(size: 11.5, weight: .medium))
                if !tab.isPrivate {
                    Text("\(report.summary.today.formatted()) today · \(report.summary.week.formatted()) this week")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            Spacer()
            Button("Settings…") { SettingsOpener.open(tab: .adBlocker) }
                .buttonStyle(.link)
                .font(.system(size: 11.5))
        }
        .padding(.horizontal, 2)
    }

    /// This site, its status, and the on/off switch.
    private var siteRow: some View {
        HStack(spacing: 10) {
            Group {
                if tab.url == nil { HushLogoTile(size: 24) } else { Favicon(url: tab.url, size: 20) }
            }
            .frame(width: 28, height: 28)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.primary.opacity(0.06)))
            VStack(alignment: .leading, spacing: 1) {
                Text(tab.host.map { AddressBar.readableHost($0).strippingWWW } ?? "New Tab")
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text(shieldsUp ? "Protected" : (blockingMode == .off ? "Blocking is off everywhere" : "Off for this site"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let host = tab.host, blockingMode != .off {
                Toggle("", isOn: Binding(
                    get: { !ContentBlocker.shared.isShieldsDown(host) },
                    set: { up in
                        ContentBlocker.shared.setShields(up, for: host, privately: tab.isPrivate)
                        tab.webView.reload()
                    }))
                .toggleStyle(FluidSwitchStyle(size: CGSize(width: 38, height: 22)))
                .labelsHidden()
                .accessibilityLabel("Turn Force Field off if this site doesn’t work properly")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .guardCard()
    }

    /// "What was blocked": the companies behind this page's blocked ads and trackers.
    private var blockedList: some View {
        let groups = TrackerCompanies.groups(tab.blockedSites)
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.88)) { showBlocked.toggle() }
            } label: {
                HStack(spacing: 8) {
                    GuardIconTile(symbol: "building.2.fill", tint: .indigo)
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
                            Favicon(url: URL(string: "https://\(group.sites.first ?? "")"), size: 15, offline: true)
                                .frame(width: 22, height: 18)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(group.company).font(.system(size: 12, weight: .medium)).lineLimit(1)
                                if group.company != group.sites.first || group.sites.count > 1 {
                                    Text(group.sites.prefix(3).joined(separator: ", ") + (group.sites.count > 3 ? " +\(group.sites.count - 3)" : ""))
                                        .font(.system(size: 10.5)).foregroundStyle(.secondary).lineLimit(1)
                                }
                            }
                            Spacer(minLength: 6)
                            Text("\(group.count)").font(.system(size: 11.5, weight: .medium)).monospacedDigit()
                                .foregroundStyle(.secondary)
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
        .guardCard()
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    /// This site's own settings: anything left on Default follows Settings › Hush Guard.
    private var siteSettings: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("This Site").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
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
            .guardCard()
        }
    }

    /// Quick actions for this tab.
    private var tabActions: some View {
        HStack(spacing: 6) {
            GuardAction(symbol: tab.javaScriptOff ? "curlybraces.square.fill" : "curlybraces.square",
                        label: tab.javaScriptOff ? "JS Off" : "JavaScript", active: tab.javaScriptOff) { tab.toggleJavaScript() }
                .accessibilityLabel(tab.javaScriptOff ? "Turn JavaScript back on in this tab" : "Turn JavaScript off in this tab")
            GuardAction(symbol: "eye.slash", label: "Hide…", active: false) { ElementZapper.shared.start(in: tab) }
                .accessibilityLabel("Click things on the page to hide them for good")
            GuardAction(symbol: "eraser", label: "Forget", active: false) { SiteForgetter.confirmAndForget(tab) }
                .accessibilityLabel("Forget This Site: delete its cookies, data and history")
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
            GuardIconTile(symbol: symbol, tint: GuardPalette.tint(for: symbol))
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
            .accessibilityLabel(chosen == nil ? "Following your default" : "Changed for this site")
        }
        .frame(height: 32)
    }

    private func set(_ value: String?) {
        guard let host = tab.host else { return }
        siteShields.update(host, privately: tab.isPrivate) { $0[keyPath: keyPath] = value }
        tab.webView.reload()
    }
}

/// The Force Field panel's colours.
enum GuardPalette {
    static let violet = Color(red: 0.55, green: 0.42, blue: 1.0)
    /// The animation's tile: a flat, deep night blue in Day and Night alike.
    static let night = Color(red: 0.07, green: 0.07, blue: 0.13)

    static func tint(for symbol: String) -> Color {
        switch symbol {
        case "shield.lefthalf.filled": return .green
        case "curlybraces": return .blue
        case "touchid": return .purple
        case "birthday.cake": return .orange
        default: return .indigo
        }
    }
}

/// A reading in the stats strip: a big number over a quiet label.
private struct GuardReading: View {
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 20, weight: .semibold))
                .monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                .contentTransitionIfAvailable()
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

private struct GuardDivider: View {
    var body: some View { Divider().frame(height: 34) }
}

/// A small coloured icon tile, as in System Settings.
struct GuardIconTile: View {
    let symbol: String
    let tint: Color

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 22, height: 22)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(tint))
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
            HStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 11.5, weight: .medium))
                Text(label).font(.system(size: 11.5))
            }
            .foregroundStyle(active ? Color.accentColor : Color.primary)
            .frame(maxWidth: .infinity)
            .frame(height: 30)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(hovering ? 0.10 : 0.06)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

private extension View {
    /// The Force Field panel's groups: a flat fill with a hairline edge, like System Settings.
    func guardCard() -> some View {
        background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.04)))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
    }

    /// Rolling-number animation.
    func contentTransitionIfAvailable() -> some View {
        contentTransition(.numericText())
    }
}

/// The Force Field animation: the saucer and its pilot zapping ads, drawn 30 times a second while
/// the panel is open (still with Reduce Motion).
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

/// The Force Field scene, drawn in one pass: deep-space stars, the saucer with its alien pilot
/// inside a Force Field bubble, and ads drifting in below to be zapped. With the shield down,
/// the bubble is gone, the saucer greys and the ads just float.
private struct GuardScene: View {
    let on: Bool
    let blocked: Int
    let t: Double
    let size: CGSize

    // Colours.
    private static let laser = Color(red: 0.55, green: 1.0, blue: 0.55)
    private static let alienTop = Color(red: 0.62, green: 1.0, blue: 0.55)
    private static let alienBottom = Color(red: 0.20, green: 0.70, blue: 0.40)
    private static let adColors = [Color(red: 1.0, green: 0.42, blue: 0.36), Color(red: 1.0, green: 0.62, blue: 0.25), Color(red: 0.95, green: 0.35, blue: 0.6)]
    private static let lightColors = [Color(red: 1.0, green: 0.45, blue: 0.55), Color(red: 1.0, green: 0.85, blue: 0.35),
                                      Color(red: 0.45, green: 1.0, blue: 0.7), Color(red: 0.45, green: 0.8, blue: 1.0)]

    // Stars: a far layer drifting slowly and a nearer, brighter one.
    private static let far: [(x: Double, y: Double, r: Double, s: Double)] = (0..<24).map { i in
        let d = Double(i)
        return ((d * 0.618).truncatingRemainder(dividingBy: 1), (d * 0.377 + 0.05).truncatingRemainder(dividingBy: 1),
                0.5 + (d * 0.29).truncatingRemainder(dividingBy: 0.6), 0.003 + (d * 0.0007).truncatingRemainder(dividingBy: 0.003))
    }
    private static let near: [(x: Double, y: Double, r: Double, s: Double)] = (0..<7).map { i in
        let d = Double(i)
        return ((d * 0.413 + 0.1).truncatingRemainder(dividingBy: 1), (d * 0.271 + 0.12).truncatingRemainder(dividingBy: 0.8),
                1.0 + (d * 0.37).truncatingRemainder(dividingBy: 0.9), 0.008 + (d * 0.0013).truncatingRemainder(dividingBy: 0.006))
    }

    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            let bob = CGFloat(sin(t * 1.6)) * 2.6
            let tilt = sin(t * 0.8) * 1.6   // degrees
            let c = CGPoint(x: w * 0.5, y: h * 0.38 + bob)
            let hullW: CGFloat = 132, hullH: CGFloat = 30

            drawStars(ctx, w: w, h: h)
            if on { drawShield(ctx, c: c, hullW: hullW, back: true) }
            drawAdsAndBeams(ctx, w: w, h: h, emitter: CGPoint(x: c.x, y: c.y + hullH * 0.62))

            var saucer = ctx
            saucer.translateBy(x: c.x, y: c.y)
            saucer.rotate(by: .degrees(tilt))
            drawSaucer(saucer, hullW: hullW, hullH: hullH)
            if on { drawShield(ctx, c: c, hullW: hullW, back: false) }
        }
        .allowsHitTesting(false)
    }

    // MARK: Stars

    private func drawStars(_ ctx: GraphicsContext, w: CGFloat, h: CGFloat) {
        let tint = on ? Color(red: 0.74, green: 0.66, blue: 1.0) : Color.white
        for (i, star) in Self.far.enumerated() {
            let x = (star.x + t * star.s).truncatingRemainder(dividingBy: 1)
            let twinkle = 0.35 + 0.65 * (sin(t * (0.8 + Double(i) * 0.13) + Double(i)) + 1) / 2
            let edge = min(1, min(x, 1 - x, star.y, 1 - star.y) * 5)
            let r = CGFloat(star.r)
            ctx.fill(Path(ellipseIn: CGRect(x: CGFloat(x) * w - r, y: CGFloat(star.y) * h - r, width: r * 2, height: r * 2)),
                     with: .color(tint.opacity(twinkle * edge * (on ? 0.7 : 0.35))))
        }
        for (i, star) in Self.near.enumerated() {
            let x = (star.x + t * star.s).truncatingRemainder(dividingBy: 1)
            let twinkle = 0.45 + 0.55 * (sin(t * (1.3 + Double(i) * 0.21) + Double(i) * 2) + 1) / 2
            let edge = min(1, min(x, 1 - x, star.y, 1 - star.y) * 5)
            let p = CGPoint(x: CGFloat(x) * w, y: CGFloat(star.y) * h)
            let r = CGFloat(star.r)
            let alpha = twinkle * edge * (on ? 1 : 0.45)
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - r * 3, y: p.y - r * 3, width: r * 6, height: r * 6)),
                     with: .radialGradient(Gradient(colors: [tint.opacity(0.35 * alpha), .clear]), center: p, startRadius: 0, endRadius: r * 3))
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)), with: .color(.white.opacity(alpha)))
            if i % 3 == 0 {
                // A four-point glint on the brightest.
                let len = r * 4.5 * CGFloat(twinkle)
                var glint = Path()
                glint.move(to: CGPoint(x: p.x - len, y: p.y)); glint.addLine(to: CGPoint(x: p.x + len, y: p.y))
                glint.move(to: CGPoint(x: p.x, y: p.y - len)); glint.addLine(to: CGPoint(x: p.x, y: p.y + len))
                ctx.stroke(glint, with: .color(.white.opacity(alpha * 0.55)), lineWidth: 0.6)
            }
        }
    }

    // MARK: The Force Field bubble

    private func drawShield(_ ctx: GraphicsContext, c: CGPoint, hullW: CGFloat, back: Bool) {
        let rx = hullW * 0.66, ry: CGFloat = 54
        let rect = CGRect(x: c.x - rx, y: c.y - ry - 6, width: rx * 2, height: ry * 2)
        let pulse = 0.5 + 0.5 * sin(t * 2.2)
        if back {
            // The shell: a soft violet glow, brighter towards its edge.
            ctx.fill(Path(ellipseIn: rect), with: .radialGradient(
                Gradient(stops: [.init(color: Color(red: 0.55, green: 0.42, blue: 1.0).opacity(0.02), location: 0),
                                 .init(color: Color(red: 0.55, green: 0.42, blue: 1.0).opacity(0.10 + 0.04 * pulse), location: 0.82),
                                 .init(color: Color(red: 0.70, green: 0.62, blue: 1.0).opacity(0.22), location: 1)]),
                center: CGPoint(x: rect.midX, y: rect.midY), startRadius: 0, endRadius: rx))
            return
        }
        // The rim, and a bright arc sweeping round it.
        ctx.stroke(Path(ellipseIn: rect), with: .color(Color(red: 0.78, green: 0.72, blue: 1.0).opacity(0.28 + 0.12 * pulse)), lineWidth: 1)
        let start = t * 0.9
        var arc = Path()
        for k in 0...28 {
            let a = start + Double(k) / 28 * 0.9
            let p = CGPoint(x: rect.midX + CGFloat(cos(a)) * rx, y: rect.midY + CGFloat(sin(a)) * ry)
            if k == 0 { arc.move(to: p) } else { arc.addLine(to: p) }
        }
        ctx.stroke(arc, with: .color(Color(red: 0.60, green: 1.0, blue: 0.85).opacity(0.18)), style: StrokeStyle(lineWidth: 5, lineCap: .round))
        ctx.stroke(arc, with: .color(.white.opacity(0.75)), style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
    }

    // MARK: The saucer and its pilot

    private func drawSaucer(_ ctx: GraphicsContext, hullW: CGFloat, hullH: CGFloat) {
        let metalTop = on ? [Color(red: 0.95, green: 0.94, blue: 1.0), Color(red: 0.66, green: 0.62, blue: 0.86)]
                          : [Color(white: 0.88), Color(white: 0.58)]
        let metalBottom = on ? [Color(red: 0.42, green: 0.38, blue: 0.62), Color(red: 0.20, green: 0.17, blue: 0.36)]
                             : [Color(white: 0.45), Color(white: 0.25)]

        // Glow underneath.
        let glowRect = CGRect(x: -hullW * 0.42, y: hullH * 0.2, width: hullW * 0.84, height: hullH * 1.1)
        ctx.fill(Path(ellipseIn: glowRect), with: .radialGradient(
            Gradient(colors: [(on ? Color(red: 0.45, green: 0.85, blue: 1.0) : Color.white).opacity(on ? 0.35 : 0.08), .clear]),
            center: CGPoint(x: 0, y: hullH * 0.75), startRadius: 0, endRadius: hullW * 0.42))

        // Underside and engine ring.
        let under = CGRect(x: -hullW * 0.32, y: hullH * 0.05, width: hullW * 0.64, height: hullH * 0.62)
        ctx.fill(Path(ellipseIn: under), with: .linearGradient(Gradient(colors: metalBottom),
                                                              startPoint: CGPoint(x: 0, y: under.minY), endPoint: CGPoint(x: 0, y: under.maxY)))
        let ring = under.insetBy(dx: hullW * 0.08, dy: hullH * 0.12).offsetBy(dx: 0, dy: hullH * 0.06)
        let engine = 0.6 + 0.4 * sin(t * 3.1)
        ctx.stroke(Path(ellipseIn: ring), with: .color((on ? Color(red: 0.45, green: 0.95, blue: 1.0) : Color(white: 0.6)).opacity(on ? 0.25 * engine : 0.2)), lineWidth: 4)
        ctx.stroke(Path(ellipseIn: ring), with: .color((on ? Color(red: 0.75, green: 1.0, blue: 1.0) : Color(white: 0.7)).opacity(on ? 0.9 * engine : 0.4)), lineWidth: 1.2)
        ctx.fill(Path(ellipseIn: CGRect(x: -4, y: under.maxY - 6, width: 8, height: 4)), with: .color((on ? Self.laser : Color(white: 0.6)).opacity(on ? 0.9 : 0.4)))

        // The canopy: glass over the pilot.
        let domeW: CGFloat = 54, domeH: CGFloat = 44
        let dome = CGRect(x: -domeW / 2, y: -hullH * 0.35 - domeH * 0.78, width: domeW, height: domeH)
        let domePath = Path(ellipseIn: dome)
        ctx.fill(domePath, with: .linearGradient(Gradient(colors: [Color(red: 0.55, green: 0.85, blue: 1.0).opacity(0.22), Color(red: 0.25, green: 0.30, blue: 0.70).opacity(0.35)]),
                                                 startPoint: CGPoint(x: 0, y: dome.minY), endPoint: CGPoint(x: 0, y: dome.maxY)))
        var inside = ctx
        inside.clip(to: domePath)
        drawAlien(inside, base: CGPoint(x: 0, y: -hullH * 0.28))
        // Glass highlights.
        ctx.stroke(domePath, with: .color(.white.opacity(0.45)), lineWidth: 0.9)
        var shine = Path()
        shine.addArc(center: CGPoint(x: dome.midX, y: dome.midY + 4), radius: domeW * 0.40, startAngle: .degrees(200), endAngle: .degrees(245), clockwise: false)
        ctx.stroke(shine, with: .color(.white.opacity(0.75)), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
        ctx.fill(Path(ellipseIn: CGRect(x: dome.midX + domeW * 0.18, y: dome.minY + domeH * 0.18, width: 4, height: 3)), with: .color(.white.opacity(0.6)))

        // The hull: brushed metal with a lit top edge and panel seams.
        let hull = CGRect(x: -hullW / 2, y: -hullH * 0.5, width: hullW, height: hullH)
        let hullPath = Path(ellipseIn: hull)
        ctx.fill(hullPath, with: .linearGradient(Gradient(colors: metalTop + [metalBottom[0]]),
                                                 startPoint: CGPoint(x: 0, y: hull.minY), endPoint: CGPoint(x: 0, y: hull.maxY)))
        ctx.stroke(hullPath, with: .color(.white.opacity(on ? 0.55 : 0.35)), lineWidth: 0.8)
        var seams = Path()
        for k in [-0.30, -0.12, 0.12, 0.30] {
            let x = hullW * CGFloat(k)
            seams.move(to: CGPoint(x: x * 0.92, y: hull.minY + hullH * 0.18))
            seams.addQuadCurve(to: CGPoint(x: x * 1.08, y: hull.maxY - hullH * 0.22), control: CGPoint(x: x * 1.04, y: 0))
        }
        ctx.stroke(seams, with: .color(.black.opacity(0.12)), lineWidth: 0.7)
        // A rim band, with running lights chasing round.
        let band = hull.insetBy(dx: 3, dy: hullH * 0.26).offsetBy(dx: 0, dy: hullH * 0.08)
        ctx.stroke(Path(ellipseIn: band), with: .color(.black.opacity(0.18)), lineWidth: 1.2)
        let lit = Int(t * 7) % 9
        for k in 0..<9 {
            let a = Double.pi * (0.10 + 0.80 * Double(k) / 8)   // along the front half
            let p = CGPoint(x: band.midX + CGFloat(cos(a)) * band.width / 2 * -1, y: band.midY + CGFloat(sin(a)) * band.height / 2)
            let base = on ? Self.lightColors[k % Self.lightColors.count] : Color(white: 0.7)
            let bright = on && k == lit
            if bright {
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - 5, y: p.y - 5, width: 10, height: 10)),
                         with: .radialGradient(Gradient(colors: [base.opacity(0.8), .clear]), center: p, startRadius: 0, endRadius: 5))
            }
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - 1.9, y: p.y - 1.9, width: 3.8, height: 3.8)),
                     with: .color(bright ? .white : base.opacity(on ? 0.9 : 0.5)))
        }
    }

    /// The pilot: a little green alien with big almond eyes, sitting in the canopy.
    private func drawAlien(_ ctx: GraphicsContext, base: CGPoint) {
        let sway = CGFloat(sin(t * 0.9)) * 1.4
        let blink = t.truncatingRemainder(dividingBy: 4.3) < 0.12
        var a = ctx
        a.translateBy(x: base.x + sway, y: base.y)
        let skin = on ? [Self.alienTop, Self.alienBottom] : [Color(white: 0.80), Color(white: 0.55)]
        // Shoulders, then the head.
        a.fill(Path(ellipseIn: CGRect(x: -15, y: -10, width: 30, height: 18)),
               with: .linearGradient(Gradient(colors: [skin[1], skin[1].opacity(0.8)]), startPoint: CGPoint(x: 0, y: -10), endPoint: CGPoint(x: 0, y: 8)))
        let head = CGRect(x: -11, y: -33, width: 22, height: 26)
        a.fill(Path(ellipseIn: head), with: .linearGradient(Gradient(colors: skin), startPoint: CGPoint(x: 0, y: head.minY), endPoint: CGPoint(x: 0, y: head.maxY)))
        // Antennae with glowing tips.
        for side: CGFloat in [-1, 1] {
            var stalk = Path()
            stalk.move(to: CGPoint(x: side * 4, y: head.minY + 3))
            stalk.addQuadCurve(to: CGPoint(x: side * 9, y: head.minY - 9), control: CGPoint(x: side * 5, y: head.minY - 6))
            a.stroke(stalk, with: .color(skin[1]), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
            let tip = CGPoint(x: side * 9, y: head.minY - 9)
            let glow = 0.6 + 0.4 * sin(t * 4 + Double(side))
            a.fill(Path(ellipseIn: CGRect(x: tip.x - 4, y: tip.y - 4, width: 8, height: 8)),
                   with: .radialGradient(Gradient(colors: [(on ? Self.laser : Color.white).opacity(0.7 * glow), .clear]), center: tip, startRadius: 0, endRadius: 4))
            a.fill(Path(ellipseIn: CGRect(x: tip.x - 1.6, y: tip.y - 1.6, width: 3.2, height: 3.2)), with: .color(on ? Color(red: 0.85, green: 1.0, blue: 0.8) : .white))
        }
        // Big almond eyes, with a glint each.
        for side: CGFloat in [-1, 1] {
            var eye = a
            eye.translateBy(x: side * 5, y: head.minY + 13)
            eye.rotate(by: .degrees(Double(side) * 28))
            let h: CGFloat = blink ? 0.8 : 7
            eye.fill(Path(ellipseIn: CGRect(x: -4.2, y: -h / 2, width: 8.4, height: h)), with: .color(Color(red: 0.04, green: 0.06, blue: 0.08)))
            if !blink {
                eye.fill(Path(ellipseIn: CGRect(x: -2.2, y: -2.6, width: 2.2, height: 1.8)), with: .color(.white.opacity(0.9)))
            }
        }
        // A small smile.
        var mouth = Path()
        mouth.addArc(center: CGPoint(x: 0, y: head.minY + 19), radius: 2.4, startAngle: .degrees(20), endAngle: .degrees(160), clockwise: false)
        a.stroke(mouth, with: .color(.black.opacity(0.35)), lineWidth: 0.8)
    }

    // MARK: Ads, beams and bursts

    private func drawAdsAndBeams(_ ctx: GraphicsContext, w: CGFloat, h: CGFloat, emitter: CGPoint) {
        let lanes: [CGFloat] = [0.18, 0.5, 0.82]
        let groundY = h * 0.86
        for (i, lane) in lanes.enumerated() {
            let phase = ((t / 3.0) + Double(i) / 3).truncatingRemainder(dividingBy: 1)
            let x = w * lane + CGFloat(sin(t * 0.9 + Double(i) * 2)) * 6
            let y = groundY + CGFloat(sin(t * 1.3 + Double(i))) * 3
            let ad = CGRect(x: x - 14, y: y - 8.5, width: 28, height: 17)
            let color = Self.adColors[i % Self.adColors.count]
            guard on else { drawAd(ctx, ad, color: color, alpha: 0.7); continue }
            switch phase {
            case ..<0.40:
                drawAd(ctx, ad.offsetBy(dx: 0, dy: CGFloat((0.4 - phase) * 18)), color: color, alpha: min(1, phase * 4))
            case ..<0.52:
                drawAd(ctx, ad, color: color, alpha: 1)
                let k = (phase - 0.40) / 0.12
                let head = CGPoint(x: emitter.x + (x - emitter.x) * k, y: emitter.y + (y - emitter.y) * k)
                drawBeam(ctx, from: emitter, to: head)
            case ..<0.82:
                let k = (phase - 0.52) / 0.30
                drawBurst(ctx, at: CGPoint(x: x, y: y), k: k, color: color, seed: i)
            default:
                break
            }
        }
    }

    /// A tapered beam: wide glow, green body and a white-hot core.
    private func drawBeam(_ ctx: GraphicsContext, from a: CGPoint, to b: CGPoint) {
        let dx = b.x - a.x, dy = b.y - a.y, len = max(1, sqrt(dx * dx + dy * dy))
        let nx = -dy / len, ny = dx / len
        func taper(_ startW: CGFloat, _ endW: CGFloat) -> Path {
            var p = Path()
            p.move(to: CGPoint(x: a.x + nx * startW, y: a.y + ny * startW))
            p.addLine(to: CGPoint(x: b.x + nx * endW, y: b.y + ny * endW))
            p.addLine(to: CGPoint(x: b.x - nx * endW, y: b.y - ny * endW))
            p.addLine(to: CGPoint(x: a.x - nx * startW, y: a.y - ny * startW))
            p.closeSubpath()
            return p
        }
        ctx.fill(taper(3, 9), with: .color(Self.laser.opacity(0.16)))
        ctx.fill(taper(1.6, 4), with: .linearGradient(Gradient(colors: [Self.laser.opacity(0.9), Self.laser.opacity(0.5)]), startPoint: a, endPoint: b))
        ctx.fill(taper(0.6, 1.4), with: .color(.white.opacity(0.95)))
        ctx.fill(Path(ellipseIn: CGRect(x: a.x - 5, y: a.y - 3.5, width: 10, height: 7)),
                 with: .radialGradient(Gradient(colors: [.white, Self.laser.opacity(0)]), center: a, startRadius: 0, endRadius: 5))
    }

    /// An ad bursting: a flash, a shock ring, sparks and tumbling fragments.
    private func drawBurst(_ ctx: GraphicsContext, at p: CGPoint, k: Double, color: Color, seed: Int) {
        let fade = 1 - k
        let flash = 10 + 30 * CGFloat(k)
        ctx.fill(Path(ellipseIn: CGRect(x: p.x - flash / 2, y: p.y - flash / 2, width: flash, height: flash)),
                 with: .radialGradient(Gradient(colors: [.white.opacity(0.9 * fade), Self.laser.opacity(0.5 * fade), .clear]),
                                       center: p, startRadius: 0, endRadius: flash / 2))
        let ring = 6 + 34 * CGFloat(k)
        ctx.stroke(Path(ellipseIn: CGRect(x: p.x - ring / 2, y: p.y - ring / 4, width: ring, height: ring / 2)),
                   with: .color(Self.laser.opacity(0.6 * fade)), lineWidth: 1.2)
        for f in 0..<8 {
            let angle = Double(f) / 8 * 2 * .pi + Double(seed)
            let reach = CGFloat(5 + 24 * k)
            // Sparks: short streaks flying out.
            let s0 = CGPoint(x: p.x + CGFloat(cos(angle)) * reach * 0.6, y: p.y + CGFloat(sin(angle)) * reach * 0.6)
            let s1 = CGPoint(x: p.x + CGFloat(cos(angle)) * reach, y: p.y + CGFloat(sin(angle)) * reach)
            var spark = Path(); spark.move(to: s0); spark.addLine(to: s1)
            ctx.stroke(spark, with: .color(.white.opacity(0.8 * fade)), style: StrokeStyle(lineWidth: 1, lineCap: .round))
            // Fragments of the ad, falling as they go.
            if f % 2 == 0 {
                let fp = CGPoint(x: p.x + CGFloat(cos(angle + 0.4)) * reach * 0.8, y: p.y + CGFloat(sin(angle + 0.4)) * reach * 0.8 + CGFloat(k * k * 12))
                var frag = ctx
                frag.translateBy(x: fp.x, y: fp.y)
                frag.rotate(by: .radians(angle + k * 6))
                let side = 4.5 * CGFloat(1 - k * 0.5)
                frag.fill(Path(roundedRect: CGRect(x: -side / 2, y: -side / 2, width: side, height: side * 0.7), cornerRadius: 1), with: .color(color.opacity(fade)))
            }
        }
    }

    /// A glossy "AD" tag.
    private func drawAd(_ ctx: GraphicsContext, _ rect: CGRect, color: Color, alpha: Double) {
        let path = Path(roundedRect: rect, cornerRadius: 5)
        ctx.fill(path, with: .linearGradient(Gradient(colors: [color.opacity(alpha), color.opacity(alpha * 0.75)]),
                                             startPoint: CGPoint(x: rect.midX, y: rect.minY), endPoint: CGPoint(x: rect.midX, y: rect.maxY)))
        ctx.stroke(path, with: .color(.white.opacity(0.35 * alpha)), lineWidth: 0.8)
        var shine = Path()
        shine.move(to: CGPoint(x: rect.minX + 4, y: rect.minY + 2.5)); shine.addLine(to: CGPoint(x: rect.maxX - 4, y: rect.minY + 2.5))
        ctx.stroke(shine, with: .color(.white.opacity(0.35 * alpha)), style: StrokeStyle(lineWidth: 1, lineCap: .round))
        ctx.draw(Text("AD").font(.system(size: 8.5, weight: .heavy, design: .rounded)).foregroundStyle(.white.opacity(alpha)),
                 at: CGPoint(x: rect.midX, y: rect.midY + 0.5))
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

/// Thin loading bar along the top of the page.
struct ProgressLine: View {
    @ObservedObject var tab: BrowserTab

    var body: some View {
        GeometryReader { geo in
            Rectangle()
                .fill(LinearGradient(colors: [.accentColor.opacity(0.6), .accentColor],
                                     startPoint: .leading, endPoint: .trailing))
                .frame(width: geo.size.width, height: 2)
                // Scaled rather than resized: animating a scale is only drawing, not layout.
                .scaleEffect(x: max(0.05, tab.progress), y: 1, anchor: .leading)
                .opacity(tab.isLoading ? 1 : 0)
                .animation(.smooth(duration: 0.26), value: tab.progress)
                .animation(.easeOut(duration: 0.4), value: tab.isLoading)
        }
        .frame(height: 2)
        .padding(.horizontal, PageCorners.radius)   // stays inside the page's rounded corners
        .allowsHitTesting(false)
    }
}

struct Hairline: View {
    var body: some View {
        Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1)
    }
}

/// Catches every click, scroll and hover over its area. Web pages are separate macOS views, so
/// a SwiftUI layer drawn over one (a frosted backdrop, say) doesn't stop clicks reaching the
/// page underneath; this does. Used behind cards and guides shown over the page.
struct ClickBlocker: NSViewRepresentable {
    /// What a click on the blocked area does (e.g. close the palette); nothing by default.
    var onClick: (() -> Void)? = nil

    final class BlockingView: NSView {
        var onClick: (() -> Void)?
        /// Every blocker on screen, so web pages can tell when one covers them (see HushWebView).
        static let all = NSHashTable<BlockingView>.weakObjects()
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window != nil { Self.all.add(self) } else { Self.all.remove(self) }
        }
        /// True when a blocker in `window` covers this point (in window coordinates).
        static func covers(_ point: NSPoint, in window: NSWindow) -> Bool {
            all.allObjects.contains { blocker in
                blocker.window === window && !blocker.isHiddenOrHasHiddenAncestor
                    && blocker.convert(blocker.bounds, to: nil).contains(point)
            }
        }
        override func hitTest(_ point: NSPoint) -> NSView? { frame.contains(point) ? self : nil }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func mouseDown(with event: NSEvent) { onClick?() }
        override func mouseUp(with event: NSEvent) {}
        override func mouseDragged(with event: NSEvent) {}
        override func rightMouseDown(with event: NSEvent) {}
        override func otherMouseDown(with event: NSEvent) {}
        override func scrollWheel(with event: NSEvent) {}
        override func resetCursorRects() { addCursorRect(bounds, cursor: .arrow) }
    }
    func makeNSView(context: Context) -> BlockingView { let v = BlockingView(); v.onClick = onClick; return v }
    func updateNSView(_ view: BlockingView, context: Context) { view.onClick = onClick }
}

struct VisualEffect: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blending: NSVisualEffectView.BlendingMode = .withinWindow
    /// Forces light or dark frosting (Stealth windows are always dark); nil follows the system.
    var appearance: NSAppearance? = nil
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blending
        view.state = .followsWindowActiveState
        view.appearance = appearance
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        if view.appearance?.name != appearance?.name { view.appearance = appearance }
    }
}

/// Hands the view's NSWindow to SwiftUI code once it's on screen.
/// The sidebar is built once (shortly after launch) and kept, so opening it is instant. Only
/// the sidebar itself slides; the page takes its new width in a single step rather than being
/// re-laid out on every frame of the animation.
private struct SidebarSlot: View {
    let model: BrowserModel
    @ObservedObject var sidebar: BrowserModel.SidebarState
    init(model: BrowserModel) { self.model = model; sidebar = model.sidebar }
    @State private var built = false
    @State private var slotOpen = false
    @State private var slidIn = false
    private let width: CGFloat = 281

    var body: some View {
        Group {
            if built {
                // A frosted card that slides in over the edge of the page. The page underneath never
                // changes size, so opening it never makes a big page lay itself out again mid-slide.
                LibrarySidebar(model: model, active: slotOpen)
                    .frame(width: width - 12)
                    .frame(maxHeight: .infinity)
                    // While it's out, the page underneath gets no clicks, scrolling or hover through it.
                    .background { if slotOpen { ClickBlocker() } }
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.1)))
                    .padding(6)
                    .offset(x: slidIn ? 0 : -width - 20)
                    .animation(.spring(response: 0.3, dampingFraction: 0.9), value: slidIn)
                    .allowsHitTesting(slotOpen)
                    .accessibilityHidden(!slotOpen)
            }
        }
        .frame(maxHeight: .infinity, alignment: .leading)
        .clipped()   // only the sidebar is clipped, never the page
        .onAppear {
            if model.sidebarOpen { open() } else {
                // Build it quietly while nothing else is happening.
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { built = true }
            }
        }
        .onChange(of: sidebar.open) { _, isOpen in isOpen ? open() : close() }
    }

    private func open() {
        built = true
        slotOpen = true                          // frosted glass on, and clickable
        DispatchQueue.main.async { slidIn = true }   // then it glides in over the page
    }

    private func close() {
        slidIn = false                           // the sidebar glides out first
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
            if !model.sidebarOpen { slotOpen = false }   // then its frosted glass switches off
        }
    }
}

/// Shown when a page's process crashed, instead of a blank tab.
/// Shown when a page couldn't load at all.
private struct LoadErrorPage: View {
    let url: URL?
    let message: String
    var insecure: URL? = nil
    var onInsecure: () -> Void = {}
    let onRetry: () -> Void

    var body: some View {
        ZStack {
            ClickBlocker()
            Rectangle().fill(.regularMaterial)   // frosted, like the rest of the window
            VStack(spacing: 14) {
                ZStack {
                    Circle().fill(Color.primary.opacity(0.05)).frame(width: 110, height: 110)
                    Image(systemName: "wifi.exclamationmark").font(.system(size: 40, weight: .light)).foregroundStyle(.secondary)
                }
                Text("Ufolio can’t open this page")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                if let host = url?.host {
                    Text(host.strippingWWW).font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
                }
                Text(message)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 400)
                Button(action: onRetry) { Label("Try Again", systemImage: "arrow.clockwise") }
                    .controlSize(.large)
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 4)
                // A site with no secure version (an old site, or a hotel or café Wi-Fi sign-in page).
                if insecure != nil {
                    VStack(spacing: 6) {
                        Text("This site may not support secure connections.")
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                        Button("Open Insecure Version", action: onInsecure)
                            .buttonStyle(.link)
                            .font(.system(size: 12.5, weight: .medium))
                        Text("Anything you send to it could be seen by others on the network.")
                            .font(.system(size: 11)).foregroundStyle(.tertiary)
                    }
                    .padding(.top, 10)
                }
            }
            .padding(40)
        }
    }
}

private struct CrashedPage: View {
    let onReload: () -> Void

    var body: some View {
        ZStack {
            Rectangle().fill(.regularMaterial)   // frosted, like the rest of the window
            VStack(spacing: 14) {
                ZStack {
                    Circle().fill(Color.primary.opacity(0.05)).frame(width: 110, height: 110)
                    HushMark(color: Color.secondary.opacity(0.7), showStars: false, outlined: true)
                        .frame(width: 58, height: 58)
                }
                Text("This page stopped working")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                Text("Something on the page made it crash. The rest of Ufolio is fine, and your other tabs weren’t affected.")
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

/// The address bar's suggestions, floating under it. The only part of the window that redraws
/// as they change.
private struct SuggestionOverlay: View {
    @ObservedObject var suggestions: SuggestionsModel
    let anchor: CGRect
    let onChoose: (Suggestion) -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            if suggestions.isVisible {
                SuggestionList(suggestions: suggestions, onChoose: onChoose)
                    .frame(width: min(max(380, anchor.width), 680))
                    .offset(x: anchor.minX, y: anchor.maxY + 6)
                    .transition(.opacity.combined(with: .offset(y: -4)))
            }
        }
        .animation(.easeOut(duration: 0.12), value: suggestions.isVisible)
    }
}

struct AddressFrameKey: PreferenceKey {
    static let defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next != .zero { value = next }
    }
}

/// Reports the window only when the view moves into a (different) window, not on every redraw.
/// It used to call back after every update of the window's contents, re-running window setup
/// and repositioning the traffic lights each time, which made the title bar lay itself out
/// again and slowed down every click in the toolbar.
struct WindowReader: NSViewRepresentable {
    let onWindow: (NSWindow?) -> Void
    func makeNSView(context: Context) -> NSView {
        let view = ReportingView()
        view.onWindow = onWindow
        return view
    }
    func updateNSView(_ view: NSView, context: Context) {
        (view as? ReportingView)?.onWindow = onWindow
    }

    final class ReportingView: NSView {
        var onWindow: ((NSWindow?) -> Void)?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            let window = self.window
            DispatchQueue.main.async { [weak self] in self?.onWindow?(window) }
        }
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
                ClickBlocker().ignoresSafeArea()   // nothing behind the card can be clicked
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
            ClickBlocker()   // the previous page is still underneath: it mustn't be clickable through the warning
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

/// The window the menu bar acts on, and the two things about it the menus show.
struct BrowserWindowRef: Equatable {
    weak var model: BrowserModel?
    let splitOpen: Bool
    let profile: UUID?
    private let id: ObjectIdentifier

    init(model: BrowserModel, splitOpen: Bool, profile: UUID?) {
        self.model = model
        self.splitOpen = splitOpen
        self.profile = profile
        id = ObjectIdentifier(model)
    }

    static func == (a: Self, b: Self) -> Bool { a.id == b.id && a.splitOpen == b.splitOpen && a.profile == b.profile }
}

private struct BrowserWindowKey: FocusedValueKey { typealias Value = BrowserWindowRef }

extension FocusedValues {
    var browserWindow: BrowserWindowRef? {
        get { self[BrowserWindowKey.self] }
        set { self[BrowserWindowKey.self] = newValue }
    }
}
