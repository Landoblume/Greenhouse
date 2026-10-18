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
enum ZoneLookup {
    enum Failure: LocalizedError {
        case invalidZIP
        case notFound

        var errorDescription: String? {
            switch self {
            case .invalidZIP: "Enter a 5-digit US ZIP code."
            case .notFound: "Couldn't find a zone for that ZIP. Pick one by hand below."
            }
        }
    }

    private struct Response: Decodable {
        let zone: String
    }

    static func zone(forZIP zip: String) async throws -> String {
        let trimmed = zip.trimmingCharacters(in: .whitespaces)
        guard trimmed.count == 5, trimmed.allSatisfy(\.isNumber),
              let url = URL(string: "https://phzmapi.org/\(trimmed).json") else { throw Failure.invalidZIP }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let zone = try? JSONDecoder().decode(Response.self, from: data).zone,
              USDAZone(zone) != nil else { throw Failure.notFound }
        return zone
    }
}
