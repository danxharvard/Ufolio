import SwiftUI
import WebKit

/// Find on Page (⌘F): a slim bar under the toolbar with the number of matches and
/// previous / next. Searching happens in the page itself; nothing leaves your Mac.
final class FindModel: ObservableObject {
    @Published var isVisible = false
    @Published var query = ""
    @Published private(set) var matches: Int?
    @Published private(set) var current = 0
    @Published var focusToken = 0

    func show() {
        isVisible = true
        focusToken += 1
    }

    func hide(in webView: WKWebView?) {
        isVisible = false
        matches = nil
        current = 0
        // Clear the highlighted match.
        webView?.evaluateJavaScript("window.getSelection && window.getSelection().removeAllRanges()", in: nil, in: .defaultClient) { _ in }
    }

    func search(in webView: WKWebView?, backwards: Bool = false, restart: Bool = false) {
        guard let webView, !query.isEmpty else { matches = nil; current = 0; return }
        if restart { current = 0 }
        let config = WKFindConfiguration()
        config.backwards = backwards
        config.caseSensitive = false
        config.wraps = true
        let text = query
        webView.find(text, configuration: config) { [weak self] result in
            guard let self, self.query == text else { return }
            if !result.matchFound { self.matches = 0; self.current = 0; return }
            self.countMatches(of: text, in: webView, backwards: backwards)
        }
    }

    /// Counts matches in the page's visible text (in Hush's own script world).
    private func countMatches(of text: String, in webView: WKWebView, backwards: Bool) {
        let script = """
        const body = document.body ? document.body.innerText.toLowerCase() : '';
        const needle = q.toLowerCase();
        let count = 0, i = 0;
        while (needle && (i = body.indexOf(needle, i)) !== -1) { count++; i += needle.length; if (count > 9999) break; }
        return count;
        """
        webView.callAsyncJavaScript(script, arguments: ["q": text], in: nil, in: .defaultClient) { [weak self] result in
            guard let self, self.query == text, case .success(let value) = result else { return }
            let total = (value as? Int) ?? (value as? NSNumber)?.intValue ?? 0
            self.matches = total
            guard total > 0 else { self.current = 0; return }
            if self.current == 0 { self.current = 1 } else {
                self.current = backwards ? (self.current - 2 + total) % total + 1 : self.current % total + 1
            }
        }
    }
}

struct FindBar: View {
    @ObservedObject var find: FindModel
    let webView: WKWebView?
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                TextField("Find on page", text: $find.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .focused($focused)
                    .onSubmit { find.search(in: webView, backwards: NSEvent.modifierFlags.contains(.shift)) }
                if let matches = find.matches {
                    Text(matches == 0 ? "No matches" : "\(find.current) of \(matches)")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(matches == 0 ? Color.orange : .secondary)
                        .monospacedDigit()
                }
            }
            .padding(.horizontal, 10)
            .frame(width: 300, height: 26)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.primary.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(focused ? 0.6 : 0), lineWidth: 1.5))

            ControlGroup {
                Button { find.search(in: webView, backwards: true) } label: { Image(systemName: "chevron.up") }
                    .help("Previous (⇧⌘G)")
                Button { find.search(in: webView) } label: { Image(systemName: "chevron.down") }
                    .help("Next (⌘G)")
            }
            .controlSize(.small)
            .fixedSize()
            .disabled(find.query.isEmpty)

            Spacer()
            Button("Done") { find.hide(in: webView) }
                .controlSize(.small)
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 12)
        .frame(height: 36)
        .onChange(of: find.query) { _ in find.search(in: webView, restart: true) }
        .onChange(of: find.focusToken) { _ in focused = true }
        .onAppear { focused = true }
    }
}
