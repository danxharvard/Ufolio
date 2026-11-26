import AppKit
import SQLite3
import UniformTypeIdentifiers

// MARK: - Bookmarks from other browsers

extension BrowserImporter {
    /// Brings over bookmarks (as Favourites). Returns how many new ones were added.
    static func importBookmarks(from source: Source) throws -> Int {
        var found: [(title: String, url: URL)] = []
        switch source.kind {
        case .chromium:
            // Chrome, Brave, Edge, Arc and Vivaldi keep bookmarks as JSON beside their history.
            let file = source.database.deletingLastPathComponent().appendingPathComponent("Bookmarks")
            guard let data = try? Data(contentsOf: file),
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let roots = json["roots"] as? [String: Any] else { return 0 }
            func walk(_ node: Any?) {
                guard let node = node as? [String: Any], found.count < 2000 else { return }
                if node["type"] as? String == "url", let link = (node["url"] as? String).flatMap(URL.init(string:)) {
                    found.append(((node["name"] as? String) ?? "", link))
                }
                (node["children"] as? [Any])?.forEach(walk)
            }
            for key in ["bookmark_bar", "other", "synced"] { walk(roots[key]) }
        case .firefox:
            found = try readSQLite(copyOf: source.database,
                                   sql: "SELECT p.url, b.title FROM moz_bookmarks b JOIN moz_places p ON b.fk = p.id WHERE b.type = 1 LIMIT 2000")
        case .safari:
            // Needs Full Disk Access, like Safari's history.
            let file = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Safari/Bookmarks.plist")
            guard let data = try? Data(contentsOf: file) else { throw ImportError.needsFullDiskAccess }
            guard let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { return 0 }
            func walk(_ node: [String: Any]) {
                guard found.count < 2000 else { return }
                if node["Title"] as? String == "com.apple.ReadingList" { return }   // Reading List isn't bookmarks
                if node["WebBookmarkType"] as? String == "WebBookmarkTypeLeaf",
                   let link = (node["URLString"] as? String).flatMap(URL.init(string:)) {
                    let title = (node["URIDictionary"] as? [String: Any])?["title"] as? String ?? ""
                    found.append((title, link))
                }
                (node["Children"] as? [[String: Any]])?.forEach(walk)
            }
            walk(plist)
        }
        let web = found.filter { ["http", "https"].contains($0.url.scheme?.lowercased() ?? "") }
        if Thread.isMainThread { return BookmarkStore.shared.add(imported: web) }   // a sync hop would deadlock
        return DispatchQueue.main.sync { BookmarkStore.shared.add(imported: web) }
    }

    private static func readSQLite(copyOf database: URL, sql: String) throws -> [(title: String, url: URL)] {
        let copy = FileManager.default.temporaryDirectory.appendingPathComponent("hush-import-\(UUID().uuidString).db")
        do { try FileManager.default.copyItem(at: database, to: copy) } catch { throw ImportError.unreadable }
        for suffix in ["-wal", "-shm"] where FileManager.default.fileExists(atPath: database.path + suffix) {
            try? FileManager.default.copyItem(atPath: database.path + suffix, toPath: copy.path + suffix)
        }
        defer { for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: copy.path + suffix) } }
        var db: OpaquePointer?
        guard sqlite3_open_v2(copy.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { sqlite3_close(db); throw ImportError.unreadable }
        defer { sqlite3_close(db) }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { throw ImportError.unreadable }
        defer { sqlite3_finalize(statement) }
        var rows: [(title: String, url: URL)] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let raw = sqlite3_column_text(statement, 0), let url = URL(string: String(cString: raw)) else { continue }
            rows.append((sqlite3_column_text(statement, 1).map { String(cString: $0) } ?? "", url))
        }
        return rows
    }
}

// MARK: - Passwords from an exported file

/// Imports passwords from the CSV file that Chrome, Safari, Firefox, Edge, Brave and most
/// password managers can export. They go into Ufolio's own encrypted vault.
enum PasswordImporter {
    struct Result {
        var added = 0
        var updated = 0
        var skipped = 0
    }

    static func importCSV(_ url: URL) throws -> Result {
        // Most exports are UTF-8, but a file saved from Excel can be UTF-16 or Windows text: those
        // used to fail with a confusing "text encoding" error.
        let data = try Data(contentsOf: url)
        guard var text = String(data: data, encoding: .utf8)
                ?? ((data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF])) ? String(data: data, encoding: .utf16) : nil)
                ?? String(data: data, encoding: .windowsCP1252) else {
            throw NSError(domain: "Ufolio", code: 2, userInfo: [NSLocalizedDescriptionKey: "That file couldn’t be read as text."])
        }
        // Some password managers (and anything saved from Excel) start the file with an invisible
        // byte-order mark, which hid the first column's name ("url") so the file was rejected.
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
        let rows = parseCSV(text)
        guard let header = rows.first?.map({ $0.lowercased().trimmingCharacters(in: .whitespaces) }) else { return Result() }
        func column(_ names: [String]) -> Int? { header.firstIndex { names.contains($0) } }
        guard let urlColumn = column(["url", "website", "login_uri", "web site"]),
              let passwordColumn = column(["password", "login_password"]) else {
            throw NSError(domain: "Ufolio", code: 1, userInfo: [NSLocalizedDescriptionKey: "That file doesn’t look like a password export (it needs url and password columns)."])
        }
        let userColumn = column(["username", "user name", "login", "login_username", "email"])
        var result = Result()
        var incoming: [(host: String, account: String, password: String)] = []
        for row in rows.dropFirst() {
            guard row.count > max(urlColumn, passwordColumn) else { result.skipped += 1; continue }
            let password = row[passwordColumn]
            let address = row[urlColumn].trimmingCharacters(in: .whitespaces)
            let link = URL(string: address.contains("://") ? address : "https://" + address)
            guard !password.isEmpty, password.count <= 512, let host = link?.host, !host.isEmpty,
                  ["http", "https"].contains(link?.scheme?.lowercased() ?? "") else { result.skipped += 1; continue }
            let user = String((userColumn.flatMap { row.count > $0 ? row[$0] : nil } ?? "").prefix(256))
            incoming.append((ContentBlocker.normalize(host), user, password))
        }
        // All in one go, compared with Ufolio's own vault only. It used to check each row against
        // the keychain too (reading an older keychain password asks for your Mac password, once
        // per row) and rewrote the encrypted vault file after every single row.
        var counts = Result(added: 0, updated: 0, skipped: result.skipped)
        let saved = Vault.update { contents in
            for item in incoming {
                if let i = contents.logins.firstIndex(where: { $0.host == item.host && $0.account == item.account }) {
                    if contents.logins[i].password == item.password { counts.skipped += 1; continue }
                    contents.logins[i].password = item.password
                    contents.logins[i].modified = Date()
                    counts.updated += 1
                } else {
                    contents.logins.append(Vault.Login(host: item.host, account: item.account, password: item.password, modified: Date()))
                    counts.added += 1
                }
            }
        }
        guard saved else {
            throw NSError(domain: "Ufolio", code: 3, userInfo: [NSLocalizedDescriptionKey: "The passwords couldn’t be saved. Please try again."])
        }
        result = counts
        return result
    }

    /// A small CSV reader: quoted fields, escaped quotes ("") and line breaks inside quotes.
    static func parseCSV(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var quoted = false
        // Windows line endings, and old Mac ones (a lone return, from Excel's "CSV (Macintosh)").
        var chars = Array(text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n"))
        if chars.first == "\u{FEFF}" { chars.removeFirst() }   // byte-order mark
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if quoted {
                if c == "\"" {
                    if i + 1 < chars.count, chars[i + 1] == "\"" { field.append("\""); i += 1 } else { quoted = false }
                } else {
                    field.append(c)
                }
            } else {
                switch c {
                case "\"": quoted = true
                case ",": row.append(field); field = ""
                case "\n": row.append(field); rows.append(row); row = []; field = ""
                default: field.append(c)
                }
            }
            i += 1
        }
        if !field.isEmpty || !row.isEmpty { row.append(field); rows.append(row) }
        return rows.filter { !($0.count == 1 && $0[0].isEmpty) }
    }

    /// Asks for the file, imports it, then offers to move it to the Trash (it holds your
    /// passwords as plain text).
    static func run(completion: @escaping (String) -> Void) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.commaSeparatedText, .plainText]
        panel.message = "Choose the passwords file you exported from your other browser."
        panel.prompt = "Import"
        guard panel.runModal() == .OK, let file = panel.url else { return }
        UserAuth.confirm("import passwords into Ufolio") { ok in
            guard ok else { return }
            DispatchQueue.global(qos: .userInitiated).async {
                let message: String
                var imported = false
                do {
                    let r = try importCSV(file)
                    message = "Imported \(r.added) new and updated \(r.updated) passwords" + (r.skipped > 0 ? " (\(r.skipped) skipped)." : ".")
                    imported = r.added + r.updated > 0
                } catch {
                    message = error.localizedDescription
                }
                DispatchQueue.main.async {
                    completion(message)
                    // Only once the passwords are safely in Ufolio: after a failed import it used to
                    // offer to bin the file anyway, which could be your only copy of them.
                    guard imported else { return }
                    DialogHost.settings.present(HushDialog(
                        art: .symbol("doc.text.fill"), badge: "trash.fill", theme: .caution, motion: .drift,
                        title: "Move the exported file to the Trash?",
                        message: "“\(file.lastPathComponent)” contains your passwords as plain text. It’s safest not to keep it now they’re saved in Ufolio.",
                        choices: [.init(title: "Keep It", role: .cancel), .init(title: "Move to Trash", role: .destructive)],
                        completion: { choice, _ in
                            if choice == 1 { NSWorkspace.shared.recycle([file]) }
                        }))
                }
            }
        }
    }
}
