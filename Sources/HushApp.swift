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
        // ONE WINDOW: Hush has a single browser window with unlimited tabs.
        Window("Hush Browser", id: "browser") {
            BrowserWindow()
                .accentColor(AccentChoice(rawValue: accent)?.color)
                .transaction { if reduceMotion { $0.animation = nil } }
                .onAppear { AppearanceMode.apply(appearance) }
                .onChange(of: appearance) { AppearanceMode.apply($0) }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1280, height: 820)
        .commands { HushCommands() }

        // Private Browsing windows (⇧⌘N): as many as you like, each forgetting everything when closed.
        WindowGroup("Private Browsing", id: "private") {
            BrowserWindow(isPrivate: true)
                .accentColor(Color(red: 0.70, green: 0.60, blue: 1.0))
                .transaction { if reduceMotion { $0.animation = nil } }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1180, height: 780)

        Window("History", id: "history") {
            HistoryWindowView()
        }
        .defaultSize(width: 640, height: 640)

        Settings {
            SettingsView()
                .transaction { if reduceMotion { $0.animation = nil } }
        }

    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        // Only one Hush at a time: if another copy is already running, bring it forward and quit.
        if let id = Bundle.main.bundleIdentifier {
            let others = NSRunningApplication.runningApplications(withBundleIdentifier: id)
                .filter { $0 != NSRunningApplication.current }
            if let running = others.first {
                running.activate(options: [.activateAllWindows])
                exit(0)
            }
        }
        // Hush has its own tabs; switch off macOS's window tabbing.
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Write everything out before Hush exits (background saves might not finish otherwise).
        BlockStats.shared.save()
        PrivacyReport.shared.save(waiting: true)
        HistoryStore.shared.save(waiting: true)
    }

    /// Clicking Hush in the Dock with no window open brings one back.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !BrowserModel.hasVisibleWindow { WindowOpener.ensureWindow() }
        return true
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // If Hush last quit with its window closed, show it again. With a single-window
        // scene this can only ever show the one window, never a second.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            if !BrowserModel.hasVisibleWindow { WindowOpener.ensureWindow() }
        }
        ContentBlocker.shared.prepare()
        ExtensionEvents.launch()
        PerformanceCenter.shared.start()
        Updater.shared.start()
    }
}

struct HushCommands: Commands {
    @Environment(\.openWindow) private var openWindow
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

        CommandGroup(replacing: .newItem) {
            Button("New Tab") {
                WindowOpener.ensureWindow()
                browser?.newTab(focus: true)
            }
            .keyboardShortcut("t")
            Button("New Private Window") { openWindow(id: "private") }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            Button("Open Location…") { browser?.focusAddressBar() }
                .keyboardShortcut("l")
        }

        Group {
        CommandGroup(after: .textEditing) {
            Divider()
            Button("Find on Page…") { browser?.find.show() }
                .keyboardShortcut("f")
            Button("Find Next") { browser?.find.search(in: browser?.selectedTab?.webView) }
                .keyboardShortcut("g")
            Button("Find Previous") { browser?.find.search(in: browser?.selectedTab?.webView, backwards: true) }
                .keyboardShortcut("g", modifiers: [.command, .shift])
        }

        CommandGroup(replacing: .printItem) {
            Button("Print…") { browser?.selectedTab?.printPage() }
                .keyboardShortcut("p")
        }

        CommandGroup(after: .pasteboard) {
            Button("Copy Clean Link") {
                guard let url = browser?.selectedTab?.url else { return }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(CleanLinks.clean(url).absoluteString, forType: .string)
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])
        }

        CommandGroup(replacing: .saveItem) {
            Button("Close Tab") { browser?.closeSelectedTab() }
                .keyboardShortcut("w")
            Button("Close Window") { NSApp.keyWindow?.performClose(nil) }
                .keyboardShortcut("w", modifiers: [.command, .shift])
            Divider()
            Button("Save Page As…") { browser?.selectedTab?.savePage() }
                .keyboardShortcut("s")
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
            Button(browser?.selectedTab?.reader != nil ? "Leave Reader" : "Show Reader") { browser?.selectedTab?.toggleReader() }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            Button("Picture in Picture") {
                if let view = browser?.selectedTab?.webView { WebKitExtras.togglePictureInPicture(view) }
            }
            .keyboardShortcut("p", modifiers: [.command, .option])
            Button("Translate Page") {
                guard let tab = browser?.selectedTab else { return }
                if tab.translation == .translated { PageTranslator.shared.showOriginal(tab) } else { PageTranslator.shared.translate(tab) }
            }
            .keyboardShortcut("y", modifiers: [.command, .shift])
            Divider()
            Toggle("Show Bookmarks Bar", isOn: $showBookmarkBar)
                .keyboardShortcut("b", modifiers: [.command, .shift])
            Toggle("Block Ads", isOn: $adBlockEnabled)
            Picker("Appearance", selection: $appearance) {
                ForEach(AppearanceMode.allCases) { Text($0.label).tag($0.rawValue) }
            }
            Divider()
        }

        CommandMenu("Tab") {
            Button(browser?.selectedTab?.isMuted == true ? "Unmute Tab" : "Mute Tab") { browser?.selectedTab?.toggleMute() }
                .keyboardShortcut("m", modifiers: [.command, .control])
            Button(browser?.selectedTab?.isPinned == true ? "Unpin Tab" : "Pin Tab") {
                if let model = browser, let tab = model.selectedTab { model.togglePin(tab) }
            }
        }
        }

        CommandMenu("History") {
            Button("Show All History") { openWindow(id: "history") }
                .keyboardShortcut("y")
            Divider()
            Button("Reopen Closed Tab") { browser?.reopenClosedTab() }
                .keyboardShortcut("t", modifiers: [.command, .shift])
            Divider()
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

enum WindowOpener {
    /// Shows the browser window, bringing it back if it was closed. There is only ever one.
    static func ensureWindow() {
        if BrowserModel.hasVisibleWindow {
            BrowserModel.frontmost?.window?.makeKeyAndOrderFront(nil)
            return
        }
        // SwiftUI lists the single window in the Window menu; choosing it reopens that window.
        let items = NSApp.mainMenu?.items.flatMap { $0.submenu?.items ?? [] } ?? []
        if let item = items.first(where: { $0.title == "Hush Browser" && $0.action != nil }), let menu = item.menu {
            menu.performActionForItem(at: menu.index(of: item))
        }
        NSApp.activate(ignoringOtherApps: true)
    }
}
