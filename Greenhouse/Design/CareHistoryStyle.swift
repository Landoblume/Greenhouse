import SwiftUI

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

    static func color(_ index: Int) -> Color { GH.threads[((index % GH.threads.count) + GH.threads.count) % GH.threads.count] }
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
    /// The row's full width.
    var width: CGFloat = 390

    func x(_ column: Int) -> CGFloat { column >= 0 && column < xs.count ? xs[column] : (xs.first ?? 0) }

    static func make(level: CareHistoryLevel, columns: Int, width: CGFloat, tight: Bool) -> LaneGeometry {
        let n = max(columns, 1)
        switch level {
        case .allThreads:
            let available = max(width - CareHistoryStyle.monthColumn - GH.Space.m, 40)
            let spacing = min(CareHistoryStyle.wideSpacing, available / CGFloat(n))
            let center = CareHistoryStyle.monthColumn + available / 2
            let xs = (0..<n).map { center + (CGFloat($0) - CGFloat(n - 1) / 2) * spacing }
            return LaneGeometry(xs: xs, contentLeading: CareHistoryStyle.monthColumn, spacing: spacing, width: width)
        case .log, .onePlant:
            let spacing = tight ? CareHistoryStyle.laneSpacingTight : CareHistoryStyle.laneSpacing
            let gutter = max(CareHistoryStyle.gutter, CGFloat(n) * spacing + 16)
            let center = CareHistoryStyle.inset + gutter / 2
            let xs = (0..<n).map { center + (CGFloat($0) - CGFloat(n - 1) / 2) * spacing }
            return LaneGeometry(xs: xs, contentLeading: CareHistoryStyle.inset + gutter + CareHistoryStyle.gutterGap, spacing: spacing, width: width)
        }
    }
}
