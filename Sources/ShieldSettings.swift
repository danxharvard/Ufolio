import SwiftUI

/// Scripts: run everything, stop scripts from other companies, or turn JavaScript off.
enum ScriptPolicy: String, CaseIterable, Identifiable {
    case allow, blockThirdParty, blockAll
    var id: String { rawValue }
    var label: String {
        switch self {
        case .allow: return "Allow"
        case .blockThirdParty: return "Block third-party"
        case .blockAll: return "Block all"
        }
    }
    var detail: String {
        switch self {
        case .allow: return "Pages run all their scripts."
        case .blockThirdParty: return "Only the site’s own scripts run, not ones from other companies."
        case .blockAll: return "No JavaScript at all. Fast and private, but many sites won’t work."
        }
    }
}

enum FingerprintLevel: String, CaseIterable, Identifiable {
    case off, standard, strict
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

enum CookiePolicy: String, CaseIterable, Identifiable {
    case allowAll, blockThirdParty, blockAll
    var id: String { rawValue }
    var label: String {
        switch self {
        case .allowAll: return "Allow all"
        case .blockThirdParty: return "Block third-party"
        case .blockAll: return "Block all"
        }
    }
}

/// The protection a page actually gets: your defaults, with any site's own changes on top.
struct Shields: Equatable {
    var blocking: BlockingMode
    var scripts: ScriptPolicy
    var fingerprinting: FingerprintLevel
    var cookies: CookiePolicy
}

/// One site's changes (nil = use the default).
struct SiteOverrides: Codable, Equatable {
    var blocking: String?
    var scripts: String?
    var fingerprinting: String?
    var cookies: String?
    var isEmpty: Bool { blocking == nil && scripts == nil && fingerprinting == nil && cookies == nil }
}

/// Hush Guard's settings: defaults for every site (Settings › Hush Guard) and per-site
/// changes (the Hush Guard panel). Sites are grouped by domain, so mail.example.com and
/// www.example.com share example.com's settings.
final class ShieldSettings: ObservableObject {
    static let shared = ShieldSettings()
    static let sitesKey = "siteShields"

    @Published private(set) var sites: [String: SiteOverrides] = [:]

    private init() {
        if let text = UserDefaults.standard.string(forKey: Self.sitesKey), let data = text.data(using: .utf8),
           let saved = try? JSONDecoder().decode([String: SiteOverrides].self, from: data) {
            sites = saved
        }
    }

    // MARK: Defaults

    static var defaults: Shields {
        let d = UserDefaults.standard
        let scripts = d.string(forKey: Prefs.scriptPolicy).flatMap(ScriptPolicy.init(rawValue:)) ?? .allow
        // Older versions had simple on/off switches for these; carry their answers over.
        let fingerprint = d.string(forKey: Prefs.fingerprintMode).flatMap(FingerprintLevel.init(rawValue:))
            ?? (Prefs.bool(Prefs.fingerprintProtection) ? .standard : .off)
        let cookies = d.string(forKey: Prefs.cookiePolicy).flatMap(CookiePolicy.init(rawValue:))
            ?? (Prefs.bool(Prefs.blockThirdPartyCookies) ? .blockThirdParty : .allowAll)
        return Shields(blocking: BlockingMode.current, scripts: scripts, fingerprinting: fingerprint, cookies: cookies)
    }

    // MARK: Per site

    static func key(for host: String) -> String { Domains.site(host) }

    func overrides(for host: String) -> SiteOverrides { sites[Self.key(for: host)] ?? SiteOverrides() }

    func effective(for host: String?) -> Shields {
        var result = Self.defaults
        guard let host, !host.isEmpty else { return result }
        let o = overrides(for: host)
        if let v = o.blocking.flatMap(BlockingMode.init(rawValue:)) { result.blocking = v }
        if let v = o.scripts.flatMap(ScriptPolicy.init(rawValue:)) { result.scripts = v }
        if let v = o.fingerprinting.flatMap(FingerprintLevel.init(rawValue:)) { result.fingerprinting = v }
        if let v = o.cookies.flatMap(CookiePolicy.init(rawValue:)) { result.cookies = v }
        return result
    }

    func update(_ host: String, _ change: (inout SiteOverrides) -> Void) {
        let key = Self.key(for: host)
        var o = sites[key] ?? SiteOverrides()
        change(&o)
        sites[key] = o.isEmpty ? nil : o
        save()
    }

    func reset(_ host: String) {
        sites[Self.key(for: host)] = nil
        save()
    }

    func resetAll() {
        sites = [:]
        save()
    }

    /// "Scripts: Block all · Cookies: Allow all" for the Settings list.
    func summary(for site: String) -> String {
        guard let o = sites[site] else { return "" }
        var parts: [String] = []
        if let v = o.blocking.flatMap(BlockingMode.init(rawValue:)) { parts.append("Ads & trackers: \(v.label)") }
        if let v = o.scripts.flatMap(ScriptPolicy.init(rawValue:)) { parts.append("Scripts: \(v.label)") }
        if let v = o.fingerprinting.flatMap(FingerprintLevel.init(rawValue:)) { parts.append("Fingerprinting: \(v.label)") }
        if let v = o.cookies.flatMap(CookiePolicy.init(rawValue:)) { parts.append("Cookies: \(v.label)") }
        return parts.joined(separator: " · ")
    }

    private func save() {
        // Saved as text: Hush Guard watches this setting and re-applies rules when it changes.
        let text = (try? JSONEncoder().encode(sites)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
        UserDefaults.standard.set(sites.isEmpty ? "" : text, forKey: Self.sitesKey)
    }
}
