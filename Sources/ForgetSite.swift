import AppKit
import SwiftUI
import WebKit

/// Forget This Site (right-click a tab): wipes everything Hush and WebKit keep about a site.
enum SiteForgetter {
    /// What the confirmation card shows.
    struct Request: Equatable {
        let site: String
        let icon: URL?
        let tabs: Int
        let pages: Int
    }

    /// Asks first (with a card over the window), then forgets the site of the given tab.
    static func confirmAndForget(_ tab: BrowserTab) {
        guard let model = tab.model, let host = tab.url?.host else { return }
        let site = Domains.site(host)
        let pages = model.isPrivate ? 0 : HistoryStore.shared.entries.values.filter { Domains.site($0.url.host ?? "") == site }.count
        let tabs = model.tabs.filter { Domains.site($0.url?.host ?? "") == site }.count
        model.forgetRequest = Request(site: site, icon: tab.url, tabs: tabs, pages: pages)
    }

    static func forget(_ site: String, in model: BrowserModel) {
        // Website data (cookies, storage, caches) in this window's store.
        let store = model.dataStore
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        store.fetchDataRecords(ofTypes: types) { records in
            let matching = records.filter { Domains.site($0.displayName) == site }
            store.removeData(ofTypes: types, for: matching) {}
        }
        if !model.isPrivate {
            HistoryStore.shared.remove(site: site)
            RecentlyClosed.shared.remove(site: site)
            SitePermissions.shared.forget(site: site)
            BookmarkOffer.shared.forget(site: site)
        }
        // Close the site's tabs (a new tab replaces them if nothing else is left).
        let tabs = model.tabs.filter { Domains.site($0.url?.host ?? "") == site }
        if tabs.count == model.tabs.count { model.newTab(focus: true) }
        for tab in tabs { model.close(tab, remember: false) }
    }
}

/// The Forget This Site card: a small animated scene, one line on what happens, and a clear choice.
struct ForgetSiteCard: View {
    let request: SiteForgetter.Request
    let onForget: () -> Void
    let onCancel: () -> Void

    static let red = [Color(red: 1.0, green: 0.42, blue: 0.38), Color(red: 0.86, green: 0.20, blue: 0.24)]

    var body: some View {
        VStack(spacing: 0) {
            ForgetScene(icon: request.icon)
                .frame(height: 118)

            VStack(spacing: 6) {
                Text("Forget \(request.site)?")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .multilineTextAlignment(.center)
                Text("Signs you out and removes its history, permissions and \(request.tabs == 1 ? "open tab" : "\(request.tabs) open tabs").")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Label("Bookmarks and passwords are kept", systemImage: "checkmark.shield.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }
            .padding(.horizontal, 22)

            HStack(spacing: 8) {
                Button(action: onCancel) { Text("Cancel").frame(maxWidth: .infinity) }
                    .keyboardShortcut(.cancelAction)
                Button(action: onForget) { Text("Forget").fontWeight(.semibold).frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent)
                    .tint(Self.red[1])
                    .keyboardShortcut(.defaultAction)
            }
            .controlSize(.large)
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 18)
        }
        .frame(width: 300)
    }
}

/// The site's icon with stars drifting past, while little bits of its data float away and fade,
/// in the same style as the Hush Guard panel.
private struct ForgetScene: View {
    let icon: URL?
    @AppStorage(Prefs.reduceMotion) private var reduceMotion = false

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { context in
            let t = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
            GeometryReader { geo in
                let center = CGPoint(x: geo.size.width / 2, y: geo.size.height * 0.56)
                ZStack {
                    GuardStars(on: true, t: t, size: geo.size)
                    // A soft glow behind the icon.
                    Circle()
                        .fill(RadialGradient(colors: [ForgetSiteCard.red[0].opacity(0.30), .clear], center: .center, startRadius: 0, endRadius: 52))
                        .frame(width: 104, height: 104)
                        .position(center)
                    // Bits of the site's data drifting away and fading.
                    ForEach(0..<9, id: \.self) { i in
                        let phase = ((t * 0.32) + Double(i) / 9).truncatingRemainder(dividingBy: 1)
                        let angle = Double(i) * 2.399 + 0.6
                        let distance = 26 + phase * 38
                        Circle()
                            .fill(i % 3 == 0 ? ForgetSiteCard.red[0] : Color(red: 0.70, green: 0.60, blue: 1.0))
                            .frame(width: 5 - 2.5 * phase, height: 5 - 2.5 * phase)
                            .opacity((1 - phase) * 0.9)
                            .position(x: center.x + cos(angle) * distance, y: center.y + sin(angle) * distance * 0.8)
                    }
                    // The site, gently bobbing.
                    ZStack(alignment: .bottomTrailing) {
                        Favicon(url: icon, size: 34)
                            .frame(width: 54, height: 54)
                            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.regularMaterial))
                            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
                            .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
                        IconTile(symbol: "eraser.fill", colors: ForgetSiteCard.red, size: 22)
                            .rotationEffect(.degrees(sin(t * 2.2) * 8))
                            .offset(x: 7, y: 7)
                    }
                    .position(x: center.x, y: center.y + sin(t * 1.4) * 2.5)
                }
            }
        }
    }
}
