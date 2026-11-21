import Foundation

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
              let items = components.queryItems, !items.isEmpty else { return nil }
        let host = url.host?.lowercased().strippingWWW ?? ""
        let siteRules = perSite.first { host == $0.key || host.hasSuffix("." + $0.key) }?.value ?? []
        let kept = items.filter { item in
            let name = item.name.lowercased()
            if everywhere.contains(name) || siteRules.contains(name) { return false }
            if prefixes.contains(where: name.hasPrefix) { return false }
            return true
        }
        guard kept.count != items.count else { return nil }
        components.queryItems = kept.isEmpty ? nil : kept
        return components.url
    }

    /// For copying: the clean address, or the original if it was already clean.
    static func clean(_ url: URL) -> URL { cleaned(url) ?? url }
}
