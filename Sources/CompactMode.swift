import SwiftUI

/// Compact mode (⌃⌘C, View menu): the tabs and toolbar (or the tab column) step aside so the
/// page fills the window. Push the pointer to the window's top edge (or left edge, with tabs
/// down the side) and they slide back in over the page, frosted as ever; they go again when the
/// pointer leaves. They also come back while you use the address bar (⌘L).
enum CompactMode {
    static var isOn: Bool { Prefs.bool(Prefs.compactMode) }

    static func toggle() {
        FeatureUsage.mark(.compact)
        UserDefaults.standard.set(!isOn, forKey: Prefs.compactMode)
    }

    /// The window buttons sit over the page in Compact mode: shown only with the tabs.
    static func showWindowButtons(_ show: Bool, in window: NSWindow?) {
        for type: NSWindow.ButtonType in [.closeButton, .miniaturizeButton, .zoomButton] {
            if let button = window?.standardWindowButton(type), button.isHidden == show { button.isHidden = !show }
        }
    }
}

/// A strip along one edge of the window that brings hidden chrome back when the pointer reaches
/// it, and the chrome itself while it's showing.
struct CompactReveal<Content: View>: View {
    let edge: Edge                    // .top or .leading
    @Binding var revealed: Bool
    /// Keeps it showing although the pointer has left (typing in the address bar, say).
    let keepOpen: () -> Bool
    @ViewBuilder let content: () -> Content
    @State private var hideWork: DispatchWorkItem?
    @State private var inside = false

    var body: some View {
        ZStack(alignment: edge == .top ? .top : .leading) {
            if revealed {
                content()
                    // Clicks on the chrome's empty parts stay with it, never the page underneath.
                    .background(ClickBlocker())
                    .onHover { now in
                        inside = now
                        if now { hideWork?.cancel() } else { hideSoon() }
                    }
                    .transition(.move(edge: edge).combined(with: .opacity))
                    .onAppear { if !inside { hideSoon(after: 1.6) } }
            } else {
                // The sensor: a hair's width along the edge.
                ClickBlocker()
                    .frame(width: edge == .top ? nil : 5, height: edge == .top ? 5 : nil)
                    .frame(maxWidth: edge == .top ? .infinity : nil, maxHeight: edge == .top ? nil : .infinity)
                    .onHover { if $0 { show() } }
            }
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.9), value: revealed)
    }

    private func show() {
        hideWork?.cancel()
        if !revealed { revealed = true }
    }

    private func hideSoon(after delay: TimeInterval = 0.35) {
        hideWork?.cancel()
        let work = DispatchWorkItem {
            guard !inside else { return }
            if keepOpen() { hideSoon(after: 0.6); return }
            revealed = false
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }
}
