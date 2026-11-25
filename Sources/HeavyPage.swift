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

    private func bar<Buttons: View>(symbol: String, text: String, @ViewBuilder buttons: () -> Buttons) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).foregroundStyle(Color.orange)
            Text(text).font(.system(size: 12)).lineLimit(1)
            Spacer()
            buttons().controlSize(.small)
        }
        .padding(.horizontal, 12)
        .frame(height: 30)
    }
}
