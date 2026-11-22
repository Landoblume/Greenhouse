import SwiftUI

/// Tiles in columns, each in the shortest column so far (worked out from
/// estimated heights, see `MasonryColumns`), the later columns starting lower.
/// Each column is a `LazyVStack`, so only tiles near the screen exist, which
/// keeps a household of a hundred plants cheap.
struct LazyMasonry<Item: Identifiable, Content: View>: View {
    let items: [Item]
    let heights: [CGFloat]
    var columns = 2
    var gutter: CGFloat = GH.Space.s
    var rowSpacing: CGFloat = GH.Space.m
    var columnStagger: CGFloat = 28
    @ViewBuilder let content: (Item, Int) -> Content

    /// A tile with its place in the whole list, identified by the item (not
    /// the position) so tiles keep their identity when filtering reshuffles.
    private struct Entry: Identifiable {
        let index: Int
        let item: Item
        var id: Item.ID { item.id }
    }

    var body: some View {
        let assignment = MasonryColumns.assign(heights: heights, columns: columns, stagger: columnStagger, spacing: rowSpacing)
        HStack(alignment: .top, spacing: gutter) {
            ForEach(Array(assignment.enumerated()), id: \.offset) { column, indices in
                LazyVStack(spacing: rowSpacing) {
                    ForEach(indices.map { Entry(index: $0, item: items[$0]) }) { entry in
                        content(entry.item, entry.index)
                    }
                }
                .padding(.top, column == 0 ? 0 : columnStagger)
            }
        }
    }
}
