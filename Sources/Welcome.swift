import SwiftUI

enum DefaultBrowser {
    static var isDefault: Bool {
        guard let handler = NSWorkspace.shared.urlForApplication(toOpen: URL(string: "https://example.com")!) else { return false }
        // By app ID, not location: a copy run from elsewhere (the disk image, a backup) is still Ufolio.
        if handler.standardizedFileURL == Bundle.main.bundleURL.standardizedFileURL { return true }
        return Bundle(url: handler)?.bundleIdentifier == Bundle.main.bundleIdentifier
    }

    /// Asks macOS to make Hush the default browser (macOS shows its own confirmation).
    static func makeDefault(completion: @escaping (Bool) -> Void = { _ in }) {
        let group = DispatchGroup()
        for scheme in ["http", "https"] {
            group.enter()
            NSWorkspace.shared.setDefaultApplication(at: Bundle.main.bundleURL, toOpenURLsWithScheme: scheme) { _ in
                group.leave()
            }
        }
        group.notify(queue: .main) { completion(isDefault) }
    }
}

/// Decides what to show when Hush opens: the welcome screen the first time,
/// otherwise (at most once per launch) the default-browser question.
enum LaunchPrompts {
    private static var handled = false

    enum Prompt { case welcome, whatsNew(ReleaseNotes.Version), defaultBrowser }

    static func next() -> Prompt? {
        guard !handled else { return nil }
        handled = true
        let current = ReleaseNotes.currentVersion
        let lastSeen = UserDefaults.standard.string(forKey: "lastSeenVersion")
        UserDefaults.standard.set(current, forKey: "lastSeenVersion")
        if !Prefs.bool(Prefs.hasOnboarded) { return .welcome }
        // First launch after an update: show what's new (once).
        if lastSeen != current, let notes = ReleaseNotes.bundled.notes(for: current), !notes.sections.isEmpty {
            return .whatsNew(notes)
        }
        let snoozed = (UserDefaults.standard.object(forKey: "defaultBannerSnoozedUntil") as? Date).map { $0 > Date() } ?? false
        if Prefs.bool(Prefs.askDefaultBrowser) && !snoozed && !DefaultBrowser.isDefault { return .defaultBrowser }
        return nil
    }
}

// MARK: - Default browser banner

/// A slim bar under the bookmarks bar asking to make Hush the default browser.
/// Closing it hides it for two weeks; Settings › General › "Ask when Ufolio opens" turns it off.
struct DefaultBrowserBanner: View {
    let onClose: () -> Void
    @State private var hoveringClose = false

    var body: some View {
        HStack(spacing: 14) {
            Button {
                UserDefaults.standard.set(Date().addingTimeInterval(14 * 86_400), forKey: "defaultBannerSnoozedUntil")
                onClose()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.secondary.opacity(hoveringClose ? 1 : 0.7))
            }
            .buttonStyle(.plain)
            .onHover { hoveringClose = $0 }
            .help("Not now")

            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 36, height: 36)
                .shadow(color: .black.opacity(0.15), radius: 2, y: 1)

            VStack(alignment: .leading, spacing: 2) {
                Text("Make Ufolio your default browser?")
                    .font(.system(size: 13, weight: .semibold))
                Text("Ufolio blocks ads and trackers, keeps your history on this Mac, and is light on battery.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 12)
            Button("Make Ufolio Default") {
                DefaultBrowser.makeDefault { isDefault in if isDefault { onClose() } }
            }
            .controlSize(.regular)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}
