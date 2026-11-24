import Foundation

/// Spots fake look-alike sites: addresses made to resemble a site you really use, by
/// swapping a letter (paypa1.com) or using foreign letters that look English (аpple.com,
/// whose "а" is Cyrillic). Only sites you actually use are protected: your bookmarks,
/// saved passwords and frequently visited sites. Nothing leaves your Mac.
enum Lookalike {
    struct Match {
        let visited: String   // the suspicious site, e.g. "paypa1.com"
        let real: String      // the site you use, e.g. "paypal.com"
    }

    /// A site you use, with its look-alike "skeleton" worked out once rather than per page.
    private struct Known { let site: String; let skeleton: String; let label: String }
    private static var known: [Known] = []
    private static var knownSet: Set<String> = []
    private static var builtAt = Date.distantPast
    private static var refreshing = false

    /// Rebuilds the list of sites you use (at most once a minute) in the background. It reads
    /// saved passwords from the keychain, which can stall for a long time, so it must never
    /// happen on the main thread in the middle of loading a page.
    static func refreshKnown() {
        guard !refreshing else { return }
        refreshing = true
        var sites = Set<String>()
        for b in BookmarkStore.shared.items { if let h = b.url.host { sites.insert(Domains.site(h)) } }
        for site in HistoryStore.shared.frequentSites(limit: 60) where site.score >= 3 { sites.insert(Domains.site(site.host)) }
        DispatchQueue.global(qos: .utility).async {
            for login in PasswordVault.logins() { sites.insert(Domains.site(login.host)) }
            sites.remove("")
            let entries = sites.map { site -> Known in
                let skeleton = skeleton(site)
                return Known(site: site, skeleton: skeleton, label: label(of: skeleton))
            }
            DispatchQueue.main.async {
                known = entries
                knownSet = sites
                builtAt = Date()
                refreshing = false
            }
        }
    }

    static func allowedAnyway(_ site: String) -> Bool {
        sessionAllowed.contains(site) || (UserDefaults.standard.stringArray(forKey: "lookalikeAllowed") ?? []).contains(site)
    }

    /// Allowed from Stealth windows: until Ufolio quits only, never written down.
    private static var sessionAllowed: Set<String> = []

    static func allow(_ site: String, remember: Bool = true) {
        guard remember else { sessionAllowed.insert(site); return }
        let list = UserDefaults.standard.stringArray(forKey: "lookalikeAllowed") ?? []
        UserDefaults.standard.set(Array(Set(list + [site])), forKey: "lookalikeAllowed")
    }

    /// Checks a host before its page loads.
    static func check(host: String) -> Match? {
        guard Prefs.bool(Prefs.lookalikeWarning) else { return nil }
        if Date().timeIntervalSince(builtAt) > 60 { refreshKnown() }
        let site = Domains.site(host)
        guard !site.isEmpty, !knownSet.contains(site), !allowedAnyway(site) else { return nil }

        let decoded = Punycode.decodeHost(site)
        let visitedSkeleton = skeleton(decoded)
        let visitedLabel = label(of: visitedSkeleton)
        for real in known {
            // Foreign or swapped letters that read the same (аpple.com, g00gle.com, rnicrosoft.com).
            if visitedSkeleton == real.skeleton {
                return Match(visited: decoded, real: real.site)
            }
            // One letter added, removed, changed or swapped (paypa1.com, amazom.co.uk, gooogle.com).
            let realLabel = real.label
            if realLabel.count >= 5, visitedLabel.count >= 5, abs(realLabel.count - visitedLabel.count) <= 1,
               distance(visitedLabel, realLabel) == 1 {
                return Match(visited: decoded, real: real.site)
            }
        }
        return nil
    }

    /// The name before the ending: "paypal" for paypal.com, "bbc" for bbc.co.uk.
    private static func label(of site: String) -> String {
        String(site.split(separator: ".").first ?? "")
    }

    /// Characters that look alike, mapped to the letter they imitate.
    private static let confusables: [Character: String] = [
        // Cyrillic
        "а": "a", "е": "e", "о": "o", "р": "p", "с": "c", "у": "y", "х": "x", "і": "i", "ј": "j", "ѕ": "s",
        "һ": "h", "ԁ": "d", "ԛ": "q", "ԝ": "w", "ӏ": "l", "ʏ": "y", "в": "b", "к": "k", "м": "m", "н": "h", "т": "t",
        // Greek
        "α": "a", "ο": "o", "ρ": "p", "ε": "e", "ι": "i", "κ": "k", "ν": "v", "τ": "t", "υ": "u", "χ": "x",
        // Latin look-alikes and accents
        "ı": "i", "ɑ": "a", "ɡ": "g", "ⅼ": "l", "à": "a", "á": "a", "â": "a", "ä": "a", "å": "a", "è": "e", "é": "e",
        "ê": "e", "ë": "e", "ì": "i", "í": "i", "î": "i", "ï": "i", "ò": "o", "ó": "o", "ô": "o", "ö": "o", "ù": "u",
        "ú": "u", "û": "u", "ü": "u", "ñ": "n", "ç": "c",
        // Digits used as letters
        "0": "o", "1": "l", "3": "e", "5": "s", "|": "l",
    ]

    static func skeleton(_ s: String) -> String {
        var out = ""
        for ch in s.lowercased() { out += confusables[ch] ?? String(ch) }
        // Letter pairs that read as one letter.
        return out.replacingOccurrences(of: "rn", with: "m").replacingOccurrences(of: "vv", with: "w")
            .replacingOccurrences(of: "i", with: "l") // i/l/1 all look alike in many fonts
            .replacingOccurrences(of: "-", with: "")
    }

    /// Edit distance (insert, delete, substitute, swap neighbours).
    static func distance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var d = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in 0...a.count { d[i][0] = i }
        for j in 0...b.count { d[0][j] = j }
        for i in 1...a.count {
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                d[i][j] = min(d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + cost)
                if i > 1, j > 1, a[i - 1] == b[j - 2], a[i - 2] == b[j - 1] {
                    d[i][j] = min(d[i][j], d[i - 2][j - 2] + 1)
                }
            }
        }
        return d[a.count][b.count]
    }
}

/// Decodes internationalised domain names ("xn--pple-43d.com" → "аpple.com"), RFC 3492.
enum Punycode {
    static func decodeHost(_ host: String) -> String {
        host.split(separator: ".").map { part -> String in
            let p = String(part)
            guard p.lowercased().hasPrefix("xn--") else { return p }
            return decode(String(p.dropFirst(4))) ?? p
        }.joined(separator: ".")
    }

    static func decode(_ input: String) -> String? {
        let base = 36, tMin = 1, tMax = 26, skew = 38, damp = 700
        var n = 128, i = 0, bias = 72
        var output: [Unicode.Scalar] = []
        var rest = Substring(input)
        if let dash = input.lastIndex(of: "-") {
            output = input[..<dash].unicodeScalars.map { $0 }
            rest = input[input.index(after: dash)...]
        }
        let digits = Array(rest.lowercased())
        var pos = 0
        func digit(_ c: Character) -> Int? {
            if let v = c.asciiValue {
                if v >= 97 && v <= 122 { return Int(v) - 97 }
                if v >= 48 && v <= 57 { return Int(v) - 22 }
            }
            return nil
        }
        func adapt(_ delta: Int, _ numPoints: Int, _ first: Bool) -> Int {
            var delta = first ? delta / damp : delta / 2
            delta += delta / numPoints
            var k = 0
            while delta > ((base - tMin) * tMax) / 2 { delta /= base - tMin; k += base }
            return k + (base - tMin + 1) * delta / (delta + skew)
        }
        while pos < digits.count {
            let oldI = i
            var w = 1, k = base
            while true {
                guard pos < digits.count, let d = digit(digits[pos]) else { return nil }
                pos += 1
                i += d * w
                let t = k <= bias ? tMin : (k >= bias + tMax ? tMax : k - bias)
                if d < t { break }
                w *= base - t
                k += base
                if i > 0x10FFFF * 4 { return nil }
            }
            bias = adapt(i - oldI, output.count + 1, oldI == 0)
            n += i / (output.count + 1)
            i %= output.count + 1
            guard let scalar = Unicode.Scalar(n) else { return nil }
            output.insert(scalar, at: i)
            i += 1
        }
        return String(String.UnicodeScalarView(output))
    }
}
