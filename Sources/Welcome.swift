import SwiftUI

enum DefaultBrowser {
    static var isDefault: Bool {
        guard let handler = NSWorkspace.shared.urlForApplication(toOpen: URL(string: "https://example.com")!) else { return false }
        return handler.standardizedFileURL == Bundle.main.bundleURL.standardizedFileURL
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

    enum Prompt { case welcome, defaultBrowser }

    static func next() -> Prompt? {
        guard !handled else { return nil }
        handled = true
        if !Prefs.bool(Prefs.hasOnboarded) { return .welcome }
        if Prefs.bool(Prefs.askDefaultBrowser) && !DefaultBrowser.isDefault { return .defaultBrowser }
        return nil
    }
}

// MARK: - Welcome

struct WelcomeView: View {
    let onDone: () -> Void
    @State private var sources = BrowserImporter.available()
    @State private var importing: String?
    @State private var imported: [String: String] = [:]
    @State private var isDefault = DefaultBrowser.isDefault
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 96, height: 96)
                    .shadow(color: Color(red: 0.4, green: 0.3, blue: 0.9).opacity(0.35), radius: 18, y: 8)
                    .scaleEffect(appeared ? 1 : 0.85)
                    .opacity(appeared ? 1 : 0)
                Text("Welcome to Hush")
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                Text("A calm, private browser for your Mac.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 36)

            VStack(alignment: .leading, spacing: 16) {
                FeatureRow(symbol: "shield.lefthalf.filled", color: Color(red: 0.45, green: 0.35, blue: 0.95),
                           title: "Ads and trackers, gone",
                           detail: "Hush blocks them before they load, so pages are cleaner and faster.")
                FeatureRow(symbol: "hand.raised.fill", color: Color(red: 0.2, green: 0.5, blue: 1),
                           title: "Private by design",
                           detail: "No account and no tracking. Your history and passwords stay on this Mac.")
                FeatureRow(symbol: "sparkles", color: Color(red: 0.95, green: 0.6, blue: 0.15),
                           title: "Made for macOS",
                           detail: "Native, light and fluid, with Day and Night themes.")
            }
            .padding(.horizontal, 48)
            .padding(.vertical, 28)
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 10)

            if !sources.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Bring your favourite sites")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Hush can show the sites you visit most from another browser on its start page.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                    HStack(spacing: 10) {
                        ForEach(sources) { source in
                            ImportButton(source: source, busy: importing == source.name,
                                         result: imported[source.name]) { run(source) }
                        }
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.04)))
                .padding(.horizontal, 36)
            }

            Spacer(minLength: 20)

            HStack {
                if !isDefault {
                    Button("Make Hush Your Default Browser") {
                        DefaultBrowser.makeDefault { isDefault = $0 }
                    }
                } else {
                    Label("Hush is your default browser", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(Color.green)
                        .font(.system(size: 12))
                }
                Spacer()
                Button("Start Browsing", action: onDone)
                    .keyboardShortcut(.defaultAction)
                    .controlSize(.large)
            }
            .padding(.horizontal, 36)
            .padding(.bottom, 28)
        }
        .frame(width: 580, height: sources.isEmpty ? 560 : 680)
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.1)) { appeared = true }
        }
    }

    private func run(_ source: BrowserImporter.Source) {
        importing = source.name
        DispatchQueue.global(qos: .userInitiated).async {
            let message: String
            do {
                let count = try BrowserImporter.importTopSites(from: source)
                message = count > 0 ? "\(count) pages" : "Nothing to import"
            } catch {
                message = error.localizedDescription
            }
            DispatchQueue.main.async {
                importing = nil
                imported[source.name] = message
            }
        }
    }
}

private struct FeatureRow: View {
    let symbol: String
    let color: Color
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(color)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13.5, weight: .semibold))
                Text(detail).font(.system(size: 12)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct ImportButton: View {
    let source: BrowserImporter.Source
    let busy: Bool
    let result: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack(alignment: .bottomTrailing) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: source.appPath))
                        .resizable()
                        .frame(width: 36, height: 36)
                    if result != nil && !busy {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(.white, Color.green)
                            .offset(x: 4, y: 4)
                    }
                }
                if busy {
                    ProgressView().controlSize(.small).frame(height: 14)
                } else {
                    Text(source.name).font(.system(size: 11)).lineLimit(1)
                }
            }
            .frame(width: 84, height: 72)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(busy)
        .help(result ?? "Import your most-visited sites from \(source.name)")
    }
}

// MARK: - Default browser prompt

struct DefaultBrowserPrompt: View {
    let onClose: () -> Void
    @State private var dontAskAgain = false

    var body: some View {
        VStack(spacing: 16) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 72, height: 72)
                .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
            VStack(spacing: 6) {
                Text("Make Hush your default browser?")
                    .font(.system(size: 17, weight: .semibold))
                Text("Links you open from Mail, Messages and other apps will open in Hush.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Toggle("Don’t ask again", isOn: $dontAskAgain)
                .toggleStyle(.checkbox)
                .font(.system(size: 12))
            HStack(spacing: 10) {
                Button("Not Now") { close() }
                    .keyboardShortcut(.cancelAction)
                    .frame(maxWidth: .infinity)
                Button("Use Hush") {
                    DefaultBrowser.makeDefault()
                    close()
                }
                .keyboardShortcut(.defaultAction)
                .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
        }
        .padding(24)
        .frame(width: 360)
    }

    private func close() {
        if dontAskAgain { UserDefaults.standard.set(false, forKey: Prefs.askDefaultBrowser) }
        onClose()
    }
}
