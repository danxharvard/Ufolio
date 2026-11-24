import AppKit
import CoreLocation
import WebKit

// MARK: - Website permissions

enum PermissionKind: String, CaseIterable {
    case location, camera, microphone

    var label: String { rawValue.capitalized }

    var symbol: String {
        switch self {
        case .location: return "location.fill"
        case .camera: return "video.fill"
        case .microphone: return "mic.fill"
        }
    }
}

/// Remembers which websites may use your location, camera and microphone,
/// and asks you the first time a site wants one.
final class SitePermissions: ObservableObject {
    static let shared = SitePermissions()

    /// host → permission → allowed
    @Published private(set) var decisions: [String: [String: Bool]]
    /// "Allow Once" answers, kept until Hush quits.
    private var sessionAllowed: Set<String> = []

    private init() {
        decisions = UserDefaults.standard.dictionary(forKey: "sitePermissions") as? [String: [String: Bool]] ?? [:]
    }

    func decision(for host: String, _ kind: PermissionKind) -> Bool? {
        decisions[ContentBlocker.normalize(host)]?[kind.rawValue]
    }

    func set(_ allowed: Bool, for host: String, _ kinds: [PermissionKind]) {
        let h = ContentBlocker.normalize(host)
        var entry = decisions[h] ?? [:]
        for kind in kinds { entry[kind.rawValue] = allowed }
        decisions[h] = entry
        save()
    }

    func forget(_ host: String, kinds: [PermissionKind]) {
        for kind in kinds { decisions[host]?[kind.rawValue] = nil }
        if decisions[host]?.isEmpty == true { decisions[host] = nil }
        save()
    }

    /// Forgets every answer for a site and its subdomains (Forget This Site).
    func forget(site: String) {
        decisions = decisions.filter { Domains.site($0.key) != site }
        sessionAllowed = sessionAllowed.filter { Domains.site(String($0.split(separator: "|").first ?? "")) != site }
        save()
    }

    private func save() {
        UserDefaults.standard.set(decisions, forKey: "sitePermissions")
    }

    private func policy(for kind: PermissionKind) -> PermissionPolicy {
        let key = kind == .location ? Prefs.locationPolicy : Prefs.cameraPolicy
        return PermissionPolicy(rawValue: Prefs.string(key)) ?? .ask
    }

    /// Decides a site's request: remembered answer, the global policy, or a prompt.
    func request(_ kinds: [PermissionKind], host: String?, window: NSWindow?, completion: @escaping (Bool) -> Void) {
        guard let host, !host.isEmpty else { completion(false); return }
        if kinds.contains(where: { policy(for: $0) == .never }) { completion(false); return }
        let siteKey = ContentBlocker.normalize(host)
        if kinds.allSatisfy({ sessionAllowed.contains(siteKey + "|" + $0.rawValue) }) { completion(true); return }
        let remembered = kinds.map { decision(for: host, $0) }
        if remembered.allSatisfy({ $0 == true }) { completion(true); return }
        if remembered.contains(where: { $0 == false }) { completion(false); return }

        let site = ContentBlocker.normalize(host)
        // One question at a time: a page asking over and over can't stack up prompts.
        if DialogHost.isBusy(window) { completion(false); return }
        let what: String
        switch Set(kinds) {
        case [.location]: what = "your location"
        case [.camera]: what = "your camera"
        case [.microphone]: what = "your microphone"
        default: what = "your camera and microphone"
        }
        let dialog = HushDialog(
            art: .site(URL(string: "https://\(host)")), badge: kinds[0].symbol, theme: .permission, motion: .orbit,
            title: "“\(site)” wants to use \(what)",
            message: kinds.contains(.location)
                ? "The website will be told your approximate position. You can change your answer any time in Settings › Location."
                : "You can change your answer any time in Settings › Privacy & Security.",
            choices: [.init(title: "Allow Once"), .init(title: "Always Allow", role: .primary), .init(title: "Don’t Allow", role: .cancel)],
            completion: { [weak self] choice, _ in
                switch choice {
                case 0:                                  // Allow Once: until Hush quits
                    for kind in kinds { self?.sessionAllowed.insert(site + "|" + kind.rawValue) }
                    completion(true)
                case 1:                                  // Always Allow: remembered for this site
                    self?.set(true, for: site, kinds)
                    completion(true)
                default:                                 // Don't Allow: remembered, so the site stops asking
                    self?.set(false, for: site, kinds)
                    completion(false)
                }
            })
        DialogHost.show(dialog, in: window)
    }
}

// MARK: - Local weather for the start page

/// The town you chose for your personal start page, and its current weather.
/// Hush never asks macOS for your location: you type a town or postcode, Apple finds
/// the place, and only its rough position (about 1 km) goes to Open-Meteo for the weather.
final class LocalWeather: ObservableObject {
    static let shared = LocalWeather()

    struct Place: Codable, Equatable {
        var name: String      // "Manchester"
        var detail: String    // "England, United Kingdom"
        var latitude: Double
        var longitude: Double
    }

    @Published private(set) var place: Place?
    @Published private(set) var temperature: Int?
    @Published private(set) var symbol = "cloud.sun"
    @Published private(set) var summary = ""
    @Published private(set) var problem: String?

    private static let placeKey = "startPagePlace"
    private var lastUpdate: Date?
    private var loading = false

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.placeKey),
           let saved = try? JSONDecoder().decode(Place.self, from: data) {
            place = saved
        }
        // The old setting asked macOS for your location; it's no longer used.
        UserDefaults.standard.removeObject(forKey: "startPageWeather")
    }

    var isPersonalised: Bool { place != nil }
    var city: String? { place?.name }

    /// Finds a town or postcode. Doesn't need (or ask for) location access.
    static func lookUp(_ query: String) async -> Result<Place, LookupError> {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 2, text.count <= 100 else { return .failure(.notFound) }
        do {
            let marks = try await CLGeocoder().geocodeAddressString(text)
            guard let mark = marks.first, let found = place(from: mark, fallback: text) else { return .failure(.notFound) }
            return .success(found)
        } catch let error as CLError where error.code == .network {
            return .failure(.offline)
        } catch {
            return .failure(.notFound)
        }
    }

    /// Turns a found place into what the start page keeps: its name and a rough position.
    static func place(from mark: CLPlacemark, fallback: String) -> Place? {
        guard let location = mark.location else { return nil }
        let name = mark.locality ?? mark.subAdministrativeArea ?? mark.name ?? fallback
        let detail = [mark.administrativeArea, mark.country]
            .compactMap { $0 }.filter { $0 != name }
            .reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
            .joined(separator: ", ")
        return Place(name: name, detail: detail,
                     latitude: (location.coordinate.latitude * 100).rounded() / 100,
                     longitude: (location.coordinate.longitude * 100).rounded() / 100)
    }

    enum LookupError: Error {
        case notFound, offline
        var message: String {
            switch self {
            case .notFound: return "Ufolio couldn’t find that place. Try a town name or a full postcode."
            case .offline: return "Ufolio couldn’t look that up. Check your internet connection and try again."
            }
        }
    }

    func save(_ newPlace: Place) {
        if let data = try? JSONEncoder().encode(newPlace) {
            UserDefaults.standard.set(data, forKey: Self.placeKey)
        }
        place = newPlace
        temperature = nil
        lastUpdate = nil
        refresh()
    }

    func clear() {
        UserDefaults.standard.removeObject(forKey: Self.placeKey)
        place = nil
        temperature = nil
        problem = nil
        lastUpdate = nil
    }

    /// Refreshes at most every 20 minutes.
    func refreshIfNeeded() {
        if let lastUpdate, Date().timeIntervalSince(lastUpdate) < 20 * 60, temperature != nil { return }
        refresh()
    }

    func refresh() {
        guard let place, !loading else { return }
        loading = true
        Task {
            await self.update(for: place)
            await MainActor.run { self.loading = false }
        }
    }

    private func update(for place: Place) async {
        let fahrenheit = Locale.current.measurementSystem == .us
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            .init(name: "latitude", value: String(place.latitude)),
            .init(name: "longitude", value: String(place.longitude)),
            .init(name: "current", value: "temperature_2m,weather_code,is_day"),
            .init(name: "temperature_unit", value: fahrenheit ? "fahrenheit" : "celsius"),
        ]
        var request = URLRequest(url: components.url!, timeoutInterval: 15)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let current = json["current"] as? [String: Any],
              let temp = current["temperature_2m"] as? Double, temp.isFinite else {
            await MainActor.run { self.problem = "Couldn’t get the weather right now" }
            return
        }
        let code = current["weather_code"] as? Int ?? 0
        let isDay = (current["is_day"] as? Int ?? 1) == 1
        let (symbol, summary) = Self.describe(code, isDay: isDay)
        await MainActor.run {
            guard self.place == place else { return }   // changed while loading
            self.temperature = Int(temp.rounded())
            self.symbol = symbol
            self.summary = summary
            self.problem = nil
            self.lastUpdate = Date()
        }
    }

    /// WMO weather codes → SF Symbol and words.
    static func describe(_ code: Int, isDay: Bool) -> (String, String) {
        switch code {
        case 0: return (isDay ? "sun.max.fill" : "moon.stars.fill", "Clear")
        case 1, 2: return (isDay ? "cloud.sun.fill" : "cloud.moon.fill", "Partly cloudy")
        case 3: return ("cloud.fill", "Cloudy")
        case 45, 48: return ("cloud.fog.fill", "Foggy")
        case 51, 53, 55, 56, 57: return ("cloud.drizzle.fill", "Drizzle")
        case 61, 63, 65, 66, 67, 80, 81, 82: return ("cloud.rain.fill", "Rain")
        case 71, 73, 75, 77, 85, 86: return ("cloud.snow.fill", "Snow")
        case 95, 96, 99: return ("cloud.bolt.rain.fill", "Thunderstorms")
        default: return ("cloud.fill", "")
        }
    }
}
