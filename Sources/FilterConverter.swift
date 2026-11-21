import Foundation

/// Converts ad-block filter lists into WebKit content-blocker rules.
///
/// Understands:
/// - Adblock Plus / uBlock Origin lists (EasyList, EasyPrivacy, AdGuard…):
///   network rules (`||ads.example.com^$third-party`), exceptions (`@@…`) and
///   element hiding (`##.ad-banner`, `example.com##.sponsor`).
/// - Hosts files (`0.0.0.0 ads.example.com`) and plain domain lists.
/// - Safari content-blocker JSON, used as-is.
///
/// Rules WebKit can't run (scriptlets, `:has-text`, regex rules, redirects…) are
/// skipped and counted, so the user can see how much of a list was used.
enum FilterConverter {
    /// Bumped whenever a conversion bug is fixed; lists converted by an older version are redone.
    /// 2: element-hiding rules were mistaken for hosts entries and blocked whole sites.
    static let version = 2

    /// WebKit's limit for one compiled list.
    static let maxRules = 150_000
    /// Element-hiding selectors are grouped so one bad selector can't hide a whole list's worth.
    static let selectorsPerRule = 50

    struct Output {
        var json: String
        var ruleCount: Int
        var skipped: Int
        var format: String
        var title: String?
    }

    enum ConversionError: LocalizedError {
        case noUsableRules(skipped: Int)
        case badJSON

        var errorDescription: String? {
            switch self {
            case .noUsableRules(let skipped):
                return skipped > 0
                    ? "None of the \(skipped.formatted()) rules in this list can run in WebKit."
                    : "This doesn't look like a filter list — no rules were found."
            case .badJSON:
                return "This JSON file isn't a valid Safari content-blocker list."
            }
        }
    }

    static func convert(_ text: String) throws -> Output {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Safari JSON starts with "[{" — but Adblock lists start with a "[Adblock Plus 2.0]" header.
        if trimmed.hasPrefix("["),
           let next = trimmed.dropFirst().first(where: { !$0.isWhitespace }), next == "{" || next == "]" {
            return try passThroughJSON(trimmed)
        }

        var blocks: [[String: Any]] = []
        var exceptions: [[String: Any]] = []
        var genericSelectors: [String] = []
        var scopedSelectors: [String: [String]] = [:] // domain list text → selectors
        var skipped = 0
        var title: String?
        var hostLines = 0
        var abpLines = 0

        for raw in trimmed.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }

            // Comments and headers.
            if line.hasPrefix("!") || line.hasPrefix("[") {
                if title == nil, line.lowercased().hasPrefix("! title:") {
                    title = String(line.dropFirst(8)).trimmingCharacters(in: .whitespaces)
                }
                continue
            }
            if line.hasPrefix("#") && !line.hasPrefix("##") && !line.hasPrefix("#@#") { continue }

            switch hostsEntry(line) {
            case .domain(let domain):
                blocks.append(blockDomain(domain))
                hostLines += 1
                continue
            case .ignore:
                continue
            case .notHosts:
                break
            }

            abpLines += 1

            // Element hiding the WebKit engine can't do (exceptions, scriptlets, extended CSS).
            if ["#@#", "#?#", "#$#", "#%#", "#@$#", "#@?#", "$$", "#+js"].contains(where: line.contains) {
                skipped += 1
                continue
            }

            if let range = line.range(of: "##") {
                let selector = String(line[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                let domains = String(line[..<range.lowerBound])
                guard !selector.isEmpty, isSupportedSelector(selector) else { skipped += 1; continue }
                if domains.isEmpty {
                    genericSelectors.append(selector)
                } else if parseDomains(domains, separator: ",") != nil {
                    scopedSelectors[domains.lowercased(), default: []].append(selector)
                } else {
                    skipped += 1
                }
                continue
            }

            if let (rule, isException) = networkRule(line) {
                if isException { exceptions.append(rule) } else { blocks.append(rule) }
            } else {
                skipped += 1
            }
        }

        var cosmetic: [[String: Any]] = []
        for chunk in stride(from: 0, to: genericSelectors.count, by: selectorsPerRule) {
            let selectors = genericSelectors[chunk..<min(chunk + selectorsPerRule, genericSelectors.count)]
            cosmetic.append([
                "trigger": ["url-filter": ".*"],
                "action": ["type": "css-display-none", "selector": selectors.joined(separator: ", ")],
            ])
        }
        for (domains, selectors) in scopedSelectors.sorted(by: { $0.key < $1.key }) {
            guard let scope = parseDomains(domains, separator: ",") else { continue }
            var trigger: [String: Any] = ["url-filter": ".*"]
            if !scope.include.isEmpty { trigger["if-domain"] = scope.include } else { trigger["unless-domain"] = scope.exclude }
            for chunk in stride(from: 0, to: selectors.count, by: selectorsPerRule) {
                let group = selectors[chunk..<min(chunk + selectorsPerRule, selectors.count)]
                cosmetic.append([
                    "trigger": trigger,
                    "action": ["type": "css-display-none", "selector": group.joined(separator: ", ")],
                ])
            }
        }

        // Exceptions must come last: they cancel the rules before them.
        var rules = blocks + cosmetic
        let room = maxRules - min(exceptions.count, maxRules / 10)
        if rules.count > room {
            skipped += rules.count - room
            rules = Array(rules.prefix(room))
        }
        rules += exceptions.prefix(maxRules - rules.count)

        guard !rules.isEmpty else { throw ConversionError.noUsableRules(skipped: skipped) }
        let data = try JSONSerialization.data(withJSONObject: rules)
        let format = hostLines > abpLines ? "Hosts file" : "Ad-block filter list"
        return Output(json: String(decoding: data, as: UTF8.self), ruleCount: rules.count,
                      skipped: skipped, format: format, title: title)
    }

    // MARK: Safari JSON

    private static func passThroughJSON(_ text: String) throws -> Output {
        guard let data = text.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw ConversionError.badJSON
        }
        var rules = array.filter { $0["trigger"] is [String: Any] && $0["action"] is [String: Any] }
        let skipped = array.count - rules.count + max(0, rules.count - maxRules)
        rules = Array(rules.prefix(maxRules))
        guard !rules.isEmpty else { throw ConversionError.badJSON }
        let out = try JSONSerialization.data(withJSONObject: rules)
        return Output(json: String(decoding: out, as: UTF8.self), ruleCount: rules.count,
                      skipped: skipped, format: "Safari content blocker", title: nil)
    }

    // MARK: Hosts files

    private enum HostsLine { case domain(String), ignore, notHosts }

    private static let localNames: Set<String> = [
        "localhost", "localhost.localdomain", "local", "broadcasthost", "ip6-localhost", "ip6-loopback",
        "0.0.0.0", "ip6-localnet", "ip6-mcastprefix", "ip6-allnodes", "ip6-allrouters", "ip6-allhosts",
    ]

    private static func hostsEntry(_ line: String) -> HostsLine {
        // Adblock element-hiding rules use "#" too ("example.com##.ad"). Those must never be read
        // as hosts lines, or the whole site gets blocked (the 0.3.1 bug).
        if ["##", "#@#", "#?#", "#$#", "#%#"].contains(where: line.contains) { return .notHosts }
        // In hosts files a comment is a "#" at the start or after whitespace.
        var withoutComment = Substring(line)
        if let r = line.range(of: " #") ?? line.range(of: "\t#") { withoutComment = line[..<r.lowerBound] }
        if withoutComment.contains("#") { return .notHosts }
        let parts = withoutComment.split(whereSeparator: { $0 == " " || $0 == "\t" })
        if parts.count >= 2, ["0.0.0.0", "127.0.0.1", "::", "::1", "0"].contains(String(parts[0])) {
            let domain = parts[1].lowercased()
            if localNames.contains(domain) { return .ignore }
            return isValidDomain(domain) ? .domain(domain) : .ignore
        }
        if parts.count == 1 && !line.hasPrefix("#") {
            let candidate = parts[0].lowercased()
            if isValidDomain(candidate) && candidate.contains(".") && !localNames.contains(candidate) {
                return .domain(candidate)
            }
        }
        return .notHosts
    }

    private static let domainCharacters = Set("abcdefghijklmnopqrstuvwxyz0123456789.-_")

    static func isValidDomain(_ s: String) -> Bool {
        !s.isEmpty && s.count < 254 && !s.hasPrefix(".") && !s.hasSuffix(".") && s.allSatisfy(domainCharacters.contains)
    }

    /// url-filter matching a domain and all its subdomains.
    static func domainFilter(_ domain: String) -> String {
        "^[^:]+://+([^:/]+\\.)?" + domain.replacingOccurrences(of: ".", with: "\\.") + "[/:]"
    }

    private static func blockDomain(_ domain: String) -> [String: Any] {
        ["trigger": ["url-filter": domainFilter(domain)], "action": ["type": "block"]]
    }

    // MARK: Adblock Plus network rules

    private static let resourceTypes: [String: String] = [
        "script": "script", "image": "image", "stylesheet": "style-sheet", "css": "style-sheet",
        "font": "font", "media": "media", "xmlhttprequest": "raw", "xhr": "raw", "websocket": "raw",
        "ping": "ping", "popup": "popup", "other": "other", "object": "other",
    ]

    /// Options that don't change what's blocked in WebKit, so they can be ignored.
    private static let harmlessOptions: Set<String> = ["important", "all", "~media", "~font", "~image"]

    private static func networkRule(_ line: String) -> ([String: Any], Bool)? {
        var text = Substring(line)
        let isException = text.hasPrefix("@@")
        if isException { text = text.dropFirst(2) }

        // Regex rules (/…/) need full regular expressions, which WebKit doesn't support.
        if text.hasPrefix("/") && text.count > 2 && (text.hasSuffix("/") || text.contains("/$")) { return nil }

        var pattern = String(text)
        var options: [String] = []
        if let dollar = pattern.lastIndex(of: "$") {
            let optionText = pattern[pattern.index(after: dollar)...]
            if !optionText.isEmpty, !optionText.contains("/") {
                options = optionText.split(separator: ",").map { $0.lowercased() }
                pattern = String(pattern[..<dollar])
            }
        }

        var trigger: [String: Any] = [:]
        var types: Set<String> = []
        var hasDomainScope = false

        for option in options {
            switch option {
            case "third-party", "3p":
                trigger["load-type"] = ["third-party"]
            case "~third-party", "first-party", "1p":
                trigger["load-type"] = ["first-party"]
            case "match-case":
                trigger["url-filter-is-case-sensitive"] = true
            case "subdocument", "frame":
                types.insert("document")
                trigger["load-context"] = ["child-frame"]
            default:
                if let type = resourceTypes[option] {
                    types.insert(type)
                } else if option.hasPrefix("domain=") {
                    guard let scope = parseDomains(String(option.dropFirst(7)), separator: "|") else { return nil }
                    if !scope.include.isEmpty { trigger["if-domain"] = scope.include } else { trigger["unless-domain"] = scope.exclude }
                    hasDomainScope = true
                } else if !harmlessOptions.contains(option) {
                    return nil // $redirect, $csp, $removeparam, $document, negated types…
                }
            }
        }

        guard let filter = urlFilter(pattern, allowMatchAll: hasDomainScope || !types.isEmpty) else { return nil }
        trigger["url-filter"] = filter
        if !types.isEmpty { trigger["resource-type"] = types.sorted() }

        let action = isException ? "ignore-previous-rules" : "block"
        return (["trigger": trigger, "action": ["type": action]], isException)
    }

    /// Turns an Adblock Plus address pattern into the limited regex WebKit accepts.
    static func urlFilter(_ pattern: String, allowMatchAll: Bool) -> String? {
        var body = Substring(pattern)
        var out = ""
        if body.hasPrefix("||") {
            out = "^[^:]+://+([^:/]+\\.)?"
            body = body.dropFirst(2)
        } else if body.hasPrefix("|") {
            out = "^"
            body = body.dropFirst()
        }
        var anchoredEnd = false
        if body.hasSuffix("|") {
            anchoredEnd = true
            body = body.dropLast()
        }
        if body.isEmpty && out.isEmpty {
            return allowMatchAll ? ".*" : nil
        }
        for ch in body {
            guard ch.isASCII, !ch.isWhitespace else { return nil }
            switch ch {
            case "*":
                if !out.hasSuffix(".*") { out += ".*" }
            case "^":
                out += "[/:?=&]"
            case ".", "+", "?", "{", "}", "(", ")", "[", "]", "\\", "$", "|":
                out += "\\" + String(ch)
            default:
                out.append(ch)
            }
        }
        if anchoredEnd { out += "$" }
        if out == ".*" || out.isEmpty { return allowMatchAll ? ".*" : nil }
        return out
    }

    private static func parseDomains(_ text: String, separator: Character) -> (include: [String], exclude: [String])? {
        var include: [String] = []
        var exclude: [String] = []
        for part in text.split(separator: separator) {
            var domain = part.lowercased().trimmingCharacters(in: .whitespaces)
            let negated = domain.hasPrefix("~")
            if negated { domain.removeFirst() }
            // Entries like "example.*" (any TLD) have no WebKit equivalent.
            guard isValidDomain(domain) else { return nil }
            if negated { exclude.append("*" + domain) } else { include.append("*" + domain) }
        }
        if include.isEmpty && exclude.isEmpty { return nil }
        return (include, exclude)
    }

    private static let unsupportedSelectorMarkers = [
        ":-abp-", ":has-text", ":contains(", ":xpath", ":matches-css", ":upward", ":remove", ":style",
        ":watch-attr", ":min-text-length", ":matches-path", ":matches-attr", ":others", ":nth-ancestor",
        ":if(", ":if-not", ":properties", ":-ext-", "+js(",
    ]

    private static func isSupportedSelector(_ selector: String) -> Bool {
        if selector.hasPrefix("^") || selector.hasPrefix("+js") { return false }
        let lower = selector.lowercased()
        return !unsupportedSelectorMarkers.contains(where: lower.contains)
    }
}
