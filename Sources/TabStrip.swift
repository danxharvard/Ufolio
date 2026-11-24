import SwiftUI
import AppKit

/// The window's two shades: the frame the tabs sit on, and the toolbar the selected tab
/// flows into. Magic Theme can tint the toolbar with the website's own colour.
enum Chrome {
    /// Frosted: a light veil over the window's translucent backdrop, so the desktop shows
    /// softly through. The selected tab uses exactly the same veil, so the two always match.
    static let toolbar = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(white: 1, alpha: 0.045) : NSColor(white: 1, alpha: 0.38)
    })
    static let tabBarHeight: CGFloat = 38

    /// Magic Theme colours for a website's colour: the toolbar in the site's colour, the tab
    /// row a shade deeper, and light or dark text to suit.
    struct Tint {
        let toolbar: Color
        let frame: Color
        let scheme: ColorScheme
    }

    static func tint(for site: NSColor?) -> Tint? {
        guard let c = site?.usingColorSpace(.sRGB) else { return nil }
        func linear(_ v: CGFloat) -> CGFloat { v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        let luminance = 0.2126 * linear(c.redComponent) + 0.7152 * linear(c.greenComponent) + 0.0722 * linear(c.blueComponent)
        let light = luminance > 0.42
        let frame = c.blended(withFraction: light ? 0.10 : 0.18, of: light ? .black : .white) ?? c
        return Tint(toolbar: Color(nsColor: c), frame: Color(nsColor: frame), scheme: light ? .light : .dark)
    }
}

/// Reports the selected tab's website colour to the window (for Magic Theme).
struct SiteColorReader: View {
    @ObservedObject var tab: BrowserTab
    let report: (NSColor?) -> Void

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear { report(tab.siteColor) }
            .onChange(of: tab.siteColor) { _, color in report(color) }
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

    var body: some View {
        GeometryReader { geo in
            let tabs = model.visibleTabs
            let selectedID = model.selectedTab?.id
            // Pinned tabs are small fixed icons; the rest share what's left.
            let pinnedCount = tabs.filter(\.isPinned).count
            let room = geo.size.width - leadingInset - 44 - 24 - spaceWidth - CGFloat(pinnedCount) * Self.pinnedWidth
            let sizes = Self.widths(room: room, count: tabs.count - pinnedCount)
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
                    ChromeTab(model: model, tab: tab, isSelected: tab.id == selectedID,
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
                NewTabButton { model.newTab(focus: true) }
                    .padding(.leading, 6)
                    .padding(.bottom, 3)
                Spacer(minLength: 0)
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .bottomLeading)
        }
        .frame(height: Chrome.tabBarHeight)
        .background(
            // Empty space in the tab row moves the window, and a double-click zooms it.
            Color.clear
                .contentShape(Rectangle())
                .gesture(WindowDragGesture())
                .simultaneousGesture(TapGesture(count: 2).onEnded { model.window?.performZoom(nil) })
        )
        .animation(.spring(response: 0.28, dampingFraction: 0.88), value: model.visibleTabs.map(\.id))
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
                var offset = value.translation.width - slotsMoved * width
                // Past halfway over a neighbour: swap places with it.
                if offset > width / 2, index < tabs.count - 1 {
                    model.moveTab(from: index, to: index + 1)
                    slotsMoved += 1
                    offset -= width
                } else if offset < -width / 2, index > 0 {
                    model.moveTab(from: index, to: index - 1)
                    slotsMoved -= 1
                    offset += width
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
    @ObservedObject var model: BrowserModel
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
                if model.isInSplit(tab) {
                    Image(systemName: "rectangle.split.2x1")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                        .help("In Split View")
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
                .help(tab.isMuted ? "Unmute this tab" : "Mute this tab")
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
                .help("Close Tab (⌘W)")
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
        }
        .help(tab.url?.host?.strippingWWW ?? tab.displayTitle)
        .contextMenu { TabMenuItems(model: model, tab: tab) }
        .animation(.easeOut(duration: 0.12), value: hovering)
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
        if !model.isPrivate && SpaceStore.shared.spaces.count > 1 {
            Menu {
                ForEach(SpaceStore.shared.spaces.filter { $0.id != tab.spaceID }) { space in
                    Button { model.move(tab, toSpace: space.id) } label: { Label(space.name, systemImage: space.symbol) }
                }
            } label: { Label("Move to Space", systemImage: "square.stack.3d.up") }
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
            for other in model.visibleTabs where other !== tab { model.close(other) }
        } label: { Label("Close Other Tabs", systemImage: "xmark.square") }
        Button {
            let mine = model.visibleTabs
            if let i = mine.firstIndex(where: { $0 === tab }) {
                for other in mine.suffix(from: i + 1) { model.close(other) }
            }
        } label: { Label(vertical ? "Close Tabs Below" : "Close Tabs to the Right", systemImage: vertical ? "arrow.down.to.line" : "arrow.right.to.line") }
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
            button.setFrameOrigin(NSPoint(x: x, y: y))
        }
    }
}
