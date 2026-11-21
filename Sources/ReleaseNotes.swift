import SwiftUI

/// The release notes bundled inside Hush (CHANGELOG.md), split into versions and sections,
/// for the What's New screen and Settings › Software Update.
struct ReleaseNotes {
    struct Section: Identifiable {
        let id = UUID()
        let heading: String       // "New", "Fixed", "Improved"… (may be empty)
        let items: [String]       // bullet points (Markdown)
    }

    struct Version: Identifiable {
        let version: String
        let intro: [String]       // lines before the first bullet that aren't headings
        let sections: [Section]
        var id: String { version }
    }

    let versions: [Version]

    static let bundled: ReleaseNotes = {
        guard let url = Bundle.main.url(forResource: "CHANGELOG", withExtension: "md"),
              let text = try? String(contentsOf: url) else { return ReleaseNotes(versions: []) }
        return parse(text)
    }()

    func notes(for version: String) -> Version? {
        versions.first { $0.version == version }
    }

    static func parse(_ text: String) -> ReleaseNotes {
        var versions: [Version] = []
        var version: String?
        var sections: [Section] = []
        var heading = ""
        var items: [String] = []
        var intro: [String] = []

        func closeSection() {
            if !items.isEmpty { sections.append(Section(heading: heading, items: items)) }
            items = []
        }
        func closeVersion() {
            closeSection()
            if let v = version { versions.append(Version(version: v, intro: intro, sections: sections)) }
            sections = []; intro = []; heading = ""
        }

        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("## ") {
                closeVersion()
                version = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            } else if version == nil {
                continue
            } else if line.hasPrefix("**") && line.hasSuffix("**") && line.count > 4 {
                closeSection()
                heading = String(line.dropFirst(2).dropLast(2))
            } else if line.hasPrefix("- ") {
                items.append(String(line.dropFirst(2)))
            } else if !line.isEmpty, raw.hasPrefix("  "), !items.isEmpty {
                items[items.count - 1] += " " + line   // a bullet continued on the next line
            } else if !line.isEmpty {
                if items.isEmpty && sections.isEmpty { intro.append(line) } else { items.append(line) }
            }
        }
        closeVersion()
        return ReleaseNotes(versions: versions)
    }

    static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    static func symbol(for heading: String) -> (String, [Color]) {
        let h = heading.lowercased()
        if h.contains("fix") { return ("wrench.and.screwdriver.fill", [Color(red: 0.25, green: 0.70, blue: 0.45), Color(red: 0.12, green: 0.52, blue: 0.32)]) }
        if h.contains("fast") || h.contains("speed") || h.contains("perform") { return ("bolt.fill", [Color(red: 1.0, green: 0.75, blue: 0.2), Color(red: 0.95, green: 0.55, blue: 0.1)]) }
        if h.contains("improv") || h.contains("chang") { return ("wand.and.stars", [Color(red: 0.30, green: 0.60, blue: 1.0), Color(red: 0.15, green: 0.40, blue: 0.95)]) }
        if h.contains("look") || h.contains("design") || h.contains("animation") { return ("paintbrush.fill", [Color(red: 0.95, green: 0.40, blue: 0.65), Color(red: 0.80, green: 0.22, blue: 0.50)]) }
        if h.contains("test") { return ("checkmark.seal.fill", [Color(white: 0.6), Color(white: 0.42)]) }
        return ("sparkles", [Color(red: 0.58, green: 0.44, blue: 1.0), Color(red: 0.38, green: 0.26, blue: 0.86)])
    }

    /// Renders a bullet's Markdown (bold, code, links).
    static func attributed(_ markdown: String) -> AttributedString {
        (try? AttributedString(markdown: markdown, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(markdown)
    }
}

/// One version's notes as cards: an icon per section, then its bullets.
struct ReleaseNotesView: View {
    let notes: ReleaseNotes.Version

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(notes.sections) { section in
                let style = ReleaseNotes.symbol(for: section.heading)
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        IconTile(symbol: style.0, colors: style.1, size: 26)
                        Text(section.heading.isEmpty ? "What’s new" : section.heading)
                            .font(.system(size: 14, weight: .semibold))
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(section.items.enumerated()), id: \.offset) { _, item in
                            HStack(alignment: .firstTextBaseline, spacing: 9) {
                                Circle().fill(style.1.first ?? .accentColor).frame(width: 5, height: 5).offset(y: -2)
                                Text(ReleaseNotes.attributed(item))
                                    .font(.system(size: 12.5))
                                    .fixedSize(horizontal: false, vertical: true)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                    .padding(.leading, 36)
                }
            }
        }
    }
}

/// Shown once after Hush updates: the new version's highlights, in a card over the window.
struct WhatsNewView: View {
    let notes: ReleaseNotes.Version
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                AnimatedHushLogo(size: 72)
                Text("What’s new in Hush \(notes.version)")
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                Text("Hush just updated. Here’s what changed.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 30)
            .padding(.bottom, 20)

            ScrollView {
                ReleaseNotesView(notes: notes)
                    .padding(.horizontal, 36)
                    .padding(.bottom, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 380)

            HStack {
                Button("See All Updates") {
                    onDone()
                    SettingsOpener.open(tab: .updates)
                }
                .buttonStyle(.link)
                Spacer()
                Button("Continue", action: onDone)
                    .keyboardShortcut(.defaultAction)
                    .controlSize(.large)
            }
            .padding(.horizontal, 30)
            .padding(.vertical, 22)
        }
        .frame(width: 540)
    }
}
