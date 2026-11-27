import SwiftUI
import WebKit

/// Link preview: a page opened in a frosted card floating over the one you're on (⌥-click a
/// link, or right-click › Preview Link), as in Zen's Glance. Read it, then open it as a tab, put
/// it beside this page in Split View, or close it (Esc, or a click outside). Nothing is added to
/// your tabs unless you keep it.
struct LinkPreviewOverlay: View {
    @ObservedObject var model: BrowserModel

    var body: some View {
        ZStack {
            if let tab = model.preview {
                LinkPreviewCard(model: model, tab: tab)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: model.preview?.id)
    }
}

private struct LinkPreviewCard: View {
    let model: BrowserModel
    @ObservedObject var tab: BrowserTab
    @State private var escMonitor: Any?

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // A click outside the card closes it; the page underneath gets nothing.
                ClickBlocker { model.closePreview() }
                Color.black.opacity(0.16).allowsHitTesting(false)
                VStack(spacing: 0) {
                    header
                    ZStack(alignment: .topLeading) {
                        WebViewHost(webView: tab.webView).id(ObjectIdentifier(tab.webView))
                        ProgressLine(tab: tab)
                    }
                    .overlay(PageCorners.shape.strokeBorder(Color.primary.opacity(0.08)).allowsHitTesting(false))
                    .padding([.horizontal, .bottom], 6)
                }
                .frame(width: max(320, geo.size.width * 0.86), height: max(240, geo.size.height * 0.9))
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.primary.opacity(0.12)))
                .shadow(color: .black.opacity(0.28), radius: 30, y: 12)
            }
        }
        .onAppear {
            // Esc closes it (the page inside has the keyboard, so it's watched for here).
            escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                guard event.keyCode == 53, event.window === model.window, model.preview === tab else { return event }
                model.closePreview()
                return nil
            }
            DispatchQueue.main.async { tab.webView.window?.makeFirstResponder(tab.webView) }
        }
        .onDisappear {
            if let escMonitor { NSEvent.removeMonitor(escMonitor) }
            escMonitor = nil
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Favicon(url: tab.url, size: 15)
            VStack(alignment: .leading, spacing: 0) {
                Text(tab.displayTitle).font(.system(size: 12.5, weight: .semibold)).lineLimit(1)
                Text(tab.url?.host?.strippingWWW ?? "").font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 12)
            PreviewButton(symbol: "rectangle.split.2x1", help: "Open in Split View") { model.expandPreview(split: true) }
            PreviewButton(symbol: "arrow.up.left.and.arrow.down.right", help: "Open as a Tab") { model.expandPreview() }
            PreviewButton(symbol: "xmark", help: "Close Preview (Esc)") { model.closePreview() }
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
    }
}

private struct PreviewButton: View {
    let symbol: String
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 24)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.primary.opacity(hovering ? 0.09 : 0)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(help)
    }
}
