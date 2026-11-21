import Foundation
import WebKit

/// Removes tracking tags from web addresses: the bits companies add to links so they can
/// follow you from one site to the next (utm_source, fbclid, gclid…). The page is the same
/// without them.
enum CleanLinks {
    /// Tracking parameters removed everywhere.
    private static let everywhere: Set<String> = [
        "fbclid", "gclid", "gclsrc", "dclid", "gbraid", "wbraid", "msclkid", "yclid", "twclid", "ttclid",
        "li_fat_id", "igshid", "igsh", "mc_cid", "mc_eid", "_hsenc", "_hsmi", "__hssc", "__hstc", "__hsfp",
        "hsctatracking", "mkt_tok", "vero_id", "vero_conv", "oly_anon_id", "oly_enc_id", "rb_clickid",
        "s_cid", "sc_cid", "wickedid", "_openstat", "epik", "ref_src", "ref_url", "srsltid", "_kx",
        "gad_source", "gad_campaignid", "irclickid", "cmpid", "zanpid", "spm", "scm",
    ]
    /// Prefixes removed everywhere (utm_source, utm_medium, …; pk_campaign…).
    private static let prefixes = ["utm_", "pk_", "piwik_", "mtm_", "hsa_", "ga_"]
    /// Parameters that only mean tracking on particular sites.
    private static let perSite: [String: Set<String>] = [
        "youtube.com": ["si", "pp", "feature"], "youtu.be": ["si", "feature"],
        "open.spotify.com": ["si", "context"], "x.com": ["s", "t"], "twitter.com": ["s", "t"],
        "instagram.com": ["igshid", "igsh"], "amazon.co.uk": ["ref", "ref_", "pf_rd_r", "pf_rd_p", "pd_rd_r", "pd_rd_w", "pd_rd_wg", "content-id"],
        "amazon.com": ["ref", "ref_", "pf_rd_r", "pf_rd_p", "pd_rd_r", "pd_rd_w", "pd_rd_wg", "content-id"],
        "linkedin.com": ["trk", "trkinfo", "lipi", "trackingid"],
    ]

    static var isEnabled: Bool { Prefs.bool(Prefs.cleanLinks) }

    /// The address without tracking tags, or nil if there was nothing to remove.
    static func cleaned(_ url: URL) -> URL? {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let query = components.percentEncodedQuery, !query.isEmpty else { return nil }
        let host = url.host?.lowercased().strippingWWW ?? ""
        let siteRules = perSite.first { host == $0.key || host.hasSuffix("." + $0.key) }?.value ?? []
        // Work on the raw, still-encoded pieces, so everything kept stays exactly as it was.
        let pieces = query.split(separator: "&", omittingEmptySubsequences: false)
        let kept = pieces.filter { piece in
            let rawName = piece.split(separator: "=", maxSplits: 1).first.map(String.init) ?? ""
            let name = (rawName.removingPercentEncoding ?? rawName).lowercased()
            if everywhere.contains(name) || siteRules.contains(name) { return false }
            if prefixes.contains(where: name.hasPrefix) { return false }
            return true
        }
        guard kept.count != pieces.count else { return nil }
        components.percentEncodedQuery = kept.isEmpty ? nil : kept.joined(separator: "&")
        return components.url
    }

    // MARK: Debouncing and De-AMP

    /// Tracking redirects: the real address is in a parameter, so go straight there.
    private static let redirectors: [(host: String, path: String, params: [String])] = [
        ("google.com", "/url", ["q", "url"]),
        ("l.facebook.com", "/l.php", ["u"]), ("lm.facebook.com", "/l.php", ["u"]),
        ("l.instagram.com", "/", ["u"]), ("l.threads.net", "/", ["u"]),
        ("out.reddit.com", "/", ["url"]), ("youtube.com", "/redirect", ["q"]),
        ("t.umblr.com", "/redirect", ["z"]), ("steamcommunity.com", "/linkfilter", ["url", "u"]),
        ("slack-redir.net", "/link", ["url"]), ("away.vk.com", "/away.php", ["to"]),
        ("linkedin.com", "/safety/go", ["url"]), ("disq.us", "/url", ["url"]),
        ("exit.sc", "/", ["url"]), ("href.li", "/", []), ("deref-gmx.net", "/mail/client", ["redirectUrl"]),
        ("deref-web.de", "/mail/client", ["redirectUrl"]), ("click.linksynergy.com", "/", ["murl"]),
    ]

    static var debounceEnabled: Bool { Prefs.bool(Prefs.debounceLinks) }
    static var deAMPEnabled: Bool { Prefs.bool(Prefs.deAMP) }

    /// Where a tracking redirect or AMP link really points, or nil.
    static func skipRedirect(_ url: URL) -> URL? {
        guard let host = url.host?.lowercased().strippingWWW else { return nil }
        if deAMPEnabled, let real = unAMP(url, host: host) { return real }
        guard debounceEnabled, let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        for rule in redirectors where host == rule.host || host.hasSuffix("." + rule.host) {
            guard url.path.hasPrefix(rule.path) else { continue }
            var target: String?
            if rule.params.isEmpty {
                target = components.percentEncodedQuery?.removingPercentEncoding   // href.li/?https://…
            } else {
                target = rule.params.lazy.compactMap { name in components.queryItems?.first { $0.name == name }?.value }.first
            }
            if let target, let real = validTarget(target, from: host) { return real }
        }
        return nil
    }

    /// Google's AMP copies of articles → the publisher's own page.
    private static func unAMP(_ url: URL, host: String) -> URL? {
        let path = url.path
        if host == "google.com" || host.hasSuffix(".google.com"), path.hasPrefix("/amp/") {
            var rest = String(path.dropFirst("/amp/".count))
            let secure = rest.hasPrefix("s/")
            if secure { rest = String(rest.dropFirst(2)) }
            return validTarget((secure ? "https://" : "http://") + rest + (url.query.map { "?" + $0 } ?? ""), from: host)
        }
        if host.hasSuffix(".cdn.ampproject.org") {
            let parts = path.split(separator: "/", maxSplits: 3).map(String.init)   // ["c" or "v", "s"?, host, path]
            guard parts.count >= 3, ["c", "v"].contains(parts[0]) else { return nil }
            let secure = parts[1] == "s"
            let tail = secure ? parts.dropFirst(2) : parts.dropFirst(1)
            return validTarget((secure ? "https://" : "http://") + tail.joined(separator: "/"), from: host)
        }
        return nil
    }

    private static func validTarget(_ text: String, from host: String) -> URL? {
        guard let url = URL(string: text), let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let target = url.host?.lowercased(), !target.isEmpty, target.strippingWWW != host else { return nil }
        return url
    }

    /// AMP pages reached directly: hop to the publisher's normal page (runs in Hush's own world).
    static let deAMPScript = WKUserScript(source: """
    (function () {
      var html = document.documentElement;
      if (!html || !(html.hasAttribute('amp') || html.hasAttribute('⚡'))) return;
      var link = document.querySelector('link[rel="canonical"]');
      if (!link || !/^https?:/.test(link.href) || link.href === location.href) return;
      location.replace(link.href);
    })();
    """, injectionTime: .atDocumentEnd, forMainFrameOnly: true, in: .defaultClient)

    /// For copying: the clean address, or the original if it was already clean.
    static func clean(_ url: URL) -> URL { cleaned(url) ?? url }
}
