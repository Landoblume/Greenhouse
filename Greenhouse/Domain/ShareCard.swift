import CoreData
import Foundation

/// What goes on a plant's "then vs now" share card, worked out from its
/// timeline and care history (see `ShareCardView` for the drawing).
enum ShareCard {
    struct Content {
        let name: String
        let latin: String?
        /// The first photo; nil when there's only one photo or none, and the
        /// card shows seedling art from when it arrived instead.
        let then: Photo?
        let thenDate: Date?
        /// The latest photo; nil when there are none.
        let now: Photo?
        let nowDate: Date
        let growth: Growth
        /// "Grown by Alex & Sam"
        let grownBy: String
    }

    /// "8" + "months of growth"
    struct Growth: Equatable {
        let value: Int
        let unit: String
    }

    static func content(for plant: Plant, now: Date = .now, calendar: Calendar = .current) -> Content {
        let timeline = Lineage.timeline(for: plant)
        let first = timeline.count >= 2 ? timeline.first?.photo : nil
        let latest = timeline.last?.photo
        let arrived = Lineage.effectiveAcquiredDate(of: plant)
        let nowDate = latest?.takenAt ?? now
        var thenDate = first?.takenAt ?? arrived
        if let then = thenDate, then > nowDate { thenDate = nowDate }  // a library photo older than the plant
        return Content(
            name: plant.displayName,
            latin: plant.scientificName.flatMap { $0.isEmpty ? nil : $0 },
            then: first,
            thenDate: thenDate,
            now: latest,
            nowDate: nowDate,
            growth: growth(from: thenDate ?? nowDate, to: nowDate, calendar: calendar),
            grownBy: grownBy(growers(for: plant))
        )
    }

    /// "12 days", "3 weeks", "8 months", "2 years" of growth.
    static func growth(from start: Date, to end: Date, calendar: Calendar = .current) -> Growth {
        let parts = calendar.dateComponents([.month, .day], from: calendar.startOfDay(for: start), to: calendar.startOfDay(for: end))
        let months = max(parts.month ?? 0, 0)
        if months >= 24 {
            let years = months / 12
            return Growth(value: years, unit: "years of growth")
        }
        if months >= 1 {
            return Growth(value: months, unit: months == 1 ? "month of growth" : "months of growth")
        }
        let days = max(calendar.dateComponents([.day], from: calendar.startOfDay(for: start), to: calendar.startOfDay(for: end)).day ?? 0, 0)
        if days >= 14 { return Growth(value: days / 7, unit: "weeks of growth") }
        return Growth(value: days, unit: days == 1 ? "day of growth" : "days of growth")
    }

    /// Everyone whose name is on the plant's care logs or milestones,
    /// including those of the plants it was combined from: most entries
    /// first, ties by name. Photos don't record who took them, so a photo
    /// only counts through the milestone it's attached to. Names are matched
    /// ignoring case, and shown in the spelling used most ("Sam" over "sam").
    static func growers(for plant: Plant) -> [String] {
        // lowercased name → spelling → count
        var spellings: [String: [String: Int]] = [:]
        func add(_ raw: String?) {
            let name = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !name.isEmpty else { return }
            spellings[name.lowercased(), default: [:]][name, default: 0] += 1
        }
        CareHistory.entries(for: plant).forEach { add($0.doneBy) }
        ([plant] + Lineage.ancestors(of: plant)).forEach { member in
            (member.milestones ?? []).forEach { add($0.addedBy) }
        }
        let people = spellings.values.map { forms -> (name: String, count: Int) in
            let best = forms.max { $0.value != $1.value ? $0.value < $1.value : $0.key > $1.key }?.key ?? ""
            return (best, forms.values.reduce(0, +))
        }
        return people
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.name < $1.name }
            .map(\.name)
    }

    /// "Grown by Sam", "Grown by Alex & Sam", "Grown by Alex, Sam & Jo";
    /// "Grown with care" when nobody's name is on anything.
    static func grownBy(_ names: [String]) -> String {
        switch names.count {
        case 0: return "Grown with care"
        case 1: return "Grown by \(names[0])"
        default: return "Grown by \(names.dropLast().joined(separator: ", ")) & \(names[names.count - 1])"
        }
    }
}
