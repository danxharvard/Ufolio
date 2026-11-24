import SwiftUI
import ImageIO
import AppKit

struct Bookmark: Codable, Identifiable, Equatable {
    var id = UUID()
    var title: String
    var url: URL
    /// The folder it's in (nil = not in a folder).
    var folder: String?
}

/// Bookmarks, saved to ~/Library/Application Support/Hush Browser/bookmarks.json.
final class BookmarkStore: ObservableObject {
    static let shared = BookmarkStore()

    @Published private(set) var items: [Bookmark] = [] {
        didSet {
            keys = Set(items.map { Self.key($0.url) })
            byFolder = Dictionary(grouping: items, by: \.folder)
        }
    }
    /// Bookmarks grouped by folder, worked out once per change: the sidebar, bookmarks bar and
    /// menus ask for each folder's bookmarks several times per redraw.
    private var byFolder: [String?: [Bookmark]] = [:]
    /// Every bookmark's address in comparable form, so "is this page bookmarked?" (asked on every
    /// redraw of the address bar) is a quick lookup rather than a pass over every bookmark.
    private var keys: Set<String> = []
    private let fileURL: URL

    private init() {
        let folder = AppPaths.support
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        fileURL = folder.appendingPathComponent("bookmarks.json")
        load()
    }

    func contains(_ url: URL) -> Bool { keys.contains(Self.key(url)) }

    func toggle(url: URL, title: String) {
        if contains(url) {
            items.removeAll { Self.same($0.url, url) }
        } else {
            items.append(Bookmark(title: title.isEmpty ? (url.host ?? url.absoluteString) : title, url: url))
        }
        save()
    }

    /// Adds bookmarks brought over from another browser, skipping ones you already have.
    func add(imported: [(title: String, url: URL)]) -> Int {
        // Added all at once: appending one by one redrew everything showing bookmarks each time.
        var seen = keys, adding: [Bookmark] = []
        for item in imported where seen.insert(Self.key(item.url)).inserted {
            let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
            adding.append(Bookmark(title: title.isEmpty ? (item.url.host ?? item.url.absoluteString) : String(title.prefix(200)), url: item.url))
        }
        guard !adding.isEmpty else { return 0 }
        items += adding
        save()
        return adding.count
    }

    func remove(_ bookmark: Bookmark) {
        items.removeAll { $0.id == bookmark.id }
        save()
    }

    func rename(_ bookmark: Bookmark, to title: String) {
        guard let i = items.firstIndex(where: { $0.id == bookmark.id }) else { return }
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        items[i].title = trimmed
        save()
    }

    // MARK: Folders and editing

    /// Folders, in the order their first bookmark appears.
    var folders: [String] {
        var seen = Set<String>(), result: [String] = []
        for f in items.compactMap(\.folder) where seen.insert(f).inserted { result.append(f) }
        return result + emptyFolders.filter { !seen.contains($0) }
    }
    /// Folders made in the sidebar that don't have a bookmark yet.
    @Published private(set) var emptyFolders: [String] = []

    func items(in folder: String?) -> [Bookmark] { byFolder[folder] ?? [] }

    func makeFolder(_ name: String) {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, !folders.contains(clean) else { return }
        emptyFolders.append(clean)
    }

    func setFolder(_ bookmark: Bookmark, _ folder: String?) {
        guard let i = items.firstIndex(where: { $0.id == bookmark.id }) else { return }
        items[i].folder = folder
        if let folder { emptyFolders.removeAll { $0 == folder } }
        save()
    }

    func setAddress(_ bookmark: Bookmark, _ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let i = items.firstIndex(where: { $0.id == bookmark.id }),
              let url = URL(string: trimmed.contains("://") ? trimmed : "https://" + trimmed),
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host != nil else { return }
        items[i].url = url
        save()
    }

    func renameFolder(_ old: String, to new: String) {
        let clean = String(new.trimmingCharacters(in: .whitespacesAndNewlines).prefix(60))
        guard !clean.isEmpty, clean != old else { return }
        for i in items.indices where items[i].folder == old { items[i].folder = clean }
        emptyFolders = emptyFolders.map { $0 == old ? clean : $0 }
        save()
    }

    /// Removes a folder; its bookmarks stay, outside any folder.
    func removeFolder(_ name: String) {
        for i in items.indices where items[i].folder == name { items[i].folder = nil }
        emptyFolders.removeAll { $0 == name }
        save()
    }

    // MARK: Import and export (the bookmarks file format every browser uses)

    /// Reads an exported bookmarks file (Chrome, Safari, Firefox, Edge, Brave…). Returns how many
    /// new bookmarks were added.
    func importHTML(_ html: String) -> Int {
        var folderStack: [String] = []
        var pendingFolder: String?
        var found: [Bookmark] = []
        let pattern = try! NSRegularExpression(pattern: #"<H3[^>]*>(.*?)</H3>|<DL>|</DL>|<A\s[^>]*HREF="([^"]*)"[^>]*>(.*?)</A>"#,
                                               options: [.caseInsensitive, .dotMatchesLineSeparators])
        let ns = html as NSString
        // Top-level containers browsers add; their bookmarks count as "not in a folder".
        let roots: Set<String> = ["bookmarks bar", "bookmarks toolbar", "favorites", "favourites", "bookmarks menu",
                                  "other bookmarks", "mobile bookmarks", "bookmarks"]
        for match in pattern.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
            let token = ns.substring(with: match.range).uppercased()
            if match.range(at: 1).location != NSNotFound {
                pendingFolder = Self.plain(ns.substring(with: match.range(at: 1)))
            } else if token == "<DL>" {
                folderStack.append(pendingFolder ?? "")
                pendingFolder = nil
            } else if token == "</DL>" {
                if !folderStack.isEmpty { folderStack.removeLast() }
            } else if match.range(at: 2).location != NSNotFound {
                let href = Self.plain(ns.substring(with: match.range(at: 2)))
                guard let url = URL(string: href), ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { continue }
                let path = folderStack.filter { !$0.isEmpty && !roots.contains($0.lowercased()) }
                let title = Self.plain(ns.substring(with: match.range(at: 3)))
                found.append(Bookmark(title: title.isEmpty ? (url.host ?? href) : String(title.prefix(200)), url: url,
                                      folder: path.isEmpty ? nil : path.suffix(2).joined(separator: " › ")))
            }
            if found.count >= 5000 { break }
        }
        var seen = keys
        let adding = found.filter { seen.insert(Self.key($0.url)).inserted }
        guard !adding.isEmpty else { return 0 }
        items += adding
        save()
        return adding.count
    }

    func exportHTML() -> String {
        func esc(_ s: String) -> String {
            s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
        }
        func line(_ b: Bookmark, indent: String) -> String {
            "\(indent)<DT><A HREF=\"\(esc(b.url.absoluteString))\">\(esc(b.title))</A>\n"
        }
        var html = """
        <!DOCTYPE NETSCAPE-Bookmark-file-1>
        <!-- Exported from Hush Browser -->
        <META HTTP-EQUIV="Content-Type" CONTENT="text/html; charset=UTF-8">
        <TITLE>Bookmarks</TITLE>
        <H1>Bookmarks</H1>
        <DL><p>

        """
        for b in items(in: nil) { html += line(b, indent: "    ") }
        for folder in folders {
            html += "    <DT><H3>\(esc(folder))</H3>\n    <DL><p>\n"
            for b in items(in: folder) { html += line(b, indent: "        ") }
            html += "    </DL><p>\n"
        }
        return html + "</DL><p>\n"
    }

    private static func plain(_ s: String) -> String {
        var t = s.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
        for (k, v) in ["&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'", "&#x27;": "'", "&nbsp;": " "] {
            t = t.replacingOccurrences(of: k, with: v)
        }
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Asks where to save, and writes the bookmarks file.
    @MainActor func exportWithPanel() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.html]
        panel.nameFieldStringValue = "Ufolio Bookmarks.html"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? exportHTML().write(to: url, atomically: true, encoding: .utf8)
    }

    /// Asks for a bookmarks file and brings its bookmarks in. Returns a message to show.
    @MainActor func importWithPanel() -> String? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.html]
        panel.message = "Choose a bookmarks file exported from another browser."
        guard panel.runModal() == .OK, let url = panel.url,
              let text = (try? String(contentsOf: url, encoding: .utf8)) ?? (try? String(contentsOf: url, encoding: .isoLatin1)) else { return nil }
        let added = importHTML(text)
        return added == 0 ? "No new bookmarks in that file." : "Added \(added) bookmark\(added == 1 ? "" : "s")."
    }

    /// Drag to reorder (the sidebar).
    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        items.move(fromOffsets: source, toOffset: destination)
        save()
    }

    func move(_ bookmark: Bookmark, by offset: Int) {
        guard let i = items.firstIndex(where: { $0.id == bookmark.id }) else { return }
        let j = i + offset
        guard items.indices.contains(j) else { return }
        items.swapAt(i, j)
        save()
    }

    private static func key(_ u: URL) -> String {
        var s = u.absoluteString.lowercased()
        if s.hasSuffix("/") { s.removeLast() }
        return s.replacingOccurrences(of: "://www.", with: "://")
    }

    private static func same(_ a: URL, _ b: URL) -> Bool { key(a) == key(b) }

    private func load() {
        if FileManager.default.fileExists(atPath: fileURL.path) {
            // Unreadable files are kept as a copy (see AppPaths.load); the starter bookmarks are
            // only for a first launch, never written over a file that's there.
            items = AppPaths.load([Bookmark].self, from: fileURL) ?? []
        } else {
            // A few starters on first launch; easy to remove (right-click › Remove).
            items = [
                Bookmark(title: "Google", url: URL(string: "https://www.google.com")!),
                Bookmark(title: "YouTube", url: URL(string: "https://www.youtube.com")!),
                Bookmark(title: "Wikipedia", url: URL(string: "https://www.wikipedia.org")!),
                Bookmark(title: "GitHub", url: URL(string: "https://github.com")!),
            ]
            save()
        }
    }

    /// Saved a moment after the last change, in the background: a drag to reorder changes the
    /// list once per bookmark you pass, and writing the whole file each time made dragging stutter.
    private var saveWork: DispatchWorkItem?
    private let saveQueue = DispatchQueue(label: "ufolio.bookmarks.save", qos: .utility)

    private func save() {
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveNow() }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    /// Writes straight away (also as Ufolio quits).
    func saveNow(waiting: Bool = false) {
        saveWork?.cancel()
        saveWork = nil
        let snapshot = items, file = fileURL
        let write = {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted]
            if let data = try? encoder.encode(snapshot) { try? data.write(to: file, options: .atomic) }
        }
        if waiting { saveQueue.sync(execute: write) } else { saveQueue.async(execute: write) }
    }
}

/// The row of bookmarks under the toolbar.
struct BookmarkBar: View {
    let model: BrowserModel   // only opens pages: tab changes don't redraw the bar
    @ObservedObject private var store = BookmarkStore.shared

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            // Lazy: only the chips in view are built (and fetch their icons), however many you have.
            LazyHStack(spacing: 2) {
                if store.items.isEmpty {
                    Text("Press ⌘D to bookmark a page — it appears here")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 8)
                }
                ForEach(store.items(in: nil)) { bookmark in
                    BookmarkChip(model: model, bookmark: bookmark)
                }
                ForEach(store.folders, id: \.self) { folder in
                    FolderChip(model: model, folder: folder)
                }
            }
            .padding(.horizontal, 10)
        }
        .frame(height: 28)
    }
}

/// A folder in the bookmarks bar: a menu of its bookmarks.
private struct FolderChip: View {
    let model: BrowserModel
    let folder: String
    @ObservedObject private var store = BookmarkStore.shared
    @State private var hovering = false

    var body: some View {
        Menu {
            let marks = store.items(in: folder)
            ForEach(marks) { bookmark in
                Button(bookmark.title) { model.open(bookmark.url, inNewTab: NSEvent.modifierFlags.contains(.command)) }
            }
            if marks.isEmpty { Text("Empty") }
            if marks.count > 1 {
                Divider()
                Button("Open All in Tabs") { model.openAll(marks.map(\.url)) }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "folder.fill").font(.system(size: 11)).foregroundStyle(Color.accentColor)
                Text(folder).font(.system(size: 12)).lineLimit(1)
            }
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.visible)
        .fixedSize()
        .padding(.horizontal, 6)
        .frame(height: 24)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.primary.opacity(hovering ? 0.08 : 0)))
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.1), value: hovering)
    }
}

private struct BookmarkChip: View {
    let model: BrowserModel
    let bookmark: Bookmark
    @State private var hovering = false
    @State private var renaming = false
    @State private var newTitle = ""

    var body: some View {
        HStack(spacing: 6) {
            Favicon(url: bookmark.url, size: 13)
            Text(bookmark.title)
                .font(.system(size: 11.5))
                .lineLimit(1)
                .frame(maxWidth: 140, alignment: .leading)
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 7)
        .frame(height: 22)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.primary.opacity(hovering ? 0.08 : 0))
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.1), value: hovering)
        .onTapGesture {
            let newTab = NSEvent.modifierFlags.contains(.command)
            model.open(bookmark.url, inNewTab: newTab)
        }
        .help(bookmark.url.absoluteString)
        .contextMenu {
            Button { model.open(bookmark.url, inNewTab: true) } label: { Label("Open in New Tab", systemImage: "plus.square.on.square") }
            Button("Copy Address") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(bookmark.url.absoluteString, forType: .string)
            }
            Divider()
            Button { newTitle = bookmark.title; renaming = true } label: { Label("Rename…", systemImage: "pencil") }
            Button { BookmarkStore.shared.move(bookmark, by: -1) } label: { Label("Move Left", systemImage: "arrow.left") }
            Button { BookmarkStore.shared.move(bookmark, by: 1) } label: { Label("Move Right", systemImage: "arrow.right") }
            Divider()
            Button { BookmarkStore.shared.remove(bookmark) } label: { Label("Remove", systemImage: "trash") }
        }
        .popover(isPresented: $renaming, arrowEdge: .bottom) {
            HStack {
                TextField("Name", text: $newTitle)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 200)
                    .onSubmit { commitRename() }
                Button("Save") { commitRename() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .animation(.easeOut(duration: 0.1), value: hovering)
    }

    private func commitRename() {
        BookmarkStore.shared.rename(bookmark, to: newTitle)
        renaming = false
    }
}

private struct PrivateWindowKey: EnvironmentKey { static let defaultValue = false }

extension EnvironmentValues {
    /// True inside a private window (so nothing it shows is saved to disk).
    var isPrivateWindow: Bool {
        get { self[PrivateWindowKey.self] }
        set { self[PrivateWindowKey.self] = newValue }
    }
}

/// A site's icon, loaded from the site itself; falls back to a coloured letter.
struct Favicon: View {
    let url: URL?
    let size: CGFloat
    @State private var image: NSImage?
    @Environment(\.isPrivateWindow) private var isPrivateWindow

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else {
                Monogram(host: url?.host, size: size)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
        .task(id: url?.host) {
            image = await FaviconCache.shared.icon(for: url, saveToDisk: !isPrivateWindow)
        }
    }
}

private struct Monogram: View {
    let host: String?
    let size: CGFloat

    var body: some View {
        let name = host?.strippingWWW ?? ""
        // Stable per site (String.hashValue changes every launch).
        let hue = Double(name.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) % 360 }) / 360
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .fill(LinearGradient(colors: [Color(hue: hue, saturation: 0.45, brightness: 0.85),
                                              Color(hue: hue, saturation: 0.6, brightness: 0.65)],
                                     startPoint: .top, endPoint: .bottom))
            Text(name.first.map { String($0).uppercased() } ?? "•")
                .font(.system(size: size * 0.58, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
        }
    }
}

/// A site's icon plus what the start page needs to lay it out nicely.
struct SiteIcon {
    let image: NSImage
    /// The largest version's width in pixels (big icons can fill a tile).
    let pixels: Int
    /// The icon's main colour, for tinting cards.
    let tint: NSColor?

    var isLarge: Bool { pixels >= 96 }
}

actor FaviconCache {
    static let shared = FaviconCache()
    /// Bounded: a few hundred icons at most, and macOS can take the memory back when it needs it.
    private let cache: NSCache<NSString, IconBox> = {
        let c = NSCache<NSString, IconBox>()
        c.countLimit = 300
        c.totalCostLimit = 24_000_000
        return c
    }()
    private final class IconBox { let icon: SiteIcon; init(_ icon: SiteIcon) { self.icon = icon } }
    /// Sites with no icon, and when that was found. Asked again after a while, so a moment
    /// offline doesn't leave every icon blank until Ufolio restarts.
    private var misses: [String: Date] = [:]
    private var inFlight: [String: Task<SiteIcon?, Never>] = [:]

    func icon(for url: URL?, saveToDisk: Bool = true) async -> NSImage? {
        await info(for: url, saveToDisk: saveToDisk)?.image
    }

    /// Fetches each site's icon once, even when many views ask at the same moment.
    /// `saveToDisk` is false in private windows: their icons stay in memory, leaving no trace.
    func info(for url: URL?, saveToDisk: Bool = true) async -> SiteIcon? {
        guard let url, let host = url.host, let scheme = url.scheme, scheme.hasPrefix("http") else { return nil }
        if let hit = cache.object(forKey: host as NSString) { return hit.icon }
        if let missed = misses[host], Date().timeIntervalSince(missed) < 600 { return nil }
        if let running = inFlight[host] { return await running.value }

        let task = Task<SiteIcon?, Never> {
            // Kept on disk for two weeks, so icons appear instantly after a relaunch.
            if let data = Self.cached(host), let icon = Self.makeIcon(data) { return icon }
            for path in ["/apple-touch-icon.png", "/apple-touch-icon-precomposed.png", "/favicon.ico"] {
                guard let iconURL = URL(string: "https://\(host)\(path)") else { continue }
                var request = URLRequest(url: iconURL)
                request.timeoutInterval = 5
                if let data = await Self.fetchSmall(request), let icon = Self.makeIcon(data) {
                    if saveToDisk { Self.store(data, for: host) }
                    return icon
                }
            }
            return nil
        }
        inFlight[host] = task
        let result = await task.value
        inFlight[host] = nil
        if let result {
            cache.setObject(IconBox(result), forKey: host as NSString, cost: max(1, result.pixels * result.pixels * 4))
        } else { misses[host] = Date() }
        return result
    }

    /// Fetches at most 1 MB: a site sending more (or lying about the size) is cut off, so an
    /// icon can never use up memory.
    private static func fetchSmall(_ request: URLRequest) async -> Data? {
        let limit = 1_000_000
        guard let (bytes, response) = try? await session.bytes(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200, response.expectedContentLength < Int64(limit) else { return nil }
        var data = Data()
        do {
            for try await byte in bytes {
                data.append(byte)
                if data.count >= limit { return nil }
            }
        } catch { return nil }
        return data
    }

    /// Icons are fetched without cookies, so sites can't recognise you from them.
    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        return URLSession(configuration: config)
    }()

    private static let folder: URL = {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let dir = caches.appendingPathComponent("Hush Browser/Icons", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private static func file(for host: String) -> URL? {
        let safe = host.lowercased()
        guard !safe.isEmpty, safe.count < 200, safe.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" }),
              !safe.hasPrefix(".") else { return nil }
        return folder.appendingPathComponent(safe)
    }

    /// Lets go of icons kept in memory (they're on disk too), when the Mac is short of memory.
    func purgeMemory() { cache.removeAllObjects() }

    /// Removes a site's saved icons (Forget This Site).
    func forget(site: String) {
        misses = misses.filter { Domains.site($0.key) != site }
        let fm = FileManager.default
        for file in (try? fm.contentsOfDirectory(at: Self.folder, includingPropertiesForKeys: nil)) ?? []
        where Domains.site(file.lastPathComponent) == site {
            cache.removeObject(forKey: file.lastPathComponent as NSString)
            try? fm.removeItem(at: file)
        }
    }

    /// Forgets saved icons (they show which sites you've visited), e.g. when history is cleared.
    nonisolated static func clearDisk() {
        let fm = FileManager.default
        for file in (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [] {
            try? fm.removeItem(at: file)
        }
    }

    private static func cached(_ host: String) -> Data? {
        guard let file = file(for: host),
              let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
              Date().timeIntervalSince(modified) < 14 * 86_400 else { return nil }
        return try? Data(contentsOf: file)
    }

    private static func store(_ data: Data, for host: String) {
        guard let file = file(for: host) else { return }
        try? data.write(to: file, options: .atomic)
    }

    /// Decodes the icon fully here, off the main thread and at no more than 256 px, so drawing
    /// it later (while you scroll the start page) is instant. Uses the sharpest version in the file.
    private static func makeIcon(_ data: Data) -> SiteIcon? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(source) > 0 else { return nil }
        var best = 0, bestWidth = 0
        for i in 0..<CGImageSourceGetCount(source) {
            let props = CGImageSourceCopyPropertiesAtIndex(source, i, nil) as? [CFString: Any]
            let width = props?[kCGImagePropertyPixelWidth] as? Int ?? 0
            if width > bestWidth { best = i; bestWidth = width }
        }
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                        kCGImageSourceThumbnailMaxPixelSize: 256,
                                        kCGImageSourceCreateThumbnailWithTransform: true,
                                        kCGImageSourceShouldCacheImmediately: true]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, best, options as CFDictionary), cg.width > 0 else { return nil }
        let image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        return SiteIcon(image: image, pixels: max(bestWidth, cg.width), tint: mainColor(of: image))
    }

    /// The average of the icon's coloured pixels (ignoring transparent and near-white ones).
    private static func mainColor(of image: NSImage) -> NSColor? {
        let side = 16
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(x: 0, y: 0, width: side, height: side))
        NSGraphicsContext.restoreGraphicsState()
        var r = 0.0, g = 0.0, b = 0.0, n = 0.0
        for x in 0..<side {
            for y in 0..<side {
                guard let c = rep.colorAt(x: x, y: y), c.alphaComponent > 0.5 else { continue }
                let brightness = (c.redComponent + c.greenComponent + c.blueComponent) / 3
                let spread = max(c.redComponent, c.greenComponent, c.blueComponent) - min(c.redComponent, c.greenComponent, c.blueComponent)
                guard brightness < 0.92 || spread > 0.12 else { continue } // skip white backgrounds
                let weight = 0.3 + spread // colourful pixels count more
                r += c.redComponent * weight; g += c.greenComponent * weight; b += c.blueComponent * weight; n += weight
            }
        }
        guard n > 0 else { return nil }
        return NSColor(red: r / n, green: g / n, blue: b / n, alpha: 1)
    }
}


// Pictures are created once and then only read, so they're safe to hand between threads
// (Hush decodes icons and news pictures off the main thread).
extension NSImage: @retroactive @unchecked Sendable {}
