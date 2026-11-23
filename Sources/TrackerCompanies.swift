import Foundation

/// Who's behind a tracker or ad server, for "What Hush Guard blocked" in the panel.
enum TrackerCompanies {
    private static let owners: [String: String] = [
        "doubleclick.net": "Google", "googlesyndication.com": "Google", "googleadservices.com": "Google",
        "googletagservices.com": "Google", "google-analytics.com": "Google", "googletagmanager.com": "Google",
        "adservice.google.com": "Google", "imasdk.googleapis.com": "Google", "googleoptimize.com": "Google", "gstatic.com": "Google",
        "facebook.net": "Meta", "facebook.com": "Meta", "fbcdn.net": "Meta", "instagram.com": "Meta",
        "amazon-adsystem.com": "Amazon", "assoc-amazon.com": "Amazon",
        "adnxs.com": "Microsoft", "bing.com": "Microsoft", "clarity.ms": "Microsoft", "licdn.com": "Microsoft (LinkedIn)",
        "linkedin.com": "Microsoft (LinkedIn)",
        "tiktok.com": "TikTok", "tiktokcdn.com": "TikTok", "ads-twitter.com": "X (Twitter)", "twitter.com": "X (Twitter)",
        "x.com": "X (Twitter)", "pinterest.com": "Pinterest", "pinimg.com": "Pinterest", "snapchat.com": "Snap", "sc-static.net": "Snap",
        "criteo.com": "Criteo", "criteo.net": "Criteo", "taboola.com": "Taboola", "outbrain.com": "Outbrain",
        "scorecardresearch.com": "Comscore", "quantserve.com": "Quantcast", "quantcount.com": "Quantcast",
        "hotjar.com": "Hotjar", "mixpanel.com": "Mixpanel", "segment.io": "Twilio Segment", "segment.com": "Twilio Segment",
        "amplitude.com": "Amplitude", "nr-data.net": "New Relic", "newrelic.com": "New Relic", "chartbeat.com": "Chartbeat",
        "chartbeat.net": "Chartbeat", "indexww.com": "Index Exchange", "casalemedia.com": "Index Exchange",
        "pubmatic.com": "PubMatic", "rubiconproject.com": "Magnite", "openx.net": "OpenX", "adsrvr.org": "The Trade Desk",
        "mathtag.com": "MediaMath", "rlcdn.com": "LiveRamp", "crwdcntrl.net": "Lotame", "exelator.com": "Nielsen",
        "tapad.com": "Tapad", "yahoo.com": "Yahoo", "teads.tv": "Teads", "adsafeprotected.com": "Integral Ad Science",
        "doubleverify.com": "DoubleVerify", "moatads.com": "Oracle", "bluekai.com": "Oracle", "demdex.net": "Adobe",
        "omtrdc.net": "Adobe", "everesttech.net": "Adobe", "optimizely.com": "Optimizely", "branch.io": "Branch",
        "krxd.net": "Salesforce", "agkn.com": "Neustar", "eyeota.net": "Eyeota", "id5-sync.com": "ID5",
        "liadm.com": "LiveIntent", "bounceexchange.com": "Wunderkind", "bouncex.net": "Wunderkind", "parsely.com": "Parse.ly",
        "statcounter.com": "StatCounter", "addthis.com": "Oracle (AddThis)", "sharethis.com": "ShareThis",
        "smartadserver.com": "Equativ", "triplelift.com": "TripleLift", "sharethrough.com": "Sharethrough",
        "33across.com": "33Across", "yieldmo.com": "Yieldmo", "sovrn.com": "Sovrn", "lijit.com": "Sovrn",
        "gumgum.com": "GumGum", "media.net": "Media.net", "mgid.com": "MGID", "revcontent.com": "Revcontent",
        "zemanta.com": "Outbrain", "adform.net": "Adform", "adroll.com": "AdRoll", "bidswitch.net": "BidSwitch",
        "onesignal.com": "OneSignal", "privy.com": "Privy", "sumo.com": "Sumo", "omappapi.com": "OptinMonster",
        "intercom.io": "Intercom", "intercomcdn.com": "Intercom", "driftt.com": "Drift", "zdassets.com": "Zendesk",
        "fpjs.io": "Fingerprint", "fpcdn.io": "Fingerprint", "fingerprintjs.com": "Fingerprint", "tiqcdn.com": "Tealium",
        "ensighten.com": "Ensighten", "sentry.io": "Sentry", "mxpnl.com": "Mixpanel", "heapanalytics.com": "Heap",
        "fullstory.com": "FullStory", "mouseflow.com": "Mouseflow", "crazyegg.com": "Crazy Egg", "luckyorange.com": "Lucky Orange",
        "kissmetrics.com": "Kissmetrics", "clicky.com": "Clicky", "yieldify.com": "Yieldify",
    ]

    /// "Google" for "securepubads.g.doubleclick.net", or the site itself when unknown.
    static func owner(of site: String) -> String {
        if let known = owners[site] { return known }
        // Try the parent domains too (e.g. "pixel.facebook.com" → "facebook.com").
        var parts = site.split(separator: ".")
        while parts.count > 2 {
            parts.removeFirst()
            if let known = owners[parts.joined(separator: ".")] { return known }
        }
        return site
    }

    struct Group: Identifiable {
        let company: String
        let sites: [String]
        let count: Int
        var id: String { company }
    }

    /// Blocked requests on a page, grouped by the company behind them, most first.
    static func groups(_ blocked: [String: Int]) -> [Group] {
        var byCompany: [String: (sites: Set<String>, count: Int)] = [:]
        for (site, count) in blocked {
            let company = owner(of: site)
            var entry = byCompany[company] ?? ([], 0)
            entry.sites.insert(site)
            entry.count += count
            byCompany[company] = entry
        }
        return byCompany.map { Group(company: $0.key, sites: $0.value.sites.sorted(), count: $0.value.count) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.company < $1.company }
    }
}
