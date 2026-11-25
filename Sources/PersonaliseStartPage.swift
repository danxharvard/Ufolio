import SwiftUI
import MapKit

/// Live place suggestions while you type a town or postcode (Apple Maps autocomplete).
/// Doesn't use or ask for your Mac's location.
final class PlaceSearch: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    struct Suggestion: Identifiable, Equatable {
        let id = UUID()
        let title: String
        let subtitle: String
        let completion: MKLocalSearchCompletion
    }

    @Published private(set) var suggestions: [Suggestion] = []
    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = .address
    }

    func update(_ text: String) {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.count < 2 || query.count > 100 {
            completer.cancel()
            suggestions = []
        } else {
            completer.queryFragment = query
        }
    }

    func cancel() { completer.cancel() }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let found = completer.results.prefix(5).map {
            Suggestion(title: $0.title, subtitle: $0.subtitle, completion: $0)
        }
        DispatchQueue.main.async { self.suggestions = Array(found) }
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        DispatchQueue.main.async { self.suggestions = [] }
    }

    /// Looks up where a suggestion is.
    static func resolve(_ suggestion: Suggestion) async -> LocalWeather.Place? {
        let search = MKLocalSearch(request: MKLocalSearch.Request(completion: suggestion.completion))
        guard let item = try? await search.start().mapItems.first else { return nil }
        return LocalWeather.place(from: item.placemark, fallback: suggestion.title)
    }
}

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
        .animation(.snappy(duration: 0.16), value: hovering)
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
    @StateObject private var search = PlaceSearch()
    @State private var highlighted = 0
    @State private var keyMonitor: Any?

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
                Text("Tell Ufolio your town or postcode and your start page will show the local weather. More personal touches are on the way.")
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

                if !search.suggestions.isEmpty && !searching {
                    suggestionList
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

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
                Text("Ufolio never uses your Mac’s location. What you type goes to Apple to find the place, and only its rough position goes to Open-Meteo for the weather.")
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
        .animation(.smooth(duration: 0.26), value: error)
        .animation(.easeOut(duration: 0.15), value: search.suggestions)
        .onChange(of: query) { _, text in
            error = nil
            highlighted = 0
            search.update(text)
        }
        .onAppear {
            DispatchQueue.main.async { focused = true }
            // ↑ and ↓ move through the suggestions while the field is focused.
            // Never two at once (a sheet can appear twice; the first monitor used to be left running).
            if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                let count = search.suggestions.count
                guard focused, count > 0 else { return event }
                switch event.keyCode {
                case 125: highlighted = (highlighted + 1) % count; return nil
                case 126: highlighted = (highlighted - 1 + count) % count; return nil
                default: return event
                }
            }
        }
        .onDisappear {
            search.cancel()
            if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
            keyMonitor = nil
        }
    }

    private var suggestionList: some View {
        VStack(spacing: 2) {
            ForEach(Array(search.suggestions.enumerated()), id: \.element.id) { index, suggestion in
                Button { choose(suggestion) } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "mappin.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(index == highlighted ? Color.white : Color.accentColor)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(suggestion.title)
                                .font(.system(size: 13, weight: .medium))
                                .lineLimit(1)
                            if !suggestion.subtitle.isEmpty {
                                Text(suggestion.subtitle)
                                    .font(.system(size: 11))
                                    .foregroundStyle(index == highlighted ? Color.white.opacity(0.8) : Color.secondary)
                                    .lineLimit(1)
                            }
                        }
                        Spacer(minLength: 0)
                        if index == highlighted {
                            Image(systemName: "return").font(.system(size: 10, weight: .semibold)).opacity(0.8)
                        }
                    }
                    .foregroundStyle(index == highlighted ? Color.white : Color.primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(index == highlighted ? Color.accentColor : Color.clear))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { if $0 { highlighted = index } }
            }
        }
        .padding(5)
        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Color.primary.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
    }

    private func choose(_ suggestion: PlaceSearch.Suggestion) {
        guard !searching else { return }
        searching = true
        error = nil
        Task { @MainActor in
            if let place = await PlaceSearch.resolve(suggestion) {
                searching = false
                weather.save(place)
                onDone()
            } else {
                searching = false
                error = LocalWeather.LookupError.notFound.message
            }
        }
    }

    private func save() {
        guard !searching, query.trimmingCharacters(in: .whitespaces).count >= 2 else { return }
        // Return picks the highlighted suggestion when there is one.
        if search.suggestions.indices.contains(highlighted) {
            choose(search.suggestions[highlighted]); return
        }
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
