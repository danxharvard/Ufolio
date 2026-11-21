import SwiftUI
import AppKit

@main
struct HushApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage(Prefs.appearance) private var appearance = AppearanceMode.system.rawValue
    @AppStorage(Prefs.accent) private var accent = AccentChoice.system.rawValue
    @AppStorage(Prefs.reduceMotion) private var reduceMotion = false

    init() {
        Prefs.register()
    }

    var body: some Scene {
        WindowGroup {
            BrowserWindow()
                .accentColor(AccentChoice(rawValue: accent)?.color)
                .transaction { if reduceMotion { $0.animation = nil } }
                .onAppear { AppearanceMode.apply(appearance) }
                .onChange(of: appearance) { AppearanceMode.apply($0) }
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified(showsTitle: false))
        .defaultSize(width: 1280, height: 820)
        .commands { HushCommands() }

        Settings {
            SettingsView()
                .transaction { if reduceMotion { $0.animation = nil } }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        // Hush has its own tabs; switch off macOS's window tabbing.
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    func applicationWillTerminate(_ notification: Notification) {
        BlockStats.shared.save()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        ContentBlocker.shared.prepare()
        Updater.shared.start()
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
        // SwiftUI refuses to quit while one of its sheets is open, so Quit closes them first.
        CommandGroup(replacing: .appTermination) {
            Button("Quit Hush Browser") { QuitHelper.quit() }
                .keyboardShortcut("q")
        }

        CommandGroup(after: .appInfo) {
            Button("Check for Updates…") {
                SettingsOpener.open(tab: .updates)
                Task { await Updater.shared.check(userInitiated: true) }
            }
        }

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
            Toggle("Block Ads", isOn: $adBlockEnabled)
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

enum QuitHelper {
    static let closeSheets = Notification.Name("HushCloseSheets")

    static func quit() {
        let hasSheet = NSApp.windows.contains { !$0.sheets.isEmpty }
        guard hasSheet else { NSApp.terminate(nil); return }
        NotificationCenter.default.post(name: closeSheets, object: nil)
        for window in NSApp.windows {
            for sheet in window.sheets { window.endSheet(sheet) }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { NSApp.terminate(nil) }
    }
}
