import SwiftUI
import UniformTypeIdentifiers

/// Tabs down the side (Settings › Appearance › Tabs): a frosted column with the window
/// buttons, back/forward/reload, the address bar, the Space switcher, pinned tabs as icons and
/// the tab list. Drag its edge to resize; narrow it right down for icons only.
struct SideTabBar: View {
    @ObservedObject var model: BrowserModel
    let suggestions: SuggestionsModel   // passed on to the address bar; the column needn't redraw as you type
    let onGo: (String) -> Void
    @AppStorage(Prefs.sideTabsWidth) private var storedWidth = 250.0
    @State private var dragStart: Double?
    /// The width while the edge is being dragged; saved to settings only when you let go, so a
    /// drag doesn't write to disk (and redraw every settings observer) on every frame.
    @State private var dragWidth: Double?
    @State private var hoveringEdge = false

    static let minWidth = 72.0, compactBelow = 150.0, maxWidth = 420.0
    private var width: Double { min(max(dragWidth ?? storedWidth, Self.minWidth), Self.maxWidth) }
    private var compact: Bool { width < Self.compactBelow }

    var body: some View {
        VStack(spacing: 0) {
            topRow
            if compact {
                compactTools
            } else {
                SelectedTab(model: model) { tab in
                    AddressBar(model: model, tab: tab, suggestions: suggestions, onGo: onGo)
                        .background(GeometryReader { geo in
                            Color.clear.preference(key: AddressFrameKey.self, value: geo.frame(in: .named("window")))
                        })
                }
                .padding(.horizontal, 10)
                .padding(.top, 4)
                toolsRow
            }
            Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1).padding(.horizontal, 12).padding(.vertical, 8)
            SideTabList(model: model, compact: compact)
        }
        .frame(width: width)
        .overlay(alignment: .trailing) { resizeHandle }
        // ⌘L with no address bar showing (icons only) opens the Command Palette instead.
        .onChange(of: model.addressFocusToken) { _, _ in if compact { model.paletteOpen = true } }
    }

    /// The window buttons sit here (Hush lines them up), then the page controls.
    private var topRow: some View {
        HStack(spacing: 2) {
            Color.clear.frame(width: 70, height: 1)
            Spacer(minLength: 0)
            if !compact {
                SidebarButton(model: model)
                SelectedTab(model: model) { NavButtons(tab: $0) }
            }
        }
        .padding(.trailing, 8)
        .frame(height: Chrome.tabBarHeight)
        // Only the empty space moves the window. With the drag on the whole row, every click on
        // the sidebar and back/forward buttons had to get past the window drag first, which made
        // them slow to respond (or miss clicks entirely).
        .background(Color.clear.contentShape(Rectangle()).gesture(WindowDragGesture()))
    }

    private var toolsRow: some View {
        HStack(spacing: 2) {
            if !model.isPrivate { SpaceButton(model: model) }
            if !model.isPrivate, let space = SpaceStore.shared.space(model.spaceID) {
                Text(space.name)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            DownloadsButton()
            if !model.isPrivate { ExtensionButtons() }
            // Force Field and Stealth sit at the top right, beside the ⋯ menu.
        }
        .padding(.horizontal, 8)
        .padding(.top, 6)
    }

    /// Icons only: the essentials stacked down the column.
    private var compactTools: some View {
        VStack(spacing: 4) {
            SelectedTab(model: model) { NavButtons(tab: $0) }
                .scaleEffect(0.9)
            ToolbarIconButton(symbol: "magnifyingglass", help: "Search or enter a website (⌘L)") { model.paletteOpen = true }
            if !model.isPrivate { SpaceButton(model: model) }
        }
        .padding(.top, 2)
    }

    private var resizeHandle: some View {
        Rectangle()
            .fill(Color.accentColor.opacity(hoveringEdge || dragStart != nil ? 0.5 : 0))
            .frame(width: 2)
            .padding(.vertical, 8)
            .frame(width: 8)
            .contentShape(Rectangle())
            .onHover { hoveringEdge = $0 }
            .pointerStyle(.frameResize(position: .trailing))
            .gesture(DragGesture(minimumDistance: 1)
                .onChanged { value in
                    if dragStart == nil { dragStart = width }
                    dragWidth = min(max((dragStart ?? width) + value.translation.width, Self.minWidth), Self.maxWidth)
                }
                .onEnded { _ in
                    if let dragWidth { storedWidth = dragWidth }
                    dragWidth = nil
                    dragStart = nil
                })
            .onTapGesture(count: 2) {
                // Double-click the edge: switch between icons only and the full column.
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { storedWidth = compact ? 250 : Self.minWidth }
            }
            .help("Drag to resize. Double-click for icons only.")
    }
}

/// Pinned tabs as a grid of icons, a New Tab row, then this Space's tabs.
private struct SideTabList: View {
    @ObservedObject var model: BrowserModel
    let compact: Bool
    @State private var dragging: UUID?

    var body: some View {
        let tabs = model.visibleTabs
        let pinned = tabs.filter(\.isPinned)
        let others = tabs.filter { !$0.isPinned }
        ScrollViewReader { proxy in
        ScrollView(.vertical, showsIndicators: false) {
            // Lazy: rows scrolled out of view aren't built, so lots of tabs stay quick.
            LazyVStack(spacing: 2) {
                if !pinned.isEmpty {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: compact ? 44 : 50), spacing: 6)], spacing: 6) {
                        ForEach(pinned) { tab in
                            PinnedTile(model: model, tab: tab, selected: tab.id == model.selectedTab?.id)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
                }
                SideRowButton(symbol: "plus", title: "New Tab", compact: compact) { model.newTab(focus: true) }
                ForEach(others) { tab in
                    // Drag and drop hold only the tab's ID: macOS can keep these handlers after a
                    // row is redrawn, and holding the tab itself would keep closed tabs in memory.
                    let id = tab.id
                    SideTabRow(model: model, inSplit: model.isInSplit(tab), tab: tab, selected: tab.id == model.selectedTab?.id, compact: compact)
                        .opacity(dragging == id ? 0.4 : 1)
                        .onDrag {
                            dragging = id
                            return NSItemProvider(object: id.uuidString as NSString)
                        }
                        .onDrop(of: [.text], delegate: SideTabDrop(target: id, model: model, dragging: $dragging))
                        .transition(.asymmetric(insertion: .move(edge: .top).combined(with: .opacity), removal: .opacity))
                        .id(id)
                }
            }
            .padding(.horizontal, 6)
            .padding(.bottom, 12)
            .animation(.spring(response: 0.28, dampingFraction: 0.88), value: tabs.map(\.id))
        }
        // The current tab is scrolled into view when it changes (switching by keyboard or the
        // palette to a tab further down used to leave it out of sight).
        .onChange(of: model.selectedID) { _, id in
            guard let id, others.contains(where: { $0.id == id }) else { return }
            withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(id) }
        }
        }
    }
}

/// Reorders as you drag one tab over another.
private struct SideTabDrop: DropDelegate {
    let target: UUID
    weak var model: BrowserModel?
    @Binding var dragging: UUID?

    func dropEntered(info: DropInfo) {
        guard let model else { return }
        let tabs = model.visibleTabs
        guard let id = dragging, id != target,
              let from = tabs.firstIndex(where: { $0.id == id }),
              let to = tabs.firstIndex(where: { $0.id == target }) else { return }
        model.moveTab(from: from, to: to)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        dragging = nil
        return true
    }
}

private struct SideTabRow: View {
    /// Not observed: a tab only needs redrawing when its own details change (or what's passed in),
    /// not every time anything in the window changes.
    let model: BrowserModel
    let inSplit: Bool
    @ObservedObject var tab: BrowserTab
    let selected: Bool
    let compact: Bool
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 9) {
            icon
            if !compact {
                if inSplit {
                    Image(systemName: "rectangle.split.2x1").font(.system(size: 9.5, weight: .semibold)).foregroundStyle(Color.accentColor)
                }
                Text(tab.displayTitle)
                    .font(.system(size: 13, weight: selected ? .medium : .regular))
                    .lineLimit(1)
                    .foregroundStyle(selected ? .primary : .secondary)
                    .opacity(tab.isAsleep ? 0.6 : 1)
                Spacer(minLength: 4)
                if tab.isPlayingAudio || tab.isMuted {
                    Button { tab.toggleMute() } label: {
                        Image(systemName: tab.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(tab.isMuted ? Color.secondary : Color.accentColor)
                            .frame(width: 20, height: 20)
                            .contentShape(Rectangle())   // clickable around the icon, not just on it
                    }
                    .buttonStyle(.plain)
                }
                if hovering || selected {
                    Button { model.close(tab) } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 18, height: 18)
                            .background(Circle().fill(Color.primary.opacity(hovering ? 0.1 : 0)))
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, compact ? 0 : 10)
        .frame(maxWidth: .infinity, alignment: compact ? .center : .leading)
        .frame(height: 34)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(selected ? SideColors.selected : Color.primary.opacity(hovering ? 0.07 : 0))
                .shadow(color: .black.opacity(selected ? 0.12 : 0), radius: 2, y: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture { model.selectedID = tab.id }
        .onHover { hovering = $0 }
        .contextMenu { TabMenuItems(model: model, tab: tab, vertical: true) }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }

    @ViewBuilder private var icon: some View {
        Group {
            if tab.isLoading && tab.url != nil {
                ProgressView().controlSize(.mini)
            } else if tab.url == nil {
                Image(systemName: "moon.stars").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
            } else {
                Favicon(url: tab.url, size: 16)
            }
        }
        .frame(width: 16, height: 16)
    }
}

private struct PinnedTile: View {
    /// Not observed: a tab only needs redrawing when its own details change (or what's passed in),
    /// not every time anything in the window changes.
    let model: BrowserModel
    @ObservedObject var tab: BrowserTab
    let selected: Bool
    @State private var hovering = false

    var body: some View {
        Favicon(url: tab.url, size: 18)
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(selected ? SideColors.selected : Color.primary.opacity(hovering ? 0.1 : 0.06)))
            .overlay(alignment: .bottomTrailing) {
                if tab.isPlayingAudio || tab.isMuted {
                    Circle().fill(tab.isMuted ? Color.secondary : Color.accentColor).frame(width: 6, height: 6).padding(5)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { model.selectedID = tab.id }
            .onHover { hovering = $0 }
            .contextMenu { TabMenuItems(model: model, tab: tab, vertical: true) }
    }
}

private struct SideRowButton: View {
    let symbol: String
    let title: String
    let compact: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: symbol).font(.system(size: 12, weight: .medium)).frame(width: 16)
                if !compact { Text(title).font(.system(size: 13)) ; Spacer() }
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, compact ? 0 : 10)
            .frame(maxWidth: .infinity, alignment: compact ? .center : .leading)
            .frame(height: 32)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.primary.opacity(hovering ? 0.07 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(compact ? title : "")
    }
}

enum SideColors {
    /// The selected tab: a soft, bright lozenge on the frosted column.
    static let selected = Color(nsColor: NSColor(name: nil) { a in
        a.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(white: 1, alpha: 0.12) : NSColor(white: 1, alpha: 0.7)
    })
}
