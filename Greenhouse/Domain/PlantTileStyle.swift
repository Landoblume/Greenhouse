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

    /// Room under the photo for the name and Latin name, used only to decide
    /// which column a tile goes in. A fixed number (not the real text height)
    /// so the columns never change with the text size.
    static let labelAllowance: CGFloat = 56

    /// A tile's height as far as column placement cares.
    static func estimatedHeight(forID id: UUID?) -> CGFloat {
        photoHeight(forID: id) + labelAllowance
    }
}

/// Which column each tile goes in: the shortest one so far, ties to the left,
/// with later columns starting `stagger` lower. Worked out from the tiles'
/// estimated heights alone, so it's the same on every launch and phone.
enum MasonryColumns {
    static func assign(heights: [CGFloat], columns: Int, stagger: CGFloat, spacing: CGFloat) -> [[Int]] {
        let count = max(1, columns)
        var bottoms = (0..<count).map { $0 == 0 ? CGFloat(0) : stagger }
        var result = Array(repeating: [Int](), count: count)
        for (index, height) in heights.enumerated() {
            let column = bottoms.indices.min { bottoms[$0] < bottoms[$1] } ?? 0
            result[column].append(index)
            bottoms[column] += height + spacing
        }
        return result
    }
}

/// The chip at the top-left of a tile: sky when watering is due, leaf when
/// it's later, terracotta when it's overdue.
struct WateringChip: Equatable {
    enum Tone: Equatable { case due, later, overdue }

    let label: String
    /// For a tile too narrow for `label` ("207d", "Due", "in 3d").
    let shortLabel: String
    let tone: Tone

    static func make(for status: DueStatus?) -> WateringChip? {
        switch status {
        case nil: nil
        case .overdue(let days)?: WateringChip(label: "Overdue · \(days) day\(days == 1 ? "" : "s")", shortLabel: "\(days)d", tone: .overdue)
        case .today?: WateringChip(label: "Water today", shortLabel: "Due", tone: .due)
        case .upcoming(1)?: WateringChip(label: "Tomorrow", shortLabel: "in 1d", tone: .later)
        case .upcoming(let days)?: WateringChip(label: "In \(days) days", shortLabel: "in \(days)d", tone: .later)
        }
    }
}
