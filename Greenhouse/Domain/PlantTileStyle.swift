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
    /// An SF Symbol: a droplet for soil, a different one for changing water.
    var icon = GrowMedium.soil.careIcon

    /// A soil plant's chip is "Water today" / "Tomorrow" / "In 4 days"; a
    /// water-, LECA- or sphagnum-grown one reads "Change water today" /
    /// "Change water tomorrow" / "Change water in 4 days". Overdue and the
    /// narrow-tile short labels say the same for every medium.
    static func make(for status: DueStatus?, medium: GrowMedium = .soil) -> WateringChip? {
        let soil = medium == .soil
        let icon = medium.careIcon
        switch status {
        case nil: return nil
        case .overdue(let days)?:
            return WateringChip(label: "Overdue · \(days) day\(days == 1 ? "" : "s")", shortLabel: "\(days)d", tone: .overdue, icon: icon)
        case .today?:
            return WateringChip(label: soil ? "Water today" : "\(medium.careTaskName) today", shortLabel: "Due", tone: .due, icon: icon)
        case .upcoming(1)?:
            return WateringChip(label: soil ? "Tomorrow" : "\(medium.careTaskName) tomorrow", shortLabel: "in 1d", tone: .later, icon: icon)
        case .upcoming(let days)?:
            return WateringChip(label: soil ? "In \(days) days" : "\(medium.careTaskName) in \(days) days", shortLabel: "in \(days)d", tone: .later, icon: icon)
        }
    }
}
