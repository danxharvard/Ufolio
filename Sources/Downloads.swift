import SwiftUI
import WebKit

/// One download in the Downloads list.
final class DownloadItem: ObservableObject, Identifiable {
    enum State: String, Codable { case downloading, paused, finished, failed, cancelled }

    let id: UUID
    @Published var filename: String
    @Published var destination: URL?
    @Published var progress: Double
    @Published var state: State
    @Published var totalBytes: Int64
    let started: Date
    /// Where the file came from (to retry), and the data needed to pick up where it stopped.
    var sourceURL: URL?
    var resumeData: Data?
    /// From a private window: listed while Hush is open, but never saved.
    var isPrivate = false
    weak var download: WKDownload?
    private var observation: NSKeyValueObservation?

    init(filename: String, download: WKDownload?) {
        id = UUID()
        self.filename = filename
        self.download = download
        progress = 0
        state = .downloading
        totalBytes = 0
        started = Date()
    }

    init(saved: Saved) {
        id = saved.id
        filename = saved.filename
        destination = saved.path.map { URL(fileURLWithPath: $0) }
        progress = 1
        state = saved.state
        totalBytes = saved.bytes
        started = saved.started
        sourceURL = saved.source.flatMap(URL.init(string:))
    }

    func watch(_ progressObject: Progress) {
        // WebKit reports every chunk (thousands a second on a fast line): only steps of half a
        // percent are passed on, so the main thread and the Downloads list aren't flooded.
        var lastSent = -1.0
        observation = progressObject.observe(\.fractionCompleted) { [weak self] p, _ in
            let fraction = p.fractionCompleted
            guard fraction - lastSent >= 0.005 || fraction >= 1 else { return }
            lastSent = fraction
            let total = p.totalUnitCount
            DispatchQueue.main.async {
                guard let self else { return }
                self.progress = fraction
                if total > 0, self.totalBytes != total { self.totalBytes = total }
            }
        }
    }

    func stopWatching() { observation = nil }

    struct Saved: Codable {
        var id: UUID
        var filename: String
        var path: String?
        var state: State
        var bytes: Int64
        var started: Date
        var source: String?
    }

    var saved: Saved {
        Saved(id: id, filename: filename, path: destination?.path, state: state == .paused ? .failed : state,
              bytes: totalBytes, started: started, source: sourceURL?.absoluteString)
    }
}

/// Saves downloads to the chosen folder (or asks where), keeps the Downloads list,
/// and bounces the Downloads stack in the Dock when a file finishes.
final class Downloads: NSObject, ObservableObject, WKDownloadDelegate {
    static let shared = Downloads()

    @Published private(set) var items: [DownloadItem] = []
    private var byDownload: [ObjectIdentifier: DownloadItem] = [:]

    /// Opened automatically after downloading when "Open safe files" is on (like Safari).
    private static let safeExtensions: Set<String> = [
        "jpg", "jpeg", "png", "gif", "heic", "webp", "tiff", "bmp",
        "mov", "mp4", "m4v", "mp3", "m4a", "aac", "wav", "aiff",
        "pdf", "txt", "rtf",
        // Not zip (opening unpacks it straight away) or csv (spreadsheet apps can run formulas in it).
    ]

    static var folder: URL {
        let saved = Prefs.string(Prefs.downloadFolder)
        // A chosen folder that's gone (an unplugged drive, say) falls back to Downloads,
        // rather than every download quietly failing.
        var isFolder: ObjCBool = false
        if !saved.isEmpty, FileManager.default.fileExists(atPath: saved, isDirectory: &isFolder), isFolder.boolValue {
            return URL(fileURLWithPath: saved, isDirectory: true)
        }
        return FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
    }

    private override init() {
        super.init()
        if let data = UserDefaults.standard.data(forKey: "downloadList"),
           let saved = try? JSONDecoder().decode([DownloadItem.Saved].self, from: data) {
            items = saved.map(DownloadItem.init(saved:))
        }
        prune()
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil,
                                               queue: .main) { [weak self] _ in
            if DownloadRetention.current == .onQuit { self?.clearFinished() }
            self?.save()
        }
    }

    var activeCount: Int { items.filter { $0.state == .downloading }.count }

    // MARK: WKDownloadDelegate

    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse,
                  suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
        // A paused or retried download picks up its old place in the list (and its file).
        // (Only briefly: if a retry never starts, a later download mustn't take its place.)
        if resuming != nil, Date().timeIntervalSince(resumingSince) >= 30 { resuming = nil }
        // Only the download that was actually retried may take its place: any other download
        // starting meanwhile used to take over the slot and overwrite the old file.
        if let item = resuming, item.sourceURL == nil || download.originalRequest?.url == item.sourceURL {
            resuming = nil
            item.download = download
            item.state = .downloading
            item.watch(download.progress)
            byDownload[ObjectIdentifier(download)] = item
            if let url = item.destination { try? FileManager.default.removeItem(at: url) }
            completionHandler(item.destination)
            return
        }
        // A site starting lots of downloads in a row (filling your Downloads folder) must ask first.
        let site = (download.webView?.url ?? download.originalRequest?.url)?.host.map(Domains.site) ?? ""
        if !site.isEmpty, !burstAllowed.contains(site) {
            let now = Date()
            let recent = (recentStarts[site] ?? []).filter { now.timeIntervalSince($0) < 30 }
            if recent.count >= 3 {
                recentStarts[site] = recent
                completionHandler(nil)
                askToAllowMany(from: site, window: download.webView?.window)
                return
            }
            recentStarts[site] = recent + [now]
        }
        let name = Self.safeFilename(suggestedFilename)

        let begin: (URL?) -> Void = { url in
            guard let url else { completionHandler(nil); return }
            let item = DownloadItem(filename: url.lastPathComponent, download: download)
            item.destination = url
            item.sourceURL = download.originalRequest?.url
            item.isPrivate = download.webView.map { !$0.configuration.websiteDataStore.isPersistent } ?? false
            item.watch(download.progress)
            self.byDownload[ObjectIdentifier(download)] = item
            self.items.insert(item, at: 0)
            completionHandler(url)
        }

        if Prefs.bool(Prefs.askWhereToSave) {
            let panel = NSSavePanel()
            panel.nameFieldStringValue = name
            panel.directoryURL = Self.folder
            let finish: (NSApplication.ModalResponse) -> Void = { response in
                guard response == .OK, let url = panel.url else { begin(nil); return }
                try? FileManager.default.removeItem(at: url) // the panel already confirmed replacing it
                begin(url)
            }
            if let window = download.webView?.window {
                panel.beginSheetModal(for: window, completionHandler: finish)
            } else {
                finish(panel.runModal())
            }
            return
        }

        // Sort into folders by type (Settings, off by default): Images, Documents, Videos…
        var folder = Self.folder
        if Prefs.bool(Prefs.sortDownloads), let kind = Self.kindFolder(for: name) {
            let sorted = folder.appendingPathComponent(kind, isDirectory: true)
            if (try? FileManager.default.createDirectory(at: sorted, withIntermediateDirectories: true)) != nil { folder = sorted }
        }
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var candidate = folder.appendingPathComponent(name)
        var n = 2
        // Also skip names taken by downloads still running: two files with the same name started
        // together were both given the same path, before either existed on disk.
        let claimed = Set(items.filter { $0.state != .finished }.compactMap { $0.destination?.standardizedFileURL.path })
        while FileManager.default.fileExists(atPath: candidate.path) || claimed.contains(candidate.standardizedFileURL.path) {
            candidate = folder.appendingPathComponent(ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)")
            n += 1
        }
        begin(candidate)
    }

    /// Sites allowed (until Hush quits) to download several files at once, and when each site's
    /// recent downloads started.
    private var burstAllowed: Set<String> = []
    private var recentStarts: [String: [Date]] = [:]
    private var askingSites: Set<String> = []

    private func askToAllowMany(from site: String, window: NSWindow?) {
        guard !askingSites.contains(site), !DialogHost.isBusy(window) else { return }
        askingSites.insert(site)
        DialogHost.show(HushDialog(
            art: .symbol("square.and.arrow.down.on.square.fill"), theme: .caution, motion: .rise,
            title: "Allow \(site) to download several files?",
            message: "This site is trying to download lots of files one after another. Ufolio stopped the rest until you say so.",
            choices: [.init(title: "Don’t Allow", role: .cancel), .init(title: "Allow", role: .primary)],
            completion: { [weak self] choice, _ in
                self?.askingSites.remove(site)
                if choice == 1 { self?.burstAllowed.insert(site); self?.recentStarts[site] = nil }
            }), in: window)
    }

    /// The folder a file is sorted into by its type, or nil to leave it at the top.
    static func kindFolder(for name: String) -> String? {
        let ext = (name as NSString).pathExtension.lowercased()
        let kinds: [(String, Set<String>)] = [
            ("Images", ["jpg", "jpeg", "png", "gif", "heic", "webp", "tiff", "tif", "bmp", "svg", "avif", "raw"]),
            ("Documents", ["pdf", "doc", "docx", "txt", "rtf", "pages", "odt", "xls", "xlsx", "csv", "numbers", "ppt", "pptx", "key", "epub", "md"]),
            ("Videos", ["mp4", "mov", "m4v", "mkv", "avi", "webm", "wmv"]),
            ("Music", ["mp3", "m4a", "aac", "wav", "flac", "aiff", "ogg", "opus"]),
            ("Archives", ["zip", "rar", "7z", "tar", "gz", "tgz", "bz2", "xz"]),
            ("Installers", ["dmg", "pkg", "app", "mpkg", "iso"]),
            ("Torrents", ["torrent"]),
        ]
        return kinds.first { $0.1.contains(ext) }?.0
    }

    /// Never let a site choose a path or disguise a file: keep only the name, drop invisible
    /// direction-changing characters (which can make "app" look like "jpg"), and keep it short.
    static func safeFilename(_ suggested: String) -> String {
        let invisible: Set<UInt32> = [0x200E, 0x200F, 0x202A, 0x202B, 0x202C, 0x202D, 0x202E, 0x2066, 0x2067, 0x2068, 0x2069, 0x061C]
        var name = String(String.UnicodeScalarView((suggested as NSString).lastPathComponent.unicodeScalars.filter {
            !invisible.contains($0.value) && !CharacterSet.controlCharacters.contains($0)
        }))
        name = name.replacingOccurrences(of: ":", with: "-").replacingOccurrences(of: "/", with: "-")
            .trimmingCharacters(in: .whitespaces)
        if name.isEmpty || name.hasPrefix(".") { name = "download" + name }
        let ext = (name as NSString).pathExtension
        let base = (name as NSString).deletingPathExtension
        // macOS allows 255 bytes per name, not characters: a long name in Japanese or emoji cut
        // to 120 or 200 characters could still be too long, and the download then failed.
        // (Room is left for " 12" when the name is already taken.)
        if ext.isEmpty || ext.count > 20 { return fitting(name, bytes: 230) }
        return fitting(base, bytes: 228 - ext.utf8.count) + "." + ext
    }

    /// The longest start of the text that fits in that many UTF-8 bytes, cut between characters.
    private static func fitting(_ text: String, bytes: Int) -> String {
        guard text.utf8.count > bytes else { return text }
        var result = ""
        for character in text {
            if result.utf8.count + character.utf8.count > bytes { break }
            result.append(character)
        }
        return result
    }

    func downloadDidFinish(_ download: WKDownload) {
        guard let item = byDownload.removeValue(forKey: ObjectIdentifier(download)) else { return }
        item.stopWatching()
        item.progress = 1
        item.state = .finished
        // A Stealth download that finished after the last Stealth window closed leaves the list
        // too (only ones already finished were removed when the window closed).
        if item.isPrivate, !BrowserModel.all.allObjects.contains(where: { $0.isPrivate }) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.forgetPrivateItems() }
        }
        if let url = item.destination {
            DistributedNotificationCenter.default().post(name: .init("com.apple.DownloadFileFinished"), object: url.path)
            // Torrent tools: show what a .torrent holds before anything opens it.
            if TorrentTools.previewOn, url.pathExtension.lowercased() == "torrent" {
                TorrentPreview.show(for: url, in: download.webView?.window)
            }
            if Prefs.bool(Prefs.openSafeFiles), Self.safeExtensions.contains(url.pathExtension.lowercased()) {
                NSWorkspace.shared.open(url)
            }
        }
        if DownloadRetention.current == .onSuccess {
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in self?.remove(item) }
        }
        save()
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        guard let item = byDownload.removeValue(forKey: ObjectIdentifier(download)) else { return }
        item.stopWatching()
        if let resumeData { item.resumeData = resumeData }
        // Pausing stops the download too; keep it paused rather than "cancelled".
        if item.state != .paused {
            item.state = (error as? URLError)?.code == .cancelled ? .cancelled : .failed
        }
        save()
    }

    // MARK: Pause, resume, retry

    /// The item a resumed or retried download belongs to, until WebKit hands it over.
    private var resuming: DownloadItem? {
        didSet { if resuming != nil { resumingSince = Date() } }
    }
    private var resumingSince = Date.distantPast

    func pause(_ item: DownloadItem) {
        guard item.state == .downloading, let download = item.download else { return }
        item.state = .paused
        // WebKit doesn't report a cancelled download back, so it's let go of here.
        byDownload[ObjectIdentifier(download)] = nil
        item.stopWatching()
        download.cancel { data in
            DispatchQueue.main.async { if let data { item.resumeData = data } }
        }
    }

    /// Carries on from where it stopped, or starts again from the beginning if it can't.
    func resume(_ item: DownloadItem) {
        // Through a window of the same kind: a Stealth download only through a Stealth window (and
        // not at all once those are closed, as their cookies are gone), a normal one never
        // through a Stealth window, so neither borrows the other's cookies.
        let model = item.isPrivate
            ? BrowserModel.all.allObjects.first { $0.isPrivate && $0.window != nil }
            : BrowserModel.frontmostNormal
        guard let webView = model?.selectedTab?.webView else { return }
        if let data = item.resumeData {
            item.resumeData = nil
            resuming = item
            item.state = .downloading
            webView.resumeDownload(fromResumeData: data) { [weak self] download in
                download.delegate = self
                // Resumed downloads keep writing to the same file without asking again.
                if self?.byDownload[ObjectIdentifier(download)] == nil {
                    self?.resuming = nil
                    item.download = download
                    item.watch(download.progress)
                    self?.byDownload[ObjectIdentifier(download)] = item
                }
            }
        } else if let source = item.sourceURL {
            resuming = item
            item.state = .downloading
            item.progress = 0
            webView.startDownload(using: URLRequest(url: source)) { [weak self] download in
                download.delegate = self
            }
        }
    }

    func canRetry(_ item: DownloadItem) -> Bool { item.resumeData != nil || item.sourceURL != nil }

    // MARK: List

    /// Stealth windows' finished downloads, out of the list (not off the disk).
    func forgetPrivateItems() {
        let before = items.count
        items.removeAll { $0.isPrivate && $0.state != .downloading && $0.state != .paused }
        if items.count != before { save() }
    }

    /// Stops a running or paused download for good. WebKit never reports a cancelled download
    /// back (the row used to stay "downloading" forever), and it leaves the half-written file
    /// behind under the real name, so both are dealt with here.
    func cancel(_ item: DownloadItem) {
        guard item.state == .downloading || item.state == .paused else { return }
        if let download = item.download {
            byDownload[ObjectIdentifier(download)] = nil
            download.cancel { _ in
                DispatchQueue.main.async { if let url = item.destination { try? FileManager.default.removeItem(at: url) } }
            }
        } else if let url = item.destination {
            try? FileManager.default.removeItem(at: url)
        }
        item.stopWatching()
        item.resumeData = nil
        item.state = .cancelled
        save()
    }

    func reveal(_ item: DownloadItem) {
        guard let url = item.destination, FileManager.default.fileExists(atPath: url.path) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func open(_ item: DownloadItem) {
        guard let url = item.destination, FileManager.default.fileExists(atPath: url.path) else { return }
        NSWorkspace.shared.open(url)
    }

    func remove(_ item: DownloadItem) {
        items.removeAll { $0.id == item.id }
        save()
    }

    /// Clears finished, failed and stopped downloads; ones still going or paused stay (Clear used
    /// to throw away a paused download, and with it any way to resume it).
    func clearFinished() {
        items.removeAll { $0.state != .downloading && $0.state != .paused }
        save()
    }

    /// "After one day": drop finished items older than a day.
    func prune() {
        guard DownloadRetention.current == .oneDay else { return }
        let cutoff = Date().addingTimeInterval(-86_400)
        let before = items.count
        // Paused downloads stay: removing them threw away what's needed to resume them.
        items.removeAll { $0.state != .downloading && $0.state != .paused && $0.started < cutoff }
        if items.count != before { save() }
    }

    private func save() {
        // Private windows' downloads are never written down (the files themselves stay, as in Safari).
        // The newest 300 at most: with "Manually" chosen the list could otherwise grow forever,
        // and it's written out whole on every change.
        let saved = items.filter { $0.state != .downloading && !$0.isPrivate }.prefix(300).map(\.saved)
        UserDefaults.standard.set(try? JSONEncoder().encode(saved), forKey: "downloadList")
    }
}

// MARK: - Toolbar button and list

struct DownloadsButton: View {
    @ObservedObject private var downloads = Downloads.shared
    @State private var showing = false

    var body: some View {
        if !downloads.items.isEmpty {
            Button { showing.toggle() } label: {
                ToolbarBadge(topSymbol: "arrow.down", bottom: "DOWNLOADS", pressed: showing)
            }
            .buttonStyle(.plain)
            .help("Downloads")
                .overlay {
                    if downloads.activeCount > 0 {
                        ActiveBar(items: downloads.items.filter { $0.state == .downloading })
                            .allowsHitTesting(false)
                    }
                }
                .popover(isPresented: $showing, arrowEdge: .bottom) { DownloadsList() }
                .onAppear { downloads.prune() }
        }
    }
}

/// How far the downloads have got: a ring travelling round the DOWNLOADS badge's outline,
/// clockwise from the top centre, gliding on as each part arrives until it meets itself.
/// (Several at once: their progress together.)
private struct ActiveBar: View {
    let items: [DownloadItem]

    var body: some View {
        // Read four times a second: the items' own updates aren't watched from here.
        TimelineView(.periodic(from: .now, by: 0.25)) { _ in
            let progress = items.isEmpty ? 0 : items.map(\.progress).reduce(0, +) / Double(items.count)
            OutlineRing(progress: max(0.02, min(1, progress)))
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
                .frame(width: ToolbarBadge.size.width, height: ToolbarBadge.size.height)
                .animation(.linear(duration: 0.25), value: progress)
        }
    }
}

/// The badge's outline, drawn from the top centre clockwise for the given share of the way round.
private struct OutlineRing: Shape {
    var progress: Double
    var animatableData: Double { get { progress } set { progress = newValue } }

    func path(in rect: CGRect) -> Path {
        // A rounded rectangle's outline starts halfway down its right side; the top centre is
        // three quarters of the way round from there.
        let outline = RoundedRectangle(cornerRadius: 6, style: .continuous).inset(by: 0.8).path(in: rect)
        let start = 0.75, end = start + progress
        var path = outline.trimmedPath(from: start, to: min(1, end))
        if end > 1 { path.addPath(outline.trimmedPath(from: 0, to: end - 1)) }
        return path
    }
}

private struct DownloadsList: View {
    @ObservedObject private var downloads = Downloads.shared
    @AppStorage(Prefs.sortDownloads) private var sortByType = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Downloads").font(.system(size: 13, weight: .semibold))
                Spacer()
                Button("Clear") { downloads.clearFinished() }
                    .buttonStyle(.link)
                    .font(.system(size: 12))
                    .disabled(downloads.items.allSatisfy { $0.state == .downloading || $0.state == .paused })
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 8)
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(downloads.items) { item in
                        DownloadRow(item: item)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.bottom, 8)
            }
            .frame(maxHeight: 340)
            Divider()
            HStack {
                Toggle("Sort into folders by type", isOn: $sortByType)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 11.5))
                Spacer()
                Button("Open Folder") { NSWorkspace.shared.open(Downloads.folder) }
                    .buttonStyle(.link)
                    .font(.system(size: 11.5))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
        .frame(width: 340)
    }
}

private struct DownloadRow: View {
    @ObservedObject var item: DownloadItem
    @State private var hovering = false
    /// Looked up once per state change, not on every progress tick (asking macOS for a file's
    /// icon isn't free, and the list redraws as downloads move).
    @State private var fileIcon: NSImage?

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: fileIcon ?? Self.genericIcon)
                .resizable()
                .frame(width: 32, height: 32)
                .task(id: item.state) { fileIcon = icon }
            VStack(alignment: .leading, spacing: 4) {
                Text(item.filename)
                    .font(.system(size: 12.5))
                    .lineLimit(1)
                    .truncationMode(.middle)
                switch item.state {
                case .downloading:
                    ProgressView(value: item.progress)
                        .progressViewStyle(.linear)
                        .controlSize(.small)
                case .paused:
                    HStack(spacing: 6) {
                        ProgressView(value: item.progress).progressViewStyle(.linear).controlSize(.small).tint(.secondary)
                        Text("Paused").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                case .finished:
                    // Says so when the file has been moved or deleted (Open used to do nothing).
                    if let url = item.destination, !FileManager.default.fileExists(atPath: url.path) {
                        Text("Moved or deleted").font(.system(size: 11)).foregroundStyle(.secondary)
                    } else {
                        Text(sizeText).font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                case .failed:
                    Text("Failed").font(.system(size: 11)).foregroundStyle(Color.orange)
                case .cancelled:
                    Text("Cancelled").font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 4)
            if item.state == .downloading {
                RowButton(symbol: "pause.circle.fill", help: "Pause") { Downloads.shared.pause(item) }
                RowButton(symbol: "xmark.circle.fill", help: "Stop") { Downloads.shared.cancel(item) }
            } else if item.state == .paused {
                RowButton(symbol: "play.circle.fill", help: "Resume", tint: .accentColor) { Downloads.shared.resume(item) }
                RowButton(symbol: "xmark.circle.fill", help: "Stop") { Downloads.shared.cancel(item) }
            } else if item.state == .failed || item.state == .cancelled, Downloads.shared.canRetry(item) {
                RowButton(symbol: "arrow.clockwise.circle.fill", help: "Try Again", tint: .accentColor) { Downloads.shared.resume(item) }
            } else if item.state == .finished {
                Button { Downloads.shared.reveal(item) } label: {
                    Image(systemName: "magnifyingglass.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                // (No hover tooltip: the downloads list closes as Finder opens, and a tooltip on a
                // view that vanishes under the pointer is what crashes SwiftUI.)
                .accessibilityLabel("Show in Finder")
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color.primary.opacity(hovering ? 0.06 : 0)))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(count: 2) { Downloads.shared.open(item) }
        // Drag a finished file out of the list into Finder, Mail or any app.
        .onDrag {
            guard item.state == .finished, let url = item.destination, FileManager.default.fileExists(atPath: url.path) else {
                return NSItemProvider()
            }
            return NSItemProvider(contentsOf: url) ?? NSItemProvider()
        }
        .contextMenu {
            Button { Downloads.shared.open(item) } label: { Label("Open", systemImage: "arrow.up.forward.square") }.disabled(item.state != .finished)
            Button { Downloads.shared.reveal(item) } label: { Label("Show in Finder", systemImage: "folder") }.disabled(item.state != .finished)
            Divider()
            Button { Downloads.shared.remove(item) } label: { Label("Remove from List", systemImage: "minus.circle") }
        }
    }

    private static let genericIcon = NSWorkspace.shared.icon(for: .data)

    private var icon: NSImage {
        if let url = item.destination, FileManager.default.fileExists(atPath: url.path) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return NSWorkspace.shared.icon(for: .data)
    }

    private var sizeText: String {
        let size = item.totalBytes > 0 ? ByteCountFormatter.string(fromByteCount: item.totalBytes, countStyle: .file) : ""
        return [size, item.started.formatted(date: .omitted, time: .shortened)].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

private struct RowButton: View {
    let symbol: String
    let help: String
    var tint: Color = .secondary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 15)).foregroundStyle(tint)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(help)   // VoiceOver said nothing useful for these
    }
}
