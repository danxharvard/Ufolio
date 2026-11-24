import SwiftUI
import ImageIO

/// What sits behind the start page.
enum StartBackground: String, CaseIterable, Identifiable {
    case frosted, desktop, daily, wallpaper, photo
    var id: String { rawValue }

    var label: String {
        switch self {
        case .frosted: return "Frosted Glass"
        case .desktop: return "Your Desktop"
        case .daily: return "Photo of the Day"
        case .wallpaper: return "macOS Wallpaper"
        case .photo: return "Your Photo"
        }
    }

    /// The saved choice; anything older (Twilight, Aurora, Plain) becomes Frosted Glass.
    static var current: StartBackground { StartBackground(rawValue: Prefs.string(Prefs.startBackground)) ?? .frosted }
}

/// Loads the start page's picture once, at screen size (a 6K wallpaper decoded in full would
/// take well over 100 MB; at screen size it's a fraction of that), and shares it between tabs.
@MainActor
final class BackgroundStore: ObservableObject {
    static let shared = BackgroundStore()

    @Published private(set) var image: NSImage?
    /// "Photo by …" for the photo of the day.
    @Published private(set) var credit: String?
    private var loadedKey: String?
    private var loading: Task<Void, Never>?

    /// Apple's wallpapers that come with macOS (still pictures only).
    nonisolated static var systemWallpapers: [URL] {
        let folders = ["/System/Library/Desktop Pictures", "/Library/Desktop Pictures"]
        let fm = FileManager.default
        var found: [URL] = []
        for folder in folders {
            for name in (try? fm.contentsOfDirectory(atPath: folder)) ?? [] {
                let ext = (name as NSString).pathExtension.lowercased()
                guard ["heic", "jpg", "jpeg", "png"].contains(ext) else { continue }
                found.append(URL(fileURLWithPath: folder).appendingPathComponent(name))
            }
        }
        return found.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    nonisolated static var folder: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Hush Browser/Background", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Makes sure the picture for the current choice is loaded (cheap when it already is).
    func refresh() {
        let choice = StartBackground.current
        let key: String
        switch choice {
        case .frosted: image = nil; credit = nil; loadedKey = nil; return
        case .desktop: key = "desktop:" + (NSScreen.main.flatMap { NSWorkspace.shared.desktopImageURL(for: $0)?.path } ?? "")
        case .wallpaper: key = "wallpaper:" + Prefs.string(Prefs.startWallpaper)
        case .photo: key = "photo:" + Prefs.string(Prefs.startPhoto)
        case .daily: key = "daily:" + Self.today
        }
        guard key != loadedKey else { return }
        loadedKey = key
        loading?.cancel()
        let maxPixels = Self.screenPixels
        loading = Task {
            var url: URL?
            var credit: String?
            switch choice {
            case .desktop: url = NSScreen.main.flatMap { NSWorkspace.shared.desktopImageURL(for: $0) }
            case .wallpaper: url = Prefs.string(Prefs.startWallpaper).isEmpty ? Self.systemWallpapers.first : URL(fileURLWithPath: Prefs.string(Prefs.startWallpaper))
            case .photo: url = Prefs.string(Prefs.startPhoto).isEmpty ? nil : URL(fileURLWithPath: Prefs.string(Prefs.startPhoto))
            case .daily: (url, credit) = await DailyPhoto.today()
            case .frosted: break
            }
            let decoded = await Task.detached(priority: .utility) { url.flatMap { Self.downsampled($0, maxPixels: maxPixels) } }.value
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.35)) {
                self.image = decoded.map { NSImage(cgImage: $0, size: .zero) }
                self.credit = decoded == nil ? nil : credit
            }
        }
    }

    /// Lets go of the picture when memory is wanted elsewhere and no start page is showing
    /// (it's decoded again the next time one opens).
    func purgeIfHidden() {
        let showing = BrowserModel.all.allObjects.contains { $0.window?.isVisible == true && $0.selectedTab?.isBlank == true }
        guard !showing else { return }
        image = nil
        loadedKey = nil
    }

    /// Saves a copy of your own photo (so it still works if you move or delete the original).
    func usePhoto(from source: URL) -> Bool {
        let ext = source.pathExtension.isEmpty ? "jpg" : source.pathExtension.lowercased()
        let dest = Self.folder.appendingPathComponent("photo-\(Int(Date().timeIntervalSince1970)).\(ext)")
        guard Self.downsampled(source, maxPixels: 64) != nil else { return false }   // really an image
        do {
            for old in (try? FileManager.default.contentsOfDirectory(at: Self.folder, includingPropertiesForKeys: nil)) ?? []
            where old.lastPathComponent.hasPrefix("photo-") { try? FileManager.default.removeItem(at: old) }
            try FileManager.default.copyItem(at: source, to: dest)
        } catch { return false }
        UserDefaults.standard.set(dest.path, forKey: Prefs.startPhoto)
        UserDefaults.standard.set(StartBackground.photo.rawValue, forKey: Prefs.startBackground)
        refresh()
        return true
    }

    private static var today: String { Date().formatted(.iso8601.year().month().day()) }

    /// The largest the picture ever needs to be: the biggest screen, in pixels.
    private static var screenPixels: Int {
        let biggest = NSScreen.screens.map { max($0.frame.width, $0.frame.height) * $0.backingScaleFactor }.max() ?? 2880
        return Int(min(biggest, 2880))   // sharp behind the shade, at a fraction of the memory
    }

    /// Decodes an image straight to the size needed, never the full original.
    nonisolated static func downsampled(_ url: URL, maxPixels: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}

/// Bing's photo of the day: a public feed that needs no account. Fetched without cookies,
/// kept on disk for the day, and only ever when you've chosen it.
enum DailyPhoto {
    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        config.urlCache = nil
        return URLSession(configuration: config)
    }()

    static func today() async -> (URL?, String?) {
        let day = Date().formatted(.iso8601.year().month().day())
        let file = BackgroundStore.folder.appendingPathComponent("daily-\(day).jpg")
        let creditFile = BackgroundStore.folder.appendingPathComponent("daily-\(day).txt")
        if FileManager.default.fileExists(atPath: file.path) {
            return (file, try? String(contentsOf: creditFile, encoding: .utf8))
        }
        guard let feed = URL(string: "https://www.bing.com/HPImageArchive.aspx?format=js&idx=0&n=1"),
              let (data, _) = try? await session.data(from: feed),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let first = (json["images"] as? [[String: Any]])?.first,
              let base = first["urlbase"] as? String,
              // Only ever a picture from Bing itself.
              let imageURL = URL(string: "https://www.bing.com" + base + "_UHD.jpg"), imageURL.host == "www.bing.com",
              let (imageData, response) = try? await session.data(from: imageURL),
              (response as? HTTPURLResponse)?.statusCode == 200, imageData.count < 30_000_000 else { return (nil, nil) }
        // Keep only today's.
        for old in (try? FileManager.default.contentsOfDirectory(at: BackgroundStore.folder, includingPropertiesForKeys: nil)) ?? []
        where old.lastPathComponent.hasPrefix("daily-") { try? FileManager.default.removeItem(at: old) }
        try? imageData.write(to: file, options: .atomic)
        let credit = (first["copyright"] as? String).map { String($0.prefix(160)) }
        try? credit?.write(to: creditFile, atomically: true, encoding: .utf8)
        return (file, credit)
    }
}

/// The start page's backdrop: frosted glass, or a picture with a gentle shade so the page reads well.
struct StartBackdrop: View {
    @ObservedObject private var store = BackgroundStore.shared
    @AppStorage(Prefs.startBackground) private var choice = StartBackground.frosted.rawValue
    @AppStorage(Prefs.startTranslucent) private var translucent = true
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            if translucent || store.image == nil {
                VisualEffect(material: .underWindowBackground, blending: .behindWindow)
            }
            if !translucent && store.image == nil {
                Color(nsColor: .windowBackgroundColor)
            }
            if let image = store.image, StartBackground.current != .frosted {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
                    .transition(.opacity)
                // A soft shade, deeper at the bottom where the cards are.
                LinearGradient(colors: [.black.opacity(0.18), .black.opacity(0.42)], startPoint: .top, endPoint: .bottom)
            }
        }
        .clipped()
        .allowsHitTesting(false)
        .onAppear { store.refresh() }
        .onChange(of: choice) { _, _ in store.refresh() }
    }
}

// MARK: - Settings › Appearance › Start page

/// Pick the start page's background: tiles for each kind, then Apple's wallpapers as thumbnails.
struct BackgroundPicker: View {
    @AppStorage(Prefs.startBackground) private var choice = StartBackground.frosted.rawValue
    @AppStorage(Prefs.startWallpaper) private var wallpaper = ""
    @State private var wallpapers: [URL] = []
    @State private var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                kindTile(.frosted, symbol: "square.on.square.dashed", colors: [Color(white: 0.75), Color(white: 0.55)])
                kindTile(.desktop, symbol: "menubar.dock.rectangle", colors: [Color(red: 0.3, green: 0.6, blue: 1), Color(red: 0.2, green: 0.4, blue: 0.9)])
                kindTile(.daily, symbol: "sun.horizon.fill", colors: [Color(red: 1, green: 0.62, blue: 0.3), Color(red: 0.95, green: 0.38, blue: 0.3)])
                Button(action: choosePhoto) {
                    tileLabel(title: StartBackground.photo.label, symbol: "photo.on.rectangle.angled",
                              colors: [Color(red: 0.6, green: 0.45, blue: 1), Color(red: 0.42, green: 0.3, blue: 0.9)],
                              selected: choice == StartBackground.photo.rawValue)
                }
                .buttonStyle(.plain)
            }
            if choice == StartBackground.daily.rawValue {
                Footnote("A new photo every day from Bing’s public photo of the day, fetched without cookies.")
            }
            if let message {
                Label(message, systemImage: "exclamationmark.circle").font(.system(size: 11.5)).foregroundStyle(.orange)
            }
            if !wallpapers.isEmpty {
                Text("macOS wallpapers").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 104, maximum: 130), spacing: 10)], spacing: 10) {
                    ForEach(wallpapers, id: \.self) { url in
                        WallpaperThumb(url: url, selected: choice == StartBackground.wallpaper.rawValue && wallpaper == url.path) {
                            wallpaper = url.path
                            choice = StartBackground.wallpaper.rawValue
                            BackgroundStore.shared.refresh()
                        }
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .task { wallpapers = await Task.detached(priority: .utility) { BackgroundStore.systemWallpapers }.value }
    }

    private func kindTile(_ kind: StartBackground, symbol: String, colors: [Color]) -> some View {
        Button {
            choice = kind.rawValue
            BackgroundStore.shared.refresh()
        } label: {
            tileLabel(title: kind.label, symbol: symbol, colors: colors, selected: choice == kind.rawValue)
        }
        .buttonStyle(.plain)
    }

    private func tileLabel(title: String, symbol: String, colors: [Color], selected: Bool) -> some View {
        VStack(spacing: 7) {
            IconTile(symbol: symbol, colors: colors, size: 34)
            Text(title).font(.system(size: 11, weight: selected ? .semibold : .regular)).lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(selected ? 0.08 : 0.03)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.08), lineWidth: selected ? 2 : 1))
        .contentShape(Rectangle())
    }

    private func choosePhoto() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.canChooseDirectories = false
        panel.message = "Choose a photo for the start page."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        message = BackgroundStore.shared.usePhoto(from: url) ? nil : "That file couldn’t be used as a picture."
    }
}

private struct WallpaperThumb: View {
    let url: URL
    let selected: Bool
    let action: () -> Void
    @State private var image: NSImage?
    @State private var hovering = false

    /// Small thumbnails only, shared across Settings visits.
    @MainActor private static let cache: NSCache<NSURL, NSImage> = {
        let c = NSCache<NSURL, NSImage>()
        c.countLimit = 80
        return c
    }()

    var body: some View {
        Button(action: action) {
            ZStack {
                Color.primary.opacity(0.06)
                if let image { Image(nsImage: image).resizable().aspectRatio(contentMode: .fill) }
            }
            .frame(height: 66)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(selected ? Color.accentColor : Color.primary.opacity(hovering ? 0.25 : 0.1), lineWidth: selected ? 2.5 : 1))
            .scaleEffect(hovering ? 1.03 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: hovering)
        .help(url.deletingPathExtension().lastPathComponent)
        .task(id: url) {
            if let hit = Self.cache.object(forKey: url as NSURL) { image = hit; return }
            let thumb = await Task.detached(priority: .utility) { BackgroundStore.downsampled(url, maxPixels: 260) }.value
            if let thumb {
                let picture = NSImage(cgImage: thumb, size: .zero)
                Self.cache.setObject(picture, forKey: url as NSURL)
                image = picture
            }
        }
    }
}
