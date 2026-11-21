import AppKit
import WebKit

/// Forget This Site (right-click a tab): wipes everything Hush and WebKit keep about a site.
enum SiteForgetter {
    /// Asks first, then forgets the site of the given tab.
    static func confirmAndForget(_ tab: BrowserTab) {
        guard let model = tab.model, let host = tab.url?.host else { return }
        let site = Domains.site(host)
        let alert = NSAlert()
        alert.messageText = "Forget \(site)?"
        alert.informativeText = "Hush will delete \(site)’s cookies and saved website data (signing you out), remove it from your history, forget its permissions and close its tabs. Your bookmarks and saved passwords are kept."
        alert.addButton(withTitle: "Forget")
        alert.addButton(withTitle: "Cancel")
        alert.icon = NSImage(systemSymbolName: "eraser.fill", accessibilityDescription: nil)
        let run: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .alertFirstButtonReturn else { return }
            forget(site, in: model)
        }
        if let window = model.window ?? tab.webView.window { alert.beginSheetModal(for: window, completionHandler: run) } else { run(alert.runModal()) }
    }

    static func forget(_ site: String, in model: BrowserModel) {
        // Website data (cookies, storage, caches) in this window's store.
        let store = model.dataStore
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        store.fetchDataRecords(ofTypes: types) { records in
            let matching = records.filter { Domains.site($0.displayName) == site }
            store.removeData(ofTypes: types, for: matching) {}
        }
        if !model.isPrivate {
            HistoryStore.shared.remove(site: site)
            RecentlyClosed.shared.remove(site: site)
            SitePermissions.shared.forget(site: site)
            BookmarkOffer.shared.forget(site: site)
        }
        // Close the site's tabs (a new tab replaces them if nothing else is left).
        let tabs = model.tabs.filter { Domains.site($0.url?.host ?? "") == site }
        if tabs.count == model.tabs.count { model.newTab(focus: true) }
        for tab in tabs { model.close(tab, remember: false) }
    }
}
