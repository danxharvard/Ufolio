import SwiftUI

/// Compact, equal-width tabs. Only shown when more than one tab is open.
struct TabStrip: View {
    @ObservedObject var model: BrowserModel

    var body: some View {
        HStack(spacing: 4) {
            ForEach(model.tabs) { tab in
                TabPill(model: model, tab: tab, isSelected: tab.id == model.selectedTab?.id)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .animation(.spring(response: 0.25, dampingFraction: 0.9), value: model.tabs.map(\.id))
    }
}

private struct TabPill: View {
    @ObservedObject var model: BrowserModel
    @ObservedObject var tab: BrowserTab
    let isSelected: Bool
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 6) {
            if tab.url == nil {
                Image(systemName: "moon.stars")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 14, height: 14)
            } else {
                Favicon(url: tab.url, size: 14)
            }
            Text(tab.displayTitle)
                .font(.system(size: 12, weight: isSelected ? .medium : .regular))
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(isSelected ? .primary : .secondary)
                .opacity(tab.isAsleep ? 0.55 : 1)
            Spacer(minLength: 0)
            Button { model.close(tab) } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 16, height: 16)
                    .background(Circle().fill(Color.primary.opacity(0.08)))
            }
            .buttonStyle(.plain)
            .opacity(hovering || isSelected ? 1 : 0)
            .help("Close Tab (⌘W)")
        }
        .padding(.horizontal, 9)
        .frame(height: 28)
        .frame(maxWidth: 240)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? Color(nsColor: .controlBackgroundColor).opacity(0.9)
                      : Color.primary.opacity(hovering ? 0.05 : 0))
                .shadow(color: .black.opacity(isSelected ? 0.08 : 0), radius: 2, y: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture { model.selectedID = tab.id }
        .onHover { hovering = $0 }
        .contextMenu {
            Button("Close Tab") { model.close(tab) }
            Button("Close Other Tabs") {
                for other in model.tabs where other !== tab { model.close(other) }
            }
        }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}
