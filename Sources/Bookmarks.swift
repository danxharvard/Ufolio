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
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Hush Browser", isDirectory: true)
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

actor FaviconCache {
    static let shared = FaviconCache()
    private var cache: [String: NSImage] = [:]
    private var misses: Set<String> = []

    func icon(for url: URL?) async -> NSImage? {
        guard let url, let host = url.host, let scheme = url.scheme, scheme.hasPrefix("http") else { return nil }
        if let hit = cache[host] { return hit }
        if misses.contains(host) { return nil }

        for path in ["/apple-touch-icon.png", "/favicon.ico"] {
            guard let iconURL = URL(string: "https://\(host)\(path)") else { continue }
            var request = URLRequest(url: iconURL)
            request.timeoutInterval = 5
            if let (data, response) = try? await URLSession.shared.data(for: request),
               (response as? HTTPURLResponse)?.statusCode == 200,
               let image = NSImage(data: data), image.isValid, image.size.width > 0 {
                cache[host] = image
                return image
            }
        }
        misses.insert(host)
        return nil
    }
}

/// What a new tab shows: a calm clock-free page with your bookmarks as tiles.
struct StartPage: View {
    @ObservedObject var model: BrowserModel
    @ObservedObject private var store = BookmarkStore.shared
    @ObservedObject private var weather = LocalWeather.shared
    @Environment(\.colorScheme) private var scheme
    @AppStorage(Prefs.startBackground) private var backgroundStyle = StartBackground.twilight.rawValue
    @AppStorage(Prefs.startGreeting) private var showGreeting = true
    @AppStorage(Prefs.startBookmarks) private var showBookmarks = true
    @AppStorage(Prefs.startPageWeather) private var showWeather = false

    private let columns = [GridItem(.adaptive(minimum: 96, maximum: 110), spacing: 18)]

    var body: some View {
        ZStack {
            StartBackgroundView(style: StartBackground(rawValue: backgroundStyle) ?? .twilight)
            VStack(spacing: 34) {
                VStack(spacing: 8) {
                    Text("Hush")
                        .font(.system(size: 54, weight: .thin, design: .rounded))
                        .tracking(2)
                    if showGreeting || (showWeather && weather.temperature != nil) {
                        HStack(spacing: 8) {
                            if showGreeting { Text(greeting) }
                            if showWeather, let temperature = weather.temperature {
                                if showGreeting { Text("·").foregroundStyle(.tertiary) }
                                Image(systemName: weather.symbol)
                                    .symbolRenderingMode(.multicolor)
                                Text("\(temperature)°")
                                if let city = weather.city {
                                    Text(city)
                                }
                            }
                        }
                        .font(.system(size: 14, weight: .regular, design: .rounded))
                        .foregroundStyle(.secondary)
                        .transition(.opacity)
                    }
                }
                if showBookmarks && !store.items.isEmpty {
                    LazyVGrid(columns: columns, spacing: 18) {
                        ForEach(store.items) { bookmark in
                            StartTile(bookmark: bookmark) {
                                model.open(bookmark.url, inNewTab: NSEvent.modifierFlags.contains(.command))
                            }
                        }
                    }
                    .frame(maxWidth: 620)
                }
            }
            .padding(40)
            .offset(y: -30)
            .animation(.easeOut(duration: 0.3), value: weather.temperature)
        }
        .onAppear { weather.refreshIfNeeded() }
        .onChange(of: showWeather) { on in if on { weather.request() } }
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "Good morning"
        case 12..<18: return "Good afternoon"
        default: return "Good evening"
        }
    }
}

/// The start page's backdrop: a soft twilight gradient, slow-drifting aurora, or plain.
struct StartBackgroundView: View {
    let style: StartBackground
    @Environment(\.colorScheme) private var scheme
    @AppStorage(Prefs.reduceMotion) private var reduceMotion = false
    @State private var drift = false

    var body: some View {
        switch style {
        case .plain:
            Color(nsColor: .windowBackgroundColor)
        case .twilight:
            LinearGradient(
                colors: scheme == .dark
                    ? [Color(red: 0.09, green: 0.09, blue: 0.13), Color(red: 0.13, green: 0.11, blue: 0.19)]
                    : [Color(red: 0.98, green: 0.97, blue: 1.0), Color(red: 0.93, green: 0.93, blue: 0.98)],
                startPoint: .top, endPoint: .bottom)
        case .aurora:
            ZStack {
                (scheme == .dark ? Color(red: 0.07, green: 0.07, blue: 0.11) : Color(red: 0.97, green: 0.97, blue: 0.99))
                GeometryReader { geo in
                    let w = geo.size.width, h = geo.size.height
                    ZStack {
                        blob(Color(red: 0.45, green: 0.35, blue: 0.95), size: w * 0.55)
                            .offset(x: drift ? -w * 0.18 : -w * 0.25, y: drift ? -h * 0.20 : -h * 0.12)
                        blob(Color(red: 0.15, green: 0.65, blue: 0.85), size: w * 0.45)
                            .offset(x: drift ? w * 0.22 : w * 0.15, y: drift ? h * 0.05 : -h * 0.08)
                        blob(Color(red: 0.95, green: 0.45, blue: 0.65), size: w * 0.40)
                            .offset(x: drift ? -w * 0.02 : w * 0.06, y: drift ? h * 0.28 : h * 0.20)
                    }
                    .frame(width: w, height: h)
                }
                .blur(radius: 90)
                .opacity(scheme == .dark ? 0.55 : 0.35)
            }
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 14).repeatForever(autoreverses: true)) { drift = true }
            }
        }
    }

    private func blob(_ color: Color, size: CGFloat) -> some View {
        Circle().fill(color).frame(width: size, height: size)
    }
}

private struct StartTile: View {
    let bookmark: Bookmark
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 9) {
                Favicon(url: bookmark.url, size: 34)
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color(nsColor: .controlBackgroundColor))
                            .shadow(color: .black.opacity(hovering ? 0.14 : 0.06),
                                    radius: hovering ? 12 : 5, y: hovering ? 6 : 2)
                    )
                Text(bookmark.title)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .scaleEffect(hovering ? 1.04 : 1)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.spring(response: 0.25, dampingFraction: 0.75), value: hovering)
        .help(bookmark.url.absoluteString)
    }
}
