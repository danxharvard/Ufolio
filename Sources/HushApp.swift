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
                .onChange(of: appearance) { _, mode in AppearanceMode.apply(mode) }
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
                .hushDialogs(DialogHost.settings)
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
        ContentBlocker.shared.startListUpdates()
        ExtensionEvents.launch()
        PerformanceCenter.shared.start()
        Updater.shared.start()
        RemovedFeatures.cleanUp()
        #if SNAPSHOT
        Snapshotter.run()   // automated screenshots in test builds only; never in releases
        #endif
    }
}

struct HushCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    /// Redraws the menus when you change a shortcut in Settings › Keyboard.
    @AppStorage(Shortcuts.storageKey) private var shortcutOverrides = ""
    @FocusedObject private var focusedBrowser: BrowserModel?
    private var browser: BrowserModel? { focusedBrowser ?? BrowserModel.frontmost }
    @ObservedObject private var bookmarks = BookmarkStore.shared
    @ObservedObject private var spaces = SpaceStore.shared
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
            .keyboardShortcut(Shortcuts.get(.newTab))
            Button("New Private Window") { openWindow(id: "private") }
                .keyboardShortcut(Shortcuts.get(.privateWindow))
            Button("Open Location…") { browser?.focusAddressBar() }
                .keyboardShortcut(Shortcuts.get(.openLocation))
            Button("Command Palette…") {
                WindowOpener.ensureWindow()
                browser?.paletteOpen.toggle()
            }
            .keyboardShortcut(Shortcuts.get(.commandPalette))
        }

        Group {
        CommandGroup(after: .textEditing) {
            Divider()
            Button("Find on Page…") { browser?.find.show() }
                .keyboardShortcut(Shortcuts.get(.find))
            Button("Find Next") { browser?.find.search(in: browser?.selectedTab?.webView) }
                .keyboardShortcut(Shortcuts.get(.findNext))
            Button("Find Previous") { browser?.find.search(in: browser?.selectedTab?.webView, backwards: true) }
                .keyboardShortcut(Shortcuts.get(.findPrevious))
        }

        CommandGroup(replacing: .printItem) {
            Button("Print…") { browser?.selectedTab?.printPage() }
                .keyboardShortcut(Shortcuts.get(.print))
        }

        CommandGroup(after: .pasteboard) {
            Button("Copy Clean Link") {
                guard let url = browser?.selectedTab?.url else { return }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(CleanLinks.clean(url).absoluteString, forType: .string)
            }
            .keyboardShortcut(Shortcuts.get(.copyCleanLink))
        }

        CommandGroup(replacing: .saveItem) {
            Button("Close Tab") { browser?.closeSelectedTab() }
                .keyboardShortcut(Shortcuts.get(.closeTab))
            Button("Close Window") { NSApp.keyWindow?.performClose(nil) }
                .keyboardShortcut(Shortcuts.get(.closeWindow))
            Divider()
            Button("Save Page As…") { browser?.selectedTab?.savePage() }
                .keyboardShortcut(Shortcuts.get(.savePage))
        }

        CommandGroup(before: .toolbar) {
            Button("Reload Page") { browser?.selectedTab?.reload() }
                .keyboardShortcut(Shortcuts.get(.reload))
            Divider()
            Button("Zoom In") { browser?.selectedTab?.zoom(by: 0.1) }
                .keyboardShortcut(Shortcuts.get(.zoomIn))
            Button("Zoom Out") { browser?.selectedTab?.zoom(by: -0.1) }
                .keyboardShortcut(Shortcuts.get(.zoomOut))
            Button("Actual Size") { browser?.selectedTab?.resetZoom() }
                .keyboardShortcut(Shortcuts.get(.actualSize))
            Divider()
            Button(browser?.sidebarOpen == true ? "Hide Sidebar" : "Show Sidebar") { browser?.sidebarOpen.toggle() }
                .keyboardShortcut(Shortcuts.get(.sidebar))
            Button(browser?.splitPair != nil ? "Close Split View" : "Split View") {
                guard let model = browser else { return }
                if model.splitPair != nil { model.closeSplit(keeping: model.selectedID) } else { model.openSplit() }
            }
            .keyboardShortcut(Shortcuts.get(.splitView))
            Button(browser?.selectedTab?.reader != nil ? "Leave Reader" : "Show Reader") { browser?.selectedTab?.toggleReader() }
                .keyboardShortcut(Shortcuts.get(.reader))
            Button("Picture in Picture") {
                if let view = browser?.selectedTab?.webView { WebKitExtras.togglePictureInPicture(view) }
            }
            .keyboardShortcut(Shortcuts.get(.pictureInPicture))
            Button("Translate Page") {
                guard let tab = browser?.selectedTab else { return }
                if tab.translation == .translated { PageTranslator.shared.showOriginal(tab) } else { PageTranslator.shared.translate(tab) }
            }
            .keyboardShortcut(Shortcuts.get(.translate))
            Divider()
            Toggle("Show Bookmarks Bar", isOn: $showBookmarkBar)
                .keyboardShortcut(Shortcuts.get(.bookmarksBar))
            Toggle("Block Ads", isOn: $adBlockEnabled)
            Picker("Appearance", selection: $appearance) {
                ForEach(AppearanceMode.allCases) { Text($0.label).tag($0.rawValue) }
            }
            Divider()
        }

        CommandMenu("Tab") {
            Button(browser?.selectedTab?.isMuted == true ? "Unmute Tab" : "Mute Tab") { browser?.selectedTab?.toggleMute() }
                .keyboardShortcut(Shortcuts.get(.muteTab))
            Button(browser?.selectedTab?.isPinned == true ? "Unpin Tab" : "Pin Tab") {
                if let model = browser, let tab = model.selectedTab { model.togglePin(tab) }
            }
            Divider()
            Button("Next Space") { browser?.switchSpace(by: 1) }
                .keyboardShortcut(Shortcuts.get(.nextSpace))
                .disabled(browser?.isPrivate != false)
            Button("Previous Space") { browser?.switchSpace(by: -1) }
                .keyboardShortcut(Shortcuts.get(.previousSpace))
                .disabled(browser?.isPrivate != false)
            ForEach(Array(spaces.spaces.prefix(9).enumerated()), id: \.element.id) { index, space in
                Button("Show \(space.name)") { browser?.switchSpace(to: space.id) }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .control)
                    .disabled(browser?.isPrivate != false)
            }
        }
        }

        CommandMenu("History") {
            Button("Show All History") { openWindow(id: "history") }
                .keyboardShortcut(Shortcuts.get(.history))
            Divider()
            Button("Reopen Closed Tab") { browser?.reopenClosedTab() }
                .keyboardShortcut(Shortcuts.get(.reopenTab))
            Divider()
            Button("Back") { browser?.selectedTab?.webView.goBack() }
                .keyboardShortcut(Shortcuts.get(.back))
            Button("Forward") { browser?.selectedTab?.webView.goForward() }
                .keyboardShortcut(Shortcuts.get(.forward))
            Divider()
            Button("Show Next Tab") { browser?.selectAdjacentTab(1) }
                .keyboardShortcut(Shortcuts.get(.nextTab))
            Button("Show Previous Tab") { browser?.selectAdjacentTab(-1) }
                .keyboardShortcut(Shortcuts.get(.previousTab))
        }

        CommandMenu("Bookmarks") {
            Button("Bookmark This Page") { browser?.toggleBookmarkForSelectedTab() }
                .keyboardShortcut(Shortcuts.get(.bookmark))
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
