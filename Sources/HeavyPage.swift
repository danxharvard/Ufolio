import SwiftUI

/// "This page is using a lot of energy": a quiet bar on a page that's kept the processor busy for
/// a while, with one-click fixes.
struct HeavyPageBar: View {
    @ObservedObject var tab: BrowserTab

    var body: some View {
        if tab.isPagePaused {
            bar(symbol: "pause.circle.fill", text: "This page is paused, so it isn’t using any energy.") {
                Button("Resume") { tab.pausePage(false) }
            }
        } else if tab.isHeavy {
            bar(symbol: "bolt.fill", text: "This page is using a lot of energy.") {
                Button("Pause Page") { tab.pausePage(true) }
                Button("Reload") { tab.isHeavy = false; tab.reload() }
                Button("Put to Sleep") { tab.isHeavy = false; tab.forceSleep() }
                Button { tab.isHeavy = false; tab.heavyDismissed = true } label: { Image(systemName: "xmark").font(.system(size: 9, weight: .bold)) }
                    .buttonStyle(.plain).accessibilityLabel("Dismiss")
            }
        }
    }

    /// In the same style as Ufolio's other bars: a hairline above, an icon tile, sliding in.
    private func bar<Buttons: View>(symbol: String, text: String, @ViewBuilder buttons: () -> Buttons) -> some View {
        VStack(spacing: 0) {
            Hairline()
            HStack(spacing: 10) {
                IconTile(symbol: symbol, colors: [Color(red: 1.0, green: 0.72, blue: 0.25), Color(red: 0.95, green: 0.50, blue: 0.12)], size: 22)
                Text(text).font(.system(size: 12.5, weight: .medium)).lineLimit(1)
                Spacer(minLength: 8)
                buttons().controlSize(.small)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
        }
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}
