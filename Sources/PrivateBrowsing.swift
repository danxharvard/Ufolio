import WebKit
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

    var body: some View {
        Button { openWindow(id: "private") } label: {
            ToolbarTile(art: .stealth)
        }
        .buttonStyle(.plain)
        .help("New Stealth Window: browse without saving history (⇧⌘N)")
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

/// The Stealth button's icon: an alien in dark glasses, travelling incognito. (It used to be a
/// half-cloaked saucer, which looked too much like the Force Field saucer beside it.)
struct StealthIcon: View {
    var color: Color

    var body: some View {
        // Drawn as an outline with the same line weight as the toolbar's other icons, with
        // solid dark glasses, so it reads at a glance as "incognito".
        ZStack {
            AlienHead().stroke(color, style: StrokeStyle(lineWidth: 1.3, lineJoin: .round))
                .padding(0.65)
            Group {
                Capsule().frame(width: 5.6, height: 3.3).rotationEffect(.degrees(18)).offset(x: -3.0, y: -0.4)
                Capsule().frame(width: 5.6, height: 3.3).rotationEffect(.degrees(-18)).offset(x: 3.0, y: -0.4)
                Rectangle().frame(width: 1.8, height: 1.0).offset(y: -0.9)
            }
            .foregroundStyle(color)
        }
        .frame(width: ToolbarIcon.glyph - 3, height: ToolbarIcon.glyph)
    }
}

/// An alien's head: a wide dome narrowing to a small chin.
private struct AlienHead: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let w = r.width, h = r.height, x = r.minX, y = r.minY
        p.move(to: CGPoint(x: x + w * 0.5, y: y + h))
        p.addCurve(to: CGPoint(x: x, y: y + h * 0.38),
                   control1: CGPoint(x: x + w * 0.30, y: y + h),
                   control2: CGPoint(x: x, y: y + h * 0.72))
        p.addCurve(to: CGPoint(x: x + w * 0.5, y: y),
                   control1: CGPoint(x: x, y: y + h * 0.12),
                   control2: CGPoint(x: x + w * 0.22, y: y))
        p.addCurve(to: CGPoint(x: x + w, y: y + h * 0.38),
                   control1: CGPoint(x: x + w * 0.78, y: y),
                   control2: CGPoint(x: x + w, y: y + h * 0.12))
        p.addCurve(to: CGPoint(x: x + w * 0.5, y: y + h),
                   control1: CGPoint(x: x + w, y: y + h * 0.72),
                   control2: CGPoint(x: x + w * 0.70, y: y + h))
        p.closeSubpath()
        return p
    }
}

/// The Stealth start page's emblem: a saucer in its cloaking field. A still picture (it used to
/// shimmer in and out as the page appeared).
struct CloakedSaucer: View {
    var body: some View {
        ZStack {
            // A soft violet glow behind it.
            Circle()
                .fill(RadialGradient(colors: [PrivateChrome.lavender.opacity(0.28), .clear], center: .center, startRadius: 0, endRadius: 70))
                .frame(width: 140, height: 140)
            // Faint rings, like a field around it.
            ForEach(0..<2) { i in
                Ellipse()
                    .strokeBorder(PrivateChrome.lavender.opacity(0.22), style: StrokeStyle(lineWidth: 1, dash: [3, 5]))
                    .frame(width: 130 + CGFloat(i) * 26, height: 54 + CGFloat(i) * 12)
                    .offset(y: 14)
            }
            SaucerArt(beam: 0)
                .frame(width: 104, height: 104)
                .opacity(0.95)
        }
        .accessibilityHidden(true)
    }
}

/// Keeps Stealth pages in the app's own appearance (the window around them is always dark).
enum StealthPageLook {
    private static var observation: NSKeyValueObservation?

    static func apply(to view: WKWebView) {
        view.appearance = NSApp.effectiveAppearance
        guard observation == nil else { return }
        observation = NSApp.observe(\.effectiveAppearance) { _, _ in
            DispatchQueue.main.async {
                for model in BrowserModel.all.allObjects where model.isPrivate {
                    for tab in model.tabs where !tab.isAsleep { tab.webView.appearance = NSApp.effectiveAppearance }
                }
            }
        }
    }
}
