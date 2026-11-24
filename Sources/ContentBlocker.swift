import WebKit
import Combine

/// A filter list the user added (from a file or a web address).
struct FilterList: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var sourceURL: URL?
    var ruleCount: Int
    var skippedCount: Int
    var format: String
    var enabled = true
    var updatedAt = Date()
    /// FilterConverter.version that produced this list's rules (nil = version 1).
    var converterVersion: Int?

    var isOutdated: Bool { (converterVersion ?? 1) < FilterConverter.version }

    var identifier: String { "hush-list-\(id.uuidString)" }
}

/// Everything Hush blocks, built on WebKit's content blocker (the engine behind
/// Safari's ad-block extensions). Rules are compiled once and cached by WebKit,
/// so blocking costs almost nothing while you browse.
final class ContentBlocker: ObservableObject {
    static let shared = ContentBlocker()

    @Published private(set) var lists: [FilterList] = []
    /// Sites where the user switched shields off.
    @Published private(set) var shieldsDown: [String] = []
    @Published private(set) var isWorking = false
    @Published var status: String?
    @Published var statusIsError = false

    private var compiled: [String: WKContentRuleList] = [:]
    private let controllers = NSHashTable<WKUserContentController>.weakObjects()
    private let hostOf = NSMapTable<WKUserContentController, NSString>.weakToStrongObjects()
    private let folder: URL
    private var settingsObserver: AnyCancellable?
    private var store: WKContentRuleListStore { WKContentRuleListStore.default() }

    private init() {
        folder = AppPaths.support.appendingPathComponent("Filters", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: folder.appendingPathComponent("lists.json")),
           let saved = try? JSONDecoder().decode([FilterList].self, from: data) {
            lists = saved
        }
        shieldsDown = UserDefaults.standard.stringArray(forKey: "shieldsDown") ?? []

        // Re-apply rules when (and only when) a blocking setting changes.
        lastSignature = Self.settingsSignature()
        settingsObserver = NotificationCenter.default
            .publisher(for: UserDefaults.didChangeNotification)
            .debounce(for: .milliseconds(150), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                let signature = Self.settingsSignature()
                if signature != self.lastSignature {
                    self.lastSignature = signature
                    self.refresh()
                }
            }
    }

    private var lastSignature = ""

    private static func settingsSignature() -> String {
        [Prefs.adBlockEnabled, Prefs.trackerBlockEnabled, Prefs.hideCookieBanners, Prefs.collapseAdSpace, Prefs.autoRejectCookies,
         Prefs.autofillPasswords, Prefs.autofillCards, Prefs.autofillContact,
         Prefs.blockThirdPartyCookies, Prefs.httpsUpgrade, Prefs.globalPrivacyControl,
         Prefs.fingerprintProtection, Prefs.deAMP, Prefs.blockAnnoyances, Prefs.blockChatWidgets]
            .map { Prefs.bool($0) ? "1" : "0" }.joined() + Prefs.string(Prefs.blockingMode)
            + Prefs.string(Prefs.scriptPolicy) + Prefs.string(Prefs.fingerprintMode) + Prefs.string(Prefs.cookiePolicy)
            + Prefs.string(ShieldSettings.sitesKey)
    }

    // MARK: Setup

    func prepare() {
        store.removeContentRuleList(forIdentifier: "hush-adblock-v1") { _ in } // from version 0.1.0
        for builtIn in BuiltInRules.allCases {
            loadCompiled(builtIn.identifier) { builtIn.json }
        }
        if ElementZapper.shared.rulesJSON != nil {
            loadCompiled(ElementZapper.ruleIdentifier) { ElementZapper.shared.rulesJSON }
        }
        for list in lists {
            if list.isOutdated {
                // Converted by an older, buggy converter: never load those rules.
                if let source = list.sourceURL {
                    importFromWeb(source, name: list.name)
                } else if let i = lists.firstIndex(where: { $0.id == list.id }) {
                    lists[i].enabled = false
                    saveLists()
                    status = "“\(list.name)” was turned off because an older version of Hush converted it incorrectly. Please import it again."
                    statusIsError = true
                }
                store.removeContentRuleList(forIdentifier: list.identifier) { _ in }
                continue
            }
            let file = jsonFile(for: list)
            loadCompiled(list.identifier) { try? String(contentsOf: file, encoding: .utf8) }
        }
    }

    /// Uses WebKit's cached compiled list, or compiles it again if the cache was cleared.
    private func loadCompiled(_ identifier: String, source: @escaping () -> String?) {
        store.lookUpContentRuleList(forIdentifier: identifier) { [weak self] list, _ in
            if let list {
                self?.install(list, as: identifier)
                return
            }
            guard let json = source() else { return }
            self?.store.compileContentRuleList(forIdentifier: identifier, encodedContentRuleList: json) { list, error in
                if let list { self?.install(list, as: identifier) }
                if let error { NSLog("Hush: couldn't compile \(identifier): \(error)") }
            }
        }
    }

    private func install(_ list: WKContentRuleList, as identifier: String) {
        DispatchQueue.main.async {
            self.compiled[identifier] = list
            self.refresh()
        }
    }

    // MARK: Applying to tabs

    func attach(_ controller: WKUserContentController) {
        controllers.add(controller)
        configure(controller)
    }

    /// Called as a tab starts loading a page, so per-site shields apply to it.
    func update(_ controller: WKUserContentController, forHost host: String?) {
        let old = hostOf.object(forKey: controller) as String?
        if let host { hostOf.setObject(host as NSString, forKey: controller) } else { hostOf.removeObject(forKey: controller) }
        let shields = ShieldSettings.shared
        if old.map(isShieldsDown) != host.map(isShieldsDown) || old == nil || shields.effective(for: old) != shields.effective(for: host) {
            configure(controller)
        }
    }

    #if SNAPSHOT
    #endif

    func refresh() {
        for controller in controllers.allObjects { configure(controller) }
    }

    /// The rule lists a page gets with these protections.
    private func identifiers(for shields: Shields) -> [String] {
        var ids: [String] = []
        if shields.blocking != .off {
            if Prefs.bool(Prefs.adBlockEnabled) { ids.append(BuiltInRules.ads.identifier) }
            if Prefs.bool(Prefs.trackerBlockEnabled) { ids.append(BuiltInRules.trackers.identifier) }
            if shields.blocking == .strict { ids.append(BuiltInRules.strict.identifier) }
            if Prefs.bool(Prefs.blockAnnoyances) { ids.append(BuiltInRules.annoyances.identifier) }
            if Prefs.bool(Prefs.blockChatWidgets) { ids.append(BuiltInRules.chatWidgets.identifier) }
            ids += lists.filter { $0.enabled && !$0.isOutdated }.map(\.identifier)
        }
        switch shields.cookies {
        case .blockThirdParty: ids.append(BuiltInRules.thirdPartyCookies.identifier)
        case .blockAll: ids.append(BuiltInRules.allCookies.identifier)
        case .allowAll: break
        }
        if shields.scripts == .blockThirdParty { ids.append(BuiltInRules.thirdPartyScripts.identifier) }
        ids.append(ElementZapper.ruleIdentifier)
        return ids
    }

    /// Element Zapper's per-site hiding rules (nil when nothing is hidden).
    func installZapperRules(_ json: String?) {
        let id = ElementZapper.ruleIdentifier
        guard let json else {
            compiled[id] = nil
            store.removeContentRuleList(forIdentifier: id) { _ in }
            refresh()
            return
        }
        store.compileContentRuleList(forIdentifier: id, encodedContentRuleList: json) { [weak self] list, error in
            if let error { NSLog("Hush: Element Zapper rules failed: \(error)") }
            if let list { self?.install(list, as: id) }
        }
    }

    private func configure(_ controller: WKUserContentController) {
        controller.removeAllContentRuleLists()
        controller.removeAllUserScripts()
        let host = hostOf.object(forKey: controller) as String?
        // The site's switch in the Hush Guard panel turns everything off for it; otherwise
        // your defaults apply, with any of the site's own settings on top.
        let shieldsOn = !(host.map(isShieldsDown) ?? false)
        if shieldsOn {
            let shields = ShieldSettings.shared.effective(for: host)
            switch shields.fingerprinting {
            case .standard: controller.addUserScript(Fingerprinting.standard)
            case .strict: controller.addUserScript(Fingerprinting.strict)
            case .off: break
            }
            for id in identifiers(for: shields) {
                if let list = compiled[id] { controller.add(list) }
            }
            if shields.blocking != .off {
                if Prefs.bool(Prefs.autoRejectCookies) { controller.addUserScript(UserScripts.rejectCookieBanners) }
                if Prefs.bool(Prefs.hideCookieBanners) { controller.addUserScript(UserScripts.hideCookieBanners) }
                if Prefs.bool(Prefs.collapseAdSpace) && (Prefs.bool(Prefs.adBlockEnabled) || lists.contains(where: \.enabled)) {
                    controller.addUserScript(UserScripts.collapseAdSpace)
                }
            }
        }
        // Secure connections are a privacy setting of their own, kept even when Hush Guard is off.
        if Prefs.bool(Prefs.httpsUpgrade), let list = compiled[BuiltInRules.httpsUpgrade.identifier] { controller.add(list) }
        if Prefs.bool(Prefs.globalPrivacyControl) { controller.addUserScript(UserScripts.globalPrivacyControl) }
        if CleanLinks.deAMPEnabled { controller.addUserScript(CleanLinks.deAMPScript) }
        if AutofillCenter.isEnabled { controller.addUserScript(AutofillCenter.script) }
    }

    // MARK: Per-site shields

    static func normalize(_ host: String) -> String {
        host.lowercased().strippingWWW
    }

    func isShieldsDown(_ host: String) -> Bool {
        let h = Self.normalize(host)
        return shieldsDown.contains { h == $0 || h.hasSuffix("." + $0) }
    }

    func setShields(_ up: Bool, for host: String) {
        let h = Self.normalize(host)
        if up {
            shieldsDown.removeAll { h == $0 || h.hasSuffix("." + $0) }
        } else if !isShieldsDown(h) {
            shieldsDown.append(h)
            shieldsDown.sort()
        }
        UserDefaults.standard.set(shieldsDown, forKey: "shieldsDown")
        for controller in controllers.allObjects { configure(controller) }
    }

    // MARK: Filter lists

    private func jsonFile(for list: FilterList) -> URL {
        folder.appendingPathComponent("\(list.id.uuidString).json")
    }

    private func saveLists() {
        if let data = try? JSONEncoder().encode(lists) {
            try? data.write(to: folder.appendingPathComponent("lists.json"), options: .atomic)
        }
    }

    func importFile(_ url: URL, name customName: String? = nil) {
        let name = customName ?? url.deletingPathExtension().lastPathComponent
        Task {
            do {
                let data = try Data(contentsOf: url)
                await importList(data: data, name: name, source: nil)
            } catch {
                await report("Couldn't read that file: \(error.localizedDescription)", error: true)
            }
        }
    }

    func importFromWeb(_ address: URL, name: String? = nil) {
        // Always over HTTPS: a list fetched in the clear could be swapped on the way to switch
        // blocking off (or hide parts of pages).
        var url = address
        if url.scheme?.lowercased() == "http", var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            parts.scheme = "https"
            url = parts.url ?? url
        }
        guard url.scheme?.lowercased() == "https", url.host != nil else {
            Task { await report("Filter lists must come from a secure (https) web address.", error: true) }
            return
        }
        Task {
            await MainActor.run { self.isWorking = true; self.statusIsError = false; self.status = "Downloading…" }
            do {
                var request = URLRequest(url: url)
                request.timeoutInterval = 60
                let (data, response) = try await URLSession.shared.data(for: request)
                guard data.count < 60_000_000 else {
                    throw NSError(domain: "Hush", code: 413, userInfo: [NSLocalizedDescriptionKey: "That list is too large."])
                }
                if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                    throw NSError(domain: "Hush", code: http.statusCode, userInfo: [
                        NSLocalizedDescriptionKey: "The server answered with error \(http.statusCode).",
                    ])
                }
                await importList(data: data, name: name ?? url.host ?? "Filter list", source: url)
            } catch {
                await report("Couldn't download the list: \(error.localizedDescription)", error: true)
            }
        }
    }

    /// Refreshes web lists more than a week old, one at a time, spaced out so nothing slows down.
    func updateStaleLists() {
        guard Prefs.bool(Prefs.autoUpdateLists) else { return }
        let stale = lists.filter { $0.enabled && $0.sourceURL != nil && Date().timeIntervalSince($0.updatedAt) > 7 * 86_400 }
        for (i, list) in stale.prefix(10).enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 45) { [weak self] in
                guard let self, Prefs.bool(Prefs.autoUpdateLists), !self.isWorking else { return }
                self.update(list)
            }
        }
    }

    private var listTimer: Timer?

    /// Checks shortly after launch, then once a day while Hush stays open.
    func startListUpdates() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 90) { [weak self] in self?.updateStaleLists() }
        listTimer = Timer.scheduledTimer(withTimeInterval: 86_400, repeats: true) { [weak self] _ in self?.updateStaleLists() }
        listTimer?.tolerance = 3_600
    }

    func update(_ list: FilterList) {
        guard let source = list.sourceURL else { return }
        importFromWeb(source, name: list.name)
    }

    private func importList(data: Data, name: String, source: URL?) async {
        await MainActor.run { self.isWorking = true; self.statusIsError = false; self.status = "Converting rules…" }
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            await report("That file isn't a text filter list.", error: true)
            return
        }
        do {
            let output = try await Task.detached(priority: .userInitiated) {
                try FilterConverter.convert(text)
            }.value

            // Re-adding the same list (same web address, or a file with the same name)
            // updates it in place instead of adding a duplicate.
            let listName = output.title ?? name
            let existing = await MainActor.run {
                self.lists.first {
                    source != nil ? $0.sourceURL == source : ($0.sourceURL == nil && $0.name == listName)
                }
            }
            var list = existing ?? FilterList(name: name, ruleCount: 0, skippedCount: 0, format: output.format)
            list.name = output.title ?? existing?.name ?? name
            list.sourceURL = source
            list.ruleCount = output.ruleCount
            list.skippedCount = output.skipped
            list.format = output.format
            list.updatedAt = Date()
            list.converterVersion = FilterConverter.version

            await MainActor.run { self.status = "Compiling \(output.ruleCount.formatted()) rules…" }
            let compiledList = try await compile(list.identifier, json: output.json)
            try output.json.write(to: jsonFile(for: list), atomically: true, encoding: .utf8)

            let finished = list
            await MainActor.run {
                self.compiled[finished.identifier] = compiledList
                if let i = self.lists.firstIndex(where: { $0.id == finished.id }) {
                    self.lists[i] = finished
                } else {
                    self.lists.append(finished)
                }
                self.saveLists()
                self.refresh()
            }
            var message = "\(existing == nil ? "Added" : "Updated") “\(finished.name)” — \(output.ruleCount.formatted()) rules"
            if output.skipped > 0 { message += " (\(output.skipped.formatted()) advanced rules skipped)" }
            await report(message, error: false)
        } catch {
            await report(error.localizedDescription, error: true)
        }
    }

    private func compile(_ identifier: String, json: String) async throws -> WKContentRuleList {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.main.async {
                self.store.compileContentRuleList(forIdentifier: identifier, encodedContentRuleList: json) { list, error in
                    if let list {
                        continuation.resume(returning: list)
                    } else {
                        continuation.resume(throwing: error ?? NSError(domain: "Hush", code: 1, userInfo: [
                            NSLocalizedDescriptionKey: "WebKit couldn't use this list.",
                        ]))
                    }
                }
            }
        }
    }

    private func report(_ message: String, error: Bool) async {
        await MainActor.run {
            self.isWorking = false
            self.status = message
            self.statusIsError = error
        }
    }

    func setEnabled(_ list: FilterList, _ enabled: Bool) {
        guard let i = lists.firstIndex(where: { $0.id == list.id }) else { return }
        lists[i].enabled = enabled
        saveLists()
        refresh()
    }

    func remove(_ list: FilterList) {
        lists.removeAll { $0.id == list.id }
        compiled[list.identifier] = nil
        saveLists()
        refresh()
        try? FileManager.default.removeItem(at: jsonFile(for: list))
        store.removeContentRuleList(forIdentifier: list.identifier) { _ in }
    }
}

// MARK: - Built-in protection

enum BuiltInRules: String, CaseIterable {
    case ads, trackers, thirdPartyCookies, httpsUpgrade, strict, allCookies, thirdPartyScripts, annoyances, chatWidgets

    var identifier: String { "hush-\(rawValue)-v2" }

    var json: String {
        let rules: [[String: Any]]
        switch self {
        case .ads:
            rules = Self.adDomains.map(Self.blockThirdParty) + [[
                "trigger": ["url-filter": ".*"],
                "action": ["type": "css-display-none", "selector": Self.adSelectors.joined(separator: ", ")],
            ]]
        case .trackers:
            rules = Self.trackerDomains.map(Self.blockThirdParty)
        case .thirdPartyCookies:
            rules = [[
                "trigger": ["url-filter": ".*", "load-type": ["third-party"]] as [String: Any],
                "action": ["type": "block-cookies"],
            ]]
        case .strict:
            // Strict: social widgets, fingerprinting services, tracking pings and all third-party cookies.
            // Strict: social widgets, fingerprinting services and tracking pings.
            rules = Self.strictDomains.map(Self.blockThirdParty) + [
                ["trigger": ["url-filter": ".*", "resource-type": ["ping"], "load-type": ["third-party"]] as [String: Any],
                 "action": ["type": "block"]],
            ]
        case .allCookies:
            rules = [[
                "trigger": ["url-filter": ".*"] as [String: Any],
                "action": ["type": "block-cookies"],
            ]]
        case .annoyances:
            // "Sign in with Google" pop-ups, push-notification prompts and newsletter pop-ups.
            rules = Self.annoyanceDomains.map(Self.blockThirdParty) + [[
                "trigger": ["url-filter": ".*"],
                "action": ["type": "css-display-none", "selector": Self.annoyanceSelectors.joined(separator: ", ")],
            ]]
        case .chatWidgets:
            rules = Self.chatDomains.map(Self.blockThirdParty)
        case .thirdPartyScripts:
            rules = [[
                "trigger": ["url-filter": ".*", "resource-type": ["script"], "load-type": ["third-party"]] as [String: Any],
                "action": ["type": "block"],
            ]]
        case .httpsUpgrade:
            rules = [[
                "trigger": ["url-filter": "^http://", "unless-domain": ["localhost", "*.local", "*.localhost", "*.test"]] as [String: Any],
                "action": ["type": "make-https"],
            ]]
        }
        let data = try! JSONSerialization.data(withJSONObject: rules)
        return String(data: data, encoding: .utf8)!
    }

    static func blockThirdParty(_ domain: String) -> [String: Any] {
        [
            "trigger": [
                "url-filter": FilterConverter.domainFilter(domain),
                "load-type": ["third-party"],
            ] as [String: Any],
            "action": ["type": "block"],
        ]
    }

    static let adDomains = [
        "doubleclick.net", "googlesyndication.com", "googleadservices.com", "googletagservices.com",
        "adservice.google.com", "imasdk.googleapis.com",
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
        "ads-api.twitter.com", "ads.linkedin.com", "ads.pinterest.com", "ads.tiktok.com", "an.facebook.com",
        "zemanta.com",
    ]

    static let trackerDomains = [
        "google-analytics.com", "googletagmanager.com", "analytics.tiktok.com",
        "scorecardresearch.com", "quantserve.com", "quantcount.com", "chartbeat.com", "chartbeat.net",
        "hotjar.com", "mouseflow.com", "crazyegg.com", "fullstory.com", "luckyorange.com",
        "mixpanel.com", "segment.io", "segment.com", "amplitude.com", "heap.io", "heapanalytics.com",
        "kissmetrics.com", "nr-data.net", "optimizely.com", "branch.io",
        "bluekai.com", "krxd.net", "demdex.net", "omtrdc.net", "everesttech.net", "agkn.com",
        "rlcdn.com", "exelator.com", "eyeota.net", "tapad.com", "mathtag.com", "adsymptotic.com",
        "bounceexchange.com", "bouncex.net", "parsely.com", "statcounter.com", "clicky.com",
        "addthis.com", "sharethis.com", "yieldify.com", "liadm.com", "id5-sync.com",
        "connect.facebook.net", "pixel.facebook.com", "bat.bing.com", "clarity.ms",
        "static.ads-twitter.com", "snap.licdn.com", "px.ads.linkedin.com", "ct.pinterest.com",
        "sc-static.net", "tr.snapchat.com",
    ]

    static let strictDomains = [
        "platform.twitter.com", "platform.x.com", "syndication.twitter.com", "widgets.pinterest.com",
        "assets.pinterest.com", "platform.linkedin.com", "static.addtoany.com", "s7.addthis.com",
        "fingerprintjs.com", "fpjs.io", "fpcdn.io", "fpnpmcdn.net", "tiqcdn.com", "ensighten.com",
        "js-agent.newrelic.com", "ingest.sentry.io", "cdn.mxpnl.com", "js.hs-analytics.net",
        "googleoptimize.com", "cdn.segment.com", "cdn.heapanalytics.com", "static.hotjar.com",
        "s.pinimg.com", "sb.scorecardresearch.com", "cdn.taboola.com", "widgets.outbrain.com",
    ]

    /// Push-notification and newsletter pop-up services. (Google's One Tap is hidden rather than
    /// blocked, so "Sign in with Google" buttons keep working.)
    static let annoyanceDomains = [
        "cdn.onesignal.com", "onesignal.com", "pushcrew.com", "pushengage.com", "izooto.com", "webpushr.com",
        "aimtell.com", "pushowl.com", "notix.io", "subscribers.com", "truepush.com", "gravitec.net",
        "widget.privy.com", "load.sumo.com", "a.omappapi.com", "poptin.com", "loader.wisepops.com",
        "a.mailmunch.co", "my.hellobar.com", "sleeknotecustomerscripts.sleeknote.com", "l.getsitecontrol.com",
    ]
    static let annoyanceSelectors = [
        "#credential_picker_container", "#credential_picker_iframe", "iframe[src*='accounts.google.com/gsi/iframe']",
        "#onesignal-slidedown-container", "#onesignal-bell-container", "#onesignal-popover-container",
        ".pushcrew-chrome-style-notification", "#pe-subscribe-popup", ".izooto-optin",
    ]
    static let chatDomains = [
        "widget.intercom.io", "js.intercomcdn.com", "js.driftt.com", "embed.tawk.to", "client.crisp.chat",
        "wchat.freshchat.com", "cdn.livechatinc.com", "code.tidio.co", "js.usemessages.com", "static.olark.com",
    ]

    static let adSelectors = [
        "ins.adsbygoogle", ".adsbygoogle", "[id^='google_ads_iframe']", "[id^='div-gpt-ad']",
        "[data-google-query-id]", ".ad-slot", ".ad-banner", ".ad-container", ".adsbox",
        ".advertisement", "[aria-label='Advertisement']", ".taboola", "[id^='taboola-']",
        ".OUTBRAIN", "[data-widget-id^='outbrain']", ".sponsored-content",
    ]

    /// What a blocked request counts as in the statistics.
    enum Category { case ads, trackers, lists, other }

    static func category(of identifier: String) -> Category {
        if identifier.hasPrefix("hush-ads") || identifier.hasPrefix("hush-annoyances") || identifier.hasPrefix("hush-chatWidgets") { return .ads }
        if identifier.hasPrefix("hush-trackers") || identifier.hasPrefix("hush-strict") { return .trackers }
        if identifier.hasPrefix("hush-list-") { return .lists }
        return .other
    }
}

enum UserScripts {
    /// Global Privacy Control: tells sites you don't want your data sold or shared.
    static let globalPrivacyControl = WKUserScript(
        source: "try{Object.defineProperty(Navigator.prototype,'globalPrivacyControl',{get:()=>true,configurable:true})}catch(e){}",
        injectionTime: .atDocumentStart, forMainFrameOnly: false)

    static let cookieBannerSelectors = [
        "#onetrust-consent-sdk", "#onetrust-banner-sdk", "#CybotCookiebotDialog", "#CybotCookiebotDialogBodyUnderlay",
        "#qc-cmp2-container", ".qc-cmp2-container", "#didomi-host", ".fc-consent-root", "[id^='sp_message_container']",
        "#usercentrics-root", "#truste-consent-track", "#truste-consent-content", ".truste_overlay", ".truste_box_overlay",
        "#cookie-law-info-bar", ".cc-window", ".cc-banner", "#cookiescript_injected", "#cmpbox", "#cmpbox2",
        ".cmp-root", "#consent_blackbar", "#iubenda-cs-banner", ".osano-cm-window", "#termly-code-snippet-support",
        "#hs-eu-cookie-confirmation", ".evidon-banner", "#gdpr-consent-tool-wrapper", "#cookie-banner", ".cookie-banner",
    ]

    /// Closes up the gaps blocked ads leave behind: empty ad slots that keep their
    /// reserved height, and "Advertisement" / "Sponsored" captions left on their own.
    /// Only touches elements that are clearly ads (by name) or that contain nothing but
    /// an ad label — never anything with real content in it.
    static let collapseAdSpace = WKUserScript(source: #"""
    (function () {
      if (window.__hushCollapse) return; window.__hushCollapse = true;
      var AD_NAME = /(^|[\s_-])(ad|ads|advert|adverts|advertisement|advertising|adslot|adunit|adbox|adsbox|adcontainer|adwrapper|adholder|adspace|adzone|adblock-placeholder|banner-ad)([\s_-]|\d|$)/i;
      var LABEL = /^\s*(advertisement|advertisements|advertising|ad|ads|sponsored|sponsored content|promoted|paid content|anzeige|werbung|publicit[ée]|publicidad|pubblicit[àa]|reclame|advertentie)\s*$/i;

      function hide(el) {
        if (!el || el === document.body || el === document.documentElement || el.dataset.hushCollapsed) return;
        el.dataset.hushCollapsed = '1';
        el.style.setProperty('display', 'none', 'important');
      }
      // textContent, not innerText: innerText makes the page lay itself out again.
      function ownText(el) {
        return (el.textContent || '').replace(/\s+/g, ' ').trim();
      }
      // "Real content": visible text that isn't just an ad label, or a loaded image/video.
      function hasRealContent(el) {
        var text = ownText(el);
        if (text && !LABEL.test(text) && text.length > 0) {
          if (text.length > 160) return true;
          var stripped = text.replace(/advertisement|advertising|sponsored|ads?\b|close|report( this)? ad|skip/gi, '').trim();
          if (stripped.length > 2) return true;
        }
        var media = el.querySelectorAll('img, video, picture, canvas');
        for (var i = 0; i < media.length; i++) {
          var m = media[i], r = m.getBoundingClientRect();
          if (r.width > 40 && r.height > 40 && !(m.tagName === 'IMG' && m.naturalWidth === 0)) return true;
        }
        return false;
      }
      function isAdNamed(el) {
        var name = (typeof el.className === 'string' ? el.className : '') + ' ' + (el.id || '');
        return AD_NAME.test(name) || el.hasAttribute('data-ad') || el.hasAttribute('data-ad-slot') ||
               el.hasAttribute('data-adunit') || el.hasAttribute('data-google-query-id') ||
               (el.id || '').indexOf('google_ads') === 0 || (el.id || '').indexOf('div-gpt-ad') === 0;
      }

      // Standard ad-slot heights (IAB sizes). An empty box reserving exactly one of these,
      // on a page where Hush blocked ads, is almost certainly a dead ad slot.
      var AD_HEIGHTS = [50, 60, 90, 100, 250, 280, 600];
      function isDeadSlot(el) {
        var cs = getComputedStyle(el);
        var reserved = Math.round(parseFloat(cs.minHeight) || 0);
        if (AD_HEIGHTS.indexOf(reserved) < 0) return false;
        if (el.querySelector('a[href], button, input, select, textarea, video, canvas, svg')) return false;
        return !hasRealContent(el);
      }
      function sweepDeadSlots() {
        if (!window.__hushAdsBlocked) return;
        var boxes = document.querySelectorAll('div, section, aside');
        for (var i = 0; i < boxes.length; i++) {
          var el = boxes[i];
          if (!el.dataset.hushCollapsed && el.offsetParent !== null && isDeadSlot(el)) hide(el);
        }
      }
      // Nothing happens until Hush reports a blocked ad on this page (pages without ads pay nothing).
      var active = false, sweeps = 0;
      var idle = window.requestIdleCallback || function (f) { return setTimeout(f, 200); };
      window.__hushSweep = function () {
        if (!active) {
          active = true;
          if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', start); else start();
        }
        idle(function () { sweep(); sweepDeadSlots(); });
      };
      function start() {
        if (!document.body) return;
        new MutationObserver(schedule).observe(document.body, { childList: true, subtree: true });
        window.addEventListener('load', function () { setTimeout(window.__hushSweep, 1500); });
        schedule();
      }

      function sweep() {
        // 1. Containers named as ads that now hold nothing real (blocked or never filled).
        var candidates = document.querySelectorAll('[class*="ad" i], [id*="ad" i], [data-ad], [data-ad-slot], [data-adunit], [data-google-query-id]');
        for (var i = 0; i < candidates.length; i++) {
          var el = candidates[i];
          if (el.dataset.hushCollapsed || !isAdNamed(el)) continue;
          if (!hasRealContent(el)) hide(el);
        }
        // 2. Lone "Advertisement" captions, plus the empty wrapper around them.
        var walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT, {
          acceptNode: function (n) { return LABEL.test(n.nodeValue) ? NodeFilter.FILTER_ACCEPT : NodeFilter.FILTER_SKIP; }
        });
        var labels = [];
        while (walker.nextNode()) labels.push(walker.currentNode.parentElement);
        labels.forEach(function (label) {
          if (!label || label.dataset.hushCollapsed) return;
          // Climb to the largest ancestor (max 4 levels) that still holds nothing but the label.
          var target = label, node = label;
          for (var depth = 0; depth < 4 && node.parentElement && node.parentElement !== document.body; depth++) {
            node = node.parentElement;
            if (hasRealContent(node)) break;
            target = node;
          }
          if (!hasRealContent(target)) hide(target);
        });
      }

      // At most one scan every 0.8 s, in idle time, never in a background tab, and at most 25
      // per page (endless feeds stop costing anything after that).
      var timer = null;
      function schedule() {
        if (!active || timer || document.hidden || sweeps >= 25) return;
        timer = setTimeout(function () { timer = null; sweeps++; idle(sweep); }, 800);
      }
      document.addEventListener('visibilitychange', function () { if (!document.hidden) schedule(); });
    })();
    """#, injectionTime: .atDocumentStart, forMainFrameOnly: true, in: .defaultClient)

    /// Clicks "Reject all" on cookie-consent pop-ups (OneTrust, Cookiebot, Didomi, Quantcast,
    /// Usercentrics, Sourcepoint, TrustArc and lookalikes). It only ever clicks inside a recognised
    /// consent pop-up, and only buttons whose text clearly means reject/decline.
    static let rejectCookieBanners = WKUserScript(source: #"""
    (function () {
      if (window.__hushReject) return; window.__hushReject = true;
      // Direct "reject" buttons of the big consent tools.
      var DIRECT = [
        '#onetrust-reject-all-handler', '.ot-pc-refuse-all-handler',
        '#CybotCookiebotDialogBodyButtonDecline', '#CybotCookiebotDialogBodyLevelButtonLevelOptinDeclineAll',
        '#didomi-notice-disagree-button', '.didomi-continue-without-agreeing',
        'button[data-testid="uc-deny-all-button"]', '#truste-consent-required', '.truste-consent-required',
        '.cc-deny', '.cmpboxbtnno', '#cookiescript_reject', '.iubenda-cs-reject-btn', '.osano-cm-denyAll',
        '[data-cookiefirst-action="reject"]', '.fc-cta-do-not-consent', '#hs-eu-decline-button',
        'button[mode="secondary"][aria-label*="reject" i]', '.sp_choice_type_REJECT_ALL', '.sp_choice_type_13'
      ];
      // Where consent pop-ups live; generic text matching only happens inside these.
      var CONTAINERS = '[id*="cookie" i], [class*="cookie" i], [id*="consent" i], [class*="consent" i], ' +
        '[id*="gdpr" i], [class*="gdpr" i], [id*="cmp" i], [class*="cmp" i], [id^="sp_message"], [class*="privacy-banner" i], ' +
        '[aria-label*="cookie" i], [aria-label*="consent" i], [aria-label*="privacy" i], [role="dialog"], [aria-modal="true"]';
      var REJECT = /^\s*(reject all|reject all cookies|reject|reject non-essential( cookies)?|reject optional cookies|reject additional( cookies)?|reject unnecessary( cookies)?|decline additional( cookies)?|decline|decline all|decline optional cookies|deny|deny all|refuse|refuse all|disagree|i disagree|do not accept|don['’]t accept|necessary (cookies )?only|only necessary( cookies)?|use necessary cookies only|accept (only )?(strictly )?necessary( cookies)?|continue without (accepting|agreeing)|nur notwendige|alle ablehnen|ablehnen|tout refuser|refuser|rechazar( todo)?|rifiuta( tutto)?|weigeren|alles weigeren)\s*$/i;
      var done = false;

      function visible(el) { var r = el.getBoundingClientRect(); return r.width > 0 && r.height > 0; }
      function press(el) {
        if (!el || done || !visible(el)) return false;
        el.click();
        done = true;
        return true;
      }
      function inShadow(root, sel) {
        var found = root.querySelector(sel);
        if (found) return found;
        var hosts = root.querySelectorAll('*');
        for (var i = 0; i < hosts.length; i++) {
          if (hosts[i].shadowRoot) { var f = inShadow(hosts[i].shadowRoot, sel); if (f) return f; }
        }
        return null;
      }
      function attempt() {
        if (done) return;
        for (var i = 0; i < DIRECT.length; i++) {
          if (press(document.querySelector(DIRECT[i]))) return;
        }
        var uc = document.querySelector('#usercentrics-root');
        if (uc && uc.shadowRoot && press(inShadow(uc.shadowRoot, 'button[data-testid="uc-deny-all-button"]'))) return;
        var boxes = document.querySelectorAll(CONTAINERS);
        for (var b = 0; b < boxes.length; b++) {
          var box = boxes[b];
          // textContent, not innerText: reading innerText makes the page lay itself out again.
          if (!/cookie|consent|privacy|gdpr|tracking|personal data|partners/i.test((box.textContent || '').slice(0, 4000))) continue;
          var buttons = box.querySelectorAll('button, [role="button"], a[href="#"], input[type="button"], input[type="submit"]');
          for (var k = 0; k < buttons.length; k++) {
            var t = (buttons[k].textContent || buttons[k].value || buttons[k].getAttribute('aria-label') || '').replace(/\s+/g, ' ').trim();
            if (t.length < 40 && REJECT.test(t) && press(buttons[k])) return;
          }
        }
      }
      // Starts once the page has loaded and the browser is idle, so it never slows loading.
      // Pop-ups often appear a little late, so it looks a few more times, then stops.
      var tries = 0;
      var idle = window.requestIdleCallback || function (f) { return setTimeout(f, 150); };
      function loop() {
        if (done || document.hidden) return;
        idle(function () {
          attempt();
          if (!done && ++tries < 12) setTimeout(loop, tries < 4 ? 400 : 1000);
        });
      }
      if (document.readyState === 'complete') loop(); else window.addEventListener('load', loop, { once: true });
    })();
    """#, injectionTime: .atDocumentEnd, forMainFrameOnly: false, in: .defaultClient)

    /// Hides common cookie-consent pop-ups and un-freezes page scrolling they lock.
    static let hideCookieBanners: WKUserScript = {
        let selectors = cookieBannerSelectors.joined(separator: ",")
        let source = """
        (function(){
          var sel = \(String(reflecting: selectors));
          function inject(){
            var root = document.head || document.documentElement; if (!root) return false;
            var s = document.createElement('style'); s.id = 'hush-cookie-banners';
            s.textContent = sel + '{display:none!important;visibility:hidden!important}';
            root.appendChild(s); return true;
          }
          if (!inject()) document.addEventListener('readystatechange', inject, {once:true});
          function unlock(){
            if (!document.querySelector(sel)) return;
            [document.documentElement, document.body].forEach(function(el){
              if (el && getComputedStyle(el).overflow === 'hidden') el.style.setProperty('overflow','auto','important');
            });
          }
          document.addEventListener('DOMContentLoaded', unlock);
          setTimeout(unlock, 1500); setTimeout(unlock, 4000);
        })();
        """
        return WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: true, in: .defaultClient)
    }()
}

// MARK: - Statistics

/// Running totals of what Hush has blocked, kept across launches.
final class BlockStats: ObservableObject {
    static let shared = BlockStats()

    @Published private(set) var ads: Int
    @Published private(set) var trackers: Int
    @Published private(set) var fromLists: Int
    @Published private(set) var since: Date
    private var saveScheduled = false

    var total: Int { ads + trackers + fromLists }

    private init() {
        let d = UserDefaults.standard
        ads = d.integer(forKey: "stats.ads")
        trackers = d.integer(forKey: "stats.trackers")
        fromLists = d.integer(forKey: "stats.lists")
        if let date = d.object(forKey: "stats.since") as? Date {
            since = date
        } else {
            since = Date()
            d.set(since, forKey: "stats.since")
        }
    }

    func record(_ identifier: String) {
        switch BuiltInRules.category(of: identifier) {
        case .ads: ads += 1
        case .trackers: trackers += 1
        case .lists: fromLists += 1
        case .other: return
        }
        scheduleSave()
    }

    func reset() {
        ads = 0; trackers = 0; fromLists = 0; since = Date()
        save()
    }

    private func scheduleSave() {
        guard !saveScheduled else { return }
        saveScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            self?.saveScheduled = false
            self?.save()
        }
    }

    func save() {
        let d = UserDefaults.standard
        d.set(ads, forKey: "stats.ads")
        d.set(trackers, forKey: "stats.trackers")
        d.set(fromLists, forKey: "stats.lists")
        d.set(since, forKey: "stats.since")
    }
}


// Hush Guard's state is only changed on the main thread; WebKit's compile callbacks hop back there.
extension ContentBlocker: @unchecked Sendable {}
