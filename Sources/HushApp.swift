import SwiftUI
import AppKit

@main
struct HushApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage(Prefs.appearance) private var appearance = AppearanceMode.system.rawValue

    var body: some Scene {
        WindowGroup {
            BrowserWindow()
                .onAppear { AppearanceMode.apply(appearance) }
                .onChange(of: appearance) { AppearanceMode.apply($0) }
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified(showsTitle: false))
        .defaultSize(width: 1280, height: 820)
        .commands { HushCommands() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        // Hush has its own tabs; switch off macOS's window tabbing.
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        AdBlocker.shared.prepare()
    }
}

enum Prefs {
    static let appearance = "appearance"
    static let showBookmarkBar = "showBookmarkBar"
    static let adBlockEnabled = "adBlockEnabled"
}

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "Match System"
        case .light: return "Day"
        case .dark: return "Night"
        }
    }

    static func apply(_ raw: String) {
        switch AppearanceMode(rawValue: raw) ?? .system {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
}

struct HushCommands: Commands {
    @FocusedObject private var focusedBrowser: BrowserModel?
    private var browser: BrowserModel? { focusedBrowser ?? BrowserModel.frontmost }
    @ObservedObject private var bookmarks = BookmarkStore.shared
    @AppStorage(Prefs.showBookmarkBar) private var showBookmarkBar = true
    @AppStorage(Prefs.adBlockEnabled) private var adBlockEnabled = true
    @AppStorage(Prefs.appearance) private var appearance = AppearanceMode.system.rawValue

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("New Tab") { browser?.newTab(focus: true) }
                .keyboardShortcut("t")
            Button("Open Location…") { browser?.focusAddressBar() }
                .keyboardShortcut("l")
        }

        CommandGroup(replacing: .saveItem) {
            Button("Close Tab") { browser?.closeSelectedTab() }
                .keyboardShortcut("w")
            Button("Close Window") { NSApp.keyWindow?.performClose(nil) }
                .keyboardShortcut("w", modifiers: [.command, .shift])
        }

        CommandGroup(before: .toolbar) {
            Button("Reload Page") { browser?.selectedTab?.reload() }
                .keyboardShortcut("r")
            Divider()
            Button("Zoom In") { browser?.selectedTab?.zoom(by: 0.1) }
                .keyboardShortcut("+")
            Button("Zoom Out") { browser?.selectedTab?.zoom(by: -0.1) }
                .keyboardShortcut("-")
            Button("Actual Size") { browser?.selectedTab?.resetZoom() }
                .keyboardShortcut("0")
            Divider()
            Toggle("Show Bookmarks Bar", isOn: $showBookmarkBar)
                .keyboardShortcut("b", modifiers: [.command, .shift])
            Toggle("Block Ads and Trackers", isOn: $adBlockEnabled)
            Picker("Appearance", selection: $appearance) {
                ForEach(AppearanceMode.allCases) { Text($0.label).tag($0.rawValue) }
            }
            Divider()
        }

        CommandMenu("History") {
            Button("Back") { browser?.selectedTab?.webView.goBack() }
                .keyboardShortcut("[")
            Button("Forward") { browser?.selectedTab?.webView.goForward() }
                .keyboardShortcut("]")
            Divider()
            Button("Show Next Tab") { browser?.selectAdjacentTab(1) }
                .keyboardShortcut("]", modifiers: [.command, .shift])
            Button("Show Previous Tab") { browser?.selectAdjacentTab(-1) }
                .keyboardShortcut("[", modifiers: [.command, .shift])
        }

        CommandMenu("Bookmarks") {
            Button("Bookmark This Page") { browser?.toggleBookmarkForSelectedTab() }
                .keyboardShortcut("d")
            if !bookmarks.items.isEmpty {
                Divider()
                ForEach(bookmarks.items) { bookmark in
                    Button(bookmark.title) { browser?.open(bookmark.url) }
                }
            }
        }
    }
}
