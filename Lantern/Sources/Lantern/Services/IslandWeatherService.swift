// IslandWeatherService.swift — local weather for the island's weather slot
//
// Auto-location via CoreLocation (when-in-use) and forecasts from
// Open-Meteo's key-less API — no API key, no vendor SDK, plain
// URLSession. The island slot only appears once a genuine temperature
// arrives; denied location or offline simply keeps the slot hidden.
// Polling is deliberately slow (15 min) and gated on the slot toggle:
// the location prompt must never fire for users who never enabled
// weather.

import CoreLocation
import Foundation

public final class IslandWeatherService: NSObject, ObservableObject, CLLocationManagerDelegate {

    /// Registered on first use; the island service drives start/stop.
    public private(set) static var shared: IslandWeatherService?

    /// Nil means no reading yet (or location denied) — the slot hides.
    @Published public private(set) var temperatureC: Double?
    @Published public private(set) var weatherCode: Int?

    private let manager = CLLocationManager()
    private var fetchTimer: Timer?
    private static let refreshInterval: TimeInterval = 900 // 15 minutes

    public override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        Self.shared = self
    }

    // MARK: - Lifecycle (driven by the island service, gated on the slot)

    /// Idempotent. Starting only prompts for authorization when the slot
    /// is on — turning the slot off also silences the prompt loop.
    func setRunning(_ running: Bool) {
        if running {
            guard fetchTimer == nil else { return }
            ensureAuthorization()
            fetchTimer = Timer.scheduledTimer(
                withTimeInterval: Self.refreshInterval, repeats: true
            ) { [weak self] _ in
                self?.manager.requestLocation()
            }
        } else {
            fetchTimer?.invalidate()
            fetchTimer = nil
            temperatureC = nil
            weatherCode = nil
        }
    }

    private func ensureAuthorization() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        default:
            break // denied / restricted — slot stays hidden, no nagging
        }
    }

    // MARK: - CoreLocation

    public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        default:
            break
        }
    }

    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        fetchWeather(latitude: location.coordinate.latitude,
                     longitude: location.coordinate.longitude)
    }

    public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Keep the last reading; the next timer tick retries.
    }

    // MARK: - Open-Meteo (key-less)

    private func fetchWeather(latitude: Double, longitude: Double) {
        var comps = URLComponents(string: "https://api.open-meteo.com/v1/forecast")
        comps?.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.3f", latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.3f", longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,weather_code"),
            URLQueryItem(name: "timezone", value: "auto"),
        ]
        guard let url = comps?.url else { return }
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data, let parsed = Self.parse(data) else { return }
            DispatchQueue.main.async {
                self.temperatureC = parsed.temp
                self.weatherCode = parsed.code
            }
        }.resume()
    }

    // MARK: - Pure helpers (testable without network or location)

    struct Payload: Codable {
        struct Current: Codable {
            let temperature_2m: Double
            let weather_code: Int
        }
        let current: Current
    }

    static func parse(_ data: Data) -> (temp: Double, code: Int)? {
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data) else { return nil }
        return (payload.current.temperature_2m, payload.current.weather_code)
    }

    /// WMO weather interpretation codes → SF Symbol names.
    static func symbol(for code: Int) -> String {
        switch code {
        case 0: return "sun.max.fill"
        case 1, 2: return "cloud.sun.fill"
        case 3: return "cloud.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51...57: return "cloud.drizzle.fill"
        case 61...67, 80...82: return "cloud.rain.fill"
        case 71...77, 85, 86: return "cloud.snow.fill"
        case 95...99: return "cloud.bolt.rain.fill"
        default: return "cloud.fill"
        }
    }

    /// WMO code → condition the island shows in words (晴/多云/阴/雨…).
    /// `key` is the localization key (zh-Hans table has the translations),
    /// `english` is the fallback rendered by L() when no table entry exists.
    static func condition(for code: Int) -> (key: String, english: String) {
        switch code {
        case 0: return ("wmo.clear", "Sunny")
        case 1: return ("wmo.clear", "Mostly Sunny")
        case 2: return ("wmo.partly", "Partly Cloudy")
        case 3: return ("wmo.overcast", "Overcast")
        case 45, 48: return ("wmo.fog", "Foggy")
        case 51...57: return ("wmo.drizzle", "Drizzle")
        case 61...67: return ("wmo.rain", "Rain")
        case 71...77, 85, 86: return ("wmo.snow", "Snow")
        case 80...82: return ("wmo.showers", "Showers")
        case 95...99: return ("wmo.thunder", "Thunderstorm")
        default: return ("wmo.overcast", "Overcast")
        }
    }
}
