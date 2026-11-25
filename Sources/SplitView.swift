import SwiftUI

/// Two tabs side by side in one window. The side you click is the active one: the address
/// bar, Find and the menus act on it.
struct SplitPair: Equatable {
    var left: UUID
    var right: UUID
    func contains(_ id: UUID?) -> Bool { id == left || id == right }
}

struct SplitPages: View {
    @ObservedObject var model: BrowserModel
    let left: BrowserTab
    let right: BrowserTab
    @State private var dragStart: CGFloat?
    /// The ratio while dragging, kept here so only the split redraws (not the whole window);
    /// handed to the window when you let go.
    @State private var dragRatio: CGFloat?

    var body: some View {
        GeometryReader { geo in
            let usable = geo.size.width - 8
            // Each side at least 220 points, or half the room when there isn't that much (a narrow
            // window with a wide side tab bar used to push the right-hand page off the edge).
            let minPane = max(0, min(220, usable / 2))
            let leftWidth = max(minPane, min(usable - minPane, usable * (dragRatio ?? model.splitRatio)))
            HStack(spacing: 0) {
                SplitPane(model: model, tab: left, side: .left)
                    .frame(width: leftWidth)
                // The divider: drag to resize, double-click to make the halves equal.
                ZStack {
                    Color.clear
                    Capsule().fill(Color.primary.opacity(0.22)).frame(width: 3, height: 34)
                }
                .frame(width: 8)
                .contentShape(Rectangle())
                // (A pushed cursor stayed stuck as the resize arrows if Split View closed under the pointer.)
                .pointerStyle(.frameResize(position: .trailing))
                .gesture(DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        let start = dragStart ?? leftWidth
                        if dragStart == nil { dragStart = leftWidth }
                        dragRatio = max(0.2, min(0.8, (start + value.translation.width) / usable))
                    }
                    .onEnded { _ in
                        if let dragRatio { model.splitRatio = dragRatio }
                        dragRatio = nil
                        dragStart = nil
                    })
                .onTapGesture(count: 2) { withAnimation(.easeOut(duration: 0.2)) { model.splitRatio = 0.5 } }
                SplitPane(model: model, tab: right, side: .right)
            }
        }
        .background(Color.primary.opacity(0.06))
    }
}

private struct SplitPane: View {
    enum Side { case left, right }
    @ObservedObject var model: BrowserModel
    @ObservedObject var tab: BrowserTab
    let side: Side

    private var isActive: Bool { model.selectedTab?.id == tab.id }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 7) {
                Group {
                    if tab.url == nil {
                        Image(systemName: "moon.stars").font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                    } else {
                        Favicon(url: tab.url, size: 13)
                    }
                }
                .frame(width: 14, height: 14)
                Text(tab.displayTitle)
                    .font(.system(size: 11.5, weight: isActive ? .semibold : .regular))
                    .foregroundStyle(isActive ? .primary : .secondary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                PaneButton(symbol: side == .left ? "arrow.right.square" : "arrow.left.square",
                           help: model.splitLinksAcross ? "Stop opening links in the other pane" : "Open links in the other pane",
                           active: model.splitLinksAcross) { model.splitLinksAcross.toggle() }
                PaneButton(symbol: "arrow.left.arrow.right", help: "Swap Sides") { model.swapSplit() }
                PaneButton(symbol: "xmark", help: "Close This Side (keeps the tab open)") { model.closeSplit(keeping: side == .left ? model.splitPair?.right : model.splitPair?.left) }
            }
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(isActive ? Color.accentColor.opacity(0.12) : Color.clear)
            .contentShape(Rectangle())
            .onTapGesture { model.selectedID = tab.id }
            TabPageContent(model: model, tab: tab)
                .id(tab.id)
                .overlay {
                    // A link from the other pane is being dragged here: a soft highlight.
                    if tab.isDropTarget {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.accentColor.opacity(0.10))
                            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(Color.accentColor.opacity(0.75), lineWidth: 2.5))
                            .padding(3)
                            .allowsHitTesting(false)
                            .transition(.opacity)
                    }
                }
                .animation(Effects.on ? .easeOut(duration: 0.15) : nil, value: tab.isDropTarget)
        }
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
            .strokeBorder(isActive ? Color.accentColor.opacity(0.7) : Color.primary.opacity(0.08), lineWidth: isActive ? 1.5 : 1))
        .padding(.vertical, 4)
        .padding(side == .left ? .leading : .trailing, 4)
        .onAppear { tab.wakeIfNeeded() }
    }
}

private struct PaneButton: View {
    let symbol: String
    let help: String
    var active = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(active ? Color.accentColor : .secondary)
                .frame(width: 18, height: 18)
                .background(Circle().fill(active ? Color.accentColor.opacity(0.15) : Color.primary.opacity(hovering ? 0.1 : 0)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(help)
    }
}
