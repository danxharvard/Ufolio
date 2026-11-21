import SwiftUI

/// The small "Personalise Start Page" button in the start page's corner.
struct PersonaliseButton: View {
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .semibold))
                Text("Personalise Start Page")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Capsule().fill(.ultraThinMaterial))
            .overlay(Capsule().strokeBorder(Color.primary.opacity(hovering ? 0.16 : 0.08)))
            .foregroundStyle(hovering ? .primary : .secondary)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
        .help("Show your local weather on the start page")
    }
}

/// The popup that asks for your town or postcode.
struct PersonaliseCard: View {
    let onDone: () -> Void
    @ObservedObject private var weather = LocalWeather.shared
    @State private var query = ""
    @State private var searching = false
    @State private var error: String?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [Color(red: 0.62, green: 0.49, blue: 0.96).opacity(0.35), .clear],
                                             startPoint: .top, endPoint: .bottom))
                        .frame(width: 96, height: 96)
                    IconTile(symbol: "location.circle.fill",
                             colors: [Color(red: 0.45, green: 0.62, blue: 1.0), Color(red: 0.42, green: 0.30, blue: 0.90)],
                             size: 58)
                }
                Text("Personalise your start page")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                Text("Tell Hush your town or postcode and your start page will show the local weather. More personal touches are on the way.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 10)
            }
            .padding(.top, 28)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Town or postcode", text: $query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 15))
                        .focused($focused)
                        .onSubmit(save)
                        .disabled(searching)
                    if searching { ProgressView().controlSize(.small) }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Color.primary.opacity(0.06)))
                .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(focused ? Color.accentColor.opacity(0.7) : Color.primary.opacity(0.1), lineWidth: focused ? 2 : 1))

                if let error {
                    Label(error, systemImage: "exclamationmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                        .transition(.opacity)
                } else if let place = weather.place {
                    HStack(spacing: 6) {
                        Image(systemName: "mappin.circle.fill").foregroundStyle(Color.accentColor)
                        Text("Currently: **\(place.name)**\(place.detail.isEmpty ? "" : ", \(place.detail)")")
                        if let t = weather.temperature {
                            Spacer(minLength: 4)
                            Image(systemName: weather.symbol).symbolRenderingMode(.multicolor)
                            Text("\(t)°")
                        }
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 32)
            .padding(.top, 22)

            HStack(spacing: 6) {
                Image(systemName: "hand.raised.fill")
                Text("Hush never uses your Mac’s location. What you type goes to Apple to find the place, and only its rough position goes to Open-Meteo for the weather.")
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(.system(size: 11))
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 32)
            .padding(.top, 14)

            HStack {
                if weather.isPersonalised {
                    Button("Remove") { weather.clear(); onDone() }
                        .buttonStyle(.link)
                }
                Spacer()
                Button("Cancel", action: onDone)
                    .keyboardShortcut(.cancelAction)
                    .controlSize(.large)
                Button("Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .controlSize(.large)
                    .disabled(searching || query.trimmingCharacters(in: .whitespaces).count < 2)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 22)
        }
        .frame(width: 460)
        .animation(.easeOut(duration: 0.2), value: error)
        .onAppear { DispatchQueue.main.async { focused = true } }
    }

    private func save() {
        guard !searching, query.trimmingCharacters(in: .whitespaces).count >= 2 else { return }
        searching = true
        error = nil
        Task { @MainActor in
            let result = await LocalWeather.lookUp(query)
            searching = false
            switch result {
            case .success(let place):
                weather.save(place)
                onDone()
            case .failure(let problem):
                error = problem.message
                focused = true
            }
        }
    }
}
