import SwiftUI
import AppKit

struct Bookmark: Codable, Identifiable, Equatable {
    var id = UUID()
    var title: String
    var url: URL
}

/// Bookmarks, saved to ~/Library/Application Support/Hush Browser/bookmarks.json.
final class BookmarkStore: ObservableObject {
    static let shared = BookmarkStore()

    @Published private(set) var items: [Bookmark] = []
    private let fileURL: URL

    private init() {
        let folder = AppPaths.support
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        fileURL = folder.appendingPathComponent("bookmarks.json")
        load()
    }

    func contains(_ url: URL) -> Bool {
        items.contains { Self.same($0.url, url) }
    }

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
        var added = 0
        for item in imported where !contains(item.url) && !items.contains(where: { Self.same($0.url, item.url) }) {
            let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
            items.append(Bookmark(title: title.isEmpty ? (item.url.host ?? item.url.absoluteString) : String(title.prefix(200)), url: item.url))
            added += 1
        }
        if added > 0 { save() }
        return added
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

    func move(_ bookmark: Bookmark, by offset: Int) {
        guard let i = items.firstIndex(where: { $0.id == bookmark.id }) else { return }
        let j = i + offset
        guard items.indices.contains(j) else { return }
        items.swapAt(i, j)
        save()
    }

    private static func same(_ a: URL, _ b: URL) -> Bool {
        func key(_ u: URL) -> String {
            var s = u.absoluteString.lowercased()
            if s.hasSuffix("/") { s.removeLast() }
            return s.replacingOccurrences(of: "://www.", with: "://")
        }
        return key(a) == key(b)
    }

    private func load() {
        if let data = try? Data(contentsOf: fileURL),
           let saved = try? JSONDecoder().decode([Bookmark].self, from: data) {
            items = saved
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

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        if let data = try? encoder.encode(items) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}

/// The row of bookmarks under the toolbar.
struct BookmarkBar: View {
    @ObservedObject var model: BrowserModel
    @ObservedObject private var store = BookmarkStore.shared

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                if store.items.isEmpty {
                    Text("Press ⌘D to bookmark a page — it appears here")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 8)
                }
                ForEach(store.items) { bookmark in
                    BookmarkChip(model: model, bookmark: bookmark)
                }
            }
            .padding(.horizontal, 10)
        }
        .frame(height: 30)
    }
}

private struct BookmarkChip: View {
    @ObservedObject var model: BrowserModel
    let bookmark: Bookmark
    @State private var hovering = false
    @State private var renaming = false
    @State private var newTitle = ""

    var body: some View {
        HStack(spacing: 6) {
            Favicon(url: bookmark.url, size: 14)
            Text(bookmark.title)
                .font(.system(size: 12))
                .lineLimit(1)
                .frame(maxWidth: 140, alignment: .leading)
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 8)
        .frame(height: 24)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.primary.opacity(hovering ? 0.08 : 0))
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture {
            let newTab = NSEvent.modifierFlags.contains(.command)
            model.open(bookmark.url, inNewTab: newTab)
        }
        .help(bookmark.url.absoluteString)
        .contextMenu {
            Button("Open in New Tab") { model.open(bookmark.url, inNewTab: true) }
            Button("Copy Address") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(bookmark.url.absoluteString, forType: .string)
            }
            Divider()
            Button("Rename…") { newTitle = bookmark.title; renaming = true }
            Button("Move Left") { BookmarkStore.shared.move(bookmark, by: -1) }
            Button("Move Right") { BookmarkStore.shared.move(bookmark, by: 1) }
            Divider()
            Button("Remove") { BookmarkStore.shared.remove(bookmark) }
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

/// A site's icon, loaded from the site itself; falls back to a coloured letter.
struct Favicon: View {
    let url: URL?
    let size: CGFloat
    @State private var image: NSImage?

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
            image = await FaviconCache.shared.icon(for: url)
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
    private var cache: [String: SiteIcon] = [:]
    private var misses: Set<String> = []
    private var inFlight: [String: Task<SiteIcon?, Never>] = [:]

    func icon(for url: URL?) async -> NSImage? {
        await info(for: url)?.image
    }

    /// Fetches each site's icon once, even when many views ask at the same moment.
    func info(for url: URL?) async -> SiteIcon? {
        guard let url, let host = url.host, let scheme = url.scheme, scheme.hasPrefix("http") else { return nil }
        if let hit = cache[host] { return hit }
        if misses.contains(host) { return nil }
        if let running = inFlight[host] { return await running.value }

        let task = Task<SiteIcon?, Never> {
            // Kept on disk for two weeks, so icons appear instantly after a relaunch.
            if let data = Self.cached(host), let icon = Self.makeIcon(data) { return icon }
            for path in ["/apple-touch-icon.png", "/apple-touch-icon-precomposed.png", "/favicon.ico"] {
                guard let iconURL = URL(string: "https://\(host)\(path)") else { continue }
                var request = URLRequest(url: iconURL)
                request.timeoutInterval = 5
                if let (data, response) = try? await Self.session.data(for: request),
                   (response as? HTTPURLResponse)?.statusCode == 200, data.count < 1_000_000,
                   let icon = Self.makeIcon(data) {
                    Self.store(data, for: host)
                    return icon
                }
            }
            return nil
        }
        inFlight[host] = task
        let result = await task.value
        inFlight[host] = nil
        if let result { cache[host] = result } else { misses.insert(host) }
        return result
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

    private static func makeIcon(_ data: Data) -> SiteIcon? {
        guard let image = NSImage(data: data), image.isValid, image.size.width > 0 else { return nil }
        let pixels = image.representations.map(\.pixelsWide).max() ?? Int(image.size.width)
        return SiteIcon(image: image, pixels: pixels, tint: mainColor(of: image))
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
