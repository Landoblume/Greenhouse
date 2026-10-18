import Contacts
import CoreLocation
import Foundation

/// A USDA plant hardiness zone like "7b": the number is the band of average
/// coldest winter night (each band is 10°F), the letter splits it in half.
struct USDAZone: Comparable, Hashable {
    let number: Int
    let half: String

    init?(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces).lowercased()
        let digits = trimmed.prefix { $0.isNumber }
        guard let number = Int(digits), (1...13).contains(number) else { return nil }
        let rest = trimmed.dropFirst(digits.count)
        guard rest.isEmpty || rest == "a" || rest == "b" else { return nil }
        self.number = number
        half = String(rest)
    }

    var label: String { "\(number)\(half)" }

    static func < (lhs: USDAZone, rhs: USDAZone) -> Bool {
        (lhs.number, lhs.half) < (rhs.number, rhs.half)
    }

    /// 1a through 13b, for picking a zone by hand.
    static let all: [String] = (1...13).flatMap { ["\($0)a", "\($0)b"] }
}

enum HardinessAdvice: Equatable {
    /// Indoor plants don't feel winter, so there's nothing to say.
    case none
    case setZip
    case noData
    case hardy(zone: String, range: String)
    case notHardy(zone: String, range: String)
    case tooWarm(zone: String, range: String)

    var message: String {
        switch self {
        case .none: ""
        case .setZip: "Set your ZIP for zone advice"
        case .noData: "No zone data for this species"
        case .hardy: "Hardy in your zone ✓"
        case .notHardy(let zone, _): "Not hardy in \(zone): bring inside before the first frost"
        case .tooWarm(let zone, _): "Zone \(zone) may be too warm for it"
        }
    }

    var detail: String? {
        switch self {
        case .hardy(_, let range), .notHardy(_, let range), .tooWarm(_, let range):
            "Survives winter outdoors in \(range)"
        case .setZip:
            "Settings → Grow zone"
        case .none, .noData:
            nil
        }
    }

    var isWarning: Bool {
        switch self {
        case .notHardy, .tooWarm: true
        default: false
        }
    }
}

enum Hardiness {
    static func advice(setting: PlantSetting, zone: String?, species: Species?) -> HardinessAdvice {
        if setting == .indoor { return .none }
        guard let zone, let parsed = USDAZone(zone) else { return .setZip }
        guard let species else { return .noData }
        let range = species.zoneRange
        if parsed.number < species.zoneMin { return .notHardy(zone: parsed.label, range: range) }
        if parsed.number > species.zoneMax { return .tooWarm(zone: parsed.label, range: range) }
        return .hardy(zone: parsed.label, range: range)
    }
}

/// ZIP code → USDA zone, via phzmapi.org (a free static mirror of the USDA map
/// data: https://phzmapi.org/84101.json → {"zone": "7b", ...}).
///
/// The USDA data is from 2023, so a ZIP created since then isn't in it. For
/// those, the zone comes from the nearest ZIP the map does know: around where
/// Apple's geocoder puts the ZIP, or, for ZIPs so new Apple doesn't know them
/// either, around the phone's location. Zones change over tens of miles, so a
/// neighbour a few miles away is a safe guess.
enum ZoneLookup {
    enum Failure: LocalizedError {
        case invalidZIP
        case notFound

        var errorDescription: String? {
            switch self {
            case .invalidZIP: "Enter a 5-digit US ZIP code."
            case .notFound: "Couldn't find a zone for that ZIP. Try Use my location, or pick one by hand below."
            }
        }
    }

    struct Match: Equatable {
        let zone: String
        /// The neighbouring ZIP the zone came from, when the ZIP itself isn't
        /// in the USDA data.
        let nearbyZIP: String?
    }

    /// Fetches the zone for one ZIP: nil when the map doesn't have it, throws
    /// when the lookup itself fails (offline, say).
    typealias Fetch = (String) async throws -> String?

    /// Distances (km) of the rings searched around a spot, nearest first. Each
    /// ring is 8 points (N, NE, E, ...), so with the spot itself at most 25
    /// reverse lookups.
    static let ringsKM: [Double] = [2, 5, 10]

    static func zone(
        forZIP zip: String,
        fetch: Fetch = fetchFromPHZM,
        geocoder: ZIPGeocoding = AppleZIPGeocoder()
    ) async throws -> Match {
        let trimmed = zip.trimmingCharacters(in: .whitespaces)
        guard isZIP(trimmed) else { throw Failure.invalidZIP }
        if let zone = try await fetch(trimmed) { return Match(zone: zone, nearbyZIP: nil) }

        guard let center = try? await geocoder.coordinate(forZIP: trimmed) else { throw Failure.notFound }
        return try await zone(near: center, skipping: trimmed, fetch: fetch, geocoder: geocoder)
    }

    /// The zone of the nearest ZIP around a spot that the USDA map knows.
    /// `nearbyZIP` is always set, since the ZIP comes from the map, not the user.
    static func zone(
        near center: CLLocationCoordinate2D,
        skipping skipped: String? = nil,
        fetch: Fetch = fetchFromPHZM,
        geocoder: ZIPGeocoding = AppleZIPGeocoder()
    ) async throws -> Match {
        var tried = Set([skipped].compactMap { $0 })
        for point in searchPoints(around: center) {
            guard let neighbour = try? await geocoder.postalCode(at: point),
                  isZIP(neighbour), tried.insert(neighbour).inserted else { continue }
            if let zone = try await fetch(neighbour) { return Match(zone: zone, nearbyZIP: neighbour) }
        }
        throw Failure.notFound
    }

    /// `center`, then points on rings around it, nearest ring first.
    static func searchPoints(around center: CLLocationCoordinate2D) -> [CLLocationCoordinate2D] {
        let kmPerDegree = 111.0
        return [center] + ringsKM.flatMap { km in
            stride(from: 0.0, to: 360.0, by: 45.0).map { bearing in
                let radians = bearing * .pi / 180
                let lat = center.latitude + km * cos(radians) / kmPerDegree
                let lon = center.longitude + km * sin(radians) / (kmPerDegree * cos(center.latitude * .pi / 180))
                return CLLocationCoordinate2D(latitude: lat, longitude: lon)
            }
        }
    }

    private static func isZIP(_ text: String) -> Bool {
        text.count == 5 && text.allSatisfy(\.isNumber)
    }

    private struct Response: Decodable {
        let zone: String
    }

    static func fetchFromPHZM(_ zip: String) async throws -> String? {
        guard let url = URL(string: "https://phzmapi.org/\(zip).json") else { return nil }
        let (data, response) = try await URLSession.shared.data(from: url)
        switch (response as? HTTPURLResponse)?.statusCode {
        case 200:
            guard let zone = try? JSONDecoder().decode(Response.self, from: data).zone,
                  USDAZone(zone) != nil else { return nil }
            return zone
        case 404:
            return nil
        default:
            throw Failure.notFound
        }
    }
}

/// Where a ZIP is, and which ZIP a spot is in. A protocol so tests can swap
/// in a fake map.
protocol ZIPGeocoding {
    func coordinate(forZIP zip: String) async throws -> CLLocationCoordinate2D?
    func postalCode(at coordinate: CLLocationCoordinate2D) async throws -> String?
}

struct AppleZIPGeocoder: ZIPGeocoding {
    func coordinate(forZIP zip: String) async throws -> CLLocationCoordinate2D? {
        let address = CNMutablePostalAddress()
        address.postalCode = zip
        address.isoCountryCode = "US"
        return try await CLGeocoder().geocodePostalAddress(address).first?.location?.coordinate
    }

    func postalCode(at coordinate: CLLocationCoordinate2D) async throws -> String? {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let placemark = try await CLGeocoder().reverseGeocodeLocation(location).first
        guard placemark?.isoCountryCode == "US" else { return nil }
        return placemark?.postalCode
    }
}

/// The phone's location, asked for once (Settings → Use my location).
@MainActor
final class OneTimeLocation: NSObject, CLLocationManagerDelegate {
    enum Failure: LocalizedError {
        case denied

        var errorDescription: String? {
            "Location is off for Greenhouse. Turn it on in the Settings app, or pick a zone by hand below."
        }
    }

    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocationCoordinate2D, Error>?

    func coordinate() async throws -> CLLocationCoordinate2D {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            manager.delegate = self
            manager.desiredAccuracy = kCLLocationAccuracyKilometer
            switch manager.authorizationStatus {
            case .notDetermined: manager.requestWhenInUseAuthorization()
            case .denied, .restricted: finish(.failure(Failure.denied))
            default: manager.requestLocation()
            }
        }
    }

    private func finish(_ result: Result<CLLocationCoordinate2D, Error>) {
        continuation?.resume(with: result)
        continuation = nil
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            guard continuation != nil else { return }
            switch status {
            case .notDetermined: break
            case .denied, .restricted: finish(.failure(Failure.denied))
            default: self.manager.requestLocation()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let coordinate = locations.last?.coordinate else { return }
        Task { @MainActor in finish(.success(coordinate)) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in finish(.failure(error)) }
    }
}
