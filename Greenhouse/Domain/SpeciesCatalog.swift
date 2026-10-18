import Foundation

/// One entry in the bundled species list (Resources/species.json).
struct Species: Codable, Identifiable, Hashable {
    let id: String
    let latin: String
    let common: [String]
    /// USDA hardiness zones where it survives winter outdoors.
    let zoneMin: Int
    let zoneMax: Int
    let light: String
    /// Starting watering interval; editable per plant.
    let waterDays: Int
    /// "tender", "semi-hardy" or "hardy".
    let frost: String
    /// Page the zone range came from, when there is one.
    let source: String?
    /// True when the zone range was read off `source`, not recalled.
    let verified: Bool?

    var primaryCommonName: String { common.first ?? latin }

    /// e.g. "plants.ces.ncsu.edu", for a short credit line.
    var sourceHost: String? { source.flatMap { URL(string: $0)?.host() } }
    var zoneRange: String { "zones \(zoneMin)–\(zoneMax)" }
}

/// Read-only species list bundled with the app. It doesn't sync: it's the same
/// on both phones because it ships in the app.
final class SpeciesCatalog {
    static let shared = SpeciesCatalog.loadBundled()

    let species: [Species]
    /// Where the care data came from, shown on care cards.
    let source: String
    private let byID: [String: Species]

    init(species: [Species], source: String) {
        self.species = species.sorted { $0.latin < $1.latin }
        self.source = source
        byID = Dictionary(species.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private struct File: Decodable {
        let source: String
        let species: [Species]
    }

    static func loadBundled(bundle: Bundle = .main) -> SpeciesCatalog {
        guard let url = bundle.url(forResource: "species", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(File.self, from: data) else {
            assertionFailure("species.json missing or malformed")
            return SpeciesCatalog(species: [], source: "")
        }
        return SpeciesCatalog(species: file.species, source: file.source)
    }

    func species(id: String?) -> Species? {
        guard let id else { return nil }
        return byID[id]
    }

    /// Matches Latin or common names, ignoring case and accents. Names that
    /// start with the query (or have a word that does) rank above names that
    /// merely contain it, so "aloe" puts Aloe vera first.
    func search(_ query: String) -> [Species] {
        let q = Self.normalize(query)
        guard !q.isEmpty else { return species }
        let scored: [(Species, Int)] = species.compactMap { entry in
            let names = ([entry.latin] + entry.common).map(Self.normalize)
            // An exact name wins, so "pothos" lists plain pothos above its
            // many "... pothos" cultivars.
            if names.contains(q) { return (entry, 0) }
            if names.contains(where: { $0.hasPrefix(q) }) { return (entry, 1) }
            if names.contains(where: { $0.split(separator: " ").contains { $0.hasPrefix(q) } }) { return (entry, 2) }
            if names.contains(where: { $0.contains(q) }) { return (entry, 3) }
            return nil
        }
        return scored.sorted { $0.1 == $1.1 ? $0.0.latin < $1.0.latin : $0.1 < $1.1 }.map(\.0)
    }

    /// Lowercases, drops accents, and strips the quotes around cultivar names,
    /// so "marble queen" matches Epipremnum aureum 'Marble Queen' word by word.
    static func normalize(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .replacingOccurrences(of: "×", with: "x")
            .filter { !"'‘’\"“”".contains($0) }
            .trimmingCharacters(in: .whitespaces)
    }
}
