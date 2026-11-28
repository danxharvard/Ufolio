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
        /// The release's name, after the version ("## 0.54.0-beta.4: smooth as butter").
        var title = ""
        var id: String { version }

        /// "Beta 4" for a beta, "Release" otherwise (for the timeline's badges).
        var badge: (label: String, beta: Bool) {
            guard let range = version.range(of: "-beta") else { return ("Release", false) }
            let number = version[range.upperBound...].trimmingCharacters(in: CharacterSet(charactersIn: "."))
            return (number.isEmpty ? "Beta" : "Beta \(number)", true)
        }
        /// The first headline feature (or the first section), for a timeline card.
        var headline: String { sections.first { !$0.heading.lowercased().contains("fix") }?.heading ?? sections.first?.heading ?? "" }
    }

    let versions: [Version]

    static let bundled: ReleaseNotes = {
        guard let url = Bundle.main.url(forResource: "CHANGELOG", withExtension: "md"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return ReleaseNotes(versions: []) }
        return parse(text)
    }()

    func notes(for version: String) -> Version? {
        versions.first { $0.version == version }
    }

    /// Everything new since the version you last used (up to five versions), as one list: an
    /// update that skipped versions (0.51.5 straight to 0.51.7) only showed the newest one's notes.
    func notes(since lastSeen: String?, upTo current: String) -> Version? {
        guard let start = versions.firstIndex(where: { $0.version == current }) else { return nil }
        var sections: [Section] = []
        for version in versions[start...].prefix(5) {
            if version.version == lastSeen { break }
            sections += version.sections
        }
        return Version(version: current, intro: versions[start].intro, sections: sections, title: versions[start].title)
    }

    static func parse(_ text: String) -> ReleaseNotes {
        var versions: [Version] = []
        var version: String?
        var sections: [Section] = []
        var heading = ""
        var items: [String] = []
        var intro: [String] = []
        var title = ""

        func closeSection() {
            if !items.isEmpty { sections.append(Section(heading: heading, items: items)) }
            items = []
        }
        func closeVersion() {
            closeSection()
            if let v = version { versions.append(Version(version: v, intro: intro, sections: sections, title: title)) }
            sections = []; intro = []; heading = ""; title = ""
        }

        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("## ") {
                closeVersion()
                // "## 0.43.0: the stability release" → "0.43.0" (the title after it is optional).
                let rest = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                version = rest.split(whereSeparator: { $0 == ":" || $0 == " " }).first.map(String.init) ?? rest
                if let colon = rest.firstIndex(of: ":") {
                    title = rest[rest.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                }
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
                // A plain sentence, not a change ("Everything in 0.51.7 is in this beta too."): it
                // used to be listed as one more bullet point.
                intro.append(line)
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
                HStack(spacing: 8) {
                    ReleaseBadge(version: notes)
                    Text(notes.version).font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary)
                }
                Text(notes.title.isEmpty ? "What’s new" : notes.title.prefix(1).uppercased() + notes.title.dropFirst())
                    .font(.system(size: 30, weight: .semibold))
                    .tracking(-0.9)
                    .multilineTextAlignment(.center)
                Text("Ufolio just updated. Here’s what changed.")
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

// MARK: - Release timeline

/// A version's badge: orange for a beta, green for a release.
struct ReleaseBadge: View {
    let version: ReleaseNotes.Version
    var body: some View {
        let badge = version.badge
        let tint = badge.beta ? Color.orange : Color.green
        Text(badge.label)
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 7).padding(.vertical, 2.5)
            .background(Capsule().fill(tint.opacity(0.16)))
    }
}

/// Every version Ufolio knows about, newest first, as cards in a row that scrolls sideways.
/// Choosing one shows its notes underneath.
struct ReleaseTimeline: View {
    let versions: [ReleaseNotes.Version]
    @Binding var selection: String?
    var current: String

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 10) {
                    ForEach(versions) { version in
                        ReleaseCard(version: version, selected: (selection ?? current) == version.version,
                                    installed: version.version == current) {
                            withAnimation(FluidSwitch.spring) { selection = version.version }
                        }
                        .id(version.version)
                    }
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 2)
            }
            .onAppear { proxy.scrollTo(selection ?? current, anchor: .leading) }
        }
    }
}

private struct ReleaseCard: View {
    let version: ReleaseNotes.Version
    let selected: Bool
    let installed: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    ReleaseBadge(version: version)
                    Spacer()
                    if installed {
                        Text("Installed").font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                    }
                }
                Text(version.title.isEmpty ? version.headline : version.title.prefix(1).uppercased() + version.title.dropFirst())
                    .font(.system(size: 13.5, weight: .semibold))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(version.version)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                if !version.headline.isEmpty, !version.title.isEmpty {
                    Text(version.headline).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .padding(12)
            .frame(width: 168, height: 118, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.primary.opacity(selected ? 0.10 : hovering ? 0.07 : 0.045)))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.06), lineWidth: selected ? 1.5 : 0.5))
            .offset(y: hovering && !selected ? -2 : 0)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.snappy(duration: 0.18), value: hovering)
        .accessibilityLabel("Ufolio \(version.version), \(version.badge.label)")
    }
}
