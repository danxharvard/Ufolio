import SwiftUI
import AppKit
import WebKit

// Torrent tools: off unless you switch them on in Settings › Privacy & Security. Ufolio never
// downloads or shares torrents itself. It only shows you what a magnet link or .torrent file
// contains, warns about traps, and hands the link to your own torrent app.

enum TorrentTools {
    static var on: Bool { Prefs.bool(Prefs.torrentTools) }
    static var previewOn: Bool { on && Prefs.bool(Prefs.torrentPreview) }
    static var siteModeOn: Bool { on && Prefs.bool(Prefs.torrentSiteMode) }
    static var fakeWarningsOn: Bool { on && Prefs.bool(Prefs.torrentFakeWarnings) }

    // MARK: Torrent index sites

    /// Well-known torrent index sites. Others are recognised by their pages (lots of magnet links).
    private static let indexSites: Set<String> = [
        "thepiratebay.org", "thepiratebay10.org", "1337x.to", "1337x.st", "1337x.so", "x1337x.ws", "x1337x.eu", "1377x.to",
        "yts.mx", "yts.lt", "yts.am", "eztv.re", "eztvx.to", "eztv.wf", "torrentgalaxy.to", "tgx.rs", "limetorrents.lol",
        "limetorrents.info", "nyaa.si", "kickasstorrents.to", "katcr.to", "kat.am", "torlock.com", "torrentdownloads.pro",
        "magnetdl.com", "rutracker.org", "glodls.to", "idope.se", "bitsearch.to", "solidtorrents.to", "torrentz2.eu",
        "zooqle.com", "torrentfunk.com", "yourbittorrent.com", "btdig.com", "knaben.eu", "torrentproject2.com",
        "fitgirl-repacks.site", "rarbg.to", "therarbg.com", "extratorrent.st", "isohunt.to", "linuxtracker.org",
    ]
    /// Sites found to be torrent index sites while you browsed (until Ufolio quits).
    private static var recognised: Set<String> = []

    static func isIndexSite(_ host: String?) -> Bool {
        guard let host, !host.isEmpty else { return false }
        let site = Domains.site(host)
        return indexSites.contains(site) || recognised.contains(site)
    }

    static func recognise(_ host: String?) {
        guard let host else { return }
        recognised.insert(Domains.site(host))
    }

    /// Pop-under and redirect ad networks common on torrent sites.
    private static let adNetworks: Set<String> = [
        "popads.net", "popcash.net", "propellerads.com", "propellerclick.com", "onclickads.net", "onclkds.com",
        "adsterra.com", "adsterratech.com", "highperformanceformat.com", "exoclick.com", "exosrv.com", "juicyads.com",
        "hilltopads.net", "hilltopads.com", "clickadu.com", "adcash.com", "monetag.com", "a-ads.com", "trafficjunky.net",
        "popmyads.com", "clickaine.com", "adskeeper.com", "mgid.com", "galaksion.com", "pushame.com", "richpush.co",
        "evadav.com", "rollerads.com", "dolohen.com", "ad-maven.com", "admaven.com", "notifpush.com",
    ]

    static func isAdNetwork(_ host: String?) -> Bool {
        guard let host else { return false }
        return adNetworks.contains(Domains.site(host))
    }

    // MARK: Torrent apps

    /// Apps on this Mac that open magnet links (Transmission, qBittorrent, …).
    static func installedApps() -> [URL] {
        guard let probe = URL(string: "magnet:?xt=urn:btih:0000000000000000000000000000000000000000") else { return [] }
        return NSWorkspace.shared.urlsForApplications(toOpen: probe).filter { $0.path != Bundle.main.bundlePath }
    }

    /// The app chosen in Settings, or the Mac's default for magnet links.
    static var chosenApp: URL? {
        let id = Prefs.string(Prefs.torrentApp)
        if !id.isEmpty, let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) { return app }
        guard let probe = URL(string: "magnet:?xt=urn:btih:0000000000000000000000000000000000000000"),
              let app = NSWorkspace.shared.urlForApplication(toOpen: probe), app.path != Bundle.main.bundlePath else { return nil }
        return app
    }

    static func appName(_ app: URL) -> String {
        FileManager.default.displayName(atPath: app.path).replacingOccurrences(of: ".app", with: "")
    }

    /// Hands a magnet link or a .torrent file to your torrent app.
    @discardableResult
    static func handOff(_ url: URL) -> Bool {
        guard let app = chosenApp else { return false }
        NSWorkspace.shared.open([url], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
        return true
    }

    // MARK: Magnet links

    struct Magnet {
        var name: String?
        var size: Int64?
        var hash: String?
        var trackers = 0
        var fileCount: Int?
        var valid: Bool { hash != nil }
    }

    static func parseMagnet(_ url: URL) -> Magnet {
        var magnet = Magnet()
        // URLComponents can't read "magnet:?…" reliably when it's oddly encoded, so read the query.
        let query = url.absoluteString.split(separator: "?", maxSplits: 1).dropFirst().first.map(String.init) ?? ""
        var selected: Set<String> = []
        for pair in query.split(separator: "&").prefix(500) {
            let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            let key = parts[0].lowercased()
            let value = (parts[1].replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? parts[1])
            switch key {
            case "dn": magnet.name = clean(value, limit: 300)
            case "xl": if let n = Int64(value), n >= 0 { magnet.size = n }
            case "tr": magnet.trackers += 1
            case "so": value.split(separator: ",").prefix(10_000).forEach { selected.insert(String($0)) }
            case "xt":
                let lower = value.lowercased()
                if lower.hasPrefix("urn:btih:") {
                    let hash = String(value.dropFirst(9))
                    let isHex = hash.count == 40 && hash.allSatisfy(\.isHexDigit)
                    let isBase32 = hash.count == 32 && hash.uppercased().allSatisfy { "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567".contains($0) }
                    if isHex || isBase32 { magnet.hash = hash.uppercased() }
                } else if lower.hasPrefix("urn:btmh:"), value.count > 12, value.count < 120 {
                    magnet.hash = String(value.dropFirst(9))
                }
            default: break
            }
        }
        if !selected.isEmpty { magnet.fileCount = selected.count }
        return magnet
    }

    /// The card shown when you click a magnet link.
    static func showMagnetCard(_ url: URL, from host: String?, in window: NSWindow?) {
        guard !DialogHost.isBusy(window) else { return }
        let magnet = parseMagnet(url)
        let app = chosenApp
        var lines: [String] = []
        if let size = magnet.size { lines.append(ByteCountFormatter.string(fromByteCount: size, countStyle: .file)) }
        if let count = magnet.fileCount { lines.append("\(count) file\(count == 1 ? "" : "s")") }
        if magnet.trackers > 0 { lines.append("\(magnet.trackers) tracker\(magnet.trackers == 1 ? "" : "s")") }
        var message = lines.joined(separator: " · ")
        if magnet.size == nil || magnet.fileCount == nil {
            message += (message.isEmpty ? "" : "\n") + "The full file list arrives once your torrent app connects."
        }
        guard magnet.valid else {
            DialogHost.show(HushDialog(
                art: .symbol("link"), badge: "exclamationmark.triangle.fill", theme: .caution, motion: .pulse,
                title: "This magnet link looks broken",
                message: "It doesn’t contain a valid torrent ID, so no torrent app could use it.",
                choices: [.init(title: "OK", role: .primary)]), in: window)
            return
        }
        let source = host.map { "From \($0.strippingWWW)" }
        guard let app else {
            DialogHost.show(HushDialog(
                art: .symbol("link"), badge: "arrow.down.circle.fill", theme: .hush, motion: .orbit,
                title: magnet.name ?? "Magnet link",
                message: message + "\n\nNo torrent app is installed. You can copy the link and open it in one later.",
                note: source.map { ("globe", $0) },
                choices: [.init(title: "Cancel", role: .cancel), .init(title: "Copy Magnet Link", role: .primary)],
                completion: { choice, _ in
                    guard choice == 1 else { return }
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(url.absoluteString, forType: .string)
                }), in: window)
            return
        }
        DialogHost.show(HushDialog(
            art: .image(NSWorkspace.shared.icon(forFile: app.path)), badge: "link", theme: .hush, motion: .orbit,
            title: magnet.name ?? "Magnet link",
            message: message,
            note: source.map { ("globe", $0) },
            choices: [.init(title: "Cancel", role: .cancel), .init(title: "Copy Link"),
                      .init(title: "Open in \(appName(app))", role: .primary)],
            completion: { choice, _ in
                if choice == 1 {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(url.absoluteString, forType: .string)
                } else if choice == 2 {
                    handOff(url)
                }
            }), in: window)
    }

    /// Text from a link or file, made safe to show: no control or direction-changing characters.
    static func clean(_ text: String, limit: Int) -> String {
        let invisible: Set<UInt32> = [0x200E, 0x200F, 0x202A, 0x202B, 0x202C, 0x202D, 0x202E, 0x2066, 0x2067, 0x2068, 0x2069, 0x061C]
        let scalars = text.unicodeScalars.filter { !invisible.contains($0.value) && !CharacterSet.controlCharacters.contains($0) }
        return String(String(String.UnicodeScalarView(scalars)).prefix(limit))
    }

    static func hasHiddenDirection(_ text: String) -> Bool {
        text.unicodeScalars.contains { [0x202E, 0x202D, 0x2066, 0x2067, 0x2068, 0x200F].contains($0.value) }
    }
}

// MARK: - Reading .torrent files

/// A careful reader for bencoding, the format of .torrent files. The files come from strangers,
/// so everything is bounded: the file's size, how deeply things nest, how many items there are
/// and every length. Nothing is fetched from the network.
enum Bencode {
    indirect enum Value {
        case int(Int64)
        case bytes([UInt8])
        case list([Value])
        case dict([String: Value])

        subscript(_ key: String) -> Value? { if case .dict(let d) = self { return d[key] } else { return nil } }
        var int: Int64? { if case .int(let n) = self { return n } else { return nil } }
        var list: [Value]? { if case .list(let l) = self { return l } else { return nil } }
        var dict: [String: Value]? { if case .dict(let d) = self { return d } else { return nil } }
        var string: String? { if case .bytes(let b) = self { return String(decoding: b, as: UTF8.self) } else { return nil } }
    }

    struct DecodeError: Error {}

    static let maxDepth = 48
    static let maxItems = 400_000

    static func decode(_ data: Data) throws -> Value {
        var reader = Reader(bytes: [UInt8](data))
        let value = try reader.value(depth: 0)
        return value
    }

    private struct Reader {
        let bytes: [UInt8]
        var i = 0
        var items = 0

        mutating func value(depth: Int) throws -> Value {
            guard depth < Bencode.maxDepth, i < bytes.count else { throw DecodeError() }
            items += 1
            guard items <= Bencode.maxItems else { throw DecodeError() }
            switch bytes[i] {
            case UInt8(ascii: "i"):
                i += 1
                let n = try number(until: UInt8(ascii: "e"), allowNegative: true)
                return .int(n)
            case UInt8(ascii: "l"):
                i += 1
                var list: [Value] = []
                while true {
                    guard i < bytes.count else { throw DecodeError() }
                    if bytes[i] == UInt8(ascii: "e") { i += 1; return .list(list) }
                    list.append(try value(depth: depth + 1))
                }
            case UInt8(ascii: "d"):
                i += 1
                var dict: [String: Value] = [:]
                while true {
                    guard i < bytes.count else { throw DecodeError() }
                    if bytes[i] == UInt8(ascii: "e") { i += 1; return .dict(dict) }
                    let key = try string()
                    let k = String(decoding: key, as: UTF8.self)
                    // "pieces" is large and never shown: skip keeping it.
                    let v = try value(depth: depth + 1)
                    dict[k] = k == "pieces" ? .bytes([]) : v
                }
            case UInt8(ascii: "0")...UInt8(ascii: "9"):
                return .bytes(try string())
            default:
                throw DecodeError()
            }
        }

        mutating func string() throws -> [UInt8] {
            let length = try number(until: UInt8(ascii: ":"), allowNegative: false)
            guard length >= 0, length <= Int64(bytes.count - i) else { throw DecodeError() }
            let end = i + Int(length)
            let slice = Array(bytes[i..<end])
            i = end
            return slice
        }

        mutating func number(until end: UInt8, allowNegative: Bool) throws -> Int64 {
            var negative = false
            var digits = 0
            var n: Int64 = 0
            if allowNegative, i < bytes.count, bytes[i] == UInt8(ascii: "-") { negative = true; i += 1 }
            while i < bytes.count, bytes[i] != end {
                let c = bytes[i]
                guard c >= UInt8(ascii: "0"), c <= UInt8(ascii: "9"), digits < 18 else { throw DecodeError() }
                n = n * 10 + Int64(c - UInt8(ascii: "0"))
                digits += 1
                i += 1
            }
            guard i < bytes.count, digits > 0 else { throw DecodeError() }
            i += 1   // the end marker
            return negative ? -n : n
        }
    }
}

struct TorrentContents {
    struct File: Identifiable {
        let id: Int
        let path: String
        let size: Int64
        var ext: String { (path as NSString).pathExtension.lowercased() }
    }
    var name: String
    var files: [File]
    var totalSize: Int64
    var fileCount: Int
    var warnings: [String]

    static let maxFileSize = 10_000_000          // real .torrent files are well under this
    static let maxFilesListed = 20_000

    static let executable: Set<String> = ["exe", "scr", "bat", "cmd", "com", "pif", "msi", "vbs", "vbe", "js", "jse", "jar",
                                          "ps1", "wsf", "hta", "lnk", "dmg", "pkg", "app", "apk", "command", "sh", "reg", "cpl"]
    static let media: Set<String> = ["mp4", "mkv", "avi", "mov", "wmv", "m4v", "mpg", "mpeg", "webm", "flv", "ts", "m2ts",
                                     "mp3", "flac", "m4a", "aac", "wav", "ogg", "opus"]
    static let documents: Set<String> = ["pdf", "epub", "mobi", "doc", "docx", "txt", "jpg", "jpeg", "png", "srt"]
    static let archives: Set<String> = ["rar", "zip", "7z"]

    /// Reads a .torrent file, or nil if it isn't one.
    static func read(_ url: URL) -> TorrentContents? {
        guard let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize, size > 0, size <= maxFileSize,
              let data = try? Data(contentsOf: url), let root = try? Bencode.decode(data), let info = root["info"] else { return nil }
        let rawName = info["name.utf-8"]?.string ?? info["name"]?.string ?? url.deletingPathExtension().lastPathComponent
        let name = TorrentTools.clean(rawName, limit: 300)
        // Checked on the names as written, before they're cleaned up for showing.
        var hiddenDirection = TorrentTools.hasHiddenDirection(rawName)
        var files: [File] = []
        var total: Int64 = 0
        var count = 0
        var unsafePath = false

        func add(_ parts: [String], _ length: Int64) {
            count += 1
            total = total &+ max(0, length)
            if !hiddenDirection, parts.contains(where: TorrentTools.hasHiddenDirection) { hiddenDirection = true }
            if parts.contains(where: { $0 == ".." || $0 == "." || $0.contains("/") || $0.contains("\\") || $0.contains(":") }) {
                unsafePath = true
            }
            if files.count < maxFilesListed {
                files.append(File(id: files.count, path: parts.joined(separator: "/"), size: max(0, length)))
            }
        }

        if let list = info["files"]?.list {
            for entry in list {
                let parts = (entry["path.utf-8"]?.list ?? entry["path"]?.list ?? []).compactMap(\.string)
                add(parts.isEmpty ? ["(unnamed)"] : parts, entry["length"]?.int ?? 0)
            }
        } else if let length = info["length"]?.int {
            add([name], length)
        } else if let tree = info["file tree"]?.dict {
            // Version 2 torrents: folders as nested dictionaries; a file is the "" key.
            func walk(_ node: [String: Bencode.Value], _ path: [String], depth: Int) {
                guard depth < 32 else { return }
                for (key, value) in node {
                    if key.isEmpty, let length = value["length"]?.int { add(path, length) }
                    else if let child = value.dict { walk(child, path + [key], depth: depth + 1) }
                }
            }
            walk(tree, [], depth: 0)
        } else {
            return nil
        }
        files = files.map { File(id: $0.id, path: TorrentTools.clean($0.path, limit: 400), size: $0.size) }
        var contents = TorrentContents(name: name, files: files, totalSize: total, fileCount: count, warnings: [])
        contents.warnings = analyse(contents, hiddenDirection: hiddenDirection, unsafePath: unsafePath)
        return contents
    }

    /// Traps worth pointing out before you open a torrent.
    private static func analyse(_ t: TorrentContents, hiddenDirection: Bool, unsafePath: Bool) -> [String] {
        var warnings: [String] = []
        let mediaBytes = t.files.filter { media.contains($0.ext) }.reduce(Int64(0)) { $0 + $1.size }
        let videoName = t.name.range(of: #"(?i)\b(2160p|1080p|720p|480p|x264|x265|hevc|h\.?264|blu-?ray|web-?dl|webrip|hdrip|dvdrip|brrip|hdtv|s\d{2}e\d{2}|movie|film)\b"#,
                                     options: .regularExpression) != nil
        let looksLikeMedia = videoName || (t.totalSize > 0 && mediaBytes * 2 > t.totalSize)
        let programs = t.files.filter { executable.contains($0.ext) }

        let disguised = t.files.filter { file in
            let name = (file.path as NSString).lastPathComponent.lowercased()
            let parts = name.split(separator: ".")
            guard parts.count >= 3, let last = parts.last, executable.contains(String(last)) else { return false }
            let before = String(parts[parts.count - 2])
            return media.contains(before) || documents.contains(before) || archives.contains(before)
        }
        if let first = disguised.first {
            warnings.append("“\((first.path as NSString).lastPathComponent)” is a program pretending to be a \(disguisedKind(first.path)). Don’t open it.")
        }
        if looksLikeMedia, !programs.isEmpty, disguised.isEmpty {
            let names = programs.prefix(2).map { ($0.path as NSString).lastPathComponent }.joined(separator: ", ")
            warnings.append("This looks like a video or music download, but it contains a program (\(names)). Real films and music never need one.")
        }
        if t.files.contains(where: { $0.ext == "lnk" }) {
            warnings.append("It contains a Windows shortcut (.lnk), a common way to hide malware.")
        }
        if hiddenDirection {
            warnings.append("A file name uses hidden characters that make its ending look different from what it really is.")
        }
        if unsafePath {
            warnings.append("Some file paths try to escape their folder. A good torrent app refuses these, but be careful.")
        }
        let hasArchive = t.files.contains { archives.contains($0.ext) }
        let passwordNote = t.files.contains { ($0.path as NSString).lastPathComponent.lowercased().contains("password") }
        if looksLikeMedia, hasArchive, passwordNote {
            warnings.append("A video packed in an archive with a “password” file is a common scam: the password usually means visiting a site or running a program.")
        }
        if videoName, mediaBytes == 0, !t.files.isEmpty {
            warnings.append("It’s named like a video, but there’s no video file inside.")
        }
        return warnings
    }

    private static func disguisedKind(_ path: String) -> String {
        let parts = (path as NSString).lastPathComponent.lowercased().split(separator: ".")
        let before = parts.count >= 2 ? String(parts[parts.count - 2]) : ""
        if ["mp3", "flac", "m4a", "aac", "wav", "ogg", "opus"].contains(before) { return "music file" }
        if media.contains(before) { return "video" }
        if archives.contains(before) { return "archive" }
        return "document"
    }
}

// MARK: - The preview card

enum TorrentPreview {
    /// Reads a downloaded .torrent (away from the main thread) and shows what's inside.
    static func show(for file: URL, in window: NSWindow?) {
        DispatchQueue.global(qos: .userInitiated).async {
            let contents = TorrentContents.read(file)
            DispatchQueue.main.async { present(contents, file: file, window: window) }
        }
    }

    private static func present(_ contents: TorrentContents?, file: URL, window: NSWindow?) {
        guard let contents else {
            DialogHost.show(HushDialog(
                art: .symbol("doc.questionmark.fill"), theme: .caution, motion: .pulse,
                title: "That isn’t a readable torrent file",
                message: "“\(TorrentTools.clean(file.lastPathComponent, limit: 120))” couldn’t be read as a .torrent file, so Ufolio won’t open it. It’s in your Downloads.",
                choices: [.init(title: "Show in Finder"), .init(title: "OK", role: .primary)],
                completion: { choice, _ in if choice == 0 { NSWorkspace.shared.activateFileViewerSelecting([file]) } }), in: window)
            return
        }
        let app = TorrentTools.chosenApp
        let risky = !contents.warnings.isEmpty
        let size = ByteCountFormatter.string(fromByteCount: contents.totalSize, countStyle: .file)
        var choices: [HushDialog.Choice] = [.init(title: "Close", role: .cancel), .init(title: "Show in Finder")]
        if let app { choices.append(.init(title: risky ? "Open Anyway" : "Open in \(TorrentTools.appName(app))", role: risky ? .destructive : .primary)) }
        DialogHost.show(HushDialog(
            art: app.map { .image(NSWorkspace.shared.icon(forFile: $0.path)) } ?? .symbol("arrow.down.doc.fill"),
            badge: risky ? "exclamationmark.triangle.fill" : "checkmark.shield.fill",
            theme: risky ? .danger : .hush, motion: risky ? .pulse : .orbit,
            title: contents.name,
            message: "\(contents.fileCount) file\(contents.fileCount == 1 ? "" : "s") · \(size)" + (app == nil ? "\nNo torrent app is installed to open it." : ""),
            detail: AnyView(TorrentFileList(contents: contents)),
            width: 420,
            choices: choices,
            completion: { choice, _ in
                if choice == 1 { NSWorkspace.shared.activateFileViewerSelecting([file]) }
                if choice == 2 { TorrentTools.handOff(file) }
            }), in: window)
    }
}

private struct TorrentFileList: View {
    let contents: TorrentContents

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(contents.warnings.enumerated()), id: \.offset) { _, warning in
                HStack(alignment: .top, spacing: 7) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
                    Text(warning).font(.system(size: 11.5)).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.red.opacity(0.10)))
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 3) {
                    ForEach(contents.files.prefix(500)) { file in
                        let program = TorrentContents.executable.contains(file.ext)
                        HStack(spacing: 7) {
                            Image(systemName: program ? "exclamationmark.octagon.fill" : symbol(file.ext))
                                .foregroundStyle(program ? Color.red : .secondary)
                                .frame(width: 14)
                            Text(file.path).font(.system(size: 11.5)).lineLimit(1).truncationMode(.middle)
                            Spacer(minLength: 6)
                            Text(ByteCountFormatter.string(fromByteCount: file.size, countStyle: .file))
                                .font(.system(size: 11)).foregroundStyle(.secondary).monospacedDigit()
                        }
                    }
                    if contents.fileCount > 500 {
                        Text("and \(contents.fileCount - 500) more").font(.system(size: 11)).foregroundStyle(.tertiary)
                    }
                }
                .padding(8)
            }
            .frame(maxHeight: 190)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.05)))
        }
        .padding(.top, 6)
    }

    private func symbol(_ ext: String) -> String {
        if ["mp4", "mkv", "avi", "mov", "wmv", "m4v", "mpg", "mpeg", "webm", "flv", "ts", "m2ts"].contains(ext) { return "film" }
        if ["mp3", "flac", "m4a", "aac", "wav", "ogg", "opus"].contains(ext) { return "music.note" }
        if ["srt", "sub", "ass", "txt", "nfo"].contains(ext) { return "doc.text" }
        if ["jpg", "jpeg", "png", "gif"].contains(ext) { return "photo" }
        if TorrentContents.archives.contains(ext) { return "doc.zipper" }
        if ext == "iso" { return "opticaldiscdrive" }
        return "doc"
    }
}

// MARK: - Torrent site mode and fake-download warnings

enum TorrentSiteGuard {
    /// Run after a page loads (in Ufolio's own script world, out of the page's reach): finds the
    /// real magnet and .torrent links, marks fake "Download" buttons and disguised programs, and
    /// takes the click away from invisible overlays. Returns whether the page looks like a torrent
    /// index, and how many traps it marked.
    static let script = """
    const MARK = 'data-ufolio-torrent';
    const here = location.hostname.replace(/^www\\./, '');
    const site = h => h.split('.').slice(-2).join('.');
    const magnets = document.querySelectorAll('a[href^="magnet:"]').length;
    const torrentLinks = document.querySelectorAll('a[href$=".torrent"], a[href*=".torrent?"]').length;
    const isIndex = magnets + torrentLinks >= 3;
    if (!isIndex && !known) return { isIndex: false, marked: 0 };
    let marked = 0;
    const badge = (el, text, colour) => {
      if (el.getAttribute(MARK)) return;
      el.setAttribute(MARK, '1');
      el.style.setProperty('outline', '2px dashed ' + colour, 'important');
      el.style.setProperty('outline-offset', '2px', 'important');
      const tag = document.createElement('span');
      tag.textContent = text;
      tag.setAttribute(MARK, 'badge');
      tag.style.cssText = 'all:initial;display:inline-block;margin:2px 4px;padding:1px 6px;border-radius:8px;font:600 11px -apple-system,sans-serif;color:#fff;background:' + colour + ';vertical-align:middle;pointer-events:none';
      el.insertAdjacentElement('afterend', tag);
    };
    const scan = () => {
      for (const a of document.querySelectorAll('a[href^="magnet:"], a[href$=".torrent"], a[href*=".torrent?"]')) {
        if (a.getAttribute(MARK)) continue;
        a.setAttribute(MARK, 'real');
        a.style.setProperty('outline', '2px solid #2fb36b', 'important');
        a.style.setProperty('outline-offset', '2px', 'important');
      }
      const words = /(download|play now|watch now|stream now|fast download|direct download|high speed|start download|anonymous download|download now|free download|instant download)/i;
      for (const el of document.querySelectorAll('a[href], button, [role=button], input[type=button], input[type=submit]')) {
        if (el.getAttribute(MARK)) continue;
        const href = el.getAttribute('href') || '';
        if (/^magnet:/i.test(href) || /\\.torrent(\\?|$)/i.test(href)) continue;
        const text = (el.innerText || el.value || el.getAttribute('title') || el.getAttribute('aria-label') || '').trim().slice(0, 80);
        const img = el.querySelector('img');
        const imgText = img ? ((img.alt || '') + ' ' + (img.src || '')) : '';
        let target = null;
        try { target = href ? new URL(href, location.href) : null; } catch (e) {}
        const offsite = target && /^https?:$/.test(target.protocol) && site(target.hostname) !== site(here);
        if (target && /\\.(exe|scr|bat|cmd|msi|dmg|pkg|apk|jar|vbs|lnk)(\\?|$)/i.test(target.pathname) && /(mp4|mkv|avi|mov|1080p|720p|movie|episode|season|video)/i.test(text + ' ' + target.pathname)) {
          badge(el, 'Program, not a video', '#d93636'); marked++; continue;
        }
        if (offsite && (words.test(text) || words.test(imgText))) {
          badge(el, 'Ad, not your download', '#d93636'); marked++; continue;
        }
      }
      // Invisible layers over the page that turn any click into a pop-under.
      const vw = innerWidth, vh = innerHeight;
      for (const el of document.querySelectorAll('body *')) {
        if (el.getAttribute(MARK)) continue;
        const s = getComputedStyle(el);
        if (s.position !== 'fixed' && s.position !== 'absolute') continue;
        const r = el.getBoundingClientRect();
        if (r.width < vw * 0.6 || r.height < vh * 0.6) continue;
        const clear = parseFloat(s.opacity) < 0.1 || (s.backgroundColor === 'rgba(0, 0, 0, 0)' && !el.innerText.trim() && !el.querySelector('img,video,canvas,iframe'));
        if (clear && (parseInt(s.zIndex) || 0) >= 100) {
          el.setAttribute(MARK, 'overlay');
          el.style.setProperty('pointer-events', 'none', 'important');
          marked++;
        }
      }
    };
    scan();
    let scans = 0, timer = null;
    new MutationObserver(() => {
      if (timer || scans > 30) return;
      timer = setTimeout(() => { timer = null; scans++; scan(); }, 1000);
    }).observe(document.documentElement, { childList: true, subtree: true });
    return { isIndex, marked };
    """
}

/// A slim bar on torrent sites saying what torrent site mode stopped.
struct TorrentGuardBar: View {
    @ObservedObject var tab: BrowserTab
    @State private var dismissedFor: Int?

    var body: some View {
        let stopped = tab.torrentPopupsBlocked, marked = tab.torrentTrapsMarked
        if (stopped > 0 || marked > 0), dismissedFor != stopped + marked {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.shield.fill").foregroundStyle(Color.accentColor)
                Text(summary(stopped: stopped, marked: marked)).font(.system(size: 12)).lineLimit(1)
                Spacer()
                Button { dismissedFor = stopped + marked } label: {
                    Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
            }
            .padding(.horizontal, 12)
            .frame(height: 28)
        }
    }

    private func summary(stopped: Int, marked: Int) -> String {
        var parts: [String] = []
        if stopped > 0 { parts.append("stopped \(stopped) pop-up\(stopped == 1 ? "" : "s") and redirect\(stopped == 1 ? "" : "s")") }
        if marked > 0 { parts.append("marked \(marked) fake download button\(marked == 1 ? "" : "s") and trap\(marked == 1 ? "" : "s")") }
        return "Torrent site mode " + parts.joined(separator: ", ") + "." + (marked > 0 ? " Green outlines are the real links." : "")
    }
}
