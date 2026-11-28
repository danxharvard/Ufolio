import AppKit
import SwiftUI
import WebKit
import Security
import LocalAuthentication
import Contacts

// MARK: - Unlocking

/// Touch ID or the Mac's password. Filling a saved login or card follows Settings › Passwords
/// (by default it never asks: save a password once and it simply fills). Seeing or copying your
/// passwords in Settings always asks.
enum UserAuth {
    enum Purpose { case fill, reveal }
    enum FillLock: String, CaseIterable, Identifiable {
        case never, session, quarterHour, always
        var id: String { rawValue }
        var label: String {
            switch self {
            case .never: return "Never ask"
            case .session: return "Once each time Ufolio opens"
            case .quarterHour: return "After 15 minutes away"
            case .always: return "Every time"
            }
        }
        static var current: FillLock { FillLock(rawValue: Prefs.string(Prefs.passwordFillLock)) ?? .never }
    }

    private static var lastSuccess: Date?
    private static var unlockedThisSession = false
    private static var observing = false

    static func confirm(_ reason: String, for purpose: Purpose = .reveal, completion: @escaping (Bool) -> Void) {
        startObserving()
        if purpose == .fill {
            switch FillLock.current {
            case .never: completion(true); return
            case .session: if unlockedThisSession { completion(true); return }
            case .quarterHour:
                // Fifteen minutes since you last used it, not since you last unlocked: it used to
                // ask again every 15 minutes even while you were signing in to things.
                if let last = lastSuccess, Date().timeIntervalSince(last) < 15 * 60 { lastSuccess = Date(); completion(true); return }
            case .always: if let last = lastSuccess, Date().timeIntervalSince(last) < 60 { completion(true); return }
            }
        } else if let last = lastSuccess, Date().timeIntervalSince(last) < 60 {
            completion(true)
            return
        }
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            completion(false)
            return
        }
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { ok, _ in
            DispatchQueue.main.async {
                if ok { lastSuccess = Date(); unlockedThisSession = true }
                completion(ok)
            }
        }
    }

    static func lock() { lastSuccess = nil }

    /// "Once each time Ufolio opens" also locks again when your Mac sleeps or its screen locks.
    private static func startObserving() {
        guard !observing else { return }
        observing = true
        let reset: (Notification) -> Void = { _ in unlockedThisSession = false; lastSuccess = nil }
        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main, using: reset)
        ws.addObserver(forName: NSWorkspace.sessionDidResignActiveNotification, object: nil, queue: .main, using: reset)
        DistributedNotificationCenter.default().addObserver(forName: NSNotification.Name("com.apple.screenIsLocked"),
                                                            object: nil, queue: .main, using: reset)
    }
}

// MARK: - Passwords (Ufolio's own vault)

struct SavedLogin: Identifiable, Hashable {
    let host: String
    let account: String
    var modified: Date?
    var id: String { host + "\u{0}" + account }
}

/// Saved passwords, in Ufolio's own encrypted vault (see Vault).
enum PasswordVault {
    /// Saved logins: the vault's, plus any older ones still in the keychain (which move into the
    /// vault the first time they're used, so macOS asks once per password, and only when needed).
    static func logins(for host: String? = nil) -> [SavedLogin] {
        let own = Vault.read().logins
            .filter { host == nil || $0.host == host }
            .map { SavedLogin(host: $0.host, account: $0.account, modified: $0.modified) }
        return (own + Vault.keychainLogins(for: host)).sorted { ($0.host, $0.account) < ($1.host, $1.account) }
    }

    static func password(for login: SavedLogin) -> String? {
        if let saved = Vault.read().logins.first(where: { $0.host == login.host && $0.account == login.account }) {
            return saved.password
        }
        return Vault.takeFromKeychain(host: login.host, account: login.account)
    }

    @discardableResult
    static func save(host: String, account: String, password: String) -> Bool {
        Vault.update { contents in
            if let i = contents.logins.firstIndex(where: { $0.host == host && $0.account == account }) {
                contents.logins[i].password = password
                contents.logins[i].modified = Date()
            } else {
                contents.logins.append(Vault.Login(host: host, account: account, password: password, modified: Date()))
            }
        }
    }

    static func delete(_ login: SavedLogin) {
        Vault.update { $0.logins.removeAll { $0.host == login.host && $0.account == login.account } }
        // An older copy in the keychain stays there, but isn't shown again.
        Vault.hideKeychainLogin(host: login.host, account: login.account)
    }

    // Sites the user said never to save passwords for.
    static var neverSave: [String] {
        get { UserDefaults.standard.stringArray(forKey: "neverSavePasswordHosts") ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: "neverSavePasswordHosts") }
    }
}

// MARK: - Strong passwords

/// Makes Safari-style strong passwords: three groups of six, like "kipzot-4hamwe-Rybfud".
/// 20 characters from a secure random source, with a digit and a capital for picky sites.
enum PasswordGenerator {
    static func make() -> String {
        let letters = Array("abcdefghijkmnopqrstuvwxyz")   // no "l", easily confused with "1"
        let digits = Array("23456789")
        var groups: [[Character]] = (0..<3).map { _ in (0..<6).map { _ in letters[random(letters.count)] } }
        let g = random(3)
        groups[g][random(6)] = digits[random(digits.count)]
        var other = random(3)
        if other == g { other = (g + 1) % 3 }
        let i = random(6)
        groups[other][i] = Character(groups[other][i].uppercased())
        return groups.map { String($0) }.joined(separator: "-")
    }

    /// A uniformly random number below `bound` from the system's secure random generator.
    private static func random(_ bound: Int) -> Int {
        var value: UInt32 = 0
        let limit = UInt32.max - UInt32.max % UInt32(bound)
        repeat {
            _ = withUnsafeMutableBytes(of: &value) { SecRandomCopyBytes(kSecRandomDefault, 4, $0.baseAddress!) }
        } while value >= limit
        return Int(value % UInt32(bound))
    }
}

// MARK: - Credit cards (Ufolio's own vault)

struct SavedCard: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var number: String
    var expMonth: Int
    var expYear: Int

    var digits: String { number.filter(\.isNumber) }
    var last4: String { String(digits.suffix(4)) }

    var brand: String {
        let d = digits
        if d.hasPrefix("4") { return "Visa" }
        if d.hasPrefix("34") || d.hasPrefix("37") { return "American Express" }
        if let two = Int(d.prefix(2)), (51...55).contains(two) { return "Mastercard" }
        if let four = Int(d.prefix(4)), (2221...2720).contains(four) { return "Mastercard" }
        if d.hasPrefix("6011") || d.hasPrefix("65") { return "Discover" }
        return "Card"
    }

    var label: String { "\(brand) •••• \(last4)" }
    var expiry: String { String(format: "%02d/%02d", expMonth, expYear % 100) }
}

enum CardVault {
    struct Summary: Identifiable, Hashable {
        let id: UUID
        let label: String
    }

    /// The vault's cards, plus older ones still in the keychain (moved in when first used).
    static func list() -> [Summary] {
        let own = Vault.read().cards.map { Summary(id: $0.id, label: "\($0.label) · \($0.expiry)") }
        let ownIDs = Set(own.map(\.id))
        return (own + Vault.keychainCards().filter { !ownIDs.contains($0.id) }).sorted { $0.label < $1.label }
    }

    static func card(_ id: UUID) -> SavedCard? {
        Vault.read().cards.first { $0.id == id } ?? Vault.takeCardFromKeychain(id)
    }

    @discardableResult
    static func save(_ card: SavedCard) -> Bool {
        Vault.update { contents in
            if let i = contents.cards.firstIndex(where: { $0.id == card.id }) { contents.cards[i] = card } else { contents.cards.append(card) }
        }
    }

    static func delete(_ id: UUID) {
        Vault.update { $0.cards.removeAll { $0.id == id } }
        Vault.hideKeychainLogin(host: "card", account: id.uuidString)
    }
}

// MARK: - Your contact card

enum MyCard {
    /// Whether Ufolio may read your contact card. Asking macOS takes a round trip to its privacy
    /// service (about 0.2 s), so the answer is kept: worked out in the background at launch and
    /// whenever you come back to Ufolio (you may have changed it in System Settings). Opening
    /// Settings › Passwords, or clicking into a name box on a page, used to wait for it each time.
    static var status: CNAuthorizationStatus {
        lock.lock(); let known = cached; lock.unlock()
        if let known { return known }
        let fresh = CNContactStore.authorizationStatus(for: .contacts)
        lock.lock(); cached = fresh; lock.unlock()
        return fresh
    }
    private static let lock = NSLock()
    private static var cached: CNAuthorizationStatus?

    /// Looks the answer up again, off the main thread.
    static func refreshStatus() {
        _ = activeWatch
        DispatchQueue.global(qos: .utility).async {
            let fresh = CNContactStore.authorizationStatus(for: .contacts)
            lock.lock(); cached = fresh; lock.unlock()
        }
    }
    private static let activeWatch: NSObjectProtocol = NotificationCenter.default.addObserver(
        forName: NSApplication.didBecomeActiveNotification, object: nil, queue: nil) { _ in refreshStatus() }

    static func requestAccess(_ completion: @escaping (Bool) -> Void) {
        CNContactStore().requestAccess(for: .contacts) { ok, _ in
            let fresh = CNContactStore.authorizationStatus(for: .contacts)
            lock.lock(); cached = fresh; lock.unlock()
            DispatchQueue.main.async { completion(ok) }
        }
    }

    private static let keys: [CNKeyDescriptor] = [
        CNContactGivenNameKey, CNContactFamilyNameKey, CNContactMiddleNameKey, CNContactOrganizationNameKey,
        CNContactEmailAddressesKey, CNContactPhoneNumbersKey, CNContactPostalAddressesKey,
    ].map { $0 as CNKeyDescriptor }

    /// Your "Me" card from Contacts, as form-field values keyed by HTML autocomplete names.
    static func fields() -> [String: String]? {
        guard status == .authorized,
              let me = try? CNContactStore().unifiedMeContactWithKeys(toFetch: keys) else { return nil }
        var f: [String: String] = [:]
        f["given-name"] = me.givenName
        f["family-name"] = me.familyName
        f["additional-name"] = me.middleName
        f["name"] = [me.givenName, me.familyName].filter { !$0.isEmpty }.joined(separator: " ")
        f["organization"] = me.organizationName
        f["email"] = me.emailAddresses.first?.value as String?
        f["tel"] = me.phoneNumbers.first?.value.stringValue
        f["tel-national"] = f["tel"]
        if let address = me.postalAddresses.first?.value {
            let lines = address.street.components(separatedBy: .newlines)
            f["street-address"] = address.street.replacingOccurrences(of: "\n", with: ", ")
            f["address-line1"] = lines.first
            f["address-line2"] = lines.dropFirst().joined(separator: ", ")
            f["address-level2"] = address.city
            f["address-level1"] = address.state
            f["postal-code"] = address.postalCode
            f["country-name"] = address.country
            f["country"] = address.isoCountryCode.uppercased()
        }
        return f.filter { !$0.value.isEmpty }
    }

    static var displayName: String? {
        guard let f = fields() else { return nil }
        return f["name"] ?? f["email"]
    }
}

// MARK: - The page side

/// Routes AutoFill messages from pages to the right tab, and owns the page script.
/// The script runs in WebKit's isolated "client" world: pages can't see it,
/// call it, or fake its messages.
final class AutofillCenter: NSObject, WKScriptMessageHandler {
    static let shared = AutofillCenter()
    static let handlerName = "hushAutofill"

    private let tabs = NSMapTable<WKWebView, BrowserTab>.weakToWeakObjects()
    private let registered = NSHashTable<WKUserContentController>.weakObjects()
    private var popover: NSPopover?
    private var lastSaveOffer: (key: String, date: Date)?
    /// Strong passwords Ufolio filled in this session (kept in memory only).
    private var generatedPasswords: Set<String> = []

    static var isEnabled: Bool {
        Prefs.bool(Prefs.autofillPasswords) || Prefs.bool(Prefs.autofillCards) || Prefs.bool(Prefs.autofillContact)
    }

    func register(_ tab: BrowserTab) {
        tabs.setObject(tab, forKey: tab.webView)
        let controller = tab.webView.configuration.userContentController
        if !registered.contains(controller) {
            registered.add(controller)
            controller.add(self, contentWorld: .defaultClient, name: Self.handlerName)
        }
    }

    /// UFOLIO_AUTOFILL_TRACE: notes each step of offering to save (for testing only).
    static let trace = ProcessInfo.processInfo.environment["UFOLIO_AUTOFILL_TRACE"] != nil
    static func note(_ text: String) { if trace { FileHandle.standardError.write(("autofill: " + text + "\n").data(using: .utf8)!) } }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        Self.note("message \((message.body as? [String: Any])?["type"] ?? "?") main=\(message.frameInfo.isMainFrame) tabKnown=\(message.webView.flatMap { tabs.object(forKey: $0) } != nil)")
        guard message.frameInfo.isMainFrame,
              let webView = message.webView,
              let tab = tabs.object(forKey: webView),
              let body = message.body as? [String: Any],
              let type = body["type"] as? String else { return }

        // Trust the origin WebKit reports, never anything the page says about itself.
        let origin = message.frameInfo.securityOrigin
        let host = ContentBlocker.normalize(origin.host)
        let secure = origin.protocol == "https" || ["localhost", "127.0.0.1"].contains(origin.host)

        switch type {
        case "focus":
            guard let kind = body["kind"] as? String,
                  let rect = body["rect"] as? [Double], rect.count == 4 else { return }
            offer(kind: kind, rect: rect, host: host, secure: secure, tab: tab)
        case "signInCheck":
            autoFillCheck(host: host, secure: secure, tab: tab)
        case "signInForm":
            autoFill(step: body["step"] as? String ?? "password", host: host, secure: secure, tab: tab)
        case "submit":
            // Stealth windows promise not to remember what you type, so they don't offer to save,
            // except a strong password Ufolio made for you there (or it would be lost for good).
            guard secure, Prefs.bool(Prefs.autofillPasswords),
                  let password = body["password"] as? String, !password.isEmpty, password.count <= 512,
                  !tab.isPrivate || generatedPasswords.contains(password) else { return }
            let username = String((body["username"] as? String ?? "").prefix(256))
            Self.note("submit for \(host), offering to save")
            offerToSave(username: username, password: password, host: host, tab: tab)
        default:
            break
        }
    }

    // MARK: Filling in by itself

    /// A sign-in form appeared: your saved login for this site goes straight in, typed and
    /// waiting (Settings › Passwords; the most recently used one if you have several). Only on
    /// secure pages, from Ufolio's own vault (never a keychain prompt), and not when you've chosen
    /// to be asked before filling: then clicking into the box offers it, as before.
    /// The page has (or now shows) a form: if there's a saved login for this site, it's told to
    /// watch for the sign-in box, which then fills in by itself.
    private func autoFillCheck(host: String, secure: Bool, tab: BrowserTab) {
        guard secure, Prefs.bool(Prefs.autofillPasswords), UserAuth.FillLock.current == .never, !host.isEmpty else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak tab] in
            guard Vault.read().logins.contains(where: { $0.host == host }) else { return }
            DispatchQueue.main.async {
                guard let tab, let current = tab.webView.url?.host, ContentBlocker.normalize(current) == host else { return }
                tab.webView.evaluateJavaScript("window.__hushWatchSignIn && window.__hushWatchSignIn()", in: nil, in: .defaultClient) { _ in }
            }
        }
    }

    private func autoFill(step: String, host: String, secure: Bool, tab: BrowserTab) {
        guard secure, Prefs.bool(Prefs.autofillPasswords), UserAuth.FillLock.current == .never,
              !host.isEmpty else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self, weak tab] in
            let login = Vault.read().logins.filter { $0.host == host }.max { $0.modified < $1.modified }
            guard let login else { return }
            DispatchQueue.main.async {
                guard let self, let tab, let current = tab.webView.url?.host, ContentBlocker.normalize(current) == host else { return }
                var data: [String: String] = ["auto": "1", "username": login.account]
                if step == "password" { data["password"] = login.password }
                self.send(kind: "login", data: data, host: host, tab: tab)
            }
        }
    }

    // MARK: Offering to fill

    private enum Option: Identifiable {
        case generate(String)
        case login(SavedLogin)
        case card(CardVault.Summary)
        case contact(String?)

        var id: String {
            switch self {
            case .generate: return "generate"
            case .login(let l): return "l" + l.id
            case .card(let c): return "c" + c.id.uuidString
            case .contact: return "me"
            }
        }
    }

    private func offer(kind: String, rect: [Double], host: String, secure: Bool, tab: BrowserTab) {
        var options: [Option] = []
        // Saved logins and cards come from the keychain, which can be slow: looked up in the
        // background so clicking into a form never stalls the window.
        func fromKeychain(_ lookup: @escaping () -> [Option]) {
            DispatchQueue.global(qos: .userInitiated).async { [weak self, weak tab] in
                let found = lookup()
                DispatchQueue.main.async {
                    guard let self, let tab, !found.isEmpty else { return }
                    self.show(found, kind: kind, at: rect, host: host, in: tab)
                }
            }
        }
        switch kind {
        case "login":
            guard secure, Prefs.bool(Prefs.autofillPasswords) else { return }
            fromKeychain { PasswordVault.logins(for: host).map(Option.login) }
            return
        case "newpassword":
            guard secure, Prefs.bool(Prefs.autofillPasswords) else { return }
            options = [.generate(PasswordGenerator.make())]
        case "card":
            guard secure, Prefs.bool(Prefs.autofillCards) else { return }
            fromKeychain { CardVault.list().map(Option.card) }
            return
        case "contact":
            // Your card is read in the background too (a Contacts look-up stalled the page
            // you were typing in).
            guard Prefs.bool(Prefs.autofillContact) else { return }
            fromKeychain {
                let status = MyCard.status
                guard status != .denied, status != .restricted else { return [] }
                return [.contact(status == .authorized ? MyCard.displayName : nil)]
            }
            return
        default:
            return
        }
        guard !options.isEmpty else { return }
        show(options, kind: kind, at: rect, host: host, in: tab)
    }

    private func show(_ options: [Option], kind: String, at rect: [Double], host: String, in tab: BrowserTab) {
        popover?.close()
        let webView = tab.webView
        // Only for a page that's on screen: a pop-up attached to a page that isn't in a window
        // (a background tab, or one you've switched away from) makes macOS raise an exception.
        // Keychain results can arrive after the tab navigates; don't show another site's options.
        guard webView.window != nil, !tab.isAsleep,
              webView.url?.host.map(ContentBlocker.normalize) == host else { return }
        let scale = webView.pageZoom * webView.magnification
        let h = rect[3] * scale
        let top = rect[1] * scale
        var anchor = NSRect(x: rect[0] * scale, y: top, width: max(rect[2] * scale, 1), height: max(h, 1))
        if !webView.isFlipped { anchor.origin.y = webView.bounds.height - top - h }
        guard webView.bounds.intersects(anchor) else { return }

        let pop = NSPopover()
        pop.behavior = .transient
        pop.animates = true
        pop.contentViewController = NSHostingController(rootView: AutofillMenu(
            rows: options.map { option in
                switch option {
                case .generate(let password):
                    return AutofillMenu.Row(id: option.id, symbol: "wand.and.stars", title: "Use Strong Password",
                                            subtitle: password)
                case .login(let login):
                    return AutofillMenu.Row(id: option.id, symbol: "key.fill", title: login.account.isEmpty ? "(no username)" : login.account,
                                            subtitle: "Password for \(login.host)")
                case .card(let card):
                    return AutofillMenu.Row(id: option.id, symbol: "creditcard.fill", title: card.label, subtitle: "Fill card details")
                case .contact(let name):
                    return AutofillMenu.Row(id: option.id, symbol: "person.crop.circle.fill",
                                            title: name.map { "Fill with \($0)" } ?? "Fill with My Card…",
                                            subtitle: "From your contact card")
                }
            },
            onPick: { [weak self, weak tab] id in
                self?.popover?.close()
                guard let tab, let option = options.first(where: { $0.id == id }) else { return }
                self?.fill(option, host: host, tab: tab)
            },
            onManage: { [weak self] in
                self?.popover?.close()
                SettingsOpener.open(tab: .passwords)
            }))
        popover = pop
        pop.show(relativeTo: anchor, of: webView, preferredEdge: webView.isFlipped ? .maxY : .minY)
    }

    private func fill(_ option: Option, host: String, tab: BrowserTab) {
        switch option {
        case .generate(let password):
            // Filled into every new-password box; Hush offers to save it when the form is sent.
            generatedPasswords.insert(password)
            if generatedPasswords.count > 20 { generatedPasswords.removeFirst() }
            send(kind: "newpassword", data: ["password": password], host: host, tab: tab)
        case .login(let login):
            UserAuth.confirm("fill your password for \(host)", for: .fill) { [weak self] ok in
                guard ok else { return }
                DispatchQueue.global(qos: .userInitiated).async {
                    guard let password = PasswordVault.password(for: login) else { return }
                    DispatchQueue.main.async {
                        self?.send(kind: "login", data: ["username": login.account, "password": password], host: host, tab: tab)
                    }
                }
            }
        case .card(let summary):
            UserAuth.confirm("fill your card details", for: .fill) { [weak self] ok in
                guard ok, let card = CardVault.card(summary.id) else { return }
                let month2 = String(format: "%02d", card.expMonth)
                let monthName = DateFormatter().monthSymbols[max(0, min(11, card.expMonth - 1))]
                self?.send(kind: "card", data: [
                    "number": card.digits, "name": card.name, "exp": card.expiry,
                    "month2": month2, "month": String(card.expMonth), "monthName": monthName,
                    "year": String(card.expYear), "year2": String(format: "%02d", card.expYear % 100),
                ], host: host, tab: tab)
            }
        case .contact:
            let go = { [weak self] in
                DispatchQueue.global(qos: .userInitiated).async {
                    guard let fields = MyCard.fields() else { return }
                    DispatchQueue.main.async { self?.send(kind: "contact", data: fields, host: host, tab: tab) }
                }
            }
            if MyCard.status == .authorized { go() } else { MyCard.requestAccess { if $0 { go() } } }
        }
    }

    /// Hands values to the page script. They travel as arguments, never pasted into code,
    /// and only if the tab is still on the same site.
    private func send(kind: String, data: [String: String], host: String, tab: BrowserTab) {
        guard let url = tab.webView.url, let current = url.host, ContentBlocker.normalize(current) == host else { return }
        // Passwords and cards only ever go to a secure page (it may have changed while Touch ID was up).
        if kind != "contact" {
            let local = current == "localhost" || current == "127.0.0.1"
            guard url.scheme == "https" || local else { return }
        }
        tab.webView.callAsyncJavaScript("return window.__hushFill(kind, data);",
                                        arguments: ["kind": kind, "data": data],
                                        in: nil, in: .defaultClient) { _ in }
    }

    // MARK: Offering to save

    private func offerToSave(username: String, password: String, host: String, tab: BrowserTab) {
        guard !PasswordVault.neverSave.contains(host) else { return }
        let key = host + "\u{0}" + username + "\u{0}" + password
        if let last = lastSaveOffer, last.key == key, Date().timeIntervalSince(last.date) < 60 { return }
        lastSaveOffer = (key, Date())

        // The keychain is read in the background: it can be slow (or ask permission), and
        // sending a sign-in form used to freeze the window while it did.
        DispatchQueue.global(qos: .userInitiated).async { [weak self, weak tab] in
            // Only Ufolio's own vault is checked: comparing with an older keychain copy would make
            // macOS ask for your Mac password in the middle of signing in.
            let saved = Vault.read().logins.first { $0.host == host && $0.account == username }
            let existing = saved.map { SavedLogin(host: $0.host, account: $0.account, modified: $0.modified) }
            let unchanged = saved?.password == password
            DispatchQueue.main.async {
                guard let self, let tab, !unchanged else { return }
                self.showSaveOffer(existing: existing, username: username, password: password, host: host, tab: tab)
            }
        }
    }

    private func showSaveOffer(existing: SavedLogin?, username: String, password: String, host: String, tab: BrowserTab) {
        Self.note("show offer: window=\(tab.webView.window != nil) busy=\(DialogHost.isBusy(tab.webView.window))")
        guard let window = tab.webView.window, !DialogHost.isBusy(window) else { return }

        let who = username.isEmpty ? "" : " for “\(username)”"
        var choices: [HushDialog.Choice] = [.init(title: existing == nil ? "Save Password" : "Update Password", role: .primary),
                                            .init(title: "Not Now", role: .cancel)]
        if existing == nil { choices.append(.init(title: "Never for This Website")) }
        DialogHost.show(HushDialog(
            art: .site(tab.url), badge: "key.fill", theme: .save, motion: .rise,
            title: existing == nil ? "Save this password?" : "Update your saved password?",
            message: existing == nil
                ? "Ufolio can keep the password\(who) on \(host) encrypted in Ufolio and fill it in for you next time."
                : "The password\(who) on \(host) has changed. Update your saved password?",
            note: ("lock.fill", "Encrypted on your Mac, filled in only on this site"),
            choices: choices,
            completion: { choice, _ in
                switch choice {
                case 0: DispatchQueue.global(qos: .userInitiated).async { PasswordVault.save(host: host, account: username, password: password) }
                case 2: PasswordVault.neverSave = PasswordVault.neverSave + [host]
                default: break
                }
            }), in: window)
    }

    // MARK: Page script

    static let script = WKUserScript(source: #"""
    (function () {
      if (window.__hushAutofillReady) return;
      window.__hushAutofillReady = true;
      function post(m) { try { webkit.messageHandlers.hushAutofill.postMessage(m); } catch (e) {} }
      function visible(el) { var r = el.getBoundingClientRect(); return r.width > 0 && r.height > 0; }
      // For filling in by itself (no click from you): only a field you could really see and use.
      // A page, or a tracker running on it, can add a tiny, see-through or off-screen login box
      // and read what lands in it; such boxes are never filled without you.
      // A floating label laid over the field is fine; a box covering the whole field isn't.
      function smaller(a, b) { return a.width * a.height < b.width * b.height * 0.8; }
      function onScreen(el) {
        var r = el.getBoundingClientRect();
        if (r.width < 24 || r.height < 12) return false;
        if (r.right <= 0 || r.bottom <= 0 || r.left >= document.documentElement.scrollWidth || r.top + window.scrollY >= document.documentElement.scrollHeight) return false;
        if (typeof el.checkVisibility === 'function' &&
            !el.checkVisibility({ opacityProperty: true, visibilityProperty: true, contentVisibilityAuto: true })) return false;
        var cs = getComputedStyle(el);
        if (parseFloat(cs.opacity) < 0.1 || cs.visibility !== 'visible' || cs.clipPath && cs.clipPath !== 'none') return false;
        // Something on top of it (a box hidden under the page): the middle of it must be the field.
        var x = r.left + r.width / 2, y = r.top + r.height / 2;
        if (x >= 0 && y >= 0 && x < window.innerWidth && y < window.innerHeight) {
          var top = document.elementFromPoint(x, y);
          if (top && top !== el && !el.contains(top) && top.control !== el && !(top.closest && top.closest('label')) &&
              !(top.parentElement && top.parentElement.contains(el) && smaller(top.getBoundingClientRect(), r))) return false;
        }
        return true;
      }
      function words(el) { return [el.name, el.id, el.placeholder, el.getAttribute('aria-label'), el.getAttribute('autocomplete')].join(' ').toLowerCase(); }
      function ac(el) { return (el.getAttribute('autocomplete') || '').toLowerCase().replace(/^section-\S+\s+/, '').replace(/^(shipping|billing)\s+/, '').trim(); }
      var CONTACT = {'name':1,'given-name':1,'additional-name':1,'family-name':1,'email':1,'tel':1,'tel-national':1,'organization':1,
                     'street-address':1,'address-line1':1,'address-line2':1,'address-level1':1,'address-level2':1,'postal-code':1,'country':1,'country-name':1};
      function isTextInput(el) { return el instanceof HTMLInputElement && /^(text|email|tel|search|url)?$/.test((el.getAttribute('type') || '').toLowerCase()); }
      function scopeOf(el) { return el.form || document; }

      function kindOf(el) {
        if (el instanceof HTMLSelectElement) { var s = ac(el); return s.indexOf('cc-') === 0 ? 'card' : (CONTACT[s] ? 'contact' : null); }
        if (!(el instanceof HTMLInputElement)) return null;
        var t = (el.type || 'text').toLowerCase(), a = ac(el), w = words(el);
        if (t === 'password') {
          // Sign-up and change-password forms: offer a strong new password instead.
          var pwCount = scopeOf(el).querySelectorAll('input[type=password]').length;
          if (a === 'new-password' || pwCount >= 2 || /new|create|confirm|repeat|sign.?up|register/.test(w)) return 'newpassword';
          return 'login';
        }
        if (a.indexOf('cc-') === 0 || /card.?num|cc.?num|cardnumber|ccnumber|credit.?card/.test(w)) return 'card';
        if (!isTextInput(el)) return null;
        if ((a === 'username' || a === 'email' || t === 'email' || /user|login|e.?mail|account/.test(w)) &&
            scopeOf(el).querySelector('input[type=password]')) return 'login';
        if (CONTACT[a]) return 'contact';
        if (t === 'email' || t === 'tel' || /first.?name|last.?name|full.?name|surname|phone|mobile|address|post.?code|zip|city|town/.test(w)) return 'contact';
        return null;
      }

      // A sign-in form on the page: Ufolio fills your saved login in straight away (once per
      // field, only visible empty ones), so it's typed in and waiting for you. Forms that appear
      // a moment later (web apps, two-step sign-ins) are noticed for the first fifteen seconds.
      var asked = [];
      function lookForSignIn() {
        var pw = Array.prototype.filter.call(document.querySelectorAll('input[type=password]'), function (el) {
          return onScreen(el) && !el.value && kindOf(el) === 'login';
        })[0];
        var user = null;
        if (!pw) {
          // The first step of a two-step sign-in: just a username or email box.
          user = Array.prototype.filter.call(document.querySelectorAll('input'), function (el) {
            return isTextInput(el) && onScreen(el) && !el.value && (/\b(username|webauthn)\b/.test(ac(el)) || (el.type === 'email' && /user|login|sign|account|identifier/.test(words(el))));
          })[0];
        }
        var target = pw || user;
        if (!target || asked.indexOf(target) !== -1) return;
        asked.push(target);
        post({ type: 'signInForm', step: pw ? 'password' : 'username' });
      }
      var started = 0;
      // Only for a site you have a saved login for: Ufolio says so (see autoFillCheck). Busy
      // pages elsewhere used to be watched for their first fifteen seconds for nothing.
      window.__hushWatchSignIn = function () {
        if (started) return;
        started = Date.now();
        watchForSignIn();
      };
      function watchForSignIn() {
        lookForSignIn();
        var timer = null;
        var observer = new MutationObserver(function () {
          if (Date.now() - started > 15000) { observer.disconnect(); return; }
          if (!timer) timer = setTimeout(function () { timer = null; lookForSignIn(); }, 300);
        });
        observer.observe(document.documentElement, { childList: true, subtree: true });
        setTimeout(function () { observer.disconnect(); }, 15000);
      }
      // Asks once whether this site has a saved login (cheap), and only then starts watching.
      if (document.querySelector('input[type=password], input[type=email], input[autocomplete~=username]') || document.forms.length) {
        post({ type: 'signInCheck' });
      } else {
        // No form yet: a sign-in box can still appear (web apps); ask the first time one does,
        // with a light check a few times early on rather than watching every change.
        var tries = 0;
        var poll = setInterval(function () {
          tries++;
          if (document.querySelector('input[type=password], input[type=email], input[autocomplete~=username]')) { clearInterval(poll); post({ type: 'signInCheck' }); }
          else if (tries >= 6) clearInterval(poll);
        }, 1000);
      }

      document.addEventListener('focusin', function (e) {
        var k = kindOf(e.target);
        if (!k) return;
        var r = e.target.getBoundingClientRect();
        post({ type: 'focus', kind: k, rect: [r.left, r.top, r.width, r.height] });
      }, true);

      // Offer to save a password when a login form is sent.
      var lastSent = '';
      function capture(scope) {
        var pws = Array.prototype.filter.call((scope || document).querySelectorAll('input[type=password]'), function (p) { return p.value; });
        if (!pws.length) return;
        var pw = pws[pws.length - 1];
        var form = pw.form || document;
        var users = Array.prototype.filter.call(form.querySelectorAll('input'), function (i) {
          return i !== pw && isTextInput(i) && i.value && (i.compareDocumentPosition(pw) & Node.DOCUMENT_POSITION_FOLLOWING);
        });
        var hinted = form.querySelector('input[autocomplete~="username"], input[name="identifier"], input[name="username"], input[type="email"]');
        var user = users.length ? users[users.length - 1].value : (hinted && hinted !== pw ? hinted.value || '' : '');
        var key = user + '\u0000' + pw.value;
        if (key === lastSent) return;
        lastSent = key;
        post({ type: 'submit', username: user.slice(0, 256), password: pw.value.slice(0, 512) });
      }
      document.addEventListener('submit', function (e) { capture(e.target); }, true);
      document.addEventListener('click', function (e) {
        var b = e.target && e.target.closest && e.target.closest('button, input[type=submit], [role=button]');
        if (b) { var f = b.form || b.closest('form') || document; setTimeout(function () { capture(f); }, 0); }
      }, true);
      document.addEventListener('keydown', function (e) {
        if (e.key === 'Enter' && e.target && e.target.type === 'password') capture(e.target.form || document);
      }, true);

      // Sign-ins that never send a form (web apps that check the password in the background,
      // and the password step of two-step sign-ins): remember what's typed in a password box,
      // and offer once the page moves on, the box goes away, or the page closes.
      var typed = { user: '', pw: '', href: location.href };
      function userNear(pw) {
        var scope = pw.form || document;
        // Two-step sign-ins keep the username in a hidden field for password managers.
        var hinted = scope.querySelector('input[autocomplete~="username"], input[name="identifier"], input[name="username"], input[type="email"]');
        if (hinted && hinted !== pw && hinted.value) return hinted.value;
        var users = Array.prototype.filter.call(scope.querySelectorAll('input'), function (i) {
          return i !== pw && isTextInput(i) && i.value && (i.compareDocumentPosition(pw) & Node.DOCUMENT_POSITION_FOLLOWING);
        });
        return users.length ? users[users.length - 1].value : '';
      }
      var watch = null;
      function remember(e) {
        var t = e.target;
        if (!(t instanceof HTMLInputElement) || t.type !== 'password' || !t.value) return;
        typed.pw = t.value; typed.user = userNear(t); typed.href = location.href;
        // Only watched from the moment a password is typed until it's offered (no timer otherwise).
        if (!watch) watch = setInterval(check, 700);
      }
      document.addEventListener('input', remember, true);
      document.addEventListener('change', remember, true);
      function flush() {
        if (!typed.pw) return;
        var key = typed.user + '\u0000' + typed.pw;
        if (key !== lastSent) {
          lastSent = key;
          post({ type: 'submit', username: typed.user.slice(0, 256), password: typed.pw.slice(0, 512) });
        }
        typed.pw = '';
        if (watch) { clearInterval(watch); watch = null; }
      }
      window.addEventListener('pagehide', flush, true);
      function check() {
        if (!typed.pw) { clearInterval(watch); watch = null; return; }
        var boxes = Array.prototype.filter.call(document.querySelectorAll('input[type=password]'), visible);
        if (location.href !== typed.href || !boxes.length) flush();
      }

      // Filling, in a way that frameworks like React notice.
      var setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set;
      function put(el, values) {
        values = [].concat(values).filter(function (v) { return v != null && v !== ''; });
        if (!el || !values.length) return false;
        if (el instanceof HTMLSelectElement) {
          for (var j = 0; j < values.length; j++) {
            var want = String(values[j]).toLowerCase();
            for (var i = 0; i < el.options.length; i++) {
              var o = el.options[i];
              if (o.value.toLowerCase() === want || o.text.trim().toLowerCase() === want) {
                el.value = o.value;
                el.dispatchEvent(new Event('change', { bubbles: true }));
                return true;
              }
            }
          }
          return false;
        }
        el.focus();
        setter.call(el, String(values[0]));
        el.dispatchEvent(new Event('input', { bubbles: true }));
        el.dispatchEvent(new Event('change', { bubbles: true }));
        return true;
      }
      function fields(scope) {
        return Array.prototype.filter.call(scope.querySelectorAll('input, select'), function (el) {
          return visible(el) && !el.disabled && !el.readOnly;
        });
      }
      function contactKey(el) {
        var a = ac(el), w = words(el);
        if (CONTACT[a]) return a;
        if (/first.?name|given/.test(w)) return 'given-name';
        if (/last.?name|surname|family/.test(w)) return 'family-name';
        if (/full.?name|(^|\s)name(\s|$)/.test(w)) return 'name';
        if (el.type === 'email' || /e.?mail/.test(w)) return 'email';
        if (el.type === 'tel' || /phone|mobile|(^|\s)tel/.test(w)) return 'tel';
        if (/company|organi[sz]ation/.test(w)) return 'organization';
        if (/address.?(line)?.?2|apartment|suite|flat/.test(w)) return 'address-line2';
        if (/address|street/.test(w)) return 'address-line1';
        if (/city|town/.test(w)) return 'address-level2';
        if (/state|county|province|region/.test(w)) return 'address-level1';
        if (/zip|post.?code|postal/.test(w)) return 'postal-code';
        if (/country/.test(w)) return 'country-name';
        return null;
      }

      window.__hushFill = function (kind, data) {
        var active = document.activeElement;
        var list = fields((active && active.form) || document);
        if (kind === 'newpassword') {
          var boxes = list.filter(function (el) { return el.type === 'password' && ac(el) !== 'current-password' && !el.value; });
          boxes.forEach(function (el) { put(el, data.password); });
          return boxes.length > 0;
        }
        if (kind === 'login') {
          var pw = list.filter(function (el) { return el.type === 'password'; })[0];
          var user = list.filter(function (el) { return el.type !== 'password' && kindOf(el) === 'login'; })[0];
          if (data.auto) {
            // Filled by itself as the page loads: only boxes you can see that are still empty.
            pw = Array.prototype.filter.call(document.querySelectorAll('input[type=password]'), function (el) {
              return onScreen(el) && !el.disabled && !el.readOnly && !el.value && kindOf(el) === 'login';
            })[0] || null;
            user = Array.prototype.filter.call(document.querySelectorAll('input'), function (el) {
              return isTextInput(el) && onScreen(el) && !el.disabled && !el.readOnly && !el.value &&
                (pw ? (kindOf(el) === 'login' && (!pw.form || el.form === pw.form)) : (/\b(username|webauthn)\b/.test(ac(el)) || el.type === 'email'));
            })[0] || null;
            if (pw && data.password) put(pw, data.password);
            if (user && data.username) put(user, data.username);
            return !!(pw || user);
          }
          if (user) put(user, data.username);
          if (pw) put(pw, data.password);
          return !!(user || pw);
        }
        var filled = 0;
        list.forEach(function (el) {
          var values = null;
          if (kind === 'card') {
            var a = ac(el), w = words(el);
            if (a === 'cc-number' || /card.?num|cc.?num|cardnumber|ccnumber/.test(w)) values = data.number;
            else if (a === 'cc-name' || /name.?on.?card|card.?holder|cc.?name/.test(w)) values = data.name;
            else if (a === 'cc-exp' || /exp(iry|iration)?.?date|mm.?\/?.?yy/.test(w)) values = data.exp;
            else if (a === 'cc-exp-month' || /exp.*month|cc.?month/.test(w)) values = [data.month2, data.month, data.monthName];
            else if (a === 'cc-exp-year' || /exp.*year|cc.?year/.test(w)) values = el.maxLength === 2 ? [data.year2] : [data.year, data.year2];
          } else {
            var key = contactKey(el);
            if (key) values = key === 'country-name' ? [data['country-name'], data['country']] : data[key];
          }
          if (values && (el instanceof HTMLSelectElement || !el.value) && put(el, values)) filled++;
        });
        return filled > 0;
      };
    })();
    """#, injectionTime: .atDocumentEnd, forMainFrameOnly: true, in: .defaultClient)
}

/// The little menu that appears under a login, card or address field.
private struct AutofillMenu: View {
    struct Row: Identifiable {
        let id: String
        let symbol: String
        let title: String
        let subtitle: String
    }

    let rows: [Row]
    let onPick: (String) -> Void
    let onManage: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(rows) { row in
                AutofillRow(row: row) { onPick(row.id) }
            }
            Divider().padding(.vertical, 4)
            Button(action: onManage) {
                Text("Passwords & AutoFill Settings…")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(6)
        .frame(width: 280)
    }
}

private struct AutofillRow: View {
    let row: AutofillMenu.Row
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: row.symbol)
                    .font(.system(size: 14))
                    .foregroundStyle(hovering ? Color.white : Color.accentColor)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text(row.title).font(.system(size: 12.5, weight: .medium)).lineLimit(1)
                    Text(row.subtitle).font(.system(size: 11)).lineLimit(1)
                        .foregroundStyle(hovering ? Color.white.opacity(0.85) : Color.secondary)
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(hovering ? Color.white : Color.primary)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(hovering ? Color.accentColor : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
