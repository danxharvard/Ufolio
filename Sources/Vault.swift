import AppKit
import CryptoKit
import Security

/// Ufolio's own store for saved passwords and cards, instead of the macOS keychain (which asks
/// for your Mac password again after every Ufolio update, because Ufolio isn't signed with a
/// paid Apple Developer ID).
///
/// Everything is in one file, encrypted with AES-256-GCM. The key is a separate file that only
/// your Mac user account can read. Like Chrome's and Firefox's own storage, this protects your
/// passwords if someone gets hold of your disk (and FileVault protects both files while your Mac
/// is locked or off), though not from a program already running as you.
enum Vault {
    struct Login: Codable, Hashable {
        var host: String
        var account: String
        var password: String
        var modified: Date
    }
    struct Contents: Codable {
        var logins: [Login] = []
        var cards: [SavedCard] = []
        /// Passwords still in the keychain that you deleted in Ufolio ("host\0account"): not shown again.
        var hiddenKeychain: [String]? = nil
    }

    private static let lock = NSLock()
    private static var cache: Contents?
    private static var keyFile: URL { AppPaths.support.appendingPathComponent("Vault.key") }
    private static var dataFile: URL { AppPaths.support.appendingPathComponent("Passwords.vault") }

    /// The vault's key: made once (32 random bytes), readable only by you.
    private static func key() -> SymmetricKey? {
        if let data = try? Data(contentsOf: keyFile), data.count == 32 { return SymmetricKey(data: data) }
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, 32, &bytes) == errSecSuccess else { return nil }
        let data = Data(bytes)
        try? FileManager.default.createDirectory(at: AppPaths.support, withIntermediateDirectories: true)
        guard FileManager.default.createFile(atPath: keyFile.path, contents: data, attributes: [.posixPermissions: 0o600]) else { return nil }
        return SymmetricKey(data: data)
    }

    /// What's saved (read from disk the first time, then kept in memory).
    static func read() -> Contents {
        lock.lock(); defer { lock.unlock() }
        return loadLocked()
    }

    private static func loadLocked() -> Contents {
        if let cache { return cache }
        var contents = Contents()
        if let sealed = try? Data(contentsOf: dataFile), let key = key(),
           let box = try? AES.GCM.SealedBox(combined: sealed),
           let plain = try? AES.GCM.open(box, using: key),
           let decoded = try? JSONDecoder().decode(Contents.self, from: plain) {
            contents = decoded
        } else if FileManager.default.fileExists(atPath: dataFile.path) {
            // Unreadable (a damaged file, or a missing key): kept aside, never overwritten.
            let aside = dataFile.deletingPathExtension().appendingPathExtension("damaged-\(Int(Date().timeIntervalSince1970))-\(UUID().uuidString.prefix(6)).vault")
            try? FileManager.default.moveItem(at: dataFile, to: aside)
            NSLog("Ufolio: the password vault couldn't be read; it was kept at \(aside.path)")
        }
        cache = contents
        return contents
    }

    /// Changes what's saved and writes it straight away (encrypted, readable only by you).
    @discardableResult
    static func update(_ change: (inout Contents) -> Void) -> Bool {
        lock.lock(); defer { lock.unlock() }
        var contents = loadLocked()
        change(&contents)
        guard let key = key(), let plain = try? JSONEncoder().encode(contents),
              let sealed = try? AES.GCM.seal(plain, using: key).combined else { return false }
        let temp = dataFile.appendingPathExtension("tmp")
        guard FileManager.default.createFile(atPath: temp.path, contents: sealed, attributes: [.posixPermissions: 0o600]) else { return false }
        do {
            if FileManager.default.fileExists(atPath: dataFile.path) {
                _ = try FileManager.default.replaceItemAt(dataFile, withItemAt: temp)
            } else {
                try FileManager.default.moveItem(at: temp, to: dataFile)
            }
        } catch {
            try? FileManager.default.removeItem(at: temp)
            return false
        }
        cache = contents
        return true
    }

    // MARK: Passwords still in the keychain, moved one at a time as they're used

    /// Ufolio's passwords still in the keychain (names only, which macOS never asks about),
    /// leaving out ones already in the vault or deleted in Ufolio.
    static func keychainLogins(for host: String? = nil) -> [SavedLogin] {
        var query: [String: Any] = [kSecClass as String: kSecClassInternetPassword, kSecAttrCreator as String: creator,
                                    kSecMatchLimit as String: kSecMatchLimitAll, kSecReturnAttributes as String: true]
        if let host { query[kSecAttrServer as String] = host }
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let items = result as? [[String: Any]] else { return [] }
        let contents = read()
        let hidden = Set(contents.hiddenKeychain ?? [])
        return items.compactMap { item -> SavedLogin? in
            guard let server = item[kSecAttrServer as String] as? String, let account = item[kSecAttrAccount as String] as? String,
                  !hidden.contains(server + "\u{0}" + account),
                  !contents.logins.contains(where: { $0.host == server && $0.account == account }) else { return nil }
            return SavedLogin(host: server, account: account, modified: item[kSecAttrModificationDate as String] as? Date)
        }
    }

    /// Reads one password from the keychain (macOS asks this once) and moves it into the vault.
    static func takeFromKeychain(host: String, account: String) -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassInternetPassword, kSecAttrCreator as String: creator,
                                    kSecAttrServer as String: host, kSecAttrAccount as String: account,
                                    kSecMatchLimit as String: kSecMatchLimitOne, kSecReturnData as String: true]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data,
              let password = String(data: data, encoding: .utf8) else { return nil }
        update { contents in
            if !contents.logins.contains(where: { $0.host == host && $0.account == account }) {
                contents.logins.append(Login(host: host, account: account, password: password, modified: Date()))
            }
        }
        return password
    }

    /// Cards still in the keychain (their labels only, which macOS never asks about).
    static func keychainCards() -> [CardVault.Summary] {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: cardService,
                                    kSecMatchLimit as String: kSecMatchLimitAll, kSecReturnAttributes as String: true]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let items = result as? [[String: Any]] else { return [] }
        let hidden = Set(read().hiddenKeychain ?? [])
        return items.compactMap { item in
            guard let account = item[kSecAttrAccount as String] as? String, let id = UUID(uuidString: account),
                  !hidden.contains("card\u{0}" + account) else { return nil }
            return CardVault.Summary(id: id, label: item[kSecAttrLabel as String] as? String ?? "Card")
        }
    }

    /// Reads one card from the keychain (macOS asks this once) and moves it into the vault.
    static func takeCardFromKeychain(_ id: UUID) -> SavedCard? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: cardService,
                                    kSecAttrAccount as String: id.uuidString, kSecMatchLimit as String: kSecMatchLimitOne,
                                    kSecReturnData as String: true]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data,
              let card = try? JSONDecoder().decode(SavedCard.self, from: data) else { return nil }
        update { contents in if !contents.cards.contains(where: { $0.id == card.id }) { contents.cards.append(card) } }
        return card
    }

    /// Stops showing a keychain password that was deleted in Ufolio.
    static func hideKeychainLogin(host: String, account: String) {
        update { contents in
            var hidden = contents.hiddenKeychain ?? []
            let key = host + "\u{0}" + account
            if !hidden.contains(key) { hidden.append(key) }
            contents.hiddenKeychain = hidden
        }
    }

    // MARK: Moving passwords out of the keychain

    private static let movedKey = "vault.movedFromKeychain"
    private static let creator = NSNumber(value: 0x4855_5348) // 'HUSH', as the keychain items were tagged
    private static let cardService = "Hush Browser Card"

    /// A little after launch: if the keychain still has Ufolio's passwords or cards, offers once
    /// to move them in. (Only their names are looked at first, which macOS never asks about.)
    static func offerToMoveIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: movedKey) else { return }
        // "Later" means a week from now, not every launch (the button in Settings is always there).
        if let later = UserDefaults.standard.object(forKey: "vault.moveLater") as? Date, later > Date() { return }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 8) {
            let count = keychainItemCount()
            DispatchQueue.main.async {
                guard count > 0 else { UserDefaults.standard.set(true, forKey: movedKey); return }
                DialogHost.show(HushDialog(
                    art: .symbol("key.fill"), badge: "arrow.down.circle.fill", theme: .save, motion: .rise,
                    title: "Move your passwords into Ufolio?",
                    message: "Ufolio now keeps saved passwords and cards in its own encrypted vault, so you won’t be asked for your Mac password every time you sign in to something. macOS will ask one last time to let Ufolio copy them across. The copies in your keychain stay as they are.",
                    choices: [.init(title: "Later", role: .cancel), .init(title: "Move Now", role: .primary)],
                    completion: { choice, _ in
                        guard choice == 1 else {
                            UserDefaults.standard.set(Date().addingTimeInterval(7 * 86_400), forKey: "vault.moveLater")
                            return
                        }
                        DispatchQueue.global(qos: .userInitiated).async {
                            let moved = moveFromKeychain()
                            DispatchQueue.main.async {
                                DialogHost.show(HushDialog(
                                    art: .symbol("checkmark.shield.fill"), theme: .save, motion: .sparkle,
                                    title: moved > 0 ? "Moved \(moved) item\(moved == 1 ? "" : "s") into Ufolio" : "Nothing was moved",
                                    message: moved > 0 ? "Your passwords and cards now fill without asking for your Mac password each time."
                                                       : "macOS didn’t let Ufolio read them. You can try again from Settings › Passwords.",
                                    choices: [.init(title: "OK", role: .primary)]), in: nil)
                            }
                        }
                    }), in: nil)
            }
        }
    }

    private static func keychainItemCount() -> Int {
        var total = 0
        for q: [String: Any] in [
            [kSecClass as String: kSecClassInternetPassword, kSecAttrCreator as String: creator],
            [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: cardService],
        ] {
            var query = q
            query[kSecMatchLimit as String] = kSecMatchLimitAll
            query[kSecReturnAttributes as String] = true
            var result: CFTypeRef?
            if SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess {
                total += (result as? [[String: Any]])?.count ?? 0
            }
        }
        return total
    }

    /// Copies every Ufolio password and card from the keychain in. Returns how many came across.
    @discardableResult
    static func moveFromKeychain() -> Int {
        var logins: [Login] = []
        var cards: [SavedCard] = []
        // The list first (names only), then each item's secret one at a time: macOS doesn't
        // reliably hand over every secret in a single request.
        func list(_ q: [String: Any]) -> [[String: Any]] {
            var query = q
            query[kSecMatchLimit as String] = kSecMatchLimitAll
            query[kSecReturnAttributes as String] = true
            var result: CFTypeRef?
            guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return [] }
            return result as? [[String: Any]] ?? []
        }
        func secret(_ q: [String: Any]) -> Data? {
            var query = q
            query[kSecMatchLimit as String] = kSecMatchLimitOne
            query[kSecReturnData as String] = true
            var result: CFTypeRef?
            guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
            return result as? Data
        }
        let passwordQuery: [String: Any] = [kSecClass as String: kSecClassInternetPassword, kSecAttrCreator as String: creator]
        for item in list(passwordQuery) {
            guard let host = item[kSecAttrServer as String] as? String, let account = item[kSecAttrAccount as String] as? String else { continue }
            var one = passwordQuery
            one[kSecAttrServer as String] = host
            one[kSecAttrAccount as String] = account
            guard let data = secret(one), let password = String(data: data, encoding: .utf8) else { continue }
            logins.append(Login(host: host, account: account, password: password,
                                modified: item[kSecAttrModificationDate as String] as? Date ?? Date()))
        }
        let cardQuery: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: cardService]
        for item in list(cardQuery) {
            guard let account = item[kSecAttrAccount as String] as? String else { continue }
            var one = cardQuery
            one[kSecAttrAccount as String] = account
            if let data = secret(one), let card = try? JSONDecoder().decode(SavedCard.self, from: data) { cards.append(card) }
        }
        guard !logins.isEmpty || !cards.isEmpty else { return 0 }
        update { contents in
            for login in logins where !contents.logins.contains(where: { $0.host == login.host && $0.account == login.account }) {
                contents.logins.append(login)
            }
            for card in cards where !contents.cards.contains(where: { $0.id == card.id }) {
                contents.cards.append(card)
            }
        }
        UserDefaults.standard.set(true, forKey: movedKey)
        return logins.count + cards.count
    }
}
