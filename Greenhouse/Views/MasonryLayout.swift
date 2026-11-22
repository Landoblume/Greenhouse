import SwiftUI

/// Tiles in columns, each dropped into the shortest column so uneven heights
/// stack up like a masonry wall. Later columns start `columnStagger` lower, so
/// the tops don't line up. Because this is a real `Layout`, tiles keep their
/// identity and spring to their new spots when the list changes.
struct MasonryLayout: Layout {
    var columns = 2
    var gutter: CGFloat = GH.Space.s
    var rowSpacing: CGFloat = GH.Space.m
    var columnStagger: CGFloat = 28

    private func columnCount(_ subviewCount: Int) -> Int { max(1, columns) }

    private struct Placement {
        var frames: [CGRect] = []
        var height: CGFloat = 0
    }

    private func place(width: CGFloat, subviews: Subviews) -> Placement {
        let count = columnCount(subviews.count)
        let columnWidth = max(0, (width - gutter * CGFloat(count - 1)) / CGFloat(count))
        // Where the next tile goes in each column; later columns start lower.
        var bottoms = (0..<count).map { $0 == 0 ? 0 : columnStagger }
        var result = Placement()
        for subview in subviews {
            let column = bottoms.indices.min { bottoms[$0] < bottoms[$1] } ?? 0
            let size = subview.sizeThatFits(ProposedViewSize(width: columnWidth, height: nil))
            let origin = CGPoint(x: CGFloat(column) * (columnWidth + gutter), y: bottoms[column])
            result.frames.append(CGRect(origin: origin, size: CGSize(width: columnWidth, height: size.height)))
            bottoms[column] += size.height + rowSpacing
        }
        result.height = max(0, (bottoms.max() ?? 0) - rowSpacing)
        return result
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 360
        return CGSize(width: width, height: place(width: width, subviews: subviews).height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let placement = place(width: bounds.width, subviews: subviews)
        for (subview, frame) in zip(subviews, placement.frames) {
            subview.place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: frame.width, height: frame.height)
            )
        }
    }
}
