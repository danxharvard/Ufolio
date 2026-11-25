import SwiftUI

/// A small preview of a tab's page when you rest the pointer on its tab (along the top or down
/// the side). It shows the picture taken when you last left that tab, or the one from when it
/// went to sleep: the page itself is never woken or kept running for it.
struct TabPreviewOnHover: ViewModifier {
    @ObservedObject var tab: BrowserTab
    let isSelected: Bool
    let edge: Edge
    @AppStorage(Prefs.tabPreviews) private var enabled = true
    @State private var hovering = false
    @State private var showing = false

    func body(content: Content) -> some View {
        content
            .onHover { inside in
                hovering = inside
                if !inside { showing = false; return }
                guard enabled, !isSelected else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    if hovering && !isSelected && tab.previewImage != nil { showing = true }
                }
            }
            .onChange(of: isSelected) { _, selected in if selected { showing = false } }
            .popover(isPresented: $showing, arrowEdge: edge) {
                TabPreviewCard(tab: tab)
            }
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
