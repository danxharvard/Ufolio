import SwiftUI

/// Little notices: a small frosted card that slides up in the page's corner to show a win, such as
/// how many ads Force Field stopped or a page that opened instantly, then fades away by itself
/// after a few seconds (or on a click). Rare by design: one at a time, a few minutes apart, and
/// Force Field's at most once per site. Settings › Appearance › Little notices turns them off.
/// The card exists only while it's showing.
final class NoticeCenter: ObservableObject {
    struct Notice: Identifiable, Equatable {
        let id = UUID()
        let art: String        // a toolbar tile's name, or "icon" for Ufolio's own
        let title: String
        let detail: String
    }

    @Published private(set) var current: Notice?
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
        post(Notice(art: "adblock", title: "Force Field", detail: "\(blocked.formatted()) ads and trackers stopped on this page"))
    }

    /// A page Ufolio had loaded ahead was swapped in (at most every ten minutes).
    func instant() {
        guard Self.allowed, Date().timeIntervalSince(Self.lastInstant) > 600 else { return }
        Self.lastInstant = Date()
        post(Notice(art: "icon", title: "Instant pages", detail: "Opened instantly: it loaded before you clicked"))
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
            self.post(Notice(art: "adblock", title: "Force Field", detail: "32 ads and trackers stopped on this page"))
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

    private var image: NSImage? {
        notice.art == "icon" ? NSApp.applicationIconImage
            : Bundle.main.url(forResource: notice.art, withExtension: "png").flatMap(NSImage.init(contentsOf:))
    }

    var body: some View {
        HStack(spacing: 11) {
            if let image {
                Image(nsImage: image).resizable().interpolation(.high)
                    .frame(width: 30, height: 30)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
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
