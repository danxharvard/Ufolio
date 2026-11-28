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

/// A drop-down drawn by Ufolio: the chosen value with up/down arrows, which opens a small panel of
/// choices that glide in one after another; picking one slides the tick across to it before the
/// panel closes. Replaces macOS's pop-up button in Settings, each of which was an AppKit view of
/// its own that the page had to build, lay out and track the pointer for. Shapes and text only;
/// the panel exists only while open.
struct FluidPicker<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(value: Value, label: String)]
    @State private var open = false
    @State private var hovering = false
    @Environment(\.isEnabled) private var enabled

    init(selection: Binding<Value>, options: [(Value, String)]) {
        _selection = selection
        self.options = options.map { (value: $0.0, label: $0.1) }
    }

    /// The chosen value's name, or "Custom" for one that isn't in the list (left by an older
    /// version, say): the button used to go blank.
    private var current: String { options.first { $0.value == selection }?.label ?? "Custom" }

    var body: some View {
        Button { open.toggle() } label: {
            HStack(spacing: 6) {
                Text(current)
                    .lineLimit(1)
                    .contentTransition(.opacity)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .font(.system(size: 12.5))
            .padding(.leading, 9).padding(.trailing, 7)
            .frame(height: 22)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.primary.opacity(open ? 0.12 : hovering ? 0.09 : 0.06)))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
            .scaleEffect(open ? 0.97 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(enabled ? 1 : 0.45)
        .onHover { hovering = $0 }
        .animation(.snappy(duration: 0.18), value: hovering)
        .animation(FluidSwitch.spring, value: open)
        .animation(.easeOut(duration: 0.15), value: selection)
        .fixedSize()
        .popover(isPresented: $open, arrowEdge: .bottom) {
            FluidPickerList(options: options, selection: selection) { picked in
                withAnimation(.easeOut(duration: 0.15)) { selection = picked }
                // A moment to see the tick move, then the panel goes.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) { open = false }
            }
        }
        .accessibilityRepresentation {
            Picker("", selection: $selection) { ForEach(options, id: \.value) { Text($0.label).tag($0.value) } }
        }
    }
}

private struct FluidPickerList<Value: Hashable>: View {
    let options: [(value: Value, label: String)]
    let selection: Value
    let choose: (Value) -> Void
    @State private var shown = false
    @State private var picked: Value?
    @State private var hovered: Value?
    @Namespace private var tick

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(Array(options.enumerated()), id: \.element.value) { index, option in
                let chosen = (picked ?? selection) == option.value
                Button { picked = option.value; choose(option.value) } label: {
                    HStack(spacing: 7) {
                        ZStack {
                            if chosen {
                                Image(systemName: "checkmark").font(.system(size: 10, weight: .bold))
                                    .matchedGeometryEffect(id: "tick", in: tick)
                            }
                        }
                        .frame(width: 12)
                        Text(option.label).font(.system(size: 12.5)).lineLimit(1)
                        Spacer(minLength: 10)
                    }
                    .foregroundStyle(hovered == option.value ? Color.white : Color.primary)
                    .padding(.horizontal, 8)
                    .frame(height: 24)
                    .background(RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(hovered == option.value ? Color.accentColor : Color.clear))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { inside in if inside { hovered = option.value } else if hovered == option.value { hovered = nil } }
                // Each choice glides in just after the one above it.
                .opacity(shown ? 1 : 0)
                .offset(y: shown ? 0 : -5)
                .animation(.spring(response: 0.32, dampingFraction: 0.82).delay(Double(min(index, 10)) * 0.015), value: shown)
            }
        }
        .padding(5)
        .frame(minWidth: 150)
        .animation(.easeOut(duration: 0.15), value: picked)
        .animation(.snappy(duration: 0.12), value: hovered)
        .onAppear { shown = true }
    }
}
