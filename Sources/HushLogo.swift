import SwiftUI

/// The Hush mark ("Eclipse"): a crescent moon quietly swallowing a tracker.
/// Drawn in code, so it's sharp at every size and can animate.
///
/// - `eclipse` 0…1 animates the tracker dot from beside the moon (0) to tucked
///   inside its curve and faded (1), the resting state.
struct HushMark: View {
    var color: Color = .white
    var eclipse: CGFloat = 1
    var showStars = true
    /// Draws the moon dimmed (used when Hush Guard is off).
    var outlined = false

    var body: some View {
        GeometryReader { geo in
            let d = min(geo.size.width, geo.size.height)
            ZStack {
                // The tracker: slides into the moon's curve and fades away.
                Circle()
                    .fill(color.opacity(0.85 - 0.6 * eclipse))
                    .frame(width: d * (0.17 - 0.03 * eclipse), height: d * (0.17 - 0.03 * eclipse))
                    .offset(x: d * (0.32 - 0.14 * eclipse), y: d * (-0.08 - 0.03 * eclipse))

                // The crescent: a disc with a smaller disc cut out of its upper right.
                ZStack {
                    // "Off" is a dimmed moon: same shape, clearly quieter.
                    Circle().fill(outlined ? color.opacity(0.4) : color)
                    Circle()
                        .fill(Color.black)
                        .frame(width: d * 0.62 * 0.84, height: d * 0.62 * 0.84)
                        .offset(x: d * 0.62 * 0.21, y: -d * 0.62 * 0.14)
                        .blendMode(.destinationOut)
                }
                .frame(width: d * 0.62, height: d * 0.62)
                .compositingGroup()
                .offset(x: -d * 0.06, y: d * 0.03)

                if showStars {
                    Circle().fill(color.opacity(0.85)).frame(width: d * 0.055, height: d * 0.055)
                        .offset(x: d * 0.31, y: -d * 0.32)
                    Circle().fill(color.opacity(0.65)).frame(width: d * 0.035, height: d * 0.035)
                        .offset(x: d * 0.40, y: -d * 0.19)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityLabel("Hush")
    }
}

/// The Hush mark on its twilight tile, as in the app icon.
struct HushLogoTile: View {
    var size: CGFloat
    var eclipse: CGFloat = 1

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.62, green: 0.49, blue: 0.96),
                                              Color(red: 0.36, green: 0.27, blue: 0.75),
                                              Color(red: 0.16, green: 0.13, blue: 0.38)],
                                     startPoint: .topTrailing, endPoint: .bottomLeading))
            HushMark(eclipse: eclipse)
                .padding(size * 0.12)
        }
        .frame(width: size, height: size)
        .shadow(color: Color(red: 0.3, green: 0.2, blue: 0.7).opacity(0.35), radius: size * 0.12, y: size * 0.05)
    }
}

/// The logo playing its eclipse once: the tracker drifts behind the moon and fades.
struct AnimatedHushLogo: View {
    var size: CGFloat
    @State private var eclipse: CGFloat = 0
    @AppStorage(Prefs.reduceMotion) private var reduceMotion = false

    var body: some View {
        HushLogoTile(size: size, eclipse: eclipse)
            .onAppear {
                guard !reduceMotion else { eclipse = 1; return }
                withAnimation(.easeInOut(duration: 1.4).delay(0.35)) { eclipse = 1 }
            }
    }
}
