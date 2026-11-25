import AppKit
import SwiftUI
import WebKit
import Security
import LocalAuthentication
import Contacts

// MARK: - Unlocking

/// Touch ID or the Mac's password before anything secret is shown or filled.
/// One unlock covers a minute, like Safari.
enum UserAuth {
    private static var lastSuccess: Date?

    static func confirm(_ reason: String, completion: @escaping (Bool) -> Void) {
        if let last = lastSuccess, Date().timeIntervalSince(last) < 60 { completion(true); return }
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            completion(false)
            return
        }
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { ok, _ in
            DispatchQueue.main.async {
                if ok { lastSuccess = Date() }
                completion(ok)
            }
        }
    }

    static func lock() { lastSuccess = nil }
}

// MARK: - Passwords (macOS Keychain)

struct SavedLogin: Identifiable, Hashable {
    let host: String
    let account: String
    var modified: Date?
    var id: String { host + "\u{0}" + account }
}

/// Passwords live in the macOS Keychain, tagged as Hush's own items.
enum PasswordVault {
    private static let creator = NSNumber(value: 0x4855_5348) // 'HUSH'

    private static func query(host: String? = nil, account: String? = nil) -> [String: Any] {
        var q: [String: Any] = [kSecClass as String: kSecClassInternetPassword,
                                kSecAttrCreator as String: creator]
        if let host { q[kSecAttrServer as String] = host }
        if let account { q[kSecAttrAccount as String] = account }
        return q
    }

    static func logins(for host: String? = nil) -> [SavedLogin] {
        var q = query(host: host)
        q[kSecMatchLimit as String] = kSecMatchLimitAll
        q[kSecReturnAttributes as String] = true
        var result: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess,
              let items = result as? [[String: Any]] else { return [] }
        return items.compactMap { item -> SavedLogin? in
            guard let server = item[kSecAttrServer as String] as? String,
                  let account = item[kSecAttrAccount as String] as? String else { return nil }
            return SavedLogin(host: server, account: account, modified: item[kSecAttrModificationDate as String] as? Date)
        }
        .sorted { ($0.host, $0.account) < ($1.host, $1.account) }
    }

    static func password(for login: SavedLogin) -> String? {
        var q = query(host: login.host, account: login.account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func save(host: String, account: String, password: String) -> Bool {
        let data = Data(password.utf8)
        let q = query(host: host, account: account)
        let status = SecItemUpdate(q as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var add = q
            add[kSecValueData as String] = data
            add[kSecAttrProtocol as String] = kSecAttrProtocolHTTPS
            add[kSecAttrLabel as String] = "\(host) (Ufolio Browser)"
            add[kSecAttrDescription as String] = "Ufolio Browser password"
            return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
        }
        return status == errSecSuccess
    }

    static func delete(_ login: SavedLogin) {
        SecItemDelete(query(host: login.host, account: login.account) as CFDictionary)
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

// MARK: - Credit cards (macOS Keychain)

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
    private static let service = "Hush Browser Card"

    struct Summary: Identifiable, Hashable {
        let id: UUID
        let label: String
    }

    static func list() -> [Summary] {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrService as String: service,
                                kSecMatchLimit as String: kSecMatchLimitAll,
                                kSecReturnAttributes as String: true]
        var result: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess,
              let items = result as? [[String: Any]] else { return [] }
        return items.compactMap { item -> Summary? in
            guard let account = item[kSecAttrAccount as String] as? String, let id = UUID(uuidString: account) else { return nil }
            return Summary(id: id, label: item[kSecAttrLabel as String] as? String ?? "Card")
        }
        .sorted { $0.label < $1.label }
    }

    static func card(_ id: UUID) -> SavedCard? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrService as String: service,
                                kSecAttrAccount as String: id.uuidString,
                                kSecReturnData as String: true,
                                kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(SavedCard.self, from: data)
    }

    @discardableResult
    static func save(_ card: SavedCard) -> Bool {
        guard let data = try? JSONEncoder().encode(card) else { return false }
        // Updated in place (it used to be deleted first, so a failed save lost the card).
        let match: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: card.id.uuidString]
        let label = "\(card.label) · \(card.expiry)"
        let status = SecItemUpdate(match as CFDictionary,
                                   [kSecValueData as String: data, kSecAttrLabel as String: label] as CFDictionary)
        guard status == errSecItemNotFound else { return status == errSecSuccess }
        var add = match
        add[kSecAttrLabel as String] = label
        add[kSecValueData as String] = data
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }

    static func delete(_ id: UUID) {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrService as String: service,
                                kSecAttrAccount as String: id.uuidString]
        SecItemDelete(q as CFDictionary)
    }
}

// MARK: - Your contact card

enum MyCard {
    static var status: CNAuthorizationStatus { CNContactStore.authorizationStatus(for: .contacts) }

    static func requestAccess(_ completion: @escaping (Bool) -> Void) {
        CNContactStore().requestAccess(for: .contacts) { ok, _ in DispatchQueue.main.async { completion(ok) } }
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

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
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
        case "submit":
            // Stealth windows promise not to remember what you type, so they don't offer to save,
            // except a strong password Ufolio made for you there (or it would be lost for good).
            guard secure, Prefs.bool(Prefs.autofillPasswords),
                  let password = body["password"] as? String, !password.isEmpty, password.count <= 512,
                  !tab.isPrivate || generatedPasswords.contains(password) else { return }
            let username = String((body["username"] as? String ?? "").prefix(256))
            offerToSave(username: username, password: password, host: host, tab: tab)
        default:
            break
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
            guard Prefs.bool(Prefs.autofillContact), MyCard.status != .denied, MyCard.status != .restricted else { return }
            options = [.contact(MyCard.status == .authorized ? MyCard.displayName : nil)]
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
        guard webView.window != nil, !tab.isAsleep else { return }
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
            UserAuth.confirm("fill your password for \(host)") { [weak self] ok in
                guard ok else { return }
                DispatchQueue.global(qos: .userInitiated).async {
                    guard let password = PasswordVault.password(for: login) else { return }
                    DispatchQueue.main.async {
                        self?.send(kind: "login", data: ["username": login.account, "password": password], host: host, tab: tab)
                    }
                }
            }
        case .card(let summary):
            UserAuth.confirm("fill your card details") { [weak self] ok in
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
                guard let fields = MyCard.fields() else { return }
                self?.send(kind: "contact", data: fields, host: host, tab: tab)
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
            let existing = PasswordVault.logins(for: host).first { $0.account == username }
            let unchanged = existing.map { PasswordVault.password(for: $0) == password } ?? false
            DispatchQueue.main.async {
                guard let self, let tab, !unchanged else { return }
                self.showSaveOffer(existing: existing, username: username, password: password, host: host, tab: tab)
            }
        }
    }

    private func showSaveOffer(existing: SavedLogin?, username: String, password: String, host: String, tab: BrowserTab) {
        guard let window = tab.webView.window, !DialogHost.isBusy(window) else { return }

        let who = username.isEmpty ? "" : " for “\(username)”"
        var choices: [HushDialog.Choice] = [.init(title: existing == nil ? "Save Password" : "Update Password", role: .primary),
                                            .init(title: "Not Now", role: .cancel)]
        if existing == nil { choices.append(.init(title: "Never for This Website")) }
        DialogHost.show(HushDialog(
            art: .site(tab.url), badge: "key.fill", theme: .save, motion: .rise,
            title: existing == nil ? "Save this password?" : "Update your saved password?",
            message: existing == nil
                ? "Ufolio can keep the password\(who) on \(host) in your Mac’s keychain and fill it in for you next time."
                : "The password\(who) on \(host) has changed. Update it in your keychain?",
            note: ("lock.fill", "Locked with your Mac password or Touch ID"),
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
      function remember(e) {
        var t = e.target;
        if (!(t instanceof HTMLInputElement) || t.type !== 'password' || !t.value) return;
        typed.pw = t.value; typed.user = userNear(t); typed.href = location.href;
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
      }
      window.addEventListener('pagehide', flush, true);
      setInterval(function () {
        if (!typed.pw) return;
        var boxes = Array.prototype.filter.call(document.querySelectorAll('input[type=password]'), visible);
        if (location.href !== typed.href || !boxes.length) flush();
      }, 700);

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
