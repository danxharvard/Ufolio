import SwiftUI
import WebKit

/// The whole window: toolbar, tab strip, bookmarks bar and page.
struct BrowserWindow: View {
    @StateObject private var model = BrowserModel()
    @StateObject private var suggestions = SuggestionsModel()
    @AppStorage(Prefs.showBookmarkBar) private var showBookmarkBar = true
    @AppStorage(Prefs.alwaysShowTabBar) private var alwaysShowTabBar = false

    private var showTabStrip: Bool { model.tabs.count > 1 || alwaysShowTabBar }
    @State private var showWelcome = false
    @State private var showDefaultBanner = false
    @State private var whatsNew: ReleaseNotes.Version?


    var body: some View {
        VStack(spacing: 0) {
            if showTabStrip || showBookmarkBar || showDefaultBanner {
                VStack(spacing: 0) {
                    if showTabStrip {
                        TabStrip(model: model)
                    }
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
                }
                .background(VisualEffect(material: .titlebar))
                .overlay(alignment: .bottom) { Hairline() }
            }

            // "Add to Hush" on Chrome Web Store pages (takes no space anywhere else).
            SelectedTab(model: model) { tab in
                WebStoreBar(tab: tab).background(VisualEffect(material: .titlebar))
            }

            ZStack(alignment: .top) {
                PageArea(model: model)
                if let tab = model.selectedTab {
                    ProgressLine(tab: tab)
                }
                if suggestions.isVisible {
                    SuggestionList(suggestions: suggestions) { choice in
                        go(choice.text)
                    }
                    .frame(width: model.addressWidth)
                    .padding(.top, 6)
                    .transition(.opacity.combined(with: .offset(y: -4)))
                }
            }
            .animation(.easeOut(duration: 0.12), value: suggestions.isVisible)
        }
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { model.windowWidth = geo.size.width }
                    .onChange(of: geo.size.width) { model.windowWidth = $0 }
            }
        )
        .background(WindowReader { window in
            // Remember the window's size and position between launches.
            if let window, model.window !== window {
                window.setFrameUsingName("HushBrowserWindow")
                window.setFrameAutosaveName("HushBrowserWindow")
            }
            model.window = window
        })
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
            NSApp.activate(ignoringOtherApps: true)
        }
        .onReceive(NotificationCenter.default.publisher(for: QuitHelper.closeSheets)) { _ in
            showWelcome = false
            showDefaultBanner = false
            whatsNew = nil
        }
        .onAppear {
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
        .toolbar { toolbarContent }
        .focusedSceneObject(model)
        .navigationTitle(model.selectedTab?.displayTitle ?? "Hush")
        .frame(minWidth: 640, minHeight: 420)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        // Each toolbar item watches the selected tab itself: SwiftUI doesn't reliably
        // refresh toolbar items when the window's own state changes.
        ToolbarItemGroup(placement: .navigation) {
            SelectedTab(model: model) { NavButtons(tab: $0) }
        }
        ToolbarItem(placement: .principal) {
            SelectedTab(model: model) { tab in
                AddressBar(model: model, tab: tab, suggestions: suggestions, onGo: go)
                    .frame(width: model.addressWidth)
            }
        }
        ToolbarItemGroup(placement: .primaryAction) {
            ExtensionButtons()
            DownloadsButton()
            SelectedTab(model: model) { ShieldsButton(tab: $0) }
            ToolbarIconButton(symbol: "plus", help: "New Tab (⌘T)") {
                model.newTab(focus: true)
            }
        }
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
            TabPage(model: model, tab: tab).id(tab.id)
        } else {
            Color.clear
        }
    }
}

private struct TabPage: View {
    @ObservedObject var model: BrowserModel
    @ObservedObject var tab: BrowserTab

    var body: some View {
        ZStack {
            // A blank tab shows only the start page, so its translucent backdrop
            // isn't drawn over an empty white web view.
            if tab.isBlank {
                StartPage(model: model)
            } else if tab.isAsleep, let snapshot = tab.snapshot {
                Image(nsImage: snapshot).resizable().aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top).clipped()
            } else {
                // A woken tab has a new web view, so key the host on it.
                WebViewHost(webView: tab.webView).id(ObjectIdentifier(tab.webView))
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

    private var shieldsUp: Bool {
        guard adsOn || trackersOn else { return false }
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

    var body: some View {
        VStack(spacing: 0) {
            GuardIllustration(on: shieldsUp, blocked: tab.blockedOnPage)
                .frame(height: 150)

            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    if tab.url == nil {
                        HushLogoTile(size: 24)
                    } else {
                        Favicon(url: tab.url, size: 22)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tab.host?.strippingWWW ?? "Hush Guard")
                            .font(.system(size: 13.5, weight: .semibold))
                            .lineLimit(1)
                        Text(shieldsUp ? "Hush Guard is on" : "Hush Guard is off for this site")
                            .font(.system(size: 11.5))
                            .foregroundStyle(shieldsUp ? Color.accentColor : Color.secondary)
                    }
                    Spacer()
                    if let host = tab.host {
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

                VStack(spacing: 2) {
                    Text("\(tab.blockedOnPage)")
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.primary)
                        .monospacedDigit()
                        .contentTransitionIfAvailable()
                    Text(tab.blockedOnPage == 1 ? "ad or tracker hushed on this page" : "ads and trackers hushed on this page")
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)

                Divider()

                HStack {
                    Text("\(stats.total.formatted()) hushed in total")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Hush Guard Settings…") { SettingsOpener.open(tab: .adBlocker) }
                        .buttonStyle(.link)
                        .font(.system(size: 11.5))
                }
            }
            .padding(16)
        }
        .frame(width: 320)
        // A solid backdrop so the panel stays readable over bright (white) pages.
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.97))
    }
}

private extension View {
    /// Rolling-number animation where macOS supports it.
    @ViewBuilder func contentTransitionIfAvailable() -> some View {
        if #available(macOS 14.0, *) { self.contentTransition(.numericText()) } else { self }
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
private struct GuardStars: View {
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
private struct LaunchCardOverlay<Card: View>: View {
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
