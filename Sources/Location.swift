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

    func forgetAll() {
        decisions = [:]
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
        let remembered = kinds.map { decision(for: host, $0) }
        if remembered.allSatisfy({ $0 == true }) { completion(true); return }
        if remembered.contains(where: { $0 == false }) { completion(false); return }

        let site = ContentBlocker.normalize(host)
        let what: String
        switch Set(kinds) {
        case [.location]: what = "your location"
        case [.camera]: what = "your camera"
        case [.microphone]: what = "your microphone"
        default: what = "your camera and microphone"
        }
        let alert = NSAlert()
        alert.messageText = "“\(site)” wants to use \(what)"
        alert.informativeText = kinds.contains(.location)
            ? "The website will be told your approximate position. You can change your answer any time in Hush Settings › Location."
            : "You can change your answer any time in Hush Settings › Privacy."
        alert.addButton(withTitle: "Allow Once")
        alert.addButton(withTitle: "Always Allow")
        alert.addButton(withTitle: "Don’t Allow")
        alert.buttons[2].keyEquivalent = "\u{1b}" // Esc = Don't Allow
        if let image = NSImage(systemSymbolName: kinds[0].symbol, accessibilityDescription: nil) {
            alert.icon = image
        }

        let finish: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            switch response {
            case .alertFirstButtonReturn:           // Allow Once: just this time
                completion(true)
            case .alertSecondButtonReturn:          // Always Allow: remembered for this site
                self?.set(true, for: site, kinds)
                completion(true)
            default:                                // Don't Allow: this time; the site can ask again later
                completion(false)
            }
        }
        if let window {
            alert.beginSheetModal(for: window, completionHandler: finish)
        } else {
            finish(alert.runModal())
        }
    }
}

// MARK: - Local weather for the start page

/// Finds your approximate location and the current weather, for a personal start page.
/// The position is rounded to about 1 km before it leaves your Mac: it goes to
/// Open-Meteo for the weather and to Apple to look up the town name.
final class LocalWeather: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = LocalWeather()

    @Published private(set) var city: String?
    @Published private(set) var temperature: Int?
    @Published private(set) var symbol = "cloud.sun"
    @Published private(set) var summary = ""
    @Published private(set) var authorization: CLAuthorizationStatus
    @Published private(set) var problem: String?

    private let manager = CLLocationManager()
    private var lastUpdate: Date?

    private override init() {
        authorization = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    var isEnabled: Bool { Prefs.bool(Prefs.startPageWeather) }

    var isAuthorized: Bool {
        authorization == .authorizedAlways
    }

    var statusText: String {
        switch authorization {
        case .notDetermined: return "Hush hasn’t asked for your location yet"
        case .denied: return "Location access is turned off for Hush in System Settings"
        case .restricted: return "Location access is restricted on this Mac"
        default:
            if let problem { return problem }
            if let city { return "Using your location near \(city)" }
            return "Location access allowed"
        }
    }

    /// Refreshes at most every 20 minutes.
    func refreshIfNeeded() {
        guard isEnabled else { return }
        if let lastUpdate, Date().timeIntervalSince(lastUpdate) < 20 * 60, temperature != nil { return }
        request()
    }

    func request() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            authorization = manager.authorizationStatus
        default:
            manager.requestLocation()
        }
    }

    func clear() {
        city = nil
        temperature = nil
        lastUpdate = nil
    }

    static func openSystemLocationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices") {
            NSWorkspace.shared.open(url)
        }
    }

    // CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        DispatchQueue.main.async {
            self.authorization = manager.authorizationStatus
            if self.isEnabled && self.isAuthorized { manager.requestLocation() }
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { await self.update(for: location) }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        DispatchQueue.main.async { self.problem = "Couldn’t find your location right now" }
    }

    private func update(for location: CLLocation) async {
        // Round to ~1 km so the exact position never leaves the Mac.
        let lat = (location.coordinate.latitude * 100).rounded() / 100
        let lon = (location.coordinate.longitude * 100).rounded() / 100
        let fahrenheit = Locale.current.measurementSystem == .us

        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            .init(name: "latitude", value: String(lat)),
            .init(name: "longitude", value: String(lon)),
            .init(name: "current", value: "temperature_2m,weather_code,is_day"),
            .init(name: "temperature_unit", value: fahrenheit ? "fahrenheit" : "celsius"),
        ]
        let rounded = CLLocation(latitude: lat, longitude: lon)
        let place = try? await CLGeocoder().reverseGeocodeLocation(rounded).first

        guard let url = components.url,
              let (data, _) = try? await URLSession.shared.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let current = json["current"] as? [String: Any],
              let temp = current["temperature_2m"] as? Double else {
            await MainActor.run { self.problem = "Couldn’t get the weather right now" }
            return
        }
        let code = current["weather_code"] as? Int ?? 0
        let isDay = (current["is_day"] as? Int ?? 1) == 1
        let (symbol, summary) = Self.describe(code, isDay: isDay)
        await MainActor.run {
            self.city = place?.locality ?? place?.subAdministrativeArea ?? place?.name
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
