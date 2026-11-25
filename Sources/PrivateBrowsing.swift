import SwiftUI

/// The private window's colours: a deep night purple, so it's obvious at a glance.
enum PrivateChrome {
    /// The one purple laid over the dark frosted glass of the whole Stealth window (toolbar, tab
    /// column, start page alike), instead of separate solid colours that never quite matched.
    static let glassTint = Color(red: 0.36, green: 0.22, blue: 0.80).opacity(0.28)
    /// The toolbar and selected tab use the same light veil as a normal window; the frame adds nothing.
    static var tint: Chrome.Tint { Chrome.Tint(toolbar: Color.white.opacity(0.045), frame: .clear, scheme: .dark) }
    static let lavender = Color(red: 0.78, green: 0.70, blue: 1.0)
}

/// The button beside Hush Guard that opens a Private Browsing window.
struct PrivateWindowButton: View {
    let isPrivate: Bool
    @Environment(\.openWindow) private var openWindow
    @State private var hovering = false

    var body: some View {
        Button { openWindow(id: "private") } label: {
            StealthIcon(color: isPrivate ? PrivateChrome.lavender : Color.primary.opacity(0.75))
                .frame(width: 28, height: 26)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.primary.opacity(hovering ? 0.08 : 0)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("New Stealth Window (⇧⌘N)")
    }
}

/// What a new tab shows in a private window.
struct PrivateStartPage: View {
    var body: some View {
        ZStack {
            // The same dark frosted purple glass as the rest of the Stealth window.
            VisualEffect(material: .underWindowBackground, blending: .behindWindow, appearance: NSAppearance(named: .darkAqua))
                .ignoresSafeArea()
            PrivateChrome.glassTint.ignoresSafeArea()
            VStack(spacing: 18) {
                CloakedSaucer()
                    .frame(width: 150, height: 120)
                Text("Stealth Mode")
                    .font(.system(size: 34, weight: .thin, design: .rounded))
                    .foregroundStyle(.white)
                Text("Ufolio won’t remember the pages you visit, what you search for or what you type in this window. Cookies and website data are kept in memory only and vanish when you close it.")
                    .font(.system(size: 13.5))
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 460)
                VStack(alignment: .leading, spacing: 10) {
                    PrivateFact(symbol: "clock.arrow.circlepath", text: "No history, suggestions or recently closed tabs")
                    PrivateFact(symbol: "lock.shield.fill", text: "Force Field keeps blocking ads and trackers")
                    PrivateFact(symbol: "puzzlepiece.extension.fill", text: "Extensions are switched off here")
                    PrivateFact(symbol: "info.circle.fill", text: "Downloads and bookmarks you make are still kept. Your internet provider and the sites you visit can still see your visits.")
                }
                .padding(18)
                .frame(maxWidth: 460, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.06)))
            }
            .padding(40)
        }
        .environment(\.colorScheme, .dark)
    }
}

private struct PrivateFact: View {
    let symbol: String
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: symbol).foregroundStyle(Color(red: 0.75, green: 0.66, blue: 1.0)).frame(width: 18)
            Text(text).font(.system(size: 12.5)).foregroundStyle(.white.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}


// MARK: - The Stealth saucer

/// A small saucer, half cloaked: the Stealth button's icon.
struct StealthIcon: View {
    var color: Color

    var body: some View {
        ZStack {
            HushMark(color: color.opacity(0.35), showStars: false)
            HushMark(color: color, showStars: false)
                .mask(LinearGradient(colors: [.black, .black, .clear], startPoint: .leading, endPoint: .trailing))
        }
        .frame(width: 19, height: 15)
    }
}

/// The Stealth start page's emblem: a saucer shimmering in and out of its cloaking field, with
/// a band of light sweeping across it. Still with Reduce Motion or Effects off.
struct CloakedSaucer: View {
    @State private var cloaked = false
    @State private var sweep = false
    @Environment(\.controlActiveState) private var activeState

    var body: some View {
        ZStack {
            // A soft violet glow behind it.
            Circle()
                .fill(RadialGradient(colors: [PrivateChrome.lavender.opacity(0.28), .clear], center: .center, startRadius: 0, endRadius: 70))
                .frame(width: 140, height: 140)
            // Faint rings, like a field around it.
            ForEach(0..<2) { i in
                Ellipse()
                    .strokeBorder(PrivateChrome.lavender.opacity(cloaked ? 0.10 : 0.22), style: StrokeStyle(lineWidth: 1, dash: [3, 5]))
                    .frame(width: 130 + CGFloat(i) * 26, height: 54 + CGFloat(i) * 12)
                    .offset(y: 14)
            }
            SaucerArt(beam: 0)
                .frame(width: 104, height: 104)
                .opacity(cloaked ? 0.32 : 0.95)
                .overlay {
                    // The shimmer: a bright band passing over the saucer (and only the saucer).
                    GeometryReader { g in
                        LinearGradient(colors: [.clear, .white.opacity(0.6), .clear], startPoint: .leading, endPoint: .trailing)
                            .frame(width: g.size.width * 0.4)
                            .offset(x: sweep ? g.size.width : -g.size.width * 0.4)
                    }
                    .mask(SaucerArt(beam: 0))
                    .allowsHitTesting(false)
                }
        }
        .onAppear { animate(Effects.on) }
        .onChange(of: activeState) { _, state in animate(Effects.on && state != .inactive) }
        .accessibilityHidden(true)
    }

    private func animate(_ on: Bool) {
        guard on else {
            var still = Transaction(animation: nil)
            still.disablesAnimations = true
            withTransaction(still) { cloaked = false; sweep = false }
            return
        }
        withAnimation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true)) { cloaked = true }
        withAnimation(.linear(duration: 2.2).delay(0.4).repeatForever(autoreverses: false)) { sweep = true }
    }
}
