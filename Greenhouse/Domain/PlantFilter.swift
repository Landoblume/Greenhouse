import Foundation

/// Search, filter and sort for the Plants tab. A per-phone view choice, so it
/// isn't synced.
struct PlantFilter: Equatable {
    enum Sort: String, CaseIterable, Identifiable {
        case added, name, nextWatering, newest

        var id: Self { self }

        var label: String {
            switch self {
            case .added: "Order added"
            case .name: "Name"
            case .nextWatering: "Next watering"
            case .newest: "Newest first"
            }
        }
    }

    var query = ""
    /// Empty means every setting.
    var settings: Set<PlantSetting> = []
    var needsWater = false
    /// Nil means every genus.
    var genus: String?
    var sort: Sort = .added

    /// Whether anything in the filter menu differs from the default (the
    /// search text has its own field).
    var isFiltering: Bool { !settings.isEmpty || needsWater || genus != nil || sort != .added }

    func apply(to plants: [Plant], now: Date = .now) -> [Plant] {
        let words = query.split(separator: " ").map(String.init)
        let kept = plants.filter { plant in
            (settings.isEmpty || settings.contains(plant.settingValue))
                && (genus == nil || Self.genus(of: plant) == genus)
                && (!needsWater || Self.needsWater(plant, now: now))
                && words.allSatisfy { Self.matches(plant, $0) }
        }
        return sorted(kept)
    }

    /// The plant's genus: the first word of its scientific name, capitalized
    /// ("aloe vera" and "Aloe barbadensis" are both "Aloe"). Nil when there's
    /// no scientific name, so those plants never match a genus filter.
    static func genus(of plant: Plant) -> String? {
        guard let word = plant.scientificName?.split(whereSeparator: \.isWhitespace).first else { return nil }
        return word.prefix(1).uppercased() + word.dropFirst().lowercased()
    }

    /// The genera present in these plants, sorted, for the filter menu.
    static func genera(in plants: [Plant]) -> [String] {
        Array(Set(plants.compactMap { genus(of: $0) }))
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// One row of the genus picker: "Monstera (3)".
    struct GenusCount: Equatable {
        let genus: String
        let count: Int
        var label: String { "\(genus) (\(count))" }
    }

    /// The genera present in these plants with how many plants each has,
    /// sorted by genus, for the picker's options.
    static func genusCounts(in plants: [Plant]) -> [GenusCount] {
        var counts: [String: Int] = [:]
        for plant in plants {
            if let genus = genus(of: plant) { counts[genus, default: 0] += 1 }
        }
        return counts
            .map { GenusCount(genus: $0.key, count: $0.value) }
            .sorted { $0.genus.localizedCaseInsensitiveCompare($1.genus) == .orderedAscending }
    }

    /// The genus picker only earns its place with a choice to make: two or
    /// more genera in the collection.
    static func offersGenusPicker(in plants: [Plant]) -> Bool {
        genera(in: plants).count >= 2
    }

    /// This filter with the genus dropped if none of these plants has it, so
    /// switching collections can't leave a genus selected that the menu no
    /// longer offers (and an empty grid with no obvious cause).
    func clearingUnavailableGenus(in plants: [Plant]) -> PlantFilter {
        guard let genus, !Self.genera(in: plants).contains(genus) else { return self }
        var adjusted = self
        adjusted.genus = nil
        return adjusted
    }

    /// Watering due today or overdue.
    static func needsWater(_ plant: Plant, now: Date = .now) -> Bool {
        switch plant.wateringTask.flatMap({ CareSchedule.status(of: $0, now: now) }) {
        case .today, .overdue: true
        default: false
        }
    }

    /// Case- and accent-insensitive match on any of the plant's names, where
    /// it lives or its notes, so "aloe", "Aloe vera" and "kitchen" all find
    /// the kitchen aloe.
    static func matches(_ plant: Plant, _ word: String) -> Bool {
        [plant.nickname, plant.commonName, plant.scientificName, plant.location, plant.notes]
            .compactMap { $0 }
            .contains { $0.range(of: word, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }

    private func sorted(_ plants: [Plant]) -> [Plant] {
        switch sort {
        case .added:
            return plants
        case .name:
            return plants.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        case .nextWatering:
            func due(_ plant: Plant) -> Date { plant.wateringTask.flatMap { CareSchedule.nextDue(for: $0) } ?? .distantFuture }
            return plants.sorted { due($0) < due($1) }
        case .newest:
            func got(_ plant: Plant) -> Date { Lineage.effectiveAcquiredDate(of: plant) ?? .distantPast }
            return plants.sorted { got($0) > got($1) }
        }
    }
}
