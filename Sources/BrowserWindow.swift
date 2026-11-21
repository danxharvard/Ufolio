import SwiftUI
import WebKit

/// The whole window: toolbar, tab strip, bookmarks bar and page.
struct BrowserWindow: View {
    @StateObject private var model = BrowserModel()
    @StateObject private var suggestions = SuggestionsModel()
    @AppStorage(Prefs.showBookmarkBar) private var showBookmarkBar = true
    @AppStorage(Prefs.alwaysShowTabBar) private var alwaysShowTabBar = false

    private var showTabStrip: Bool { model.tabs.count > 1 || alwaysShowTabBar }
    @State private var windowWidth: CGFloat = 1280

    private var addressWidth: CGFloat {
        min(720, max(260, windowWidth - 420))
    }

    var body: some View {
        VStack(spacing: 0) {
            if showTabStrip || showBookmarkBar {
                VStack(spacing: 0) {
                    if showTabStrip {
                        TabStrip(model: model)
                    }
                    if showBookmarkBar {
                        BookmarkBar(model: model)
                    }
                }
                .background(VisualEffect(material: .titlebar))
                .overlay(alignment: .bottom) { Hairline() }
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
                    .frame(width: addressWidth)
                    .padding(.top, 6)
                    .transition(.opacity.combined(with: .offset(y: -4)))
                }
            }
            .animation(.easeOut(duration: 0.12), value: suggestions.isVisible)
        }
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { windowWidth = geo.size.width }
                    .onChange(of: geo.size.width) { windowWidth = $0 }
            }
        )
        .background(WindowReader { model.window = $0 })
        .toolbar { toolbarContent }
        .focusedSceneObject(model)
        .navigationTitle(model.selectedTab?.displayTitle ?? "Hush")
        .frame(minWidth: 640, minHeight: 420)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            if let tab = model.selectedTab {
                NavButtons(tab: tab)
            }
        }
        ToolbarItem(placement: .principal) {
            if let tab = model.selectedTab {
                AddressBar(model: model, tab: tab, suggestions: suggestions, onGo: go)
                    .frame(width: addressWidth)
            }
        }
        ToolbarItemGroup(placement: .primaryAction) {
            if let tab = model.selectedTab {
                ShieldsButton(tab: tab)
            }
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
            WebViewHost(webView: tab.webView)
                .opacity(tab.isBlank ? 0 : 1)
            if tab.isBlank {
                StartPage(model: model)
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

/// The shield in the toolbar: how much was blocked on this page, and per-site shields.
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

    var body: some View {
        ToolbarIconButton(
            symbol: shieldsUp ? "shield.lefthalf.filled" : "shield.slash",
            help: "Hush Shields",
            tint: shieldsUp ? .accentColor : nil
        ) {
            showing.toggle()
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

private struct ShieldsPanel: View {
    @ObservedObject var tab: BrowserTab
    let shieldsUp: Bool
    @ObservedObject private var stats = BlockStats.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: shieldsUp ? "shield.lefthalf.filled" : "shield.slash")
                    .font(.system(size: 22))
                    .foregroundStyle(shieldsUp ? Color.accentColor : Color.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(tab.host?.strippingWWW ?? "Hush Shields")
                        .font(.system(size: 13, weight: .semibold))
                    Text(shieldsUp ? "Shields are up" : "Shields are down for this site")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
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
                    .help("Turn shields off if this site doesn’t work properly")
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(tab.blockedOnPage)")
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text(tab.blockedOnPage == 1 ? "ad or tracker blocked on this page" : "ads and trackers blocked on this page")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Divider()

            HStack {
                Text("\(stats.total.formatted()) blocked in total")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Ad Blocker Settings…") { SettingsOpener.open(tab: .adBlocker) }
                    .buttonStyle(.link)
                    .font(.system(size: 11.5))
            }
        }
        .padding(16)
        .frame(width: 300)
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
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .withinWindow
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
