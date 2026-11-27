import SwiftUI

/// The hidden developer area: it appears in Settings › Software Update only after you click the
/// Ufolio icon on the start page five times in a row. It holds the experimental builds channel,
/// which you turn on yourself and only after agreeing to what experimental builds are.
enum DeveloperArea {
    private static var clicks = 0
    private static var lastClick = Date.distantPast

    static var isUnlocked: Bool { Prefs.bool(Prefs.developerUnlocked) }

    /// A click on the start page's Ufolio icon. Five in a row (no more than a second and a half
    /// apart) unlocks the developer area.
    static func iconClicked(in window: NSWindow?) {
        guard !isUnlocked else { return }
        let now = Date()
        clicks = now.timeIntervalSince(lastClick) < 1.5 ? clicks + 1 : 1
        lastClick = now
        guard clicks >= 5 else { return }
        clicks = 0
        UserDefaults.standard.set(true, forKey: Prefs.developerUnlocked)
        DialogHost.show(HushDialog(
            art: .symbol("hammer.fill"), theme: .hush,
            title: "Developer area unlocked",
            message: "You’ll find it in Settings › Software Update.",
            choices: [.init(title: "Not Now", role: .cancel), .init(title: "Open Settings", role: .primary)],
            completion: { choice, _ in if choice == 1 { SettingsOpener.open(tab: .updates) } }), in: window)
    }

    /// Hides the area again (experimental builds stop too).
    static func lock() {
        UserDefaults.standard.set(false, forKey: Prefs.experimentalUpdates)
        UserDefaults.standard.set(false, forKey: Prefs.developerUnlocked)
    }

    static let terms = "By agreeing to receive experimental builds, you acknowledge that they are exactly that: experimental, and most probably very buggy. They could be slow, unresponsive or worse. Experimental builds aren’t intended for the average Joe: they’re for tech enthusiasts and developers, to give feedback."
}

/// Settings › Software Update › Developer (only once unlocked).
struct DeveloperSection: View {
    @AppStorage(Prefs.developerUnlocked) private var unlocked = false
    @AppStorage(Prefs.experimentalUpdates) private var experimental = false

    var body: some View {
        if unlocked {
            Section {
                DescribedToggle(title: "Start Receiving Experimental Builds",
                                detail: "Very early versions, before beta. Each one is checked exactly like a regular update before it installs.",
                                isOn: Binding(get: { experimental }, set: { wanted in
                                    if wanted { askToAgree() } else { experimental = false }
                                }))
                Button("Hide Developer Area") { DeveloperArea.lock() }
                    .buttonStyle(.link)
            } header: { SectionTitle("Developer") }
        }
    }

    /// Experimental builds only start once you've agreed to the terms.
    private func askToAgree() {
        DialogHost.settings.present(HushDialog(
            art: .symbol("flask.fill"), theme: .caution,
            title: "Receive experimental builds?",
            message: DeveloperArea.terms,
            width: 340,
            choices: [.init(title: "Cancel", role: .cancel), .init(title: "I Agree", role: .primary)],
            completion: { choice, _ in
                guard choice == 1 else { return }
                experimental = true
                Task { await Updater.shared.check(userInitiated: false) }
            }))
    }
}
