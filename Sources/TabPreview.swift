import SwiftUI
import AppKit

/// A small preview of a tab's page when you rest the pointer on its tab (along the top or down
/// the side). It shows the picture taken when you last left that tab, or the one from when it
/// went to sleep: the page itself is never woken or kept running for it.
struct TabPreviewOnHover: ViewModifier {
    @ObservedObject var tab: BrowserTab
    let isSelected: Bool
    let edge: Edge
    @AppStorage(Prefs.tabPreviews) private var enabled = true
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .onHover { inside in
                hovering = inside
                if !inside { TabPreviewPanel.hide(for: tab.id); return }
                guard enabled, !isSelected else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    // Not while a button is held (dragging tabs to reorder them).
                    guard hovering, !isSelected, tab.hasPreview, NSEvent.pressedMouseButtons == 0,
                          let window = tab.model?.window else { return }
                    TabPreviewPanel.show(tab, edge: edge, in: window)
                }
            }
            .onChange(of: isSelected) { _, selected in if selected { TabPreviewPanel.hide(for: tab.id) } }
            .onDisappear { TabPreviewPanel.hide(for: tab.id) }
    }
}

/// The preview's own small window: it never becomes the active window and ignores the pointer,
/// like a tooltip. (A popover could take the keyboard away from the address bar or the page you
/// were typing in, just by resting the pointer on a tab.)
enum TabPreviewPanel {
    private static var panel: NSPanel?
    private static var shownFor: UUID?

    static func show(_ tab: BrowserTab, edge: Edge, in window: NSWindow) {
        let panel = self.panel ?? make()
        self.panel = panel
        let host = NSHostingView(rootView: TabPreviewCard(tab: tab)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.12))))
        let size = host.fittingSize
        panel.contentView = host
        // Placed from where the pointer is when it appears (no tab has to keep track of where it
        // is): under the tab bar for tabs along the top, beside the column for tabs down the side.
        let mouse = NSEvent.mouseLocation
        let frame = window.frame
        var origin = edge == .trailing
            ? NSPoint(x: frame.minX + Prefs.double(Prefs.sideTabsWidth) + 8, y: mouse.y - size.height / 2)
            : NSPoint(x: mouse.x - size.width / 2, y: frame.maxY - Chrome.tabBarHeight - size.height - 4)
        if let visible = window.screen?.visibleFrame {
            origin.x = min(max(origin.x, visible.minX + 4), visible.maxX - size.width - 4)
            origin.y = min(max(origin.y, visible.minY + 4), visible.maxY - size.height - 4)
        }
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        if panel.parent !== window { panel.parent?.removeChildWindow(panel); window.addChildWindow(panel, ordered: .above) }
        panel.orderFront(nil)
        shownFor = tab.id
    }

    static func hide(for id: UUID) {
        guard shownFor == id, let panel else { return }
        shownFor = nil
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
        panel.contentView = nil
    }

    private static func make() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = true
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.collectionBehavior = [.transient, .ignoresCycle]
        return panel
    }
}

private struct TabPreviewCard: View {
    @ObservedObject var tab: BrowserTab

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            if let image = tab.previewImage {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 260, height: 160, alignment: .top)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.primary.opacity(0.1)))
            }
            Text(tab.displayTitle).font(.system(size: 12, weight: .semibold)).lineLimit(1)
            HStack(spacing: 5) {
                if tab.isAsleep { Image(systemName: "moon.zzz.fill").foregroundStyle(.secondary) }
                Text(tab.url?.host?.strippingWWW ?? "").lineLimit(1)
                if tab.isAsleep { Text("· asleep") }
            }
            .font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(width: 280)
    }
}

extension View {
    func tabPreview(_ tab: BrowserTab, selected: Bool, edge: Edge) -> some View {
        modifier(TabPreviewOnHover(tab: tab, isSelected: selected, edge: edge))
    }
}
