import SwiftUI

/// The setup guide shown the first time Hush opens (and again from Settings › General):
/// one question per screen, each answer saved as you go, so Back always shows what you picked.
struct SetupGuide: View {
    let onDone: () -> Void
    static let showAgain = Notification.Name("HushShowSetupGuide")

    enum Step: Int, CaseIterable {
        case welcome, bringStuff, search, guardMode, tabs, look, defaultBrowser, done
    }

    @State private var step: Step = .welcome
    @State private var forward = true
    @State private var appeared = false
    @State private var buttonHover = false

    // Answers (each starts from the current setting).
    /// Found when the guide appears. (As starting values these were worked out again, scanning
    /// for other browsers, every time the window redrew behind the guide.)
    @State private var sources: [BrowserImporter.Source] = []
    /// Each browser's app icon, looked up once with the scan (asking macOS for them on every
    /// redraw, each hover and click on that step, made it stutter).
    @State private var icons: [String: NSImage] = [:]
    @State private var importChoice: String? = nil          // nil = start fresh
    @State private var importing = false
    @State private var importResult: String?
    @AppStorage(Prefs.searchEngine) private var engine = SearchEngine.google.rawValue
    @AppStorage(Prefs.blockingMode) private var blocking = BlockingMode.standard.rawValue
    @AppStorage(Prefs.tabLayout) private var tabLayout = TabLayout.top.rawValue
    @AppStorage(Prefs.appearance) private var appearance = AppearanceMode.system.rawValue
    @AppStorage(Prefs.accent) private var accent = AccentChoice.system.rawValue
    /// Set when the guide appears (as a starting value, macOS was asked again every time the
    /// window behind the guide redrew).
    @State private var makeDefault = true
    @State private var isDefault = false

    var body: some View {
        ZStack {
            SetupBackdrop(hue: step.hue).ignoresSafeArea()
            HStack(spacing: 0) {
                leftPanel
                    .frame(width: 330)
                // A hairline between question and choices, fading out at both ends.
                LinearGradient(colors: [.clear, Color.primary.opacity(0.1), .clear], startPoint: .top, endPoint: .bottom)
                    .frame(width: 1)
                    .padding(.vertical, 30)
                rightPanel
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(width: 860, height: 540)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            // Glass catches the light along its top edge.
            .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(LinearGradient(colors: [Color.white.opacity(0.32), Color.white.opacity(0.06), Color.white.opacity(0.12)],
                                             startPoint: .top, endPoint: .bottom), lineWidth: 1))
            .shadow(color: .black.opacity(0.3), radius: 50, y: 24)
            .scaleEffect(appeared ? 1 : 0.94)
            .offset(y: appeared ? 0 : 14)
            .blur(radius: appeared ? 0 : 8)
            .opacity(appeared ? 1 : 0)
        }
        .onAppear {
            isDefault = DefaultBrowser.isDefault
            makeDefault = !isDefault
            // Looking for other browsers and their icons touches the disk: done off the main
            // thread, well before you reach that step.
            Task.detached(priority: .userInitiated) {
                let found = BrowserImporter.available()
                var art: [String: NSImage] = [:]
                // A browser since removed (its bookmarks still on the Mac) has no app to take an icon
                // from: macOS handed back a blank document. It gets a globe instead.
                for source in found.prefix(5) where FileManager.default.fileExists(atPath: source.appPath) {
                    art[source.name] = NSWorkspace.shared.icon(forFile: source.appPath)
                }
                let ready = art
                await MainActor.run { sources = found; icons = ready }
            }
            withAnimation(.spring(response: 0.7, dampingFraction: 0.86)) { appeared = true }
            // The address bar behind the guide had the keyboard: Return (and any typing) went into
            // it, unseen, instead of pressing Get Started. (Once more a moment later, as a new
            // window puts the cursor in its address bar as it opens.)
            let unfocus = { if let window = NSApp.keyWindow, window.firstResponder is NSText { window.makeFirstResponder(nil) } }
            DispatchQueue.main.async(execute: unfocus)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: unfocus)
        }
    }

    // MARK: Left: the question

    private var leftPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            Group {
                if step != .welcome && step != .done {
                    Button { go(-1) } label: {
                        Label("Back", systemImage: "arrow.left").font(.system(size: 13, weight: .medium))
                    }
                    .buttonStyle(GuidePress())
                    .disabled(importing)
                    .foregroundStyle(Color.accentColor)
                    .keyboardShortcut(.leftArrow, modifiers: [])
                    .transition(.opacity.combined(with: .offset(x: -6)))
                } else {
                    Color.clear
                }
            }
            .frame(height: 20)
            .padding(.bottom, 26)

            VStack(alignment: .leading, spacing: 14) {
                if step != .welcome && step != .done {
                    Text("STEP \(step.rawValue) OF \(Step.allCases.count - 2)")
                        .font(.system(size: 10.5, weight: .bold)).tracking(1.4)
                        .foregroundStyle(Color.accentColor.opacity(0.9))
                }
                Text(step.title)
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .fixedSize(horizontal: false, vertical: true)
                Text(step.detail)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .id(step)
            .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 10)).combined(with: .glide(blur: 6)),
                                    removal: .opacity.combined(with: .glide(blur: 4))))

            Spacer()

            ProgressDots(count: Step.allCases.count, current: step.rawValue)
                .padding(.bottom, 18)

            Button(action: next) {
                HStack(spacing: 8) {
                    if importing { ProgressView().controlSize(.small).tint(.white) }
                    Text(importing ? "Importing…" : step.buttonTitle)
                        .font(.system(size: 14, weight: .semibold))
                        .contentTransition(.interpolate)
                    if !importing {
                        Image(systemName: step == .done ? "sparkles" : "arrow.right")
                            .font(.system(size: 12.5, weight: .bold))
                            .offset(x: buttonHover ? 3 : 0)
                            .contentTransition(.symbolEffect(.replace))
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 42)
                .foregroundStyle(.white)
                .background(
                    RoundedRectangle(cornerRadius: 13, style: .continuous).fill(Color.accentColor.gradient)
                        .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .fill(LinearGradient(colors: [Color.white.opacity(buttonHover ? 0.26 : 0.18), .clear],
                                                 startPoint: .top, endPoint: .center)))
                        .shadow(color: Color.accentColor.opacity(buttonHover ? 0.45 : 0.28), radius: buttonHover ? 14 : 8, y: 5)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(GuidePress(scale: 0.965))
            .onHover { hovering in withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { buttonHover = hovering } }
            .disabled(importing)
            .keyboardShortcut(.defaultAction)
        }
        .padding(36)
    }

    // MARK: Right: the choices

    @ViewBuilder private var rightPanel: some View {
        ZStack {
            switch step {
            case .welcome: welcomeArt
            case .bringStuff: bringStuffChoices
            case .search: searchChoices
            case .guardMode: guardChoices
            case .tabs: tabChoices
            case .look: lookChoices
            case .defaultBrowser: defaultChoices
            case .done: summary
            }
        }
        .id(step)
        .transition(.asymmetric(
            insertion: .opacity.combined(with: .offset(x: forward ? 36 : -36)).combined(with: .scale(scale: 0.97)).combined(with: .glide(blur: 10)),
            removal: .opacity.combined(with: .offset(x: forward ? -36 : 36)).combined(with: .scale(scale: 0.98)).combined(with: .glide(blur: 8))))
        .padding(36)
    }

    private var welcomeArt: some View {
        VStack(spacing: 22) {
            UFOZapperScene()
                .frame(height: 210)
            VStack(alignment: .leading, spacing: 14) {
                Highlight(symbol: "bolt.fill", color: .orange, text: "Blazing fast: ads and trackers stopped before they reach the page")
                    .staggered(0, base: 0.25)
                Highlight(symbol: "memorychip.fill", color: .green, text: "Native and light on memory and battery")
                    .staggered(1, base: 0.25)
                Highlight(symbol: "hand.raised.fill", color: .blue, text: "No account, no tracking: your data stays on this Mac")
                    .staggered(2, base: 0.25)
            }
        }
    }

    private var bringStuffChoices: some View {
        VStack(spacing: 12) {
            ChoiceCard(title: "No, start fresh", selected: importChoice == nil) { importChoice = nil }
                .staggered(0)
            ForEach(Array(sources.prefix(5).enumerated()), id: \.element.id) { index, source in
                ChoiceCard(title: source.name, subtitle: "Bookmarks and the sites you visit most",
                           selected: importChoice == source.name,
                           art: AnyView(Group {
                               if let icon = icons[source.name] { Image(nsImage: icon).resizable().frame(width: 34, height: 34) }
                               else { Image(systemName: "globe").font(.system(size: 20)).foregroundStyle(.secondary).frame(width: 34, height: 34) }
                           })) {
                    importChoice = source.name
                }
                .staggered(index + 1)
            }
            if let importResult {
                Label(importResult, systemImage: "exclamationmark.circle").font(.system(size: 12)).foregroundStyle(.orange)
            }
        }
        .frame(maxWidth: 380)
    }

    private var searchChoices: some View {
        VStack(spacing: 10) {
            ForEach(Array(SearchEngine.allCases.enumerated()), id: \.element.id) { index, option in
                ChoiceCard(title: option.name, subtitle: option.setupNote, selected: engine == option.rawValue,
                           art: AnyView(Favicon(url: option.homepage, size: 26))) {
                    engine = option.rawValue
                }
                .staggered(index)
            }
        }
        .frame(maxWidth: 380)
    }

    private var guardChoices: some View {
        VStack(spacing: 12) {
            ForEach(Array(BlockingMode.allCases.enumerated()), id: \.element.id) { index, option in
                ChoiceCard(title: option.label + (option == .standard ? " (recommended)" : ""), subtitle: option.detail,
                           selected: blocking == option.rawValue,
                           art: AnyView(IconTile(symbol: option.symbol, colors: option.colors, size: 34))) {
                    blocking = option.rawValue
                }
                .staggered(index)
            }
        }
        .frame(maxWidth: 400)
    }

    private var tabChoices: some View {
        HStack(alignment: .top, spacing: 18) {
            ForEach(Array(TabLayout.allCases.enumerated()), id: \.element.id) { index, option in
                PreviewCard(title: option.label, subtitle: option.detail, selected: tabLayout == option.rawValue) {
                    LayoutPreview(side: option == .side)
                } action: { tabLayout = option.rawValue }
                .staggered(index)
            }
        }
    }

    private var lookChoices: some View {
        VStack(spacing: 26) {
            HStack(alignment: .top, spacing: 14) {
                ForEach(Array(AppearanceMode.allCases.enumerated()), id: \.element.id) { index, option in
                    PreviewCard(title: option.label, subtitle: nil, selected: appearance == option.rawValue) {
                        ThemePreview(mode: option)
                    } action: { appearance = option.rawValue }
                    .staggered(index)
                }
            }
            VStack(spacing: 10) {
                Text("Accent colour").font(.system(size: 12.5, weight: .semibold)).foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    ForEach(AccentChoice.allCases) { option in
                        Button { accent = option.rawValue } label: {
                            Circle()
                                .fill(option.color.map { AnyShapeStyle($0.gradient) }
                                      ?? AnyShapeStyle(AngularGradient(colors: [.red, .orange, .yellow, .green, .blue, .purple, .red], center: .center)))
                                .frame(width: 22, height: 22)
                                .overlay(Circle().strokeBorder(Color.primary.opacity(accent == option.rawValue ? 0.75 : 0), lineWidth: 2)
                                    .padding(accent == option.rawValue ? -4 : 2))
                                .scaleEffect(accent == option.rawValue ? 1.12 : 1)
                                .animation(.spring(response: 0.32, dampingFraction: 0.6), value: accent)
                        }
                        .buttonStyle(GuidePress(scale: 0.85))
                        .help(option.label)
                    }
                }
            }
        }
    }

    private var defaultChoices: some View {
        VStack(spacing: 12) {
            if isDefault {
                ChoiceCard(title: "Ufolio is already your default browser", selected: true,
                           art: AnyView(Image(systemName: "checkmark.seal.fill").font(.system(size: 24)).foregroundStyle(.green))) {}
            } else {
                ChoiceCard(title: "Yes, make Ufolio my default", subtitle: "macOS will ask you to confirm.", selected: makeDefault) { makeDefault = true }
                    .staggered(0)
                ChoiceCard(title: "Not yet, I'm still exploring", selected: !makeDefault) { makeDefault = false }
                    .staggered(1)
            }
        }
        .frame(maxWidth: 380)
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 14) {
            SummaryRow(symbol: "magnifyingglass", text: "Searching with \((SearchEngine(rawValue: engine) ?? .google).name)")
                .staggered(0)
            SummaryRow(symbol: "shield.lefthalf.filled", text: "Force Field: \((BlockingMode(rawValue: blocking) ?? .standard).label)")
                .staggered(1)
            SummaryRow(symbol: tabLayout == TabLayout.side.rawValue ? "sidebar.left" : "rectangle.topthird.inset.filled",
                       text: (TabLayout(rawValue: tabLayout) ?? .top).label)
                .staggered(2)
            SummaryRow(symbol: "paintbrush.fill", text: "\((AppearanceMode(rawValue: appearance) ?? .system).label) theme")
                .staggered(3)
            if let importResult { SummaryRow(symbol: "square.and.arrow.down", text: importResult) }
            if isDefault { SummaryRow(symbol: "checkmark.seal.fill", text: "Ufolio is your default browser") }
            Text("You can change any of these in Settings (⌘,).")
                .font(.system(size: 12)).foregroundStyle(.secondary).padding(.top, 6)
        }
        .frame(maxWidth: 380, alignment: .leading)
    }

    // MARK: Moving between steps

    private func go(_ delta: Int) {
        guard let target = Step(rawValue: step.rawValue + delta) else { return }
        forward = delta > 0
        withAnimation(.spring(response: 0.5, dampingFraction: 0.88)) { step = target }
    }

    private func next() {
        switch step {
        case .bringStuff:
            guard let name = importChoice, let source = sources.first(where: { $0.name == name }) else { importResult = nil; go(1); return }
            importing = true
            DispatchQueue.global(qos: .userInitiated).async {
                let message: String
                do {
                    let pages = try BrowserImporter.importTopSites(from: source)
                    let marks = (try? BrowserImporter.importBookmarks(from: source)) ?? 0
                    message = "Brought over \(marks) bookmarks and \(pages) favourite sites from \(source.name)"
                } catch {
                    message = error.localizedDescription
                }
                DispatchQueue.main.async {
                    importing = false
                    importResult = message
                    if step == .bringStuff { go(1) }   // you might have gone back meanwhile
                }
            }
        case .defaultBrowser:
            if makeDefault && !isDefault {
                DefaultBrowser.makeDefault { isDefault = $0 }
            }
            go(1)
        case .done:
            UserDefaults.standard.set(true, forKey: Prefs.hasOnboarded)
            onDone()
        default:
            go(1)
        }
    }
}

// MARK: - Steps

extension SetupGuide.Step {
    var title: String {
        switch self {
        case .welcome: return "Welcome to Ufolio."
        case .bringStuff: return "Bring your stuff along."
        case .search: return "Pick your search engine."
        case .guardMode: return "How much should Ufolio block?"
        case .tabs: return "Where should your tabs go?"
        case .look: return "Make it yours."
        case .defaultBrowser: return "Make Ufolio your default?"
        case .done: return "You're all set."
        }
    }

    var detail: String {
        switch self {
        case .welcome: return "Light on your Mac, yet seriously powerful. Ads and trackers are blocked before they ever reach the page. Let's set it up: it takes less than a minute."
        case .bringStuff: return "Pick a browser to bring over your bookmarks and favourite sites, and pick up right where you left off."
        case .search: return "Used when you type in the address bar. You can change it any time."
        case .guardMode: return "Force Field blocks ads and trackers before they load, so pages are cleaner and faster."
        case .tabs: return "Tabs along the top, or down the side where long titles have room. Switch any time in Settings."
        case .look: return "Day, Night, or follow your Mac. Then pick an accent colour."
        case .defaultBrowser: return "Links from other apps will open in Ufolio. You can always change this later."
        case .done: return "Fast, private and light. Here's how Ufolio is set up."
        }
    }

    var buttonTitle: String {
        switch self {
        case .welcome: return "Get Started"
        case .done: return "Start Browsing"
        default: return "Next"
        }
    }

    /// Each step tints the backdrop its own colour.
    var hue: Double {
        [0.74, 0.58, 0.52, 0.76, 0.62, 0.92, 0.44, 0.33][rawValue]
    }
}

extension SearchEngine {
    var homepage: URL {
        switch self {
        case .google: return URL(string: "https://www.google.com")!
        case .duckduckgo: return URL(string: "https://duckduckgo.com")!
        case .bing: return URL(string: "https://www.bing.com")!
        case .brave: return URL(string: "https://search.brave.com")!
        case .ecosia: return URL(string: "https://www.ecosia.org")!
        }
    }

    var setupNote: String? {
        switch self {
        case .duckduckgo: return "Doesn't track your searches"
        case .brave: return "Its own private index"
        case .ecosia: return "Plants trees with its profits"
        default: return nil
        }
    }
}

// MARK: - Pieces

/// A slowly shifting wash of colour behind the guide, tinted for each step.
private struct SetupBackdrop: View {
    let hue: Double
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            // Frosted, but solid to the pointer: the page behind can't be clicked through it.
            ClickBlocker()
            VisualEffect(material: .fullScreenUI, blending: .withinWindow)
            RadialGradient(colors: [Color(hue: hue, saturation: 0.55, brightness: 0.85).opacity(scheme == .dark ? 0.45 : 0.55), .clear],
                           center: .topLeading, startRadius: 0, endRadius: 900)
            RadialGradient(colors: [Color(hue: (hue + 0.12).truncatingRemainder(dividingBy: 1), saturation: 0.5, brightness: 0.8)
                                        .opacity(scheme == .dark ? 0.35 : 0.45), .clear],
                           center: .bottomTrailing, startRadius: 0, endRadius: 800)
        }
        .animation(.easeInOut(duration: 0.8), value: hue)
        .contentShape(Rectangle())
        .onTapGesture {}   // clicks around the guide do nothing
    }
}

private struct ChoiceCard: View {
    let title: String
    var subtitle: String? = nil
    let selected: Bool
    var art: AnyView? = nil
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    Circle().strokeBorder(selected ? Color.accentColor : Color.secondary.opacity(0.5), lineWidth: 1.5)
                    Circle().fill(Color.accentColor)
                        .overlay(Image(systemName: "checkmark").font(.system(size: 9, weight: .heavy)).foregroundStyle(.white))
                        .scaleEffect(selected ? 1 : 0.2)
                        .opacity(selected ? 1 : 0)
                }
                .frame(width: 20, height: 20)
                .animation(.spring(response: 0.34, dampingFraction: 0.58), value: selected)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(selected ? Color.accentColor : .primary)
                    if let subtitle {
                        Text(subtitle).font(.system(size: 11.5)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 8)
                if let art { art }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, subtitle == nil ? 15 : 12)
            .background(RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(selected ? AnyShapeStyle(Color.accentColor.opacity(0.12)) : AnyShapeStyle(Color.primary.opacity(hovering ? 0.075 : 0.045))))
            .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous)
                .strokeBorder(selected ? Color.accentColor.opacity(0.85) : Color.primary.opacity(hovering ? 0.14 : 0.08), lineWidth: selected ? 1.5 : 1))
            .shadow(color: .black.opacity(hovering ? 0.14 : 0), radius: 10, y: 4)
            .offset(y: hovering ? -1.5 : 0)
            .contentShape(Rectangle())
        }
        .buttonStyle(GuidePress(scale: 0.98))
        .onHover { hovering = $0 }
        .animation(.spring(response: 0.28, dampingFraction: 0.75), value: hovering)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: selected)
    }
}

private struct PreviewCard<Preview: View>: View {
    let title: String
    let subtitle: String?
    let selected: Bool
    @ViewBuilder let preview: Preview
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                preview
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.1), lineWidth: selected ? 2.5 : 1))
                    .shadow(color: .black.opacity(hovering ? 0.25 : 0.12), radius: hovering ? 10 : 5, y: 3)
                Text(title).font(.system(size: 13, weight: selected ? .semibold : .medium))
                    .foregroundStyle(selected ? Color.accentColor : .primary)
                if let subtitle {
                    Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        .frame(width: 180)
                }
            }
            .scaleEffect(hovering ? 1.025 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(GuidePress(scale: 0.97))
        .onHover { hovering = $0 }
        .animation(.spring(response: 0.3, dampingFraction: 0.72), value: hovering)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: selected)
    }
}

/// A tiny drawing of the window with tabs along the top or down the side.
struct LayoutPreview: View {
    let side: Bool

    var body: some View {
        let frame = Color.primary.opacity(0.08)
        let page = Color(nsColor: .textBackgroundColor)
        let line = Color.primary.opacity(0.18)
        ZStack(alignment: .topLeading) {
            frame
            if side {
                HStack(spacing: 5) {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 3) { ForEach(0..<3) { _ in Circle().fill(line).frame(width: 5, height: 5) } }
                        RoundedRectangle(cornerRadius: 3).fill(line).frame(height: 9)
                        RoundedRectangle(cornerRadius: 3).fill(Color.accentColor.opacity(0.55)).frame(height: 9)
                        ForEach(0..<4) { _ in RoundedRectangle(cornerRadius: 3).fill(line).frame(height: 7) }
                        Spacer()
                    }
                    .frame(width: 52)
                    RoundedRectangle(cornerRadius: 5).fill(page)
                }
                .padding(6)
            } else {
                VStack(spacing: 5) {
                    HStack(spacing: 4) {
                        HStack(spacing: 3) { ForEach(0..<3) { _ in Circle().fill(line).frame(width: 5, height: 5) } }
                        RoundedRectangle(cornerRadius: 3).fill(Color.accentColor.opacity(0.55)).frame(width: 34, height: 9)
                        ForEach(0..<2) { _ in RoundedRectangle(cornerRadius: 3).fill(line).frame(width: 28, height: 7) }
                        Spacer()
                    }
                    RoundedRectangle(cornerRadius: 3).fill(line).frame(height: 9)
                    RoundedRectangle(cornerRadius: 5).fill(page)
                }
                .padding(6)
            }
        }
        .frame(width: 180, height: 120)
    }
}

private struct ThemePreview: View {
    let mode: AppearanceMode

    var body: some View {
        ZStack {
            switch mode {
            case .light: mini(dark: false)
            case .dark: mini(dark: true)
            case .system:
                mini(dark: false)
                mini(dark: true).mask(LinearGradient(stops: [.init(color: .clear, location: 0.5), .init(color: .black, location: 0.5)],
                                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            }
        }
        .frame(width: 120, height: 80)
    }

    private func mini(dark: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 3) {
                ForEach([Color.red, .yellow, .green], id: \.self) { Circle().fill($0.opacity(0.8)).frame(width: 5, height: 5) }
                Spacer()
            }
            .padding(6)
            .background(dark ? Color(white: 0.2) : Color(white: 0.9))
            (dark ? Color(white: 0.12) : Color.white)
                .overlay(Text("Ufolio").font(.system(size: 13, weight: .light, design: .rounded))
                    .foregroundStyle(dark ? Color.white.opacity(0.8) : Color.black.opacity(0.7)))
        }
    }
}

private struct Highlight: View {
    let symbol: String
    let color: Color
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 15, weight: .semibold)).foregroundStyle(color)
                .frame(width: 32, height: 32)
                .background(Circle().fill(color.opacity(0.15)))
            Text(text).font(.system(size: 13.5))
        }
    }
}

private struct SummaryRow: View {
    let symbol: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill").font(.system(size: 16)).foregroundStyle(.green)
            Image(systemName: symbol).font(.system(size: 13)).foregroundStyle(.secondary).frame(width: 18)
            Text(text).font(.system(size: 13.5)).fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct ProgressDots: View {
    let count: Int
    let current: Int
    @Namespace private var pill

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { i in
                Capsule()
                    .fill(i < current ? Color.accentColor.opacity(0.45) : Color.primary.opacity(0.18))
                    .frame(width: i == current ? 22 : 6, height: 6)
                    .overlay {
                        if i == current { Capsule().fill(Color.accentColor.gradient).matchedGeometryEffect(id: "pill", in: pill) }
                    }
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.78), value: current)
    }
}

// MARK: - Fluid motion

/// Presses down a touch while held and springs back, like a button on iPhone.
private struct GuidePress: ButtonStyle {
    var scale: CGFloat = 0.95

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .brightness(configuration.isPressed ? -0.03 : 0)
            .animation(.spring(response: 0.24, dampingFraction: 0.62), value: configuration.isPressed)
    }
}

/// Comes into focus: blurred at the start of a transition, sharp at the end.
private struct GlideBlur: ViewModifier {
    let radius: CGFloat
    func body(content: Content) -> some View { content.blur(radius: radius) }
}

extension AnyTransition {
    fileprivate static func glide(blur radius: CGFloat) -> AnyTransition {
        .modifier(active: GlideBlur(radius: radius), identity: GlideBlur(radius: 0))
    }
}

/// Drifts in shortly after the one before it, so a list arrives as a gentle wave.
private struct Staggered: ViewModifier {
    let index: Int
    let base: Double
    @AppStorage(Prefs.reduceMotion) private var reduceMotion = false
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 10)
            .scaleEffect(shown ? 1 : 0.97, anchor: .top)
            .onAppear {
                guard !reduceMotion else { shown = true; return }
                withAnimation(.spring(response: 0.5, dampingFraction: 0.82).delay(base + Double(index) * 0.05)) { shown = true }
            }
    }
}

extension View {
    fileprivate func staggered(_ index: Int, base: Double = 0.08) -> some View { modifier(Staggered(index: index, base: base)) }
}
