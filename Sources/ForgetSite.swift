import AppKit
import SwiftUI
import WebKit

/// Forget This Site (right-click a tab): wipes everything Hush and WebKit keep about a site.
enum SiteForgetter {
    /// Asks first (with Hush's dialog card), then forgets the site of the given tab.
    static func confirmAndForget(_ tab: BrowserTab) {
        guard let model = tab.model, let host = tab.url?.host else { return }
        let site = Domains.site(host)
        let tabs = model.tabs.filter { Domains.site($0.url?.host ?? "") == site }.count
        model.dialogs.present(HushDialog(
            art: .site(tab.url), badge: "eraser.fill", theme: .danger, motion: .drift,
            title: "Forget \(site)?",
            message: "Signs you out and removes its history, permissions and \(tabs == 1 ? "open tab" : "\(tabs) open tabs").",
            note: ("checkmark.shield.fill", "Bookmarks and passwords are kept"),
            choices: [.init(title: "Cancel", role: .cancel), .init(title: "Forget", role: .destructive)],
            completion: { choice, _ in if choice == 1 { forget(site, in: model) } }))
    }

    static func forget(_ site: String, in model: BrowserModel) {
        // Website data (cookies, storage, caches): this private window's, or every profile's.
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        for store in model.isPrivate ? [model.dataStore] : SpaceStore.shared.allDataStores {
            store.fetchDataRecords(ofTypes: types) { records in
                let matching = records.filter { Domains.site($0.displayName) == site }
                store.removeData(ofTypes: types, for: matching) {}
            }
        }
        if !model.isPrivate {
            HistoryStore.shared.remove(site: site)
            RecentlyClosed.shared.remove(site: site)
            SitePermissions.shared.forget(site: site)
            BookmarkOffer.shared.forget(site: site)
            PrivacyReport.shared.forget(site: site)   // it lists the sites you visited too
            Task { await FaviconCache.shared.forget(site: site) }
        }
        // Close the site's tabs (a new tab replaces them if nothing else is left).
        let tabs = model.tabs.filter { Domains.site($0.url?.host ?? "") == site }
        if model.visibleTabs.allSatisfy({ open in tabs.contains { $0 === open } }) { model.newTab(focus: true) }
        for tab in tabs { model.close(tab, remember: false) }
    }
}

