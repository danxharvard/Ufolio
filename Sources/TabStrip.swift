import SwiftUI
import AppKit

/// The window's two shades: the frame the tabs sit on, and the toolbar the selected tab
/// flows into. A Stealth window tints both.
enum Chrome {
    /// Frosted: a light veil over the window's translucent backdrop, so the desktop shows
    /// softly through. The selected tab uses exactly the same veil, so the two always match.
    static let toolbar = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(white: 1, alpha: 0.045) : NSColor(white: 1, alpha: 0.38)
    })
    static let tabBarHeight: CGFloat = 38

    /// A tinted look (Stealth windows): toolbar, tab row and light or dark text.
    struct Tint {
        let toolbar: Color
        let frame: Color
        let scheme: ColorScheme
    }

}

/// The tab row in the title bar, beside the window buttons: the selected tab is a raised
/// "folder tab" joined to the toolbar below; the others are quiet titles with thin dividers.
struct WindowTabBar: View {
    @ObservedObject var model: BrowserModel
    var toolbarColor: Color = Chrome.toolbar
    var leadingInset: CGFloat = 80
    @State private var hoveredID: UUID?
    static let pinnedWidth: CGFloat = 46
    private var spaceWidth: CGFloat { model.isPrivate ? 0 : 34 }
    /// Drag to reorder: the tab being dragged and how far it is from its slot.
    @State private var draggingID: UUID?
    @State private var dragOffset: CGFloat = 0
    @State private var slotsMoved: CGFloat = 0
    /// Closing tabs one after another: the widths stay put while the pointer is in the tab row, so
    /// the next tab's close button is right under it (as in Safari), and settle once it leaves.
    @State private var pointerInRow = false
    @State private var heldSizes: (selected: CGFloat, other: CGFloat)?

    var body: some View {
        GeometryReader { geo in
            let all = model.visibleTabs
            let selectedID = model.selectedTab?.id
            // Pinned tabs are small fixed icons; the rest share what's left.
            let pinnedCount = all.filter(\.isPinned).count
            let room = geo.size.width - leadingInset - 44 - 24 - spaceWidth - CGFloat(pinnedCount) * Self.pinnedWidth
            // Too many to fit even at their narrowest: show the ones around the current tab, and
            // a "+N" menu for the rest (they used to run off the edge, out of reach).
            let layout = Self.fit(all, selectedID: selectedID, room: room)
            let tabs = layout.shown
            let sizes = layout.hidden.isEmpty ? (heldSizes ?? layout.sizes) : layout.sizes
            let width = sizes.other
            // Bottom-aligned, so every tab sits right on the toolbar below it.
            HStack(alignment: .bottom, spacing: 0) {
                Color.clear.frame(width: leadingInset, height: 1)
                if !model.isPrivate {
                    SpaceButton(model: model)
                        .padding(.trailing, 4)
                        .frame(height: Chrome.tabBarHeight, alignment: .center)
                        .offset(y: 2)   // level with the window buttons
                }
                ForEach(Array(tabs.enumerated()), id: \.element.id) { index, tab in
                    let next = index + 1 < tabs.count ? tabs[index + 1] : nil
                    let divider = next != nil && tab.id != selectedID && next?.id != selectedID
                        && hoveredID != tab.id && hoveredID != next?.id
                    let dragging = draggingID == tab.id
                    ChromeTab(model: model, inSplit: model.isInSplit(tab), tab: tab, isSelected: tab.id == selectedID,
                              width: tab.isPinned ? Self.pinnedWidth : tab.id == selectedID ? sizes.selected : width,
                              showsDivider: divider && draggingID == nil, fill: toolbarColor, hoveredID: $hoveredID)
                        .offset(x: dragging ? dragOffset : 0)
                        // The dragged tab follows the pointer exactly; the others slide out of its way.
                        .transaction { if dragging { $0.animation = nil } }
                        .zIndex(dragging ? 2 : tab.id == selectedID ? 1 : 0)
                        // New tabs grow in from the tab row; closed ones shrink away.
                        .transition(.asymmetric(insertion: .scale(scale: 0.85, anchor: .bottom).combined(with: .opacity),
                                                removal: .opacity.animation(.easeOut(duration: 0.12))))
                        .gesture(reorderGesture(for: tab, width: width))
                }
                if !layout.hidden.isEmpty {
                    OverflowTabsButton(model: model, tabs: layout.hidden)
                        .padding(.leading, 4)
                        .padding(.bottom, 3)
                }
                NewTabButton { model.newTab(focus: true) }
                    .padding(.leading, 6)
                    .padding(.bottom, 3)
                Spacer(minLength: 0)
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .bottomLeading)
            .onChange(of: all.count) { old, new in
                // A tab closed under the pointer: keep the sizes from before (they still fit).
                if new < old, pointerInRow, heldSizes == nil, Self.fit(all, selectedID: selectedID, room: room).hidden.isEmpty {
                    heldSizes = Self.widths(room: room, count: all.filter { !$0.isPinned }.count + (old - new))
                } else if new > old {
                    heldSizes = nil
                }
            }
        }
        .frame(height: Chrome.tabBarHeight)
        .onHover { inside in
            pointerInRow = inside
            if !inside, heldSizes != nil { withAnimation(.spring(response: 0.28, dampingFraction: 0.88)) { heldSizes = nil } }
        }
        .background(
            // Empty space in the tab row moves the window, and a double-click zooms it.
            Color.clear
                .contentShape(Rectangle())
                .gesture(WindowDragGesture())
                .simultaneousGesture(TapGesture(count: 2).onEnded { model.window?.performZoom(nil) })
        )
        .animation(.spring(response: 0.28, dampingFraction: 0.88), value: model.visibleTabs.map(\.id))
    }

    /// Which tabs the row shows, and how wide. Pinned tabs always show. When the others can't all
    /// fit at their narrowest, a run of them around the selected tab shows (the selected one with
    /// room for its title) and the rest go in the "+N" menu.
    static func fit(_ all: [BrowserTab], selectedID: UUID?, room: CGFloat)
        -> (shown: [BrowserTab], hidden: [BrowserTab], sizes: (selected: CGFloat, other: CGFloat)) {
        let pinned = all.filter(\.isPinned), others = all.filter { !$0.isPinned }
        let sizes = widths(room: room, count: others.count)
        let needed = others.isEmpty ? 0 : sizes.selected + CGFloat(others.count - 1) * sizes.other
        guard needed > room + 1, others.count > 1 else { return (all, [], sizes) }
        let overflowButton: CGFloat = 40, minOther: CGFloat = 36, selectedWidth: CGFloat = 120
        let capacity = max(1, min(others.count, Int((room - overflowButton - selectedWidth) / minOther) + 1))
        let current = others.firstIndex { $0.id == selectedID } ?? 0
        let start = max(0, min(current - (capacity - 1) / 2, others.count - capacity))
        let shown = Array(others[start..<start + capacity])
        let hidden = Array(others[..<start]) + Array(others[(start + capacity)...])
        return (pinned + shown, hidden, (selected: selectedWidth, other: minOther))
    }

    /// Tab widths: shared equally while there's room; when crowded, the selected tab keeps
    /// enough room for its title and the others shrink towards icons.
    static func widths(room: CGFloat, count: Int) -> (selected: CGFloat, other: CGFloat) {
        guard count > 0 else { return (0, 0) }
        let even = min(240, room / CGFloat(count))
        guard even < 150, count > 1 else { return (max(even, 40), max(even, 40)) }
        let selected = min(180, max(even, room - CGFloat(count - 1) * 40))
        let other = max(36, (room - selected) / CGFloat(count - 1))
        return (selected, other)
    }

    private func reorderGesture(for tab: BrowserTab, width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                if draggingID == nil {
                    draggingID = tab.id
                    slotsMoved = 0
                    if model.selectedID != tab.id { model.selectedID = tab.id }
                }
                let tabs = model.visibleTabs
                guard draggingID == tab.id, let index = tabs.firstIndex(where: { $0 === tab }) else { return }
                // A pinned tab is narrower: it swaps places after half its own width.
                let slot = tab.isPinned ? Self.pinnedWidth : width
                var offset = value.translation.width - slotsMoved * slot
                // Past halfway over a neighbour: swap places with it. Only counted if it really
                // moved: a tab can't pass the pinned ones (or they it), and counting the refused
                // move made the tab jump a whole slot away from the pointer.
                func moved(to target: Int) -> Bool {
                    model.moveTab(from: index, to: target)
                    return model.visibleTabs.firstIndex(where: { $0 === tab }) == target
                }
                if offset > slot / 2, index < tabs.count - 1, moved(to: index + 1) {
                    slotsMoved += 1
                    offset -= slot
                } else if offset < -slot / 2, index > 0, moved(to: index - 1) {
                    slotsMoved -= 1
                    offset += slot
                }
                dragOffset = offset
            }
            .onEnded { _ in
                // Settle into its new slot.
                withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                    dragOffset = 0
                    draggingID = nil
                }
                slotsMoved = 0
            }
    }
}

private struct ChromeTab: View {
    /// Not observed: a tab only needs redrawing when its own details change (or what's passed in),
    /// not every time anything in the window changes.
    let model: BrowserModel
    let inSplit: Bool
    @ObservedObject var tab: BrowserTab
    let isSelected: Bool
    let width: CGFloat
    let showsDivider: Bool
    let fill: Color
    @Binding var hoveredID: UUID?

    private var hovering: Bool { hoveredID == tab.id }
    private var showsClose: Bool { (isSelected || hovering) && width > 96 && !tab.isPinned }
    /// Narrow tabs show just their icon, rather than a couple of letters and "…".
    private var showsTitle: Bool { width > 84 && !tab.isPinned }

    var body: some View {
        HStack(spacing: 7) {
            Group {
                if tab.isLoading && tab.url != nil {
                    ProgressView().controlSize(.mini)
                } else if tab.url == nil {
                    Image(systemName: "moon.stars")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                } else {
                    Favicon(url: tab.url, size: 15)
                }
            }
            .frame(width: 16, height: 16)
            .overlay(alignment: .bottomTrailing) {
                // Pinned tabs show sound as a small dot on their icon.
                if tab.isPinned && (tab.isPlayingAudio || tab.isMuted) {
                    Circle().fill(tab.isMuted ? Color.secondary : Color.accentColor).frame(width: 6, height: 6).offset(x: 3, y: 3)
                }
            }
            if showsTitle {
                if inSplit {
                    Image(systemName: "rectangle.split.2x1")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }
                Text(tab.displayTitle)
                    .font(.system(size: 12.5, weight: isSelected ? .medium : .regular))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .opacity(tab.isAsleep ? 0.55 : 1)
                Spacer(minLength: 0)
            }
            if (tab.isPlayingAudio || tab.isMuted) && showsTitle {
                Button { tab.toggleMute() } label: {
                    Image(systemName: tab.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(tab.isMuted ? Color.secondary : Color.accentColor)
                        .frame(width: 18, height: 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            if showsClose {
                Button { model.close(tab) } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 16, height: 16)
                        .background(Circle().fill(Color.primary.opacity(0.08)))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, showsTitle ? 12 : 0)
        .frame(width: width, height: 31)
        .background {
            if isSelected {
                // No drop shadow: under a frosted (see-through) fill it would show through and
                // make the tab darker than the toolbar. A fine edge outlines it instead.
                TabShape(foot: 8, radius: 10)
                    .fill(fill)
                    .overlay(TabEdge(foot: 8, radius: 10).stroke(Color.primary.opacity(0.1), lineWidth: 0.5))
                    .padding(.horizontal, -8)
            } else if hovering {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.07))
                    .padding(.horizontal, 3)
                    .padding(.top, 2)
                    .padding(.bottom, 4)
            }
        }
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Color.primary.opacity(0.16))
                .frame(width: 1, height: 16)
                .padding(.bottom, 2)
                .opacity(showsDivider ? 1 : 0)
        }
        .contentShape(Rectangle())
        .onTapGesture { model.selectedID = tab.id }
        .onHover { inside in
            if inside { hoveredID = tab.id } else if hoveredID == tab.id { hoveredID = nil }
            model.pointerOverTab(tab, inside)   // a middle-click closes the tab under the pointer
        }
        // No tooltips on tabs or their buttons: macOS's tooltip timer could reach a tab that had
        // just been closed under the pointer and crash Ufolio (a SwiftUI fault).
        .contextMenu { TabMenuItems(model: model, tab: tab) }
        .tabPreview(tab, selected: isSelected, edge: .bottom)
        .animation(.snappy(duration: 0.16), value: hovering)
    }
}

/// A tab's right-click menu (the same for tabs along the top and down the side).
struct TabMenuItems: View {
    // Plain references, not observed: macOS can keep a menu's contents after the row redraws,
    // and an observing menu would keep closed tabs (and their pages) in memory. The tab row
    // itself observes the tab, so the menu is rebuilt whenever anything it shows changes.
    let model: BrowserModel
    let tab: BrowserTab
    var vertical = false

    var body: some View {
        Button { model.newTab(focus: true) } label: { Label("New Tab", systemImage: "plus.square") }
        Divider()
        if model.isInSplit(tab) {
            Button { model.closeSplit(keeping: tab.id) } label: { Label("Close Split View", systemImage: "rectangle") }
        } else if tab.id == model.selectedTab?.id {
            Button { model.openSplit() } label: { Label("Open Split View with New Tab", systemImage: "rectangle.split.2x1") }
        } else {
            Button { model.openSplit(with: tab) } label: { Label("Open in Split View", systemImage: "rectangle.split.2x1") }
        }
        Button { model.togglePin(tab) } label: { Label(tab.isPinned ? "Unpin Tab" : "Pin Tab", systemImage: tab.isPinned ? "pin.slash" : "pin") }
        if Prefs.bool(Prefs.autoPictureInPicture), let host = tab.host {
            let off = AutoPictureInPicture.isOff(for: host)
            Button { AutoPictureInPicture.setOff(!off, for: host) } label: {
                Label(off ? "Pop Out Videos on This Site" : "Don’t Pop Out Videos on This Site", systemImage: "pip")
            }
        }
        if !model.isPrivate, tab.url != nil, !DockedSites.shared.isDocked(tab.url) {
            Button { model.dock(tab) } label: { Label("Dock This Site", systemImage: "sidebar.right") }
        }
        if !model.isPrivate && SpaceStore.shared.spaces.count > 1 {
            Menu {
                ForEach(SpaceStore.shared.spaces.filter { $0.id != tab.spaceID }) { space in
                    Button { model.move(tab, toSpace: space.id) } label: { Label(space.name, systemImage: space.symbol) }
                }
            } label: { Label("Move to Orbit", systemImage: "square.stack.3d.up") }
        }
        Button { tab.toggleMute() } label: { Label(tab.isMuted ? "Unmute Tab" : "Mute Tab", systemImage: tab.isMuted ? "speaker.wave.2" : "speaker.slash") }
        Button { tab.toggleJavaScript() } label: { Label(tab.javaScriptOff ? "Turn On JavaScript in This Tab" : "Turn Off JavaScript in This Tab", systemImage: "curlybraces") }
        if tab.url != nil {
            Divider()
            Button { SiteForgetter.confirmAndForget(tab) } label: { Label("Forget This Site…", systemImage: "eraser") }
        }
        Divider()
        Button { model.close(tab) } label: { Label("Close Tab", systemImage: "xmark") }
        Button {
            // Pinned tabs stay, as in Safari and Chrome.
            for other in model.visibleTabs where other !== tab && !other.isPinned { model.close(other) }
        } label: { Label("Close Other Tabs", systemImage: "xmark.square") }
        Button {
            let mine = model.visibleTabs
            if let i = mine.firstIndex(where: { $0 === tab }) {
                for other in mine.suffix(from: i + 1) where !other.isPinned { model.close(other) }
            }
        } label: { Label(vertical ? "Close Tabs Below" : "Close Tabs to the Right", systemImage: vertical ? "arrow.down.to.line" : "arrow.right.to.line") }
        }
}

/// "+N": the tabs that don't fit in the row, as a menu.
private struct OverflowTabsButton: View {
    let model: BrowserModel
    let tabs: [BrowserTab]
    @State private var hovering = false

    var body: some View {
        Menu {
            ForEach(tabs, id: \.id) { tab in
                Button(tab.displayTitle) { model.selectedID = tab.id }
            }
        } label: {
            Text("+\(tabs.count)")
                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .frame(minWidth: 30, minHeight: 26)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.primary.opacity(hovering ? 0.08 : 0.04)))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .onHover { hovering = $0 }
    }
}

private struct NewTabButton: View {
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 26)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.primary.opacity(hovering ? 0.08 : 0)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("New Tab (⌘T)")
    }
}

/// A folder tab: rounded top corners and outward-curving feet that melt into the toolbar.
struct TabShape: Shape {
    var foot: CGFloat
    var radius: CGFloat

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let f = foot, r = radius
        p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.minX + f, y: rect.maxY - f), control: CGPoint(x: rect.minX + f, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX + f, y: rect.minY + r))
        p.addQuadCurve(to: CGPoint(x: rect.minX + f + r, y: rect.minY), control: CGPoint(x: rect.minX + f, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - f - r, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - f, y: rect.minY + r), control: CGPoint(x: rect.maxX - f, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - f, y: rect.maxY - f))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.maxY), control: CGPoint(x: rect.maxX - f, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

/// The selected tab's outline: its sides and top only, so no line is drawn where it meets the toolbar.
struct TabEdge: Shape {
    var foot: CGFloat
    var radius: CGFloat

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let f = foot, r = radius
        p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.minX + f, y: rect.maxY - f), control: CGPoint(x: rect.minX + f, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX + f, y: rect.minY + r))
        p.addQuadCurve(to: CGPoint(x: rect.minX + f + r, y: rect.minY), control: CGPoint(x: rect.minX + f, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - f - r, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - f, y: rect.minY + r), control: CGPoint(x: rect.maxX - f, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - f, y: rect.maxY - f))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.maxY), control: CGPoint(x: rect.maxX - f, y: rect.maxY))
        return p
    }
}

/// Lines the red, yellow and green window buttons up with the tabs.
enum TrafficLights {
    static func align(in window: NSWindow?, rowHeight: CGFloat = Chrome.tabBarHeight) {
        guard let window, !window.styleMask.contains(.fullScreen),
              let close = window.standardWindowButton(.closeButton),
              let titlebar = close.superview else { return }
        let buttons: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
        // Centre of the tabs, measured from the top of the window.
        let centre = rowHeight - 31 / 2 - 1
        for (i, type) in buttons.enumerated() {
            guard let button = window.standardWindowButton(type) else { continue }
            let size = button.frame.size
            let y = titlebar.isFlipped ? centre - size.height / 2
                                       : titlebar.bounds.height - centre - size.height / 2
            let x = 13 + CGFloat(i) * 20
            let origin = NSPoint(x: x, y: y)
            if button.frame.origin != origin { button.setFrameOrigin(origin) }   // moving them re-lays out the title bar
        }
    }
}
