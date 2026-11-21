import WebKit

/// Blocks ads and trackers using WebKit's built-in content blocker (the same
/// engine Safari's ad-block extensions use). Rules are compiled once and cached
/// by WebKit, so blocking costs almost nothing while browsing.
final class AdBlocker {
    static let shared = AdBlocker()

    private static let identifier = "hush-adblock-v1"
    private var ruleList: WKContentRuleList?
    private let controllers = NSHashTable<WKUserContentController>.weakObjects()

    private var enabled: Bool {
        UserDefaults.standard.object(forKey: Prefs.adBlockEnabled) as? Bool ?? true
    }

    func prepare() {
        guard let store = WKContentRuleListStore.default() else { return }
        store.lookUpContentRuleList(forIdentifier: Self.identifier) { [weak self] list, _ in
            if let list {
                self?.install(list)
                return
            }
            store.compileContentRuleList(forIdentifier: Self.identifier,
                                         encodedContentRuleList: Self.rulesJSON()) { list, error in
                if let error { NSLog("Hush ad blocker failed to compile: \(error)") }
                if let list { self?.install(list) }
            }
        }
    }

    func attach(to webView: WKWebView) {
        let controller = webView.configuration.userContentController
        controllers.add(controller)
        if enabled, let ruleList { controller.add(ruleList) }
    }

    /// Re-applies the on/off setting to every open tab.
    func refresh() {
        guard let ruleList else { return }
        for controller in controllers.allObjects {
            controller.remove(ruleList)
            if enabled { controller.add(ruleList) }
        }
    }

    private func install(_ list: WKContentRuleList) {
        DispatchQueue.main.async {
            self.ruleList = list
            self.refresh()
        }
    }

    // MARK: Rules

    /// Ad networks and trackers, blocked when a site loads them from elsewhere.
    static let blockedDomains = [
        // Google ads & analytics
        "doubleclick.net", "googlesyndication.com", "googleadservices.com", "google-analytics.com",
        "googletagservices.com", "googletagmanager.com", "adservice.google.com", "pagead2.googlesyndication.com",
        "imasdk.googleapis.com",
        // Ad exchanges & networks
        "adnxs.com", "adsrvr.org", "advertising.com", "amazon-adsystem.com", "adform.net", "adroll.com",
        "criteo.com", "criteo.net", "casalemedia.com", "openx.net", "pubmatic.com", "rubiconproject.com",
        "smartadserver.com", "taboola.com", "outbrain.com", "revcontent.com", "mgid.com", "media.net",
        "teads.tv", "triplelift.com", "sharethrough.com", "33across.com", "indexww.com", "yieldmo.com",
        "contextweb.com", "bidswitch.net", "sovrn.com", "lijit.com", "gumgum.com", "spotxchange.com",
        "spotx.tv", "springserve.com", "zedo.com", "adition.com", "adtech.com", "yieldlab.net",
        "adzerk.net", "carbonads.com", "buysellads.com", "propellerads.com", "popads.net", "popcash.net",
        "exoclick.com", "juicyads.com", "trafficjunky.net", "adsterra.com", "hilltopads.net",
        "admob.com", "applovin.com", "unityads.unity3d.com", "inmobi.com", "smaato.net", "mopub.com",
        "serving-sys.com", "flashtalking.com", "innovid.com", "moatads.com", "doubleverify.com",
        "adsafeprotected.com", "ads.yahoo.com", "advertising.yahoo.com", "ads.twitter.com",
        "ads-api.twitter.com", "ads.linkedin.com", "ads.pinterest.com", "ads.tiktok.com",
        "analytics.tiktok.com", "an.facebook.com",
        // Trackers & analytics
        "scorecardresearch.com", "quantserve.com", "quantcount.com", "chartbeat.com", "chartbeat.net",
        "hotjar.com", "mouseflow.com", "crazyegg.com", "fullstory.com", "luckyorange.com",
        "mixpanel.com", "segment.io", "segment.com", "amplitude.com", "heap.io", "heapanalytics.com",
        "kissmetrics.com", "newrelic.com", "nr-data.net", "optimizely.com", "branch.io",
        "bluekai.com", "krxd.net", "demdex.net", "omtrdc.net", "everesttech.net", "agkn.com",
        "rlcdn.com", "exelator.com", "eyeota.net", "tapad.com", "mathtag.com", "adsymptotic.com",
        "bounceexchange.com", "bouncex.net", "parsely.com", "statcounter.com", "clicky.com",
        "addthis.com", "sharethis.com", "zemanta.com", "yieldify.com", "liadm.com", "id5-sync.com",
        "connect.facebook.net", "pixel.facebook.com", "bat.bing.com", "clarity.ms",
        "static.ads-twitter.com", "snap.licdn.com", "px.ads.linkedin.com", "ct.pinterest.com",
        "sc-static.net", "tr.snapchat.com",
    ]

    /// Common ad slots hidden on every page, so blocked ads don't leave empty boxes.
    static let hiddenSelectors = [
        "ins.adsbygoogle", ".adsbygoogle", "[id^='google_ads_iframe']", "[id^='div-gpt-ad']",
        "[data-google-query-id]", ".ad-slot", ".ad-banner", ".ad-container", ".adsbox",
        ".advertisement", "[aria-label='Advertisement']", ".taboola", "[id^='taboola-']",
        ".OUTBRAIN", "[data-widget-id^='outbrain']", ".sponsored-content",
    ]

    static func rulesJSON() -> String {
        var rules: [[String: Any]] = blockedDomains.map { domain in
            let escaped = domain.replacingOccurrences(of: ".", with: "\\.")
            let rule: [String: Any] = [
                "trigger": [
                    "url-filter": "^[^:]+://+([^:/]+\\.)?\(escaped)[/:]",
                    "load-type": ["third-party"],
                ] as [String: Any],
                "action": ["type": "block"],
            ]
            return rule
        }
        rules.append([
            "trigger": ["url-filter": ".*"],
            "action": ["type": "css-display-none", "selector": hiddenSelectors.joined(separator: ", ")],
        ])
        let data = try! JSONSerialization.data(withJSONObject: rules)
        return String(data: data, encoding: .utf8)!
    }
}
