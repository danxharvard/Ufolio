import SwiftUI
import AppKit

/// Every question Hush asks uses this one card: a small animated scene (in the Hush Guard
/// style), a title, a line or two of explanation and clear buttons. Each kind of question has
/// its own colours and motion.
struct HushDialog: Identifiable {
    let id = UUID()

    enum Art {
        case symbol(String)          // an SF Symbol on a gradient tile
        case site(URL?)              // a website's icon
        case image(NSImage)          // e.g. an app's or extension's icon
    }

    /// How the little particles move around the art.
    enum Motion { case drift, orbit, rise, pulse, sparkle }

    enum Theme {
        case hush, danger, permission, save, caution

        var colors: [Color] {
            switch self {
            case .hush: return [Color(red: 0.62, green: 0.49, blue: 1.0), Color(red: 0.38, green: 0.26, blue: 0.86)]
            case .danger: return [Color(red: 1.0, green: 0.42, blue: 0.38), Color(red: 0.86, green: 0.20, blue: 0.24)]
            case .permission: return [Color(red: 0.35, green: 0.65, blue: 1.0), Color(red: 0.16, green: 0.42, blue: 0.95)]
            case .save: return [Color(red: 0.35, green: 0.82, blue: 0.55), Color(red: 0.15, green: 0.60, blue: 0.38)]
            case .caution: return [Color(red: 1.0, green: 0.72, blue: 0.25), Color(red: 0.95, green: 0.50, blue: 0.12)]
            }
        }
    }

    struct Choice {
        enum Role { case primary, destructive, cancel, normal }
        let title: String
        var role: Role = .normal
    }

    var art: Art
    var badge: String? = nil
    var theme: Theme = .hush
    var motion: Motion = .orbit
    var title: String
    var message: String = ""
    var note: (symbol: String, text: String)? = nil
    var checkbox: String? = nil
    var choices: [Choice]
    /// Called with the index of the button chosen and whether the checkbox was ticked.
    var completion: (Int, Bool) -> Void = { _, _ in }

    var cancelIndex: Int { choices.firstIndex { $0.role == .cancel } ?? choices.count - 1 }
    var defaultIndex: Int? { choices.firstIndex { $0.role == .primary || $0.role == .destructive } }
}

/// A queue of dialogs for one window: shown one at a time, in order.
final class DialogHost: ObservableObject {
    @Published private(set) var queue: [HushDialog] = []

    /// Hosts for windows that aren't browser windows.
    static let settings = DialogHost()
    static let history = DialogHost()

    var current: HushDialog? { queue.first }

    func present(_ dialog: HushDialog) {
        queue.append(dialog)
    }

    func finish(_ dialog: HushDialog, choice: Int, checked: Bool) {
        queue.removeAll { $0.id == dialog.id }
        dialog.completion(choice, checked)
    }

    /// Answers every waiting dialog with Cancel (e.g. when Hush quits or the window closes).
    func cancelAll() {
        let waiting = queue
        queue = []
        for dialog in waiting { dialog.completion(dialog.cancelIndex, false) }
    }

    /// True when a window already has questions waiting (so a page can't pile more on).
    static func isBusy(_ window: NSWindow?) -> Bool {
        (BrowserModel.all.allObjects.first { $0.window === window && window != nil }?.dialogs.queue.count ?? 0) >= 2
    }

    /// The host for whichever window you're using: a browser window, Settings or History.
    static var active: DialogHost {
        let key = NSApp.keyWindow
        if let model = BrowserModel.all.allObjects.first(where: { $0.window === key && key != nil }) { return model.dialogs }
        let id = key?.identifier?.rawValue.lowercased() ?? ""
        if id.contains("settings") || key?.title.contains("Settings") == true { return .settings }
        if id.contains("history") { return .history }
        return BrowserModel.frontmostNormal?.dialogs ?? .settings
    }

    /// Shows a dialog over the browser window it belongs to, or as a standard alert if there
    /// isn't one (so a question is never lost).
    static func show(_ dialog: HushDialog, in window: NSWindow?) {
        if let model = BrowserModel.all.allObjects.first(where: { $0.window === window && window != nil }) ?? (window == nil ? BrowserModel.frontmostNormal : nil) {
            model.dialogs.present(dialog)
        } else {
            fallback(dialog, window: window)
        }
    }

    private static func fallback(_ dialog: HushDialog, window: NSWindow?) {
        let alert = NSAlert()
        alert.messageText = dialog.title
        alert.informativeText = dialog.message
        for choice in dialog.choices { alert.addButton(withTitle: choice.title) }
        if let checkbox = dialog.checkbox {
            alert.showsSuppressionButton = true
            alert.suppressionButton?.title = checkbox
        }
        let finish: (NSApplication.ModalResponse) -> Void = { response in
            let index = response.rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
            dialog.completion(max(0, min(dialog.choices.count - 1, index)), alert.suppressionButton?.state == .on)
        }
        if let window { alert.beginSheetModal(for: window, completionHandler: finish) } else { finish(alert.runModal()) }
    }
}

extension View {
    /// Shows the host's dialogs as cards over this view.
    func hushDialogs(_ host: DialogHost) -> some View {
        modifier(DialogOverlay(host: host))
    }
}

private struct DialogOverlay: ViewModifier {
    @ObservedObject var host: DialogHost

    func body(content: Content) -> some View {
        content
            .overlay {
                if let dialog = host.current {
                    LaunchCardOverlay {
                        HushDialogCard(dialog: dialog) { choice, checked in
                            host.finish(dialog, choice: choice, checked: checked)
                        }
                    }
                    .id(dialog.id)
                    .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.2), value: host.current?.id)
            .onReceive(NotificationCenter.default.publisher(for: QuitHelper.closeSheets)) { _ in host.cancelAll() }
    }
}

struct HushDialogCard: View {
    let dialog: HushDialog
    let onFinish: (Int, Bool) -> Void
    @State private var checked = false

    var body: some View {
        VStack(spacing: 0) {
            DialogScene(art: dialog.art, badge: dialog.badge, colors: dialog.theme.colors, motion: dialog.motion)
                .frame(height: 118)

            VStack(spacing: 6) {
                Text(dialog.title)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                if !dialog.message.isEmpty {
                    ScrollView {
                        Text(dialog.message)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity)
                    }
                    .frame(maxHeight: 150)
                    .fixedSize(horizontal: false, vertical: dialog.message.count < 400)
                }
                if let note = dialog.note {
                    Label(note.text, systemImage: note.symbol)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                }
                if let checkbox = dialog.checkbox {
                    Toggle(checkbox, isOn: $checked)
                        .toggleStyle(.checkbox)
                        .font(.system(size: 11.5))
                        .padding(.top, 4)
                }
            }
            .padding(.horizontal, 22)

            buttons
                .controlSize(.large)
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 18)
        }
        .frame(width: 300)
    }

    @ViewBuilder private var buttons: some View {
        if dialog.choices.count <= 2 {
            // Two choices side by side, the main one on the right (as on the Mac).
            HStack(spacing: 8) {
                ForEach(Array(dialog.choices.enumerated()).sorted { order($0.element) < order($1.element) }, id: \.offset) { index, choice in
                    button(index, choice)
                }
            }
        } else {
            // Three or more: stacked, the main one first.
            VStack(spacing: 7) {
                ForEach(Array(dialog.choices.enumerated()).sorted { order($1.element) < order($0.element) }, id: \.offset) { index, choice in
                    button(index, choice)
                }
            }
        }
    }

    private func order(_ choice: HushDialog.Choice) -> Int {
        switch choice.role {
        case .cancel: return 0
        case .normal: return 1
        case .primary, .destructive: return 2
        }
    }

    @ViewBuilder private func button(_ index: Int, _ choice: HushDialog.Choice) -> some View {
        let main = choice.role == .primary || choice.role == .destructive
        let colors = choice.role == .destructive ? HushDialog.Theme.danger.colors : dialog.theme.colors
        Button { onFinish(index, checked) } label: { Text(choice.title).frame(maxWidth: .infinity) }
            .buttonStyle(DialogButtonStyle(main: main, colors: colors))
            .keyboardShortcut(main && index == dialog.defaultIndex ? .defaultAction
                              : (index == dialog.cancelIndex && choice.role == .cancel ? .cancelAction : nil))
    }
}

/// Hush's dialog buttons: rounded, the main one in the dialog's own colours, the others a soft
/// glass button. They look the same whether or not the window is in front.
private struct DialogButtonStyle: ButtonStyle {
    let main: Bool
    let colors: [Color]
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: main ? .semibold : .medium))
            .foregroundStyle(main ? Color.white : Color.primary)
            .frame(height: 34)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(main ? AnyShapeStyle(LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom))
                               : AnyShapeStyle(Color.primary.opacity(hovering ? 0.12 : 0.08)))
            )
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(main ? Color.white.opacity(0.18) : Color.primary.opacity(0.06)))
            .brightness(configuration.isPressed ? -0.06 : (main && hovering ? 0.04 : 0))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// The animated top of every dialog: drifting stars, a soft glow, the art gently floating,
/// and particles that move in the dialog's own way.
struct DialogScene: View {
    let art: HushDialog.Art
    let badge: String?
    let colors: [Color]
    let motion: HushDialog.Motion
    @AppStorage(Prefs.reduceMotion) private var reduceMotion = false

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { context in
            let t = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
            GeometryReader { geo in
                let center = CGPoint(x: geo.size.width / 2, y: geo.size.height * 0.56)
                ZStack {
                    GuardStars(on: true, t: t, size: geo.size)
                    Circle()
                        .fill(RadialGradient(colors: [colors[0].opacity(0.32), .clear], center: .center, startRadius: 0, endRadius: 54))
                        .frame(width: 108, height: 108)
                        .scaleEffect(motion == .pulse ? 1 + 0.06 * sin(t * 2.4) : 1)
                        .position(center)
                    particles(t: t, center: center)
                    artView(t: t)
                        .position(x: center.x, y: center.y + sin(t * 1.4) * 2.5)
                }
            }
        }
    }

    @ViewBuilder private func particles(t: Double, center: CGPoint) -> some View {
        switch motion {
        case .drift:
            // Bits floating away and fading: something being let go.
            ForEach(0..<9, id: \.self) { i in
                let phase = ((t * 0.32) + Double(i) / 9).truncatingRemainder(dividingBy: 1)
                let angle = Double(i) * 2.399 + 0.6
                let distance = 26 + phase * 38
                Circle().fill(i % 3 == 0 ? colors[0] : Color(red: 0.70, green: 0.60, blue: 1.0))
                    .frame(width: 5 - 2.5 * phase, height: 5 - 2.5 * phase)
                    .opacity((1 - phase) * 0.9)
                    .position(x: center.x + cos(angle) * distance, y: center.y + sin(angle) * distance * 0.8)
            }
        case .orbit:
            // Beads circling, like a request waiting for an answer.
            ForEach(0..<5, id: \.self) { i in
                let angle = t * 0.9 + Double(i) * (2 * .pi / 5)
                Circle().fill(colors[0])
                    .frame(width: 4.5, height: 4.5)
                    .opacity(0.55 + 0.4 * sin(t * 1.7 + Double(i)))
                    .position(x: center.x + cos(angle) * 44, y: center.y + sin(angle) * 30)
            }
        case .rise:
            // Sparks rising and settling: something being kept safe.
            ForEach(0..<8, id: \.self) { i in
                let phase = ((t * 0.28) + Double(i) / 8).truncatingRemainder(dividingBy: 1)
                let x = center.x + (Double(i) - 3.5) * 11 + sin(t + Double(i)) * 3
                Image(systemName: "sparkle").font(.system(size: 7 - 3 * phase))
                    .foregroundStyle(colors[0])
                    .opacity(sin(phase * .pi) * 0.9)
                    .position(x: x, y: center.y + 34 - phase * 66)
            }
        case .pulse:
            // Rings spreading out: a page asking for your attention.
            ForEach(0..<3, id: \.self) { i in
                let phase = ((t * 0.45) + Double(i) / 3).truncatingRemainder(dividingBy: 1)
                Circle().strokeBorder(colors[0].opacity((1 - phase) * 0.6), lineWidth: 1.5)
                    .frame(width: 56 + phase * 70, height: 56 + phase * 70)
                    .position(center)
            }
        case .sparkle:
            // Twinkling stars around the art: something new arriving.
            ForEach(0..<6, id: \.self) { i in
                let angle = Double(i) * 1.047 + 0.3
                let twinkle = (sin(t * 2.2 + Double(i) * 1.3) + 1) / 2
                Image(systemName: "sparkle").font(.system(size: 6 + 5 * twinkle))
                    .foregroundStyle(colors[0])
                    .opacity(0.3 + 0.7 * twinkle)
                    .position(x: center.x + cos(angle) * 46, y: center.y + sin(angle) * 32)
            }
        }
    }

    @ViewBuilder private func artView(t: Double) -> some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                switch art {
                case .symbol(let name):
                    IconTile(symbol: name, colors: colors, size: 54)
                case .site(let url):
                    Favicon(url: url, size: 34)
                        .frame(width: 54, height: 54)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.regularMaterial))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
                case .image(let image):
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fit).frame(width: 54, height: 54)
                }
            }
            .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
            if let badge {
                IconTile(symbol: badge, colors: colors, size: 22)
                    .rotationEffect(.degrees(motion == .drift ? sin(t * 2.2) * 8 : 0))
                    .offset(x: 7, y: 7)
            }
        }
    }
}

/// Questions asked from more than one place.
enum HushDialogs {
    static func clearHistory(in host: DialogHost) {
        host.present(HushDialog(
            art: .symbol("clock.arrow.circlepath"), badge: "trash.fill", theme: .danger, motion: .drift,
            title: "Clear all history?",
            message: "This removes every page Ufolio remembers, including suggestions, recently closed tabs and the privacy report. It can’t be undone.",
            choices: [.init(title: "Cancel", role: .cancel), .init(title: "Clear History", role: .destructive)],
            completion: { choice, _ in
                guard choice == 1 else { return }
                HistoryStore.shared.clear()
                RecentlyClosed.shared.clear()
                PrivacyReport.shared.reset()
            }))
    }
}
