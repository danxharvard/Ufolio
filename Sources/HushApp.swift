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
        Window("Ufolio Browser", id: "browser") {
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
        WindowGroup("Stealth Mode", id: "private") {
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

        // Settings is Hush's own window (SettingsWindow), which opens much faster than SwiftUI's.

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

    /// Quitting cancels downloads that are still running, so ask first (as Safari does).
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let running = Downloads.shared.activeCount
        guard running > 0 else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = running == 1 ? "A download is still in progress." : "\(running) downloads are still in progress."
        alert.informativeText = "If you quit now, \(running == 1 ? "it" : "they") will be cancelled."
        alert.addButton(withTitle: "Don’t Quit")
        alert.addButton(withTitle: "Quit")
        return alert.runModal() == .alertSecondButtonReturn ? .terminateNow : .terminateCancel
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Write everything out before Hush exits (background saves might not finish otherwise).
        BrowserModel.all.allObjects.forEach { $0.saveSessionNow() }   // the last second of changes too
        BookmarkStore.shared.saveNow(waiting: true)
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
        Lookalike.refreshKnown()   // ready before the first page loads
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
    @AppStorage(Prefs.tabLayout) private var tabLayout = TabLayout.top.rawValue
    @AppStorage(Prefs.adBlockEnabled) private var adBlockEnabled = true
    @AppStorage(Prefs.appearance) private var appearance = AppearanceMode.system.rawValue

    var body: some Commands {
        // SwiftUI refuses to quit while one of its sheets is open, so Quit closes them first.
        CommandGroup(replacing: .appTermination) {
            Button("Quit Ufolio Browser") { QuitHelper.quit() }
                .keyboardShortcut("q")
        }

        CommandGroup(replacing: .appSettings) {
            Button("Settings…") { SettingsWindow.show() }
                .keyboardShortcut(",", modifiers: .command)
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
            Button("New Stealth Window") { openWindow(id: "private") }
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
            Button("Close Tab") {
                // In Settings or History, ⌘W closes that window, not a tab in the browser behind it.
                if let key = NSApp.keyWindow, !BrowserModel.all.allObjects.contains(where: { $0.window === key }) {
                    key.performClose(nil)
                } else {
                    browser?.closeSelectedTab()
                }
            }
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
            Toggle("Show Tabs Down the Side", isOn: Binding(
                get: { tabLayout == TabLayout.side.rawValue },
                set: { tabLayout = ($0 ? TabLayout.side : TabLayout.top).rawValue }))
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
            Button("Next Orbit") { browser?.switchSpace(by: 1) }
                .keyboardShortcut(Shortcuts.get(.nextSpace))
                .disabled(browser?.isPrivate != false)
            Button("Previous Orbit") { browser?.switchSpace(by: -1) }
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
                // The first 40 not in a folder: macOS rebuilds the whole menu bar whenever bookmarks
                // change, and listing thousands made that a noticeable pause.
                ForEach(bookmarks.items(in: nil).prefix(40)) { bookmark in
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
        if let item = items.first(where: { $0.title == "Ufolio Browser" && $0.action != nil }), let menu = item.menu {
            menu.performActionForItem(at: menu.index(of: item))
        }
        NSApp.activate(ignoringOtherApps: true)
    }
}


/// Hush's Settings window. SwiftUI's built-in Settings window took most of a second to appear
/// every time; this one is built when you first open it and then kept ready, so it reopens
/// instantly. If the Mac runs short of memory it's let go (see PerformanceCenter).
@MainActor
enum SettingsWindow {
    private static var window: NSWindow?

    /// Whether the window's contents are live. A closed Settings window would otherwise keep
    /// redrawing in the background whenever ads are blocked, stats change or memory is measured.
    final class Presence: ObservableObject { @Published var live = true }
    static let presence = Presence()
    private static var closeObserver: NSObjectProtocol?
    private static var idleRelease: DispatchWorkItem?

    static func show() {
        let w = window ?? make()
        window = w
        idleRelease?.cancel()
        if !presence.live { presence.live = true }
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }

    /// Lets go of the window (when memory is short), unless it's open.
    static func releaseNow() {
        guard let w = window, !w.isVisible else { return }
        w.contentViewController = nil
        window = nil
        // The old window's close-watcher goes too (a new one is made with the next window).
        if let closeObserver { NotificationCenter.default.removeObserver(closeObserver) }
        closeObserver = nil
        idleRelease?.cancel()
    }

    private static func make() -> NSWindow {
        let controller = NSHostingController(rootView: SettingsRoot())
        controller.sceneBridgingOptions = [.all]   // the centred title and sidebar search
        let w = NSWindow(contentViewController: controller)
        w.title = "Settings"
        w.identifier = NSUserInterfaceItemIdentifier("settings")
        w.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
        w.isReleasedWhenClosed = false
        w.tabbingMode = .disallowed
        if !w.setFrameUsingName("HushSettings") { w.center() }
        w.setFrameAutosaveName("HushSettings")
        closeObserver = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: w, queue: .main) { _ in
            MainActor.assumeIsolated {
                // Reopening within half a minute is instant; after that the contents are put away.
                let work = DispatchWorkItem { if !(window?.isVisible ?? false) { presence.live = false } }
                idleRelease?.cancel()
                idleRelease = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 30, execute: work)
            }
        }
        return w
    }
}

private struct SettingsRoot: View {
    @AppStorage(Prefs.reduceMotion) private var reduceMotion = false
    @ObservedObject private var presence = SettingsWindow.presence
    var body: some View {
        if presence.live {
            SettingsView()
                .hushDialogs(DialogHost.settings)
                .transaction { if reduceMotion { $0.animation = nil } }
        } else {
            Color.clear
        }
    }
}
