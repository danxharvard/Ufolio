import AppKit
import SwiftUI
import WebKit

// MARK: - Safari extensions on this Mac

/// A Safari extension found inside an installed app (Safari extensions ship inside Mac apps,
/// usually from the Mac App Store).
struct SafariExtensionInfo: Identifiable {
    enum Kind { case webExtension, contentBlocker }
    let bundleID: String
    let name: String
    let appName: String
    let appURL: URL
    let appexURL: URL
    let kind: Kind
    var id: String { bundleID }

    /// The content blocker's rules, if the app ships them as a file Hush can read.
    var blockerList: URL? {
        let file = appexURL.appendingPathComponent("Contents/Resources/blockerList.json")
        return FileManager.default.fileExists(atPath: file.path) ? file : nil
    }
}

enum SafariExtensionFinder {
    static func find() -> [SafariExtensionInfo] {
        let fm = FileManager.default
        let folders = [URL(fileURLWithPath: "/Applications"), fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications")]
        var found: [SafariExtensionInfo] = []
        for folder in folders {
            guard let apps = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else { continue }
            for app in apps where app.pathExtension == "app" {
                let plugins = app.appendingPathComponent("Contents/PlugIns")
                guard let appexes = try? fm.contentsOfDirectory(at: plugins, includingPropertiesForKeys: nil) else { continue }
                for appex in appexes where appex.pathExtension == "appex" {
                    guard let bundle = Bundle(url: appex), let info = bundle.infoDictionary,
                          let point = (info["NSExtension"] as? [String: Any])?["NSExtensionPointIdentifier"] as? String,
                          let id = bundle.bundleIdentifier else { continue }
                    let kind: SafariExtensionInfo.Kind
                    switch point {
                    case "com.apple.Safari.web-extension": kind = .webExtension
                    case "com.apple.Safari.content-blocker": kind = .contentBlocker
                    default: continue
                    }
                    let name = (info["CFBundleDisplayName"] as? String) ?? (info["CFBundleName"] as? String) ?? appex.deletingPathExtension().lastPathComponent
                    found.append(SafariExtensionInfo(bundleID: id, name: name, appName: app.deletingPathExtension().lastPathComponent,
                                                     appURL: app, appexURL: appex, kind: kind))
                }
            }
        }
        return found.sorted { $0.appName.localizedCaseInsensitiveCompare($1.appName) == .orderedAscending }
    }
}

// MARK: - Installed extensions (any macOS)

struct InstalledExtension: Codable, Identifiable, Equatable {
    var id: String          // Chrome Web Store ID, "safari-<bundle id>", or generated for unpacked folders
    var name: String
    var version: String
    var enabled = true
    var source: String?     // the Chrome Web Store page, or "safari:<path to the .appex>"

    var isSafari: Bool { source?.hasPrefix("safari:") == true }
    var safariBundleURL: URL? { isSafari ? URL(fileURLWithPath: String(source!.dropFirst(7))) : nil }
}

/// Keeps track of installed extensions and installs new ones from the Chrome Web Store or a
/// folder. Running them needs WebKit's extension system, which arrived in macOS 15.4.
final class ExtensionStore: ObservableObject {
    static let shared = ExtensionStore()

    @Published private(set) var installed: [InstalledExtension] = []
    @Published private(set) var isWorking = false
    @Published var status: String?
    @Published var statusIsError = false

    let folder: URL
    private var listFile: URL { folder.appendingPathComponent("extensions.json") }

    static var isSupported: Bool {
        if #available(macOS 15.4, *) { return true }
        return false
    }

    private init() {
        folder = AppPaths.support.appendingPathComponent("Extensions", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if let saved = AppPaths.load([InstalledExtension].self, from: listFile) {
            installed = saved
        }
    }

    func directory(for ext: InstalledExtension) -> URL {
        folder.appendingPathComponent(ext.id, isDirectory: true)
    }

    private func save() {
        if let data = try? JSONEncoder().encode(installed) { try? data.write(to: listFile, options: .atomic) }
    }

    /// The 32-letter extension ID in a Chrome Web Store link (or the ID on its own).
    static func webStoreID(from text: String) -> String? {
        let pattern = try! NSRegularExpression(pattern: "(?:^|[/=])([a-p]{32})(?:$|[/?#&])")
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let range = NSRange(trimmed.startIndex..., in: trimmed)
        guard let match = pattern.firstMatch(in: trimmed, range: range),
              let idRange = Range(match.range(at: 1), in: trimmed) else { return nil }
        return String(trimmed[idRange])
    }

    // MARK: Installing

    @MainActor
    func install(fromWebStore text: String) async {
        guard let id = Self.webStoreID(from: text) else {
            report("That doesn’t look like a Chrome Web Store link. Open the extension’s page in the Web Store and copy its address.", error: true)
            return
        }
        isWorking = true
        status = "Downloading…"
        statusIsError = false
        do {
            var components = URLComponents(string: "https://clients2.google.com/service/update2/crx")!
            components.queryItems = [
                .init(name: "response", value: "redirect"),
                .init(name: "prodversion", value: "131.0"),
                .init(name: "acceptformat", value: "crx2,crx3"),
                .init(name: "x", value: "id=\(id)&uc"),
            ]
            let (data, response) = try await URLSession.shared.data(from: components.url!)
            guard (response as? HTTPURLResponse)?.statusCode == 200, !data.isEmpty else {
                throw ExtensionError("The Chrome Web Store didn’t provide this extension.")
            }
            guard data.count < 200_000_000 else { throw ExtensionError("This extension is too large to add.") }
            let zip = try Self.zipData(fromCRX: data)
            let staging = try await Self.unpack(zip: zip)
            // Always link to the store page itself, never to whatever text was pasted.
            await finishInstall(from: staging, id: id, source: "https://chromewebstore.google.com/detail/\(id)")
        } catch {
            report(error.localizedDescription, error: true)
        }
    }

    /// Adds a Safari web extension. It keeps running from inside its own app.
    @MainActor
    func install(safari info: SafariExtensionInfo) async {
        guard #available(macOS 15.4, *) else { report("Extensions need macOS 15.4 or later.", error: true); return }
        guard let bundle = Bundle(url: info.appexURL) else { report("Couldn’t open \(info.appName)’s extension.", error: true); return }
        isWorking = true
        statusIsError = false
        do {
            let ext = try await WKWebExtension(appExtensionBundle: bundle)
            let name = ext.displayName ?? info.name
            guard await ExtensionManager.shared.confirmInstall(ext, name: name) else {
                report("“\(name)” wasn’t added.", error: false)
                return
            }
            let record = InstalledExtension(id: "safari-" + info.bundleID, name: name,
                                            version: ext.displayVersion ?? ext.version ?? "",
                                            source: "safari:" + info.appexURL.path)
            installed.removeAll { $0.id == record.id }
            installed.append(record)
            save()
            await ExtensionManager.shared.load(record)
            report("Added “\(name)” from \(info.appName).", error: false)
        } catch {
            report("Ufolio couldn’t load this Safari extension: \(error.localizedDescription)", error: true)
        }
    }

    /// Installs an unpacked extension folder (for developers, or extensions from elsewhere).
    @MainActor
    func install(fromFolder url: URL) async {
        isWorking = true
        statusIsError = false
        let staging = FileManager.default.temporaryDirectory.appendingPathComponent("hush-ext-\(UUID().uuidString)")
        do {
            try await Task.detached(priority: .userInitiated) {
                try FileManager.default.copyItem(at: url, to: staging)
            }.value
            let id = "local-" + UUID().uuidString.lowercased().prefix(12)
            await finishInstall(from: staging, id: String(id), source: nil)
        } catch {
            report("Couldn’t read that folder: \(error.localizedDescription)", error: true)
        }
    }

    @MainActor
    private func finishInstall(from staging: URL, id: String, source: String?) async {
        defer { try? FileManager.default.removeItem(at: staging) }
        guard FileManager.default.fileExists(atPath: staging.appendingPathComponent("manifest.json").path) else {
            report("That isn’t a browser extension (it has no manifest.json).", error: true)
            return
        }
        guard #available(macOS 15.4, *) else {
            report("Extensions need macOS 15.4 or later.", error: true)
            return
        }
        do {
            try FolderSafety.check(staging)
            let ext = try await WKWebExtension(resourceBaseURL: staging)
            let name = ext.displayName ?? "Extension"
            guard await ExtensionManager.shared.confirmInstall(ext, name: name) else {
                report("“\(name)” wasn’t added.", error: false)
                return
            }
            let record = InstalledExtension(id: id, name: name, version: ext.displayVersion ?? ext.version ?? "",
                                            source: source)
            let destination = directory(for: record)
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.copyItem(at: staging, to: destination)
            installed.removeAll { $0.id == id }
            installed.append(record)
            save()
            await ExtensionManager.shared.load(record)
            report("Added “\(name)”.", error: false)
        } catch {
            report("Ufolio couldn’t load this extension: \(error.localizedDescription)", error: true)
        }
    }

    /// Chrome extensions come as .crx: a small signed header followed by an ordinary zip.
    static func zipData(fromCRX data: Data) throws -> Data {
        let bytes = [UInt8](data)
        func le32(_ offset: Int) -> Int {
            Int(bytes[offset]) | Int(bytes[offset + 1]) << 8 | Int(bytes[offset + 2]) << 16 | Int(bytes[offset + 3]) << 24
        }
        if bytes.count > 4, bytes[0] == 0x50, bytes[1] == 0x4B { return data } // already a zip
        guard bytes.count > 16, bytes[0] == 0x43, bytes[1] == 0x72, bytes[2] == 0x32, bytes[3] == 0x34 else { // "Cr24"
            throw ExtensionError("The download wasn’t a Chrome extension.")
        }
        let start: Int
        switch le32(4) {
        case 3: start = 12 + le32(8)
        case 2: start = 16 + le32(8) + le32(12)
        default: throw ExtensionError("This extension uses a format Ufolio doesn’t recognise.")
        }
        guard start < bytes.count else { throw ExtensionError("The extension download was damaged.") }
        return data.subdata(in: start..<data.count)
    }

    private static func unpack(zip: Data) async throws -> URL {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("hush-ext-\(UUID().uuidString)")
        let zipFile = temp.appendingPathExtension("zip")
        try zip.write(to: zipFile)
        defer { try? FileManager.default.removeItem(at: zipFile) }
        // Refuse archives with entries that would land outside the folder ("zip slip").
        let listing = try await ProcessRunner.run("/usr/bin/zipinfo", ["-1", zipFile.path])
        guard listing.succeeded else { throw ExtensionError("The extension couldn’t be unpacked.") }
        let names = listing.output.split(whereSeparator: \.isNewline)
        guard names.count < 50_000, !names.contains(where: { name in
            name.hasPrefix("/") || name.hasPrefix("~") || name.split(separator: "/").contains("..") || name.contains("\\")
        }) else { throw ExtensionError("This extension’s files are packed in an unsafe way, so Ufolio didn’t add it.") }
        // Nor links: a link to somewhere else on your Mac, followed by a file "inside" it, would
        // write outside the folder too. Extensions never need them.
        let details = try await ProcessRunner.run("/usr/bin/zipinfo", [zipFile.path])
        guard details.succeeded, !details.output.split(whereSeparator: \.isNewline).contains(where: { $0.hasPrefix("l") }) else {
            throw ExtensionError("This extension’s files are packed in an unsafe way, so Ufolio didn’t add it.")
        }
        let unzip = try await ProcessRunner.run("/usr/bin/ditto", ["-x", "-k", zipFile.path, temp.path])
        guard unzip.succeeded else { throw ExtensionError("The extension couldn’t be unpacked.") }
        // Chrome's signature metadata isn't used by WebKit.
        try? FileManager.default.removeItem(at: temp.appendingPathComponent("_metadata"))
        return temp
    }

    // MARK: Managing

    @MainActor
    func setEnabled(_ ext: InstalledExtension, _ enabled: Bool) {
        guard let i = installed.firstIndex(where: { $0.id == ext.id }) else { return }
        installed[i].enabled = enabled
        save()
        if #available(macOS 15.4, *) {
            let record = installed[i]   // captured now: the list may change before the task runs
            if enabled { Task { await ExtensionManager.shared.load(record) } } else { ExtensionManager.shared.unload(ext.id) }
        }
    }

    /// Extensions with their own button next to Hush Guard: the first three running ones.
    func inToolbar(_ ext: InstalledExtension) -> Bool {
        installed.filter(\.enabled).prefix(3).contains { $0.id == ext.id }
    }

    /// Moves an extension to the front, so it gets one of the three toolbar buttons.
    @MainActor
    func showInToolbar(_ ext: InstalledExtension) {
        guard let i = installed.firstIndex(where: { $0.id == ext.id }), i > 0 else { return }
        installed.insert(installed.remove(at: i), at: 0)
        save()
    }

    @MainActor
    func remove(_ ext: InstalledExtension) {
        if #available(macOS 15.4, *) { ExtensionManager.shared.unload(ext.id) }
        installed.removeAll { $0.id == ext.id }
        save()
        // Safari extensions live inside their own app: never delete that.
        if !ext.isSafari { try? FileManager.default.removeItem(at: directory(for: ext)) }
    }

    @MainActor
    private func report(_ message: String, error: Bool) {
        isWorking = false
        status = message
        statusIsError = error
    }
}

struct ExtensionError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

/// Tells running extensions what the browser is doing. Safe to call on any macOS.
enum ExtensionEvents {
    private static var active: Bool { !ExtensionStore.shared.installed.isEmpty }

    static func attach(_ config: WKWebViewConfiguration) {
        guard active, #available(macOS 15.4, *) else { return }
        MainActor.assumeIsolated { config.webExtensionController = ExtensionManager.shared.controller }
    }
    static func opened(_ tab: BrowserTab) {
        guard active, !tab.isPrivate, #available(macOS 15.4, *) else { return }
        MainActor.assumeIsolated { ExtensionManager.shared.tabOpened(tab) }
    }
    static func closed(_ tab: BrowserTab) {
        guard active, !tab.isPrivate, #available(macOS 15.4, *) else { return }
        MainActor.assumeIsolated { ExtensionManager.shared.tabClosed(tab) }
    }
    static func activated(_ tab: BrowserTab, previous: BrowserTab?) {
        guard active, !tab.isPrivate, #available(macOS 15.4, *) else { return }
        MainActor.assumeIsolated { ExtensionManager.shared.tabActivated(tab, previous: previous) }
    }
    static func moved(_ tab: BrowserTab, from index: Int, in model: BrowserModel) {
        guard active, !tab.isPrivate, #available(macOS 15.4, *) else { return }
        MainActor.assumeIsolated { ExtensionManager.shared.tabMoved(tab, from: index, in: model) }
    }

    static func changed(_ tab: BrowserTab) {
        guard active, !tab.isPrivate, #available(macOS 15.4, *) else { return }
        MainActor.assumeIsolated { ExtensionManager.shared.tabChanged(tab) }
    }
    static func launch() {
        guard active, #available(macOS 15.4, *) else { return }
        MainActor.assumeIsolated { ExtensionManager.shared.loadAll() }
    }
}

// MARK: - Running extensions (macOS 15.4+)

/// Runs extensions with WebKit's built-in extension system and connects them to Hush's
/// window and tabs, toolbar buttons and pop-ups.
@available(macOS 15.4, *)
@MainActor
final class ExtensionManager: NSObject, ObservableObject, WKWebExtensionControllerDelegate {
    static let shared = ExtensionManager()

    let controller = WKWebExtensionController()
    @Published private(set) var contexts: [String: WKWebExtensionContext] = [:]
    /// Where each extension's toolbar button is, so pop-ups open under it.
    var anchors: [String: NSView] = [:]

    private override init() {
        super.init()
        controller.delegate = self
    }

    func loadAll() {
        for ext in ExtensionStore.shared.installed where ext.enabled {
            Task { await load(ext) }
        }
    }

    func load(_ record: InstalledExtension) async {
        guard contexts[record.id] == nil else { return }
        do {
            let ext: WKWebExtension
            if let appex = record.safariBundleURL {
                guard let bundle = Bundle(url: appex) else { throw ExtensionError("Its app is no longer installed.") }
                ext = try await WKWebExtension(appExtensionBundle: bundle)
            } else {
                ext = try await WKWebExtension(resourceBaseURL: ExtensionStore.shared.directory(for: record))
            }
            let context = WKWebExtensionContext(for: ext)
            context.uniqueIdentifier = record.id
            // Permissions were shown to and accepted by the user when the extension was added.
            for permission in ext.requestedPermissions { context.setPermissionStatus(.grantedExplicitly, for: permission) }
            for pattern in ext.allRequestedMatchPatterns { context.setPermissionStatus(.grantedExplicitly, for: pattern) }
            try controller.load(context)
            contexts[record.id] = context
            // Open tabs were made before this extension; rebuild their pages so it runs in them now.
            for model in BrowserModel.all.allObjects where !model.isPrivate {
                for tab in model.tabs where tab.webView.configuration.webExtensionController == nil { tab.adoptExtensions() }
            }
            if let model = BrowserModel.frontmostNormal {
                controller.didOpenWindow(model)
                for tab in model.tabs { controller.didOpenTab(tab) }
                if let selected = model.selectedTab { controller.didActivateTab(selected) }
            }
        } catch {
            NSLog("Ufolio: couldn't load extension \(record.name): \(error)")
        }
    }

    func unload(_ id: String) {
        guard let context = contexts.removeValue(forKey: id) else { return }
        try? controller.unload(context)
        anchors[id] = nil
    }

    /// Shows what an extension wants before it's added, the way Chrome does.
    func confirmInstall(_ ext: WKWebExtension, name: String) async -> Bool {
        #if SNAPSHOT
        if ProcessInfo.processInfo.environment["SNAP_MODE"] != nil { return true } // automated tests only
        #endif
        var lines: [String] = []
        let patterns = ext.allRequestedMatchPatterns.map { $0.string }
        if patterns.contains(where: { $0 == "<all_urls>" || $0.hasPrefix("*://*/") || $0.hasPrefix("http://*/") || $0.hasPrefix("https://*/") }) {
            lines.append("Read and change all your data on all websites")
        } else if !patterns.isEmpty {
            let hosts = patterns.prefix(4).map { $0.replacingOccurrences(of: "*://", with: "").replacingOccurrences(of: "/*", with: "") }
            lines.append("Read and change your data on " + hosts.joined(separator: ", ") + (patterns.count > 4 ? " and more" : ""))
        }
        let readable: [String: String] = [
            "tabs": "Read your browsing activity", "history": "Read and change your browsing history",
            "bookmarks": "Read and change your bookmarks", "cookies": "Read and change cookies",
            "downloads": "Manage your downloads", "clipboardRead": "Read what you copy",
            "clipboardWrite": "Change what you copy", "webNavigation": "See the pages you visit",
            "nativeMessaging": "Talk to other apps on your Mac", "notifications": "Show notifications",
        ]
        for permission in ext.requestedPermissions.map(\.rawValue).sorted() {
            if let text = readable[permission] { lines.append(text) }
        }
        let message = lines.isEmpty
            ? "This extension doesn’t ask for any special access."
            : "It will be able to:\n" + lines.map { "• " + $0 }.joined(separator: "\n")
        let art: HushDialog.Art = ext.icon(for: CGSize(width: 64, height: 64)).map { .image($0) } ?? .symbol("puzzlepiece.extension.fill")
        return await withCheckedContinuation { continuation in
            DialogHost.active.present(HushDialog(
                art: art, badge: "plus", theme: .hush, motion: .sparkle,
                title: "Add “\(name)” to Ufolio?", message: message,
                choices: [.init(title: "Cancel", role: .cancel), .init(title: "Add Extension", role: .primary)],
                completion: { choice, _ in continuation.resume(returning: choice == 1) }))
        }
    }

    func performAction(_ id: String) {
        guard let context = contexts[id] else { return }
        context.performAction(for: BrowserModel.frontmostNormal?.selectedTab)
    }

    // MARK: Telling extensions what the browser is doing

    func tabOpened(_ tab: BrowserTab) { controller.didOpenTab(tab) }
    func tabClosed(_ tab: BrowserTab) { controller.didCloseTab(tab) }
    func tabActivated(_ tab: BrowserTab, previous: BrowserTab?) { controller.didActivateTab(tab, previousActiveTab: previous) }
    func tabMoved(_ tab: BrowserTab, from index: Int, in model: BrowserModel) {
        controller.didMoveTab(tab, from: index, in: model)
    }
    func tabChanged(_ tab: BrowserTab) { controller.didChangeTabProperties([.URL, .title, .loading], for: tab) }

    // MARK: WKWebExtensionControllerDelegate

    func webExtensionController(_ controller: WKWebExtensionController, openWindowsFor extensionContext: WKWebExtensionContext) -> [any WKWebExtensionWindow] {
        BrowserModel.frontmostNormal.map { [$0] } ?? []
    }

    /// The only addresses an extension may open or load: web pages and extension pages.
    static func allowedToOpen(_ url: URL) -> Bool {
        ["http", "https", "webkit-extension"].contains(url.scheme?.lowercased() ?? "")
    }

    func webExtensionController(_ controller: WKWebExtensionController, focusedWindowFor extensionContext: WKWebExtensionContext) -> (any WKWebExtensionWindow)? {
        BrowserModel.frontmostNormal
    }

    func webExtensionController(_ controller: WKWebExtensionController, openNewTabUsing configuration: WKWebExtension.TabConfiguration,
                                for extensionContext: WKWebExtensionContext,
                                completionHandler: @escaping ((any WKWebExtensionTab)?, (any Error)?) -> Void) {
        guard let model = BrowserModel.frontmostNormal else { completionHandler(nil, nil); return }
        let address = configuration.url.flatMap { Self.allowedToOpen($0) ? $0 : nil }
        let tab = model.newTab(url: address, select: configuration.shouldBeActive)
        completionHandler(tab, nil)
    }

    /// windows.create: Hush keeps everything in tabs, so the pages open as tabs in the window.
    func webExtensionController(_ controller: WKWebExtensionController, openNewWindowUsing configuration: WKWebExtension.WindowConfiguration,
                                for extensionContext: WKWebExtensionContext,
                                completionHandler: @escaping ((any WKWebExtensionWindow)?, (any Error)?) -> Void) {
        guard let model = BrowserModel.frontmostNormal else { completionHandler(nil, nil); return }
        let urls = configuration.tabURLs.filter(Self.allowedToOpen)
        if urls.isEmpty { model.newTab(focus: true) } else { for (i, url) in urls.prefix(20).enumerated() { model.newTab(url: url, select: i == 0) } }
        completionHandler(model, nil)
    }

    func webExtensionController(_ controller: WKWebExtensionController, promptForPermissionMatchPatterns matchPatterns: Set<WKWebExtension.MatchPattern>,
                                in tab: (any WKWebExtensionTab)?, for extensionContext: WKWebExtensionContext,
                                completionHandler: @escaping (Set<WKWebExtension.MatchPattern>, Date?) -> Void) {
        let name = extensionContext.webExtension.displayName ?? "An extension"
        let art: HushDialog.Art = extensionContext.webExtension.icon(for: CGSize(width: 64, height: 64)).map { .image($0) } ?? .symbol("puzzlepiece.extension.fill")
        let all = matchPatterns.contains { $0.matchesAllHosts }
        let sites = matchPatterns.compactMap(\.host).filter { !$0.isEmpty }.sorted().prefix(5).joined(separator: ", ")
        DialogHost.active.present(HushDialog(
            art: art, badge: "globe", theme: .permission, motion: .orbit,
            title: "“\(name)” wants access to more sites",
            message: all ? "It’s asking to read and change your data on all websites." : "It’s asking for access to: \(sites)",
            choices: [.init(title: "Don’t Allow", role: .cancel), .init(title: "Allow", role: .primary)],
            completion: { choice, _ in completionHandler(choice == 1 ? matchPatterns : [], nil) }))
    }

    func webExtensionController(_ controller: WKWebExtensionController, openOptionsPageFor extensionContext: WKWebExtensionContext,
                                completionHandler: @escaping ((any Error)?) -> Void) {
        if let url = extensionContext.optionsPageURL { BrowserModel.frontmostNormal?.newTab(url: url) }
        completionHandler(nil)
    }

    func webExtensionController(_ controller: WKWebExtensionController, promptForPermissions permissions: Set<WKWebExtension.Permission>,
                                in tab: (any WKWebExtensionTab)?, for extensionContext: WKWebExtensionContext,
                                completionHandler: @escaping (Set<WKWebExtension.Permission>, Date?) -> Void) {
        let name = extensionContext.webExtension.displayName ?? "An extension"
        let art: HushDialog.Art = extensionContext.webExtension.icon(for: CGSize(width: 64, height: 64)).map { .image($0) } ?? .symbol("puzzlepiece.extension.fill")
        DialogHost.active.present(HushDialog(
            art: art, badge: "lock.open.fill", theme: .permission, motion: .orbit,
            title: "“\(name)” wants more access",
            message: "It’s asking for: " + permissions.map(\.rawValue).sorted().joined(separator: ", "),
            choices: [.init(title: "Don’t Allow", role: .cancel), .init(title: "Allow", role: .primary)],
            completion: { choice, _ in completionHandler(choice == 1 ? permissions : [], nil) }))
    }

    func webExtensionController(_ controller: WKWebExtensionController, promptForPermissionToAccess urls: Set<URL>,
                                in tab: (any WKWebExtensionTab)?, for extensionContext: WKWebExtensionContext,
                                completionHandler: @escaping (Set<URL>, Date?) -> Void) {
        let name = extensionContext.webExtension.displayName ?? "An extension"
        let art: HushDialog.Art = extensionContext.webExtension.icon(for: CGSize(width: 64, height: 64)).map { .image($0) } ?? .symbol("puzzlepiece.extension.fill")
        DialogHost.active.present(HushDialog(
            art: art, badge: "globe", theme: .permission, motion: .orbit,
            title: "Allow “\(name)” on this site?",
            message: urls.compactMap(\.host).sorted().joined(separator: ", "),
            choices: [.init(title: "Don’t Allow", role: .cancel), .init(title: "Allow", role: .primary)],
            completion: { choice, _ in completionHandler(choice == 1 ? urls : [], nil) }))
    }

    func webExtensionController(_ controller: WKWebExtensionController, didUpdate action: WKWebExtension.Action,
                                forExtensionContext context: WKWebExtensionContext) {
        objectWillChange.send()
    }

    func webExtensionController(_ controller: WKWebExtensionController, presentActionPopup action: WKWebExtension.Action,
                                for context: WKWebExtensionContext, completionHandler: @escaping ((any Error)?) -> Void) {
        guard let popover = action.popupPopover else { completionHandler(nil); return }
        if let anchor = anchors[context.uniqueIdentifier], anchor.window != nil {
            popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
        } else if let view = BrowserModel.frontmost?.window?.contentView {
            popover.show(relativeTo: NSRect(x: view.bounds.maxX - 60, y: view.bounds.maxY - 10, width: 1, height: 1), of: view, preferredEdge: .minY)
        }
        completionHandler(nil)
    }
}

// MARK: - Hush's window and tabs, as extensions see them

@available(macOS 15.4, *)
extension BrowserModel: WKWebExtensionWindow {
    func tabs(for context: WKWebExtensionContext) -> [any WKWebExtensionTab] { tabs }
    func activeTab(for context: WKWebExtensionContext) -> (any WKWebExtensionTab)? { selectedTab }
    func windowType(for context: WKWebExtensionContext) -> WKWebExtension.WindowType { .normal }
    func windowState(for context: WKWebExtensionContext) -> WKWebExtension.WindowState { .normal }
    func isPrivate(for context: WKWebExtensionContext) -> Bool { false }
    func frame(for context: WKWebExtensionContext) -> CGRect { window?.frame ?? .zero }
    func screenFrame(for context: WKWebExtensionContext) -> CGRect { window?.screen?.frame ?? .zero }
    func focus(for context: WKWebExtensionContext, completionHandler: @escaping ((any Error)?) -> Void) {
        window?.makeKeyAndOrderFront(nil)
        completionHandler(nil)
    }
}

@available(macOS 15.4, *)
extension BrowserTab: WKWebExtensionTab {
    func window(for context: WKWebExtensionContext) -> (any WKWebExtensionWindow)? { model }
    func indexInWindow(for context: WKWebExtensionContext) -> Int { model?.tabs.firstIndex { $0 === self } ?? 0 }
    func webView(for context: WKWebExtensionContext) -> WKWebView? { isAsleep ? nil : webView }
    func title(for context: WKWebExtensionContext) -> String? { title }
    func url(for context: WKWebExtensionContext) -> URL? { url }
    func isLoadingComplete(for context: WKWebExtensionContext) -> Bool { !isLoading }
    func isSelected(for context: WKWebExtensionContext) -> Bool { model?.selectedTab === self }
    func activate(for context: WKWebExtensionContext, completionHandler: @escaping ((any Error)?) -> Void) {
        model?.selectedID = id
        completionHandler(nil)
    }
    func close(for context: WKWebExtensionContext, completionHandler: @escaping ((any Error)?) -> Void) {
        model?.close(self)
        completionHandler(nil)
    }
    func loadURL(_ url: URL, for context: WKWebExtensionContext, completionHandler: @escaping ((any Error)?) -> Void) {
        // Web and extension pages only. load() treats an address as typed by you, so a
        // javascript: one would run in the page: an extension could reach sites it has no access to.
        guard ExtensionManager.allowedToOpen(url) else {
            completionHandler(NSError(domain: "Ufolio", code: 1, userInfo: [NSLocalizedDescriptionKey: "That address can't be opened by an extension."]))
            return
        }
        load(url)
        completionHandler(nil)
    }
    func reload(fromOrigin: Bool, for context: WKWebExtensionContext, completionHandler: @escaping ((any Error)?) -> Void) {
        webView.reload()
        completionHandler(nil)
    }
}

// MARK: - Toolbar buttons

/// One button per extension that has a toolbar action, with its icon and badge.
struct ExtensionButtons: View {
    var body: some View {
        if #available(macOS 15.4, *) {
            ExtensionButtonRow(manager: ExtensionManager.shared)
        }
    }
}

@available(macOS 15.4, *)
private struct ExtensionButtonRow: View {
    @ObservedObject var manager: ExtensionManager
    @ObservedObject private var store = ExtensionStore.shared
    /// How many extensions get their own button next to Hush Guard; the rest live in Settings.
    static let limit = 3

    var body: some View {
        // In the order you added them, skipping ones that are turned off or haven't loaded.
        let running = store.installed.filter { $0.enabled && manager.contexts[$0.id] != nil }
        let tab = BrowserModel.frontmost?.selectedTab
        HStack(spacing: 2) {
            ForEach(running.prefix(Self.limit)) { ext in
                if let action = manager.contexts[ext.id]?.action(for: tab) {
                    ExtensionButton(id: ext.id, action: action, manager: manager)
                }
            }
            if running.count > Self.limit {
                MoreExtensionsButton(count: running.count - Self.limit)
            }
        }
    }
}

/// Shown when more than three extensions are running: opens Settings › Extensions.
private struct MoreExtensionsButton: View {
    let count: Int
    @State private var hovering = false

    var body: some View {
        Button { SettingsOpener.open(tab: .extensions) } label: {
            Image(systemName: "puzzlepiece.extension")
                .font(.system(size: 13))
                .overlay(alignment: .topTrailing) {
                    Text("+\(count)")
                        .font(.system(size: 7.5, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 2.5)
                        .frame(minHeight: 11)
                        .background(Capsule().fill(Color.secondary))
                        .offset(x: 9, y: -5)
                }
                .frame(width: 28, height: 26)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.primary.opacity(hovering ? 0.08 : 0)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help(count == 1 ? "1 more extension in Settings › Extensions" : "\(count) more extensions in Settings › Extensions")
        .onHover { hovering = $0 }
    }
}

@available(macOS 15.4, *)
private struct ExtensionButton: View {
    let id: String
    let action: WKWebExtension.Action
    let manager: ExtensionManager
    @State private var hovering = false

    var body: some View {
        Button { manager.performAction(id) } label: {
            ZStack(alignment: .topTrailing) {
                Group {
                    if let icon = action.icon(for: CGSize(width: 16, height: 16)) {
                        Image(nsImage: icon).resizable().interpolation(.high)
                    } else {
                        Image(systemName: "puzzlepiece.extension")
                    }
                }
                .frame(width: 16, height: 16)
                .frame(width: 28, height: 26)
                if !action.badgeText.isEmpty {
                    Text(action.badgeText)
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 3)
                        .frame(minWidth: 12, minHeight: 12)
                        .background(Capsule().fill(Color.red))
                        .offset(x: 2, y: 1)
                }
            }
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.primary.opacity(hovering ? 0.08 : 0)))
            .background(AnchorReader { manager.anchors[id] = $0 })
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(action.label)
        .onHover { hovering = $0 }
        .opacity(action.isEnabled ? 1 : 0.45)
    }
}

/// Hands back the NSView behind a SwiftUI view, to anchor pop-ups to it.
private struct AnchorReader: NSViewRepresentable {
    let onView: (NSView) -> Void
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { onView(view) }
        return view
    }
    func updateNSView(_ view: NSView, context: Context) {}
}

// MARK: - "Add to Ufolio" on Chrome Web Store pages

/// A slim bar above Chrome Web Store extension pages with a one-click Add to Hush button
/// (the store only shows its own button to Chrome itself).
struct WebStoreBar: View {
    @ObservedObject var tab: BrowserTab
    @ObservedObject private var store = ExtensionStore.shared
    @State private var adding = false

    private var extensionID: String? {
        guard ExtensionStore.isSupported, let url = tab.url, let host = url.host?.lowercased(),
              host == "chromewebstore.google.com" || (host == "chrome.google.com" && url.path.hasPrefix("/webstore")),
              url.path.contains("/detail/") else { return nil }
        return ExtensionStore.webStoreID(from: url.absoluteString)
    }

    private var name: String {
        let title = tab.title.replacingOccurrences(of: " - Chrome Web Store", with: "")
            .replacingOccurrences(of: " – Chrome Web Store", with: "")
        return title.isEmpty ? "this extension" : "“\(title)”"
    }

    var body: some View {
        if let id = extensionID {
            let installed = store.installed.contains { $0.id == id }
            VStack(spacing: 0) {
                Hairline()
                HStack(spacing: 12) {
                    IconTile(symbol: "puzzlepiece.extension.fill",
                             colors: [Color(red: 1.0, green: 0.62, blue: 0.25), Color(red: 0.95, green: 0.42, blue: 0.18)], size: 30)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(installed ? "\(name) is in Ufolio" : "Add \(name) to Ufolio")
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(1)
                        Text(statusLine(installed: installed))
                            .font(.system(size: 11.5))
                            .foregroundStyle(store.statusIsError && adding ? Color.orange : Color.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 12)
                    if store.isWorking && adding {
                        ProgressView().controlSize(.small)
                    }
                    if installed {
                        Label("Added", systemImage: "checkmark.circle.fill")
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(Color.green)
                        Button("Manage…") { SettingsOpener.open(tab: .extensions) }
                    } else {
                        Button("Add to Ufolio") {
                            adding = true
                            let link = tab.url?.absoluteString ?? id
                            Task { @MainActor in await store.install(fromWebStore: link) }
                        }
                        .keyboardShortcut(.defaultAction)
                        .disabled(store.isWorking)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
            }
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    private func statusLine(installed: Bool) -> String {
        if adding, let status = store.status { return status }
        if installed { return "It works on tabs you open from now on." }
        return "Ufolio can run most Chrome extensions. You’ll see what it can access first."
    }
}
