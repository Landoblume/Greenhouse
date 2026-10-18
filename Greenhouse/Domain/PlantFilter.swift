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
    var sort: Sort = .added

    /// Whether anything in the filter menu differs from the default (the
    /// search text has its own field).
    var isFiltering: Bool { !settings.isEmpty || needsWater || sort != .added }

    func apply(to plants: [Plant], now: Date = .now) -> [Plant] {
        let words = query.split(separator: " ").map(String.init)
        let kept = plants.filter { plant in
            (settings.isEmpty || settings.contains(plant.settingValue))
                && (!needsWater || Self.needsWater(plant, now: now))
                && words.allSatisfy { Self.matches(plant, $0) }
        }
        return sorted(kept)
    }

    /// Watering due today or overdue.
    static func needsWater(_ plant: Plant, now: Date = .now) -> Bool {
        switch plant.wateringTask.flatMap({ CareSchedule.status(of: $0, now: now) }) {
        case .today, .overdue: true
        default: false
        }
    }

    /// Case- and accent-insensitive match on any of the plant's names or where
    /// it lives, so "aloe", "Aloe vera" and "kitchen" all find the kitchen aloe.
    static func matches(_ plant: Plant, _ word: String) -> Bool {
        [plant.nickname, plant.commonName, plant.scientificName, plant.location]
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
