import SwiftUI

// Project Fluid: controls drawn by Ufolio itself, light enough to build in a moment and animated
// with nothing but shapes (no pictures, blur or extra windows, so they cost next to no memory).

/// A switch like the iPhone's: the knob glides across on a soft spring, the track fills with the
/// accent colour, and the knob stretches a little while you hold it. Replaces macOS's own switch
/// control, which was a separate AppKit view per switch: a Settings page with twenty of them took
/// noticeably longer to open.
struct FluidSwitchStyle: ToggleStyle {
    var size = CGSize(width: 32, height: 19)

    func makeBody(configuration: Configuration) -> some View {
        FluidSwitch(isOn: configuration.$isOn, size: size)
            .accessibilityRepresentation { Toggle(isOn: configuration.$isOn) { configuration.label } }
    }
}

struct FluidSwitch: View {
    @Binding var isOn: Bool
    var size = CGSize(width: 32, height: 19)
    @Environment(\.isEnabled) private var enabled

    static let spring = Animation.spring(response: 0.3, dampingFraction: 0.72)

    var body: some View {
        Button { withAnimation(Self.spring) { isOn.toggle() } } label: { EmptyView() }
            .buttonStyle(Track(isOn: isOn, size: size))
            .opacity(enabled ? 1 : 0.45)
            // A change from elsewhere (a menu, another window) glides too.
            .animation(Self.spring, value: isOn)
    }

    private struct Track: ButtonStyle {
        let isOn: Bool
        let size: CGSize

        func makeBody(configuration: Configuration) -> some View {
            let inset: CGFloat = 2
            let knob = size.height - inset * 2
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule().fill(isOn ? Color.accentColor : Color.primary.opacity(0.17))
                Capsule().strokeBorder(Color.primary.opacity(isOn ? 0 : 0.06), lineWidth: 0.5)
                Capsule()
                    .fill(Color.white)
                    .frame(width: knob + (configuration.isPressed ? 5 : 0), height: knob)
                    .shadow(color: .black.opacity(0.22), radius: 1.2, y: 0.6)
                    .padding(inset)
            }
            .frame(width: size.width, height: size.height)
            .contentShape(Capsule())
            .animation(.spring(response: 0.22, dampingFraction: 0.8), value: configuration.isPressed)
        }
    }
}
