import SwiftUI
import WebKit

/// Docked sites: sites you keep beside every page (chat, music, mail), each in a panel that opens
/// from a slim rail at the window's right edge. A docked site loads the first time you open it
/// and then stays loaded (music keeps playing, chats stay connected) until you undock it, or the
/// Mac runs short of memory while it's tucked away. Not in Stealth windows.
struct DockedSite: Codable, Identifiable, Equatable {
    var id = UUID()
    var url: URL
    var title: String
}

final class DockedSites: ObservableObject {
    static let shared = DockedSites()
    static let limit = 8

    @Published private(set) var sites: [DockedSite] = []

    private init() {
        if let data = UserDefaults.standard.data(forKey: Prefs.dockedSites),
           let saved = try? JSONDecoder().decode([DockedSite].self, from: data) {
            sites = Array(saved.prefix(Self.limit))
        }
    }

    /// Docks a site (or returns the one already docked for that website).
    @discardableResult
    func dock(_ url: URL, title: String) -> DockedSite? {
        guard ["http", "https"].contains(url.scheme?.lowercased() ?? ""), let host = url.host else { return nil }
        if let existing = sites.first(where: { $0.url.host == host }) { return existing }
        guard sites.count < Self.limit else { return nil }
        FeatureUsage.mark(.docked)
        let site = DockedSite(url: url, title: title.isEmpty ? host.strippingWWW : String(title.prefix(80)))
        sites.append(site)
        save()
        return site
    }

    func undock(_ site: DockedSite) {
        sites.removeAll { $0.id == site.id }
        save()
        for model in BrowserModel.all.allObjects { model.dockRemoved(site.id) }
    }

    func isDocked(_ url: URL?) -> Bool {
        guard let host = url?.host else { return false }
        return sites.contains { $0.url.host == host }
    }

    private func save() {
        UserDefaults.standard.set(try? JSONEncoder().encode(sites), forKey: Prefs.dockedSites)
    }
}

extension BrowserModel {
    /// Opens a docked site's panel (loading it the first time), or tucks it away if it's open.
    func toggleDock(_ site: DockedSite) {
        guard !isPrivate else { return }
        if dockOpen == site.id { dockOpen = nil; return }
        if dockTabs[site.id] == nil {
            let tab = BrowserTab(model: self, store: currentStore)
            // In this Orbit's profile: its sign-ins, and its history (not the default profile's).
            tab.spaceID = spaceID
            tab.load(site.url)
            dockTabs[site.id] = tab
        }
        dockOpen = site.id
    }

    func dockRemoved(_ id: UUID) {
        if dockOpen == id { dockOpen = nil }
        dockTabs.removeValue(forKey: id)?.tearDown()
    }

    /// Memory running short: docked sites that are tucked away let go of their pages (they
    /// load again when you next open them).
    func releaseHiddenDocks() {
        for (id, tab) in dockTabs where id != dockOpen {
            tab.tearDown()
            dockTabs[id] = nil
        }
    }

    /// Lets go of docked pages: all of them (the window closing, website data cleared), or one
    /// site's (Forget This Site). They load afresh the next time you open them.
    func releaseDocks(site: String? = nil) {
        for (id, tab) in dockTabs where site == nil || Domains.site(tab.url?.host ?? "") == site {
            if dockOpen == id { dockOpen = nil }
            tab.tearDown()
            dockTabs[id] = nil
        }
    }

    /// Switching to an Orbit with another profile (or an Orbit's profile changing): docked pages signed in under the old profile
    /// let go (they load again, in the new profile, when you next open them). A docked chat
    /// used to stay signed in to the other profile's account.
    func releaseDocksFromOtherProfiles() {
        for (id, tab) in dockTabs where tab.dataStore !== currentStore {
            if dockOpen == id { dockOpen = nil }
            tab.tearDown()
            dockTabs[id] = nil
        }
        // Their history goes to this Orbit's profile from now on.
        for tab in dockTabs.values { tab.spaceID = spaceID }
    }

    /// Docks the page in a tab and opens its panel.
    func dock(_ tab: BrowserTab) {
        guard !isPrivate, let url = tab.url, let site = DockedSites.shared.dock(url, title: tab.displayTitle) else { return }
        if dockOpen != site.id { toggleDock(site) }
    }
}

/// The docked panel (if one is open) and the rail of docked sites, at the page's right.
struct DockArea: View {
    @ObservedObject var model: BrowserModel
    @ObservedObject private var store = DockedSites.shared
    @AppStorage("dock.wide") private var wide = false
    /// The window's width, so a panel never takes more than 40% of it (a narrow window's page
    /// was squeezed to almost nothing).
    @State private var windowWidth: CGFloat = 1400

    var body: some View {
        if !model.isPrivate && !store.sites.isEmpty {
            HStack(spacing: 6) {
                if let id = model.dockOpen, let site = store.sites.first(where: { $0.id == id }), let tab = model.dockTabs[id] {
                    DockPanel(model: model, site: site, tab: tab, wide: $wide)
                        .frame(width: min(wide ? 560 : 390, max(260, windowWidth * 0.4)))
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
                DockRail(model: model, sites: store.sites)
            }
            .padding(.leading, 6)
            .animation(.spring(response: 0.3, dampingFraction: 0.88), value: model.dockOpen)
            .onAppear { windowWidth = model.window?.frame.width ?? windowWidth }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResizeNotification)) { note in
                if let window = note.object as? NSWindow, window === model.window { windowWidth = window.frame.width }
            }
        }
    }
}

private struct DockRail: View {
    @ObservedObject var model: BrowserModel
    let sites: [DockedSite]

    var body: some View {
        VStack(spacing: 6) {
            ForEach(sites) { site in
                DockIcon(site: site, open: model.dockOpen == site.id) { model.toggleDock(site) }
                    .contextMenu {
                        Button { model.toggleDock(site) } label: {
                            Label(model.dockOpen == site.id ? "Tuck Away" : "Open", systemImage: "sidebar.right")
                        }
                        Button { model.open(site.url, inNewTab: true) } label: { Label("Open in New Tab", systemImage: "plus.square.on.square") }
                        Divider()
                        Button("Undock", role: .destructive) { DockedSites.shared.undock(site) }
                    }
            }
            if sites.count < DockedSites.limit, let tab = model.selectedTab, tab.url != nil, !DockedSites.shared.isDocked(tab.url) {
                Button { model.dock(tab) } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 30, height: 30)
                        .background(Circle().strokeBorder(Color.primary.opacity(0.15), style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dock This Site")
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .frame(width: 34)
    }
}

private struct DockIcon: View {
    let site: DockedSite
    let open: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Favicon(url: site.url, size: 20)
                .frame(width: 32, height: 32)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.primary.opacity(open ? 0.12 : hovering ? 0.07 : 0)))
                .overlay(alignment: .trailing) {
                    if open { Capsule().fill(Color.accentColor).frame(width: 3, height: 14).offset(x: 5) }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(site.title)
    }
}

private struct DockPanel: View {
    let model: BrowserModel
    let site: DockedSite
    @ObservedObject var tab: BrowserTab
    @Binding var wide: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Favicon(url: tab.url ?? site.url, size: 14)
                Text(tab.displayTitle).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                Spacer(minLength: 6)
                DockButton(symbol: "arrow.clockwise", help: "Reload") { tab.reload() }
                DockButton(symbol: wide ? "arrow.right.to.line" : "arrow.left.to.line", help: wide ? "Narrower" : "Wider") { wide.toggle() }
                DockButton(symbol: "sidebar.right", help: "Tuck Away") { model.toggleDock(site) }
            }
            .padding(.horizontal, 8)
            .frame(height: 30)
            ZStack(alignment: .topLeading) {
                WebViewHost(webView: tab.webView).id(ObjectIdentifier(tab.webView))
                ProgressLine(tab: tab)
            }
            .overlay(PageCorners.shape.strokeBorder(Color.primary.opacity(0.08)).allowsHitTesting(false))
        }
    }
}

private struct DockButton: View {
    let symbol: String
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 22)
                .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Color.primary.opacity(hovering ? 0.09 : 0)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(help)
    }
}
