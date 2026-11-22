import Foundation

/// What a Plants-tab tile shows that doesn't come straight from the plant:
/// its photo height and its watering chip.
enum PlantTileStyle {
    /// The masonry's tile photo heights, in points.
    static let photoHeights: [CGFloat] = [150, 166, 182, 198, 214]

    /// A photo height that varies from tile to tile but never changes for a
    /// plant, so the grid doesn't reshuffle between launches or phones. It's
    /// worked out from the plant's id (summing its bytes; Swift's own hashing
    /// is seeded differently on every launch).
    static func photoHeight(forID id: UUID?) -> CGFloat {
        guard let id else { return photoHeights[2] }
        let sum = withUnsafeBytes(of: id.uuid) { $0.reduce(0) { $0 &+ Int($1) } }
        return photoHeights[sum % photoHeights.count]
    }
}

/// The chip at the top-left of a tile: sky when watering is due, leaf when
/// it's later, terracotta when it's overdue.
struct WateringChip: Equatable {
    enum Tone: Equatable { case due, later, overdue }

    let label: String
    let tone: Tone

    static func make(for status: DueStatus?) -> WateringChip? {
        switch status {
        case nil: nil
        case .overdue(let days)?: WateringChip(label: "Overdue · \(days) day\(days == 1 ? "" : "s")", tone: .overdue)
        case .today?: WateringChip(label: "Water today", tone: .due)
        case .upcoming(1)?: WateringChip(label: "Tomorrow", tone: .later)
        case .upcoming(let days)?: WateringChip(label: "In \(days) days", tone: .later)
        }
    }
}
