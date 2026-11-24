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
        observation = progressObject.observe(\.fractionCompleted) { [weak self] p, _ in
            let fraction = p.fractionCompleted
            let total = p.totalUnitCount
            DispatchQueue.main.async {
                self?.progress = fraction
                if total > 0 { self?.totalBytes = total }
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
        if !saved.isEmpty { return URL(fileURLWithPath: saved, isDirectory: true) }
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

        let folder = Self.folder
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var candidate = folder.appendingPathComponent(name)
        var n = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
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
        var base = (name as NSString).deletingPathExtension
        if base.utf8.count > 200 { base = String(base.prefix(120)) }
        return ext.isEmpty || ext.count > 20 ? String(name.prefix(200)) : base + "." + ext
    }

    func downloadDidFinish(_ download: WKDownload) {
        guard let item = byDownload.removeValue(forKey: ObjectIdentifier(download)) else { return }
        item.stopWatching()
        item.progress = 1
        item.state = .finished
        if let url = item.destination {
            DistributedNotificationCenter.default().post(name: .init("com.apple.DownloadFileFinished"), object: url.path)
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
        download.cancel { data in
            DispatchQueue.main.async { if let data { item.resumeData = data } }
        }
    }

    /// Carries on from where it stopped, or starts again from the beginning if it can't.
    func resume(_ item: DownloadItem) {
        guard let webView = BrowserModel.frontmostNormal?.selectedTab?.webView ?? BrowserModel.frontmost?.selectedTab?.webView else { return }
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

    func cancel(_ item: DownloadItem) {
        item.download?.cancel { _ in }
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

    func clearFinished() {
        items.removeAll { $0.state != .downloading }
        save()
    }

    /// "After one day": drop finished items older than a day.
    func prune() {
        guard DownloadRetention.current == .oneDay else { return }
        let cutoff = Date().addingTimeInterval(-86_400)
        items.removeAll { $0.state != .downloading && $0.started < cutoff }
    }

    private func save() {
        // Private windows' downloads are never written down (the files themselves stay, as in Safari).
        let saved = items.filter { $0.state != .downloading && !$0.isPrivate }.map(\.saved)
        UserDefaults.standard.set(try? JSONEncoder().encode(saved), forKey: "downloadList")
    }
}

// MARK: - Toolbar button and list

struct DownloadsButton: View {
    @ObservedObject private var downloads = Downloads.shared
    @State private var showing = false

    var body: some View {
        if !downloads.items.isEmpty {
            ToolbarIconButton(symbol: "arrow.down.circle", help: "Downloads") { showing.toggle() }
                .overlay {
                    if downloads.activeCount > 0 {
                        ActiveRing(items: downloads.items.filter { $0.state == .downloading })
                            .allowsHitTesting(false)
                    }
                }
                .popover(isPresented: $showing, arrowEdge: .bottom) { DownloadsList() }
                .onAppear { downloads.prune() }
        }
    }
}

private struct ActiveRing: View {
    let items: [DownloadItem]

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { _ in
            let progress = items.isEmpty ? 0 : items.map(\.progress).reduce(0, +) / Double(items.count)
            Circle()
                .trim(from: 0, to: max(0.03, progress))
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: 21, height: 21)
                .animation(.easeOut(duration: 0.25), value: progress)
        }
    }
}

private struct DownloadsList: View {
    @ObservedObject private var downloads = Downloads.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Downloads").font(.system(size: 13, weight: .semibold))
                Spacer()
                Button("Clear") { downloads.clearFinished() }
                    .buttonStyle(.link)
                    .font(.system(size: 12))
                    .disabled(downloads.items.allSatisfy { $0.state == .downloading })
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
        }
        .frame(width: 340)
    }
}

private struct DownloadRow: View {
    @ObservedObject var item: DownloadItem
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: icon)
                .resizable()
                .frame(width: 32, height: 32)
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
                    Text(sizeText).font(.system(size: 11)).foregroundStyle(.secondary)
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
                RowButton(symbol: "xmark.circle.fill", help: "Stop") {
                    item.resumeData = nil
                    item.state = .cancelled
                }
            } else if item.state == .failed || item.state == .cancelled, Downloads.shared.canRetry(item) {
                RowButton(symbol: "arrow.clockwise.circle.fill", help: "Try Again", tint: .accentColor) { Downloads.shared.resume(item) }
            } else if item.state == .finished {
                Button { Downloads.shared.reveal(item) } label: {
                    Image(systemName: "magnifyingglass.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Show in Finder")
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
        .help(help)
    }
}
