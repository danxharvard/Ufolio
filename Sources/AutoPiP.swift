import WebKit

/// Picture in Picture on tab switch: when a video is playing and you switch to another tab, it
/// pops out into a floating window, and goes back into its tab when you return. On by default
/// (Settings › Appearance), and can be turned off for any site from the tab's menu.
enum AutoPictureInPicture {
    private static let offSitesKey = "autoPiP.offSites"

    static var offSites: [String] {
        get { UserDefaults.standard.stringArray(forKey: offSitesKey) ?? [] }
        set { UserDefaults.standard.set(Array(Set(newValue)).sorted(), forKey: offSitesKey) }
    }

    static func isOff(for host: String?) -> Bool {
        guard let host else { return true }
        return offSites.contains(Domains.site(host))
    }

    static func setOff(_ off: Bool, for host: String?) {
        guard let host else { return }
        let site = Domains.site(host)
        offSites = off ? offSites + [site] : offSites.filter { $0 != site }
    }

    /// Worth checking: the setting's on, the site isn't excluded, and the page has a video that
    /// can float (a quick question to WebKit, no page script yet).
    static func wanted(for tab: BrowserTab) -> Bool {
        Prefs.bool(Prefs.autoPictureInPicture) && !isOff(for: tab.host)
            && WebKitExtras.canPictureInPicture(tab.webView) && !WebKitExtras.isPictureInPictureActive(tab.webView)
    }

    /// Pops the tab's video out if one is actually playing; tells you whether it did.
    static func popOut(_ tab: BrowserTab, completion: @escaping (Bool) -> Void) {
        let check = "return Array.from(document.querySelectorAll('video')).some(v => !v.paused && !v.ended && v.readyState > 2 && v.offsetWidth > 150);"
        tab.webView.callAsyncJavaScript(check, arguments: [:], in: nil, in: .defaultClient) { [weak tab] result in
            guard let tab, case .success(let value) = result, (value as? Bool) == true,
                  tab.model?.selectedTab !== tab else { completion(false); return }
            WebKitExtras.togglePictureInPicture(tab.webView)
            tab.autoPictureInPicture = true
            completion(true)
        }
    }

    /// Back in its tab when you return (if it's still floating: you may have closed it yourself).
    static func bringBack(_ tab: BrowserTab) {
        guard tab.autoPictureInPicture else { return }
        tab.autoPictureInPicture = false
        if WebKitExtras.isPictureInPictureActive(tab.webView) { WebKitExtras.togglePictureInPicture(tab.webView) }
    }
}
