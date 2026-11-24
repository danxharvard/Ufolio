import SwiftUI

/// The private window's colours: a deep night purple, so it's obvious at a glance.
enum PrivateChrome {
    static let toolbar = Color(red: 0.17, green: 0.13, blue: 0.30)
    static let frame = Color(red: 0.11, green: 0.08, blue: 0.21)
    static var tint: Chrome.Tint { Chrome.Tint(toolbar: toolbar, frame: frame, scheme: .dark) }
}

/// The button beside Hush Guard that opens a Private Browsing window.
struct PrivateWindowButton: View {
    let isPrivate: Bool
    @Environment(\.openWindow) private var openWindow
    @State private var hovering = false

    var body: some View {
        Button { openWindow(id: "private") } label: {
            Image(systemName: "eyeglasses")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isPrivate ? Color(red: 0.78, green: 0.70, blue: 1.0) : Color.primary.opacity(0.75))
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
            LinearGradient(colors: [Color(red: 0.16, green: 0.11, blue: 0.32), Color(red: 0.06, green: 0.05, blue: 0.13)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            VStack(spacing: 18) {
                ZStack {
                    Circle().fill(Color.white.opacity(0.06)).frame(width: 120, height: 120)
                    Image(systemName: "eyeglasses")
                        .font(.system(size: 46, weight: .light))
                        .foregroundStyle(LinearGradient(colors: [Color(red: 0.85, green: 0.78, blue: 1.0), Color(red: 0.58, green: 0.48, blue: 0.98)],
                                                        startPoint: .top, endPoint: .bottom))
                }
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
