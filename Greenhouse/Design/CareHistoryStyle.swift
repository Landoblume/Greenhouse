import SwiftUI
import UIKit

/// Sizes and colors for the care-history threads (from the Threads board),
/// kept out of Theme.swift so the tokens file stays shared and unowned.
enum CareHistoryStyle {
    /// The log and one-plant gutter: threads braid inside it.
    static let gutter: CGFloat = 72
    /// Lanes are this far apart; they tighten at accessibility text sizes.
    static let laneSpacing: CGFloat = 20
    static let laneSpacingTight: CGFloat = 14
    /// The log gutter's distance from the screen edge.
    static let inset: CGFloat = 12
    /// Gap between the gutter and the row's words.
    static let gutterGap: CGFloat = 12
    static let thread: CGFloat = 3
    /// One plant: the chosen lane goes thick and the others become hairlines.
    static let focusThread: CGFloat = 4
    static let hairline: CGFloat = 1.5
    static let hairlineOpacity = 0.35
    static let dot: CGFloat = 12
    static let halo: CGFloat = 3
    static let node: CGFloat = 26
    /// Branches out of a combine are cubic curves with vertical tangents over this height.
    static let branch: CGFloat = 44
    /// All threads: the left-hand month labels, and the widest lane spacing.
    static let monthColumn: CGFloat = 60
    static let wideSpacing: CGFloat = 95
    /// All threads: room kept clear right of the lanes, so every label can
    /// sit to the right of its dot, even on the rightmost lane.
    static let labelRoom: CGFloat = 104
    /// All threads: from a dot's center to its label.
    static let labelGap: CGFloat = 14

    static func color(_ index: Int) -> Color { GH.threads[((index % GH.threads.count) + GH.threads.count) % GH.threads.count] }

    /// How far down a row its dot goes: `padding` (which stays the same at
    /// every text size), then half a line of `style` text at `size`. That's
    /// level with the middle of the title's first line however big the text.
    static func titleMiddle(below padding: CGFloat, style: UIFont.TextStyle, size: DynamicTypeSize) -> CGFloat {
        padding + lineHeight(style, size: size) / 2
    }

    static func lineHeight(_ style: UIFont.TextStyle, size: DynamicTypeSize) -> CGFloat {
        let traits = UITraitCollection(preferredContentSizeCategory: UIContentSizeCategory(size))
        return UIFont.preferredFont(forTextStyle: style, compatibleWith: traits).lineHeight
    }
}

/// The three zoom levels, outermost first.
enum CareHistoryLevel: Int, CaseIterable, Identifiable {
    case allThreads, log, onePlant
    var id: Int { rawValue }

    var title: String {
        switch self {
        case .allThreads: "All threads"
        case .log: "Log"
        case .onePlant: "One plant"
        }
    }

    /// The shortest a row gets, for guessing how many rows fill the screen.
    var shortestRow: CGFloat {
        switch self {
        case .allThreads: 18
        case .log: 40
        case .onePlant: 46
        }
    }

    func zoomed(by steps: Int) -> CareHistoryLevel {
        CareHistoryLevel(rawValue: min(max(rawValue + steps, 0), CareHistoryLevel.allCases.count - 1)) ?? self
    }
}

/// Where each column's lane sits across a row, for one level and width.
struct LaneGeometry: Equatable {
    let xs: [CGFloat]
    /// Where the row's words start.
    let contentLeading: CGFloat
    let spacing: CGFloat

    func x(_ column: Int) -> CGFloat { column >= 0 && column < xs.count ? xs[column] : (xs.first ?? 0) }

    static func make(level: CareHistoryLevel, columns: Int, width: CGFloat, tight: Bool) -> LaneGeometry {
        let n = max(columns, 1)
        switch level {
        case .allThreads:
            // Lanes fill what's left after the month labels on the left and
            // the label room on the right.
            let available = max(width - CareHistoryStyle.monthColumn - CareHistoryStyle.labelRoom, 40)
            let spacing = min(CareHistoryStyle.wideSpacing, available / CGFloat(n))
            let center = CareHistoryStyle.monthColumn + available / 2
            let xs = (0..<n).map { center + (CGFloat($0) - CGFloat(n - 1) / 2) * spacing }
            return LaneGeometry(xs: xs, contentLeading: CareHistoryStyle.monthColumn, spacing: spacing)
        case .log, .onePlant:
            let spacing = tight ? CareHistoryStyle.laneSpacingTight : CareHistoryStyle.laneSpacing
            let gutter = max(CareHistoryStyle.gutter, CGFloat(n) * spacing + 16)
            let center = CareHistoryStyle.inset + gutter / 2
            let xs = (0..<n).map { center + (CGFloat($0) - CGFloat(n - 1) / 2) * spacing }
            return LaneGeometry(xs: xs, contentLeading: CareHistoryStyle.inset + gutter + CareHistoryStyle.gutterGap, spacing: spacing)
        }
    }
}
