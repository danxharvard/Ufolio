import SwiftUI
import WebKit

/// Cookie auto-cleaner (Settings › Privacy & Security, off by default): deletes the cookies and
/// website data of sites you haven't used for 30 days. It never touches a site that's open in a
/// tab, one you have a saved password for (so you stay signed in), or one you've marked "keep".
/// It runs in the background at most once a day, only after a couple of quiet minutes (never
/// while you're browsing), and Settings shows what it cleaned.
enum CookieCleaner {
    static var enabled: Bool { Prefs.bool(Prefs.cookieCleaner) }
    static let days = 30

    private static let seenKey = "cookieCleaner.lastSeen"     // [site: last used], kept only while it's on
    private static let keepKey = "cookieCleaner.keep"
    private static let runKey = "cookieCleaner.lastRun"
    private static let cleanedKey = "cookieCleaner.lastCleaned"

    /// When a page last started loading (the cleaner waits for a quiet spell).
    static var lastActivity = Date()

    static var kept: [String] {
        get { UserDefaults.standard.stringArray(forKey: keepKey) ?? [] }
        set { UserDefaults.standard.set(Array(Set(newValue)).sorted(), forKey: keepKey) }
    }
    static var lastRun: Date? { UserDefaults.standard.object(forKey: runKey) as? Date }
    static var lastCleaned: [String] { UserDefaults.standard.stringArray(forKey: cleanedKey) ?? [] }

    private static var seen: [String: Date] {
        get { (UserDefaults.standard.dictionary(forKey: seenKey) as? [String: Date]) ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: seenKey) }
    }

    /// A site was used (a page from it finished loading in a normal window).
    static func noteVisit(_ host: String?) {
        guard enabled, let host, !host.isEmpty else { return }
        let site = Domains.site(host)
        var all = seen
        if let last = all[site], Date().timeIntervalSince(last) < 3600 { return }   // at most once an hour per site
        all[site] = Date()
        seen = all
    }

    /// Switched on: every site that already has data starts its 30 days now, so nothing you use
    /// is wiped just because Ufolio hadn't been keeping track yet.
    static func switchedOn() {
        let stores = SpaceStore.shared.allDataStores
        for store in stores {
            store.fetchDataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes()) { records in
                var all = seen
                for record in records where all[Domains.site(record.displayName)] == nil { all[Domains.site(record.displayName)] = Date() }
                seen = all
            }
        }
        UserDefaults.standard.set(Date(), forKey: runKey)   // the first clean is a day away
    }

    static func switchedOff() {
        UserDefaults.standard.removeObject(forKey: seenKey)   // nothing kept about your browsing
    }

    /// Called every half minute by the performance timer: cleans when it's due and things are quiet.
    static func runIfDue() {
        guard enabled, Date().timeIntervalSince(lastActivity) > 120,
              Date().timeIntervalSince(lastRun ?? .distantPast) > 86_400 else { return }
        UserDefaults.standard.set(Date(), forKey: runKey)
        run()
    }

    static func run(completion: (() -> Void)? = nil) {
        let cutoff = Date().addingTimeInterval(-Double(days) * 86_400)
        let recent = Set(seen.filter { $0.value > cutoff }.map(\.key))
        let open = Set(BrowserModel.all.allObjects.flatMap(\.tabs).compactMap { $0.url?.host }.map(Domains.site))
        let keep = Set(kept)
        let stores = SpaceStore.shared.allDataStores
        // Saved passwords mean you're likely signed in there: read in the background (never the keychain's secrets).
        DispatchQueue.global(qos: .utility).async {
            let signedIn = Set(PasswordVault.logins().map { Domains.site($0.host) })
            DispatchQueue.main.async {
                var cleaned: Set<String> = []
                var remaining = stores.count
                for store in stores {
                    store.fetchDataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes()) { records in
                        let old = records.filter { record in
                            let site = Domains.site(record.displayName)
                            return !recent.contains(site) && !open.contains(site) && !keep.contains(site) && !signedIn.contains(site)
                        }
                        old.forEach { cleaned.insert(Domains.site($0.displayName)) }
                        store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), for: old) {
                            remaining -= 1
                            guard remaining == 0 else { return }
                            UserDefaults.standard.set(Array(cleaned).sorted(), forKey: cleanedKey)
                            // Forget the dates of sites that are gone.
                            seen = seen.filter { !cleaned.contains($0.key) }
                            completion?()
                        }
                    }
                }
            }
        }
    }
}

/// Settings › Privacy & Security › Cookie auto-cleaner.
struct CookieCleanerSection: View {
    @AppStorage(Prefs.cookieCleaner) private var enabled = false
    @State private var kept = CookieCleaner.kept
    @State private var cleaned = CookieCleaner.lastCleaned
    @State private var newSite = ""
    @State private var running = false

    var body: some View {
        Section {
            DescribedToggle(title: "Clean up old cookies and website data",
                            detail: "Deletes the data of sites you haven’t used for 30 days. Never sites open in a tab, ones you have a saved password for, or ones you keep below. Runs quietly once a day.",
                            isOn: $enabled)
                .onChange(of: enabled) { _, on in if on { CookieCleaner.switchedOn() } else { CookieCleaner.switchedOff() } }
            if enabled {
                HStack {
                    Text(summary).font(.system(size: 12)).foregroundStyle(.secondary)
                    Spacer()
                    Button(running ? "Cleaning…" : "Clean Now") {
                        running = true
                        CookieCleaner.run { running = false; cleaned = CookieCleaner.lastCleaned }
                    }
                    .disabled(running)
                }
                if !cleaned.isEmpty {
                    DisclosureGroup("Cleaned last time (\(cleaned.count))") {
                        ForEach(cleaned, id: \.self) { site in
                            HStack {
                                Text(site).font(.system(size: 12))
                                Spacer()
                                Button("Keep in Future") { kept = (kept + [site]).sorted(); CookieCleaner.kept = kept }
                                    .buttonStyle(.link).font(.system(size: 11.5))
                                    .disabled(kept.contains(site))
                            }
                        }
                    }
                }
                ForEach(kept, id: \.self) { site in
                    HStack {
                        Image(systemName: "pin.fill").foregroundStyle(.secondary)
                        Text(site)
                        Spacer()
                        Button { kept.removeAll { $0 == site }; CookieCleaner.kept = kept } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless).accessibilityLabel("Stop keeping \(site)")
                    }
                }
                HStack {
                    TextField("Always keep a site (e.g. example.com)", text: $newSite)
                        .onSubmit(addSite)
                    Button("Keep", action: addSite).disabled(newSite.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        } header: { SectionTitle("Cookie auto-cleaner") }
    }

    private var summary: String {
        guard let last = CookieCleaner.lastRun else { return "Not run yet." }
        let when = last.formatted(date: .abbreviated, time: .shortened)
        return cleaned.isEmpty ? "Last checked \(when): nothing to clean." : "Last cleaned \(when): \(cleaned.count) site\(cleaned.count == 1 ? "" : "s")."
    }

    private func addSite() {
        let text = newSite.trimmingCharacters(in: .whitespaces).lowercased()
        let host = URL(string: text.contains("://") ? text : "https://" + text)?.host ?? text
        guard !host.isEmpty else { return }
        kept = Array(Set(kept + [Domains.site(host)])).sorted()
        CookieCleaner.kept = kept
        newSite = ""
    }
}
