import SwiftUI
import AppKit

/// Every keyboard shortcut Hush has, with its default. You can change them in
/// Settings › Keyboard; changes are saved as a small list of overrides.
enum ShortcutAction: String, CaseIterable, Identifiable {
    case newTab, privateWindow, openLocation, closeTab, closeWindow, reopenTab
    case find, findNext, findPrevious
    case reload, back, forward, nextTab, previousTab
    case print, savePage, copyCleanLink
    case zoomIn, zoomOut, actualSize
    case splitView, reader, pictureInPicture, translate, muteTab
    case bookmark, bookmarksBar, history, sidebar
    case commandPalette, nextSpace, previousSpace

    var id: String { rawValue }

    var title: String {
        switch self {
        case .newTab: return "New Tab"
        case .privateWindow: return "New Stealth Window"
        case .openLocation: return "Open Location"
        case .closeTab: return "Close Tab"
        case .closeWindow: return "Close Window"
        case .reopenTab: return "Reopen Closed Tab"
        case .find: return "Find on Page"
        case .findNext: return "Find Next"
        case .findPrevious: return "Find Previous"
        case .reload: return "Reload Page"
        case .back: return "Back"
        case .forward: return "Forward"
        case .nextTab: return "Show Next Tab"
        case .previousTab: return "Show Previous Tab"
        case .print: return "Print"
        case .savePage: return "Save Page As"
        case .copyCleanLink: return "Copy Clean Link"
        case .zoomIn: return "Zoom In"
        case .zoomOut: return "Zoom Out"
        case .actualSize: return "Actual Size"
        case .splitView: return "Split View"
        case .reader: return "Reader"
        case .pictureInPicture: return "Picture in Picture"
        case .translate: return "Translate Page"
        case .muteTab: return "Mute Tab"
        case .bookmark: return "Bookmark This Page"
        case .bookmarksBar: return "Show Bookmarks Bar"
        case .history: return "Show All History"
        case .sidebar: return "Show Bookmarks & History Sidebar"
        case .commandPalette: return "Command Palette"
        case .nextSpace: return "Next Orbit"
        case .previousSpace: return "Previous Orbit"
        }
    }

    var group: String {
        switch self {
        case .newTab, .privateWindow, .openLocation, .closeTab, .closeWindow, .reopenTab: return "Tabs and windows"
        case .find, .findNext, .findPrevious: return "Find"
        case .reload, .back, .forward, .nextTab, .previousTab: return "Getting around"
        case .print, .savePage, .copyCleanLink: return "Pages"
        case .zoomIn, .zoomOut, .actualSize: return "Zoom"
        case .splitView, .reader, .pictureInPicture, .translate, .muteTab: return "Views and media"
        case .bookmark, .bookmarksBar, .history, .sidebar: return "Bookmarks and history"
        case .commandPalette, .nextSpace, .previousSpace: return "Command Palette and Orbits"
        }
    }

    var defaultShortcut: KeyCombo {
        switch self {
        case .newTab: return KeyCombo("t")
        case .privateWindow: return KeyCombo("n", [.command, .shift])
        case .openLocation: return KeyCombo("l")
        case .closeTab: return KeyCombo("w")
        case .closeWindow: return KeyCombo("w", [.command, .shift])
        case .reopenTab: return KeyCombo("t", [.command, .shift])
        case .find: return KeyCombo("f")
        case .findNext: return KeyCombo("g")
        case .findPrevious: return KeyCombo("g", [.command, .shift])
        case .reload: return KeyCombo("r")
        case .back: return KeyCombo("[")
        case .forward: return KeyCombo("]")
        case .nextTab: return KeyCombo("]", [.command, .shift])
        case .previousTab: return KeyCombo("[", [.command, .shift])
        case .print: return KeyCombo("p")
        case .savePage: return KeyCombo("s")
        case .copyCleanLink: return KeyCombo("c", [.command, .shift])
        case .zoomIn: return KeyCombo("+")
        case .zoomOut: return KeyCombo("-")
        case .actualSize: return KeyCombo("0")
        case .splitView: return KeyCombo("s", [.command, .control])
        case .reader: return KeyCombo("r", [.command, .shift])
        case .pictureInPicture: return KeyCombo("p", [.command, .option])
        case .translate: return KeyCombo("y", [.command, .shift])
        case .muteTab: return KeyCombo("m", [.command, .control])
        case .bookmark: return KeyCombo("d")
        case .bookmarksBar: return KeyCombo("b", [.command, .shift])
        case .history: return KeyCombo("y")
        case .sidebar: return KeyCombo("l", [.command, .shift])
        case .commandPalette: return KeyCombo("k")
        case .nextSpace: return KeyCombo("]", [.command, .control])
        case .previousSpace: return KeyCombo("[", [.command, .control])
        }
    }
}

/// A key plus modifiers, saved as text like "cmd+shift+t".
struct KeyCombo: Equatable {
    var key: String
    var modifiers: EventModifiers

    init(_ key: String, _ modifiers: EventModifiers = .command) {
        self.key = key.lowercased()
        self.modifiers = modifiers
    }

    init?(stored: String) {
        let parts = stored.split(separator: "+", omittingEmptySubsequences: false).map(String.init)
        guard let key = parts.last, !key.isEmpty || stored.hasSuffix("++") else { return nil }
        var mods: EventModifiers = []
        for part in parts.dropLast() {
            switch part {
            case "cmd": mods.insert(.command)
            case "shift": mods.insert(.shift)
            case "opt": mods.insert(.option)
            case "ctrl": mods.insert(.control)
            default: break
            }
        }
        self.init(key.isEmpty ? "+" : key, mods)
    }

    var stored: String {
        var parts: [String] = []
        if modifiers.contains(.control) { parts.append("ctrl") }
        if modifiers.contains(.option) { parts.append("opt") }
        if modifiers.contains(.shift) { parts.append("shift") }
        if modifiers.contains(.command) { parts.append("cmd") }
        return (parts + [key]).joined(separator: "+")
    }

    var shortcut: KeyboardShortcut? {
        guard let character = key.first, key.count == 1 else { return nil }
        return KeyboardShortcut(KeyEquivalent(character), modifiers: modifiers)
    }

    /// "⇧⌘T"
    var display: String {
        var text = ""
        if modifiers.contains(.control) { text += "⌃" }
        if modifiers.contains(.option) { text += "⌥" }
        if modifiers.contains(.shift) { text += "⇧" }
        if modifiers.contains(.command) { text += "⌘" }
        return text + key.uppercased()
    }
}

enum Shortcuts {
    static let storageKey = "shortcutOverrides"
    /// Marks a shortcut you removed on purpose.
    private static let none = "none"

    /// Saved as JSON text, so the menus (which watch this setting) redraw when it changes.
    private static var cached: (text: String, value: [String: String])?
    private static var overrides: [String: String] {
        get {
            // Decoded once per change (the menu bar asks for ~30 shortcuts every time it refreshes).
            let text = UserDefaults.standard.string(forKey: storageKey) ?? ""
            if let cached, cached.text == text { return cached.value }
            let saved = text.data(using: .utf8).flatMap { try? JSONDecoder().decode([String: String].self, from: $0) } ?? [:]
            cached = (text, saved)
            return saved
        }
        set {
            let text = (try? JSONEncoder().encode(newValue)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
            UserDefaults.standard.set(newValue.isEmpty ? "" : text, forKey: storageKey)
        }
    }

    static func combo(_ action: ShortcutAction) -> KeyCombo? {
        guard let saved = overrides[action.rawValue] else { return action.defaultShortcut }
        return saved == none ? nil : KeyCombo(stored: saved)
    }

    /// For the menus.
    static func get(_ action: ShortcutAction) -> KeyboardShortcut? { combo(action)?.shortcut }

    static func set(_ combo: KeyCombo?, for action: ShortcutAction) {
        var all = overrides
        if combo == action.defaultShortcut { all[action.rawValue] = nil } else { all[action.rawValue] = combo?.stored ?? none }
        overrides = all
    }

    static func reset() { overrides = [:] }

    static var isCustomised: Bool { !overrides.isEmpty }

    /// Which other action already uses this combination (Hush's own, or one macOS reserves).
    static func conflict(for combo: KeyCombo, except action: ShortcutAction) -> String? {
        if let other = ShortcutAction.allCases.first(where: { $0 != action && self.combo($0) == combo }) { return other.title }
        let reserved: [(KeyCombo, String)] = [(KeyCombo("q"), "Quit"), (KeyCombo(","), "Settings"), (KeyCombo("h"), "Hide Ufolio"),
                                              (KeyCombo("m"), "Minimise"), (KeyCombo("c"), "Copy"), (KeyCombo("v"), "Paste"),
                                              (KeyCombo("x"), "Cut"), (KeyCombo("a"), "Select All"), (KeyCombo("z"), "Undo")]
        return reserved.first { $0.0 == combo }?.1
    }
}

// MARK: - Settings › Keyboard

struct KeyboardSettings: View {
    @AppStorage(Shortcuts.storageKey) private var overridesText = ""   // redraws when shortcuts change
    @State private var recording: ShortcutAction?
    @State private var message: String?
    @State private var monitor: Any?
    @State private var revision = 0

    private var groups: [(String, [ShortcutAction])] {
        var order: [String] = []
        var map: [String: [ShortcutAction]] = [:]
        for action in ShortcutAction.allCases {
            if map[action.group] == nil { order.append(action.group) }
            map[action.group, default: []].append(action)
        }
        return order.map { ($0, map[$0] ?? []) }
    }

    var body: some View {
        Form {
            Section {
                SettingsHeader(tab: .keyboard, subtitle: "See every shortcut, and change any of them. Click a shortcut, then press the keys you’d like to use.")
            }
            ForEach(groups, id: \.0) { group in
                Section {
                    ForEach(group.1) { action in
                        LabeledContent(action.title) {
                            ShortcutField(action: action, recording: recording == action, revision: revision) {
                                startRecording(action)
                            }
                        }
                    }
                } header: { SectionTitle(group.0) }
            }
            Section {
                HStack {
                    if let message {
                        Label(message, systemImage: "exclamationmark.circle.fill").font(.system(size: 11.5)).foregroundStyle(.orange)
                    }
                    Spacer()
                    Button("Restore Defaults") {
                        Shortcuts.reset()
                        revision += 1
                        message = nil
                    }
                    .disabled(!Shortcuts.isCustomised)
                }
            } footer: {
                Footnote("While recording: press Delete to remove a shortcut, or Esc to cancel. Shortcuts need ⌘ or ⌃.")
            }
        }
        .formStyle(SafariFormStyle())
        .onDisappear(perform: stopRecording)
    }

    private func startRecording(_ action: ShortcutAction) {
        stopRecording()
        recording = action
        message = nil
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Only keys pressed in Settings: typing in a browser window mid-recording used to be swallowed.
            guard let action = recording, event.window?.identifier?.rawValue == "settings" else { return event }
            switch event.keyCode {
            case 53:                                   // Esc: cancel
                stopRecording()
            case 51, 117:                              // Delete: remove the shortcut
                Shortcuts.set(nil, for: action)
                revision += 1
                stopRecording()
            default:
                let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                guard flags.contains(.command) || flags.contains(.control) else {
                    message = "Shortcuts need ⌘ or ⌃."
                    return nil
                }
                // The key itself, without Shift applied: ⇧⌘[ used to be recorded as ⇧⌘{ (the shifted
                // character), which showed oddly and didn't trigger reliably.
                let base = event.characters(byApplyingModifiers: []) ?? event.charactersIgnoringModifiers
                guard let key = base?.lowercased().first, key.isASCII, !key.isWhitespace else { return nil }
                var mods: EventModifiers = []
                if flags.contains(.command) { mods.insert(.command) }
                if flags.contains(.shift) { mods.insert(.shift) }
                if flags.contains(.option) { mods.insert(.option) }
                if flags.contains(.control) { mods.insert(.control) }
                let combo = KeyCombo(String(key), mods)
                if let clash = Shortcuts.conflict(for: combo, except: action) {
                    message = "\(combo.display) is already used for \(clash)."
                    return nil
                }
                Shortcuts.set(combo, for: action)
                revision += 1
                stopRecording()
            }
            return nil
        }
    }

    private func stopRecording() {
        recording = nil
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}

private struct ShortcutField: View {
    let action: ShortcutAction
    let recording: Bool
    let revision: Int
    let onClick: () -> Void
    @State private var hovering = false

    var body: some View {
        let combo = Shortcuts.combo(action)
        let changed = combo != action.defaultShortcut
        Button(action: onClick) {
            HStack(spacing: 6) {
                if recording {
                    Text("Type a shortcut…").foregroundStyle(Color.accentColor)
                } else {
                    Text(combo?.display ?? "None")
                        .foregroundStyle(combo == nil ? .secondary : .primary)
                        .font(.system(size: 12.5, design: .rounded).weight(.medium))
                }
                if changed && !recording {
                    Circle().fill(Color.accentColor).frame(width: 5, height: 5).help("Changed from \(action.defaultShortcut.display)")
                }
            }
            .frame(minWidth: 110)
            .padding(.vertical, 4)
            .padding(.horizontal, 10)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(recording ? Color.accentColor.opacity(0.12) : Color.primary.opacity(hovering ? 0.09 : 0.055)))
            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(recording ? Color.accentColor : Color.clear, lineWidth: 1.5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .id(revision)
    }
}
