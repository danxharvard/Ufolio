import SwiftUI
import AppKit

/// The rounded address field in the middle of the toolbar.
/// Shows the site's name while browsing and the full address while typing.
struct AddressBar: View {
    @ObservedObject var model: BrowserModel
    @ObservedObject var tab: BrowserTab
    @ObservedObject var suggestions: SuggestionsModel
    /// This tab's profile's bookmarks (for the star).
    @ObservedObject private var bookmarks: BookmarkStore
    @AppStorage(Prefs.showFullAddress) private var showFullAddress = false
    @AppStorage(Prefs.searchEngine) private var engine = SearchEngine.google.rawValue
    let onGo: (String) -> Void

    init(model: BrowserModel, tab: BrowserTab, suggestions: SuggestionsModel, onGo: @escaping (String) -> Void) {
        _model = ObservedObject(wrappedValue: model)
        _tab = ObservedObject(wrappedValue: tab)
        _suggestions = ObservedObject(wrappedValue: suggestions)
        _bookmarks = ObservedObject(wrappedValue: BookmarkStore.store(for: tab.profileID))
        self.onGo = onGo
    }

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
                .help(leadingSymbol == "lock.open" ? "Parts of this page aren’t sent securely"
                      : leadingSymbol == "lock.fill" ? "Secure connection" : "")

            AddressTextField(
                register: { [weak model] field in model?.addressField = field },
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
                    // Back to the page, so Space and the arrow keys scroll it again (focus used to go nowhere).
                    if let page = model.selectedTab?.webView, !(model.selectedTab?.isBlank ?? true) {
                        DispatchQueue.main.async { page.window?.makeFirstResponder(page) }
                    }
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
        guard tab.url?.scheme == "https" else { return "globe" }
        // Secure address, but parts of the page came over plain http: an open padlock, honestly.
        return tab.isSecure || tab.isLoading ? "lock.fill" : "lock.open"
    }
}

/// An NSTextField wrapper, so the arrow keys, Return and Esc can drive the suggestions.
struct AddressTextField: NSViewRepresentable {
    /// Hands the field to its window, so "focus the address bar" can go straight to it.
    var register: (NSTextField) -> Void = { _ in }
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
        register(field)
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
        let alignment: NSTextAlignment = centered ? .center : .left
        if field.alignment != alignment { field.alignment = alignment }   // re-setting it can drop the selection
        register(field)
        // (Focusing is done directly by BrowserModel.focusAddressBar, which checks it worked.)
        context.coordinator.lastFocusToken = focusToken
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
            if field.alignment != .left { field.alignment = .left }
            DispatchQueue.main.async { (field as? FocusTextField)?.selectEverything() }
        }

        func controlTextDidChange(_ note: Notification) {
            guard let field = note.object as? NSTextField else { return }
            (field as? FocusTextField)?.keepAllSelected = false   // you're typing now
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
    /// While true, the whole address stays selected, whatever else redraws or updates the
    /// field. It ends when you type, press a key or click inside the field again.
    var keepAllSelected = false
    private var selectionObserver: NSObjectProtocol?
    private var eventMonitor: Any?
    /// The click that gave the field focus. macOS focuses a clicked field *before* handing it
    /// the click, so without this the focusing click would look like a second click inside.
    private var focusingClick: TimeInterval?

    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok {
            keepAllSelected = true
            let event = NSApp.currentEvent
            focusingClick = event?.type == .leftMouseDown ? event?.timestamp : nil
            onFocus?()
            selectEverything()
            startGuarding()
        }
        return ok
    }

    // The first click into the field selects the whole address, like Safari, so you can copy
    // it or type over it. A second click places the cursor as usual.
    override func mouseDown(with event: NSEvent) {
        // The click that focuses the field selects the whole address (and keeps it selected
        // through the release). Only a later click places the cursor.
        if currentEditor() == nil || event.timestamp == focusingClick {
            if currentEditor() == nil { window?.makeFirstResponder(self) }
            focusingClick = event.timestamp
            keepAllSelected = true
            selectEverything()
            return
        }
        keepAllSelected = false
        super.mouseDown(with: event)
    }

    override func textDidEndEditing(_ notification: Notification) {
        stopGuarding()
        super.textDidEndEditing(notification)
    }

    func selectEverything() {
        guard let editor = currentEditor() else { return }
        let all = NSRange(location: 0, length: (editor.string as NSString).length)
        if editor.selectedRange != all { editor.selectedRange = all }
    }

    /// Puts in new text, keeping everything selected if the field has just been focused.
    func setText(_ text: String) {
        stringValue = text
        if keepAllSelected { selectEverything() }
    }

    /// Keeps the address selected until you do something with it.
    private func startGuarding() {
        stopGuarding()
        if let editor = currentEditor() {
            selectionObserver = NotificationCenter.default.addObserver(
                forName: NSTextView.didChangeSelectionNotification, object: editor, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, self.keepAllSelected else { return }
                    // Something moved the selection on its own: select everything again.
                    DispatchQueue.main.async { if self.keepAllSelected { self.selectEverything() } }
                }
            }
        }
        // Your own typing, keys or a click inside the field end it (seen before they're handled).
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self, self.keepAllSelected, event.window === self.window else { return event }
            if event.type == .keyDown {
                self.keepAllSelected = false
            } else {
                let point = self.convert(event.locationInWindow, from: nil)
                if self.bounds.contains(point), self.currentEditor() != nil, event.timestamp != self.focusingClick {
                    self.keepAllSelected = false
                }
            }
            return event
        }
    }

    private func stopGuarding() {
        keepAllSelected = false
        if let selectionObserver { NotificationCenter.default.removeObserver(selectionObserver) }
        selectionObserver = nil
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
        eventMonitor = nil
    }

    deinit {
        if let selectionObserver { NotificationCenter.default.removeObserver(selectionObserver) }
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
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
            let url = URL(string: (local ? "http://" : "https://") + input)
            if let url { lastGuess = (url, input) }
            return url
        }
        return searchURL(for: input)
    }

    /// The last address guessed from typed text (e.g. "node.js" → https://node.js). If no such
    /// server exists, the tab searches for the text instead (see BrowserTab).
    static var lastGuess: (url: URL, text: String)?

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
