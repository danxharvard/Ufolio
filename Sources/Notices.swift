import SwiftUI

/// Little notices: a small frosted card that slides up in the page's corner to show a win, such as
/// how many ads Force Field stopped or a page that opened instantly, then fades away by itself
/// after a few seconds (or on a click). Rare by design: one at a time, a few minutes apart, and
/// Force Field's at most once per site. Settings › Appearance › Little notices turns them off.
/// The card exists only while it's showing.
final class NoticeCenter: ObservableObject {
    struct Notice: Identifiable, Equatable {
        let id = UUID()
        let symbol: String     // an SF Symbol, in a small coloured tile
        let colors: [Color]
        let title: String
        let detail: String
    }

    @Published private(set) var current: Notice?
    private static let green = [Color(red: 0.30, green: 0.82, blue: 0.45), Color(red: 0.12, green: 0.60, blue: 0.30)]
    private static let blue = [Color(red: 0.30, green: 0.62, blue: 1.0), Color(red: 0.10, green: 0.42, blue: 0.95)]
    private var hide: DispatchWorkItem?
    private static var lastShown = Date.distantPast
    private static var forceFieldSites: Set<String> = []
    private static var lastInstant = Date.distantPast

    private static var allowed: Bool {
        Prefs.bool(Prefs.showNotices) && Date().timeIntervalSince(lastShown) > 180
    }

    /// After a page loaded with a lot blocked (once per site per session).
    func forceField(blocked: Int, site: String) {
        guard blocked >= 15, !site.isEmpty, Self.allowed, !Self.forceFieldSites.contains(site) else { return }
        Self.forceFieldSites.insert(site)
        post(Notice(symbol: "shield.lefthalf.filled", colors: Self.green, title: "Force Field", detail: "\(blocked.formatted()) ads and trackers stopped on this page"))
    }

    /// A page Ufolio had loaded ahead was swapped in (at most every ten minutes).
    func instant() {
        guard Self.allowed, Date().timeIntervalSince(Self.lastInstant) > 600 else { return }
        Self.lastInstant = Date()
        post(Notice(symbol: "bolt.fill", colors: Self.blue, title: "Instant pages", detail: "Opened instantly: it loaded before you clicked"))
    }

    private func post(_ notice: Notice) {
        Self.lastShown = Date()
        withAnimation(FluidSwitch.spring) { current = notice }
        hide?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.dismiss() }
        hide = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.4, execute: work)
    }

    /// Testing only (UFOLIO_NOTICE_TEST=1): a sample notice a few seconds after the window opens.
    func showSampleIfAsked() {
        guard ProcessInfo.processInfo.environment["UFOLIO_NOTICE_TEST"] != nil else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            self.post(Notice(symbol: "shield.lefthalf.filled", colors: Self.green, title: "Force Field", detail: "32 ads and trackers stopped on this page"))
        }
    }

    func dismiss() {
        hide?.cancel()
        withAnimation(.easeOut(duration: 0.25)) { current = nil }
    }
}

/// Where notices appear: the page's bottom-right corner.
struct NoticeHost: View {
    @ObservedObject var center: NoticeCenter

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if let notice = center.current {
                NoticeCard(notice: notice)
                    .onTapGesture { center.dismiss() }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(14)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
    }
}

private struct NoticeCard: View {
    let notice: NoticeCenter.Notice

    var body: some View {
        HStack(spacing: 11) {
            IconTile(symbol: notice.symbol, colors: notice.colors, size: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(notice.title).font(.system(size: 12.5, weight: .semibold))
                Text(notice.detail).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer(minLength: 6)
            Text("now").font(.system(size: 10.5)).foregroundStyle(.tertiary)
                .frame(maxHeight: .infinity, alignment: .top)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .frame(width: 290)
        .fixedSize(horizontal: false, vertical: true)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.primary.opacity(0.1)))
        .shadow(color: .black.opacity(0.22), radius: 14, y: 6)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isStaticText)
    }
}
