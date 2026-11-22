import SwiftUI
import AppKit

/// The rounded address field in the middle of the toolbar.
/// Shows the site's name while browsing and the full address while typing.
struct AddressBar: View {
    @ObservedObject var model: BrowserModel
    @ObservedObject var tab: BrowserTab
    @ObservedObject var suggestions: SuggestionsModel
    @ObservedObject private var bookmarks = BookmarkStore.shared
    @AppStorage(Prefs.showFullAddress) private var showFullAddress = false
    @AppStorage(Prefs.searchEngine) private var engine = SearchEngine.google.rawValue
    let onGo: (String) -> Void

    @State private var text = ""
    @State private var isEditing = false
    @State private var hovering = false

    private var displayText: String { display(tab.url, hovering: hovering) }

    /// The site's name normally; the full address while the pointer is over the bar.
    private func display(_ url: URL?, hovering: Bool = false) -> String {
        guard let url else { return "" }
        if showFullAddress || hovering { return url.absoluteString }
        return url.host?.strippingWWW ?? url.absoluteString
    }

    private var isBookmarked: Bool {
        tab.url.map { bookmarks.contains($0) } ?? false
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: leadingSymbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 14)

            AddressTextField(
                text: $text,
                isEditing: $isEditing,
                placeholder: "Search \((SearchEngine(rawValue: engine) ?? .google).name) or enter a website",
                centered: false,
                focusToken: model.addressFocusToken,
                onBeginEditing: {
                    text = tab.url?.absoluteString ?? ""
                    suggestions.activate()
                },
                onChange: { suggestions.update(query: $0) },
                onSubmit: {
                    let chosen = suggestions.selected?.text ?? text
                    onGo(chosen)
                },
                onMove: { suggestions.move(by: $0) },
                onCancel: {
                    if suggestions.isVisible {
                        suggestions.dismiss()
                        return false
                    }
                    text = displayText
                    return true
                },
                onEndEditing: {
                    text = displayText
                    suggestions.dismiss()
                }
            )

            if tab.url != nil && !isEditing {
                ReaderButton(tab: tab)
                TranslateButton(tab: tab)
                Button { model.toggleBookmarkForSelectedTab() } label: {
                    Image(systemName: isBookmarked ? "star.fill" : "star")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(isBookmarked ? Color.yellow : Color.secondary)
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(isBookmarked ? "Remove Bookmark (⌘D)" : "Bookmark This Page (⌘D)")
                .opacity(hovering || isBookmarked ? 1 : 0)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(isEditing ? Color(nsColor: .textBackgroundColor)
                      : Color.primary.opacity(hovering ? 0.08 : 0.055))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(isEditing ? 0.55 : 0), lineWidth: 1.5)
        )
        .shadow(color: .black.opacity(isEditing ? 0.08 : 0), radius: 6, y: 2)
        .onHover { inside in
            hovering = inside
            if !isEditing { text = display(model.selectedTab?.url, hovering: inside) }
        }
        .animation(.easeOut(duration: 0.15), value: isEditing)
        .animation(.easeOut(duration: 0.12), value: hovering)
        .onAppear { text = displayText }
        // onChange actions can still see the previous values, so always use the new value
        // or read the selected tab from the model, never the captured `tab`.
        .onChange(of: tab.url) { _, newURL in
            // A page arriving while the bar is focused but untouched (e.g. a link from another app).
            if !isEditing || text.isEmpty { text = display(newURL) }
        }
        // Switching tabs must show the new tab's address (or nothing, for a new tab).
        .onChange(of: tab.id) { _, _ in
            if !isEditing { text = display(model.selectedTab?.url) }
            suggestions.dismiss()
        }
        .onChange(of: showFullAddress) { _, _ in if !isEditing { text = display(model.selectedTab?.url) } }
    }

    private var leadingSymbol: String {
        if isEditing || tab.url == nil { return "magnifyingglass" }
        return tab.url?.scheme == "https" ? "lock.fill" : "globe"
    }
}

/// An NSTextField wrapper, so the arrow keys, Return and Esc can drive the suggestions.
struct AddressTextField: NSViewRepresentable {
    @Binding var text: String
    @Binding var isEditing: Bool
    let placeholder: String
    let centered: Bool
    let focusToken: Int
    let onBeginEditing: () -> Void
    let onChange: (String) -> Void
    let onSubmit: () -> Void
    let onMove: (Int) -> Void
    /// Return true to leave the field (give focus back to the page).
    let onCancel: () -> Bool
    let onEndEditing: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> FocusTextField {
        let field = FocusTextField()
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 13)
        field.lineBreakMode = .byTruncatingTail
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        field.placeholderString = placeholder
        field.delegate = context.coordinator
        field.onFocus = { [weak field, weak coordinator = context.coordinator] in
            guard let field, let coordinator else { return }
            coordinator.beginEditing(field)
        }
        return field
    }

    func updateNSView(_ field: FocusTextField, context: Context) {
        context.coordinator.parent = self
        // Follow the toolbar's light or dark look (Magic Theme can differ from the system's).
        let look = NSAppearance(named: context.environment.colorScheme == .dark ? .darkAqua : .aqua)
        if field.appearance?.name != look?.name { field.appearance = look }
        if field.stringValue != text { field.setText(text) }
        field.alignment = centered ? .center : .left
        if context.coordinator.lastFocusToken != focusToken {
            context.coordinator.lastFocusToken = focusToken
            DispatchQueue.main.async { field.window?.makeFirstResponder(field) }
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: AddressTextField
        var lastFocusToken: Int

        init(_ parent: AddressTextField) {
            self.parent = parent
            self.lastFocusToken = parent.focusToken
        }

        func beginEditing(_ field: NSTextField) {
            guard !parent.isEditing else { return }
            parent.isEditing = true
            parent.onBeginEditing()
            field.alignment = .left
            DispatchQueue.main.async { field.currentEditor()?.selectAll(nil) }
        }

        func controlTextDidChange(_ note: Notification) {
            guard let field = note.object as? NSTextField else { return }
            parent.text = field.stringValue
            parent.onChange(field.stringValue)
        }

        func controlTextDidEndEditing(_ note: Notification) {
            parent.isEditing = false
            parent.onEndEditing()
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.moveUp(_:)):
                parent.onMove(-1); return true
            case #selector(NSResponder.moveDown(_:)):
                parent.onMove(1); return true
            case #selector(NSResponder.insertNewline(_:)):
                parent.onSubmit()
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                if parent.onCancel() {
                    control.window?.makeFirstResponder(nil)
                }
                return true
            default:
                return false
            }
        }
    }
}

final class FocusTextField: NSTextField {
    var onFocus: (() -> Void)?
    /// Set when the field gains focus: once the full address replaces the short site name,
    /// it's all selected, ready to type over.
    var selectAllAfterUpdate = false

    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok {
            selectAllAfterUpdate = true
            onFocus?()
        }
        return ok
    }

    // Clicking into the field selects everything, like Safari.
    override func mouseDown(with event: NSEvent) {
        let wasEditing = currentEditor() != nil
        super.mouseDown(with: event)
        if !wasEditing {
            currentEditor()?.selectAll(nil)
            // The address is swapped in a moment later; select it again then.
            DispatchQueue.main.async { [weak self] in
                guard let self, self.selectAllAfterUpdate else { return }
                self.selectAllAfterUpdate = false
                self.currentEditor()?.selectAll(nil)
            }
        }
    }

    /// Puts in new text, keeping everything selected if the field has just been focused.
    func setText(_ text: String) {
        stringValue = text
        if selectAllAfterUpdate, let editor = currentEditor() {
            selectAllAfterUpdate = false
            editor.selectAll(nil)
        }
    }
}

/// Turns what was typed into a URL: a web address if it looks like one, otherwise a Google search.
enum URLResolver {
    static func resolve(_ raw: String) -> URL? {
        let input = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return nil }

        if let url = URL(string: input), let scheme = url.scheme?.lowercased(),
           ["http", "https", "file", "about"].contains(scheme) {
            return url
        }
        if looksLikeAddress(input) {
            // Local servers usually don't do HTTPS.
            let host = input.split(separator: "/").first.map { String($0.split(separator: ":").first ?? "") } ?? ""
            let local = host == "localhost" || host.hasSuffix(".local") || host.split(separator: ".").allSatisfy { Int($0) != nil }
            return URL(string: (local ? "http://" : "https://") + input)
        }
        return searchURL(for: input)
    }

    static func searchURL(for query: String) -> URL? {
        SearchEngine.current.searchURL(query)
    }

    static func looksLikeAddress(_ s: String) -> Bool {
        if s.contains(" ") { return false }
        if s.hasPrefix("localhost") { return true }
        let host = s.split(separator: "/", maxSplits: 1).first.map(String.init) ?? s
        let hostOnly = host.split(separator: ":").first.map(String.init) ?? host
        let parts = hostOnly.split(separator: ".")
        guard parts.count >= 2, let tld = parts.last, tld.count >= 2 else { return false }
        return tld.allSatisfy { $0.isLetter } || parts.allSatisfy { Int($0) != nil }
    }
}
