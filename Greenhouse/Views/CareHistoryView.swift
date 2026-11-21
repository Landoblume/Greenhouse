import CoreData
import SwiftUI

/// Pushed from a plant's page with a value link, so it works alongside the
/// other value links in the stack (see CLAUDE.md, Navigation).
struct CareHistoryRoute: Hashable {
    let plant: Plant
}

/// Every time something was done for this plant: what, when, and by whom, as
/// a changelog. Each plant it came from is its own colored thread, and the
/// threads join where the plants were combined.
struct CareHistoryView: View {
    @ObservedObject var plant: Plant

    var body: some View {
        let timeline = CareHistory.timeline(for: plant)
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if let stats = CareHistory.stats(for: plant) {
                    CareStatsHeader(stats: stats)
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                } else {
                    Text("Nothing's been done for \(plant.displayName) yet. Marking a reminder done adds it here.")
                        .foregroundStyle(.secondary)
                        .padding()
                }
                ForEach(timeline.rows) { row in
                    CareHistoryRow(row: row, viewedPlant: plant, laneCount: timeline.threads.count)
                        .fluidScrollRow()
                }
            }
        }
        .navigationTitle("Care history")
        .navigationBarTitleDisplayMode(.inline)
        .redrawsOnCareLogChanges(plant)
    }
}

/// "Watered 23 times since May 2023 · mostly by Sam 💚"
struct CareStatsHeader: View {
    let stats: CareHistory.Stats

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(stats.headline)
                .font(.headline)
            if let others = stats.others {
                Text(others)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }
}

/// Lane colors: system colors, so they adapt to dark mode. The source plant's
/// name is always written out too, so color is never the only cue.
enum ThreadPalette {
    static let colors: [Color] = [.green, .blue, .orange, .pink, .purple, .teal]
    static func color(_ lane: Int) -> Color { colors[lane % colors.count] }
}

/// One row of the list: a month header, a care log, or a combine, drawn
/// beside the threads' lines.
struct CareHistoryRow: View {
    let row: CareHistory.Row
    let viewedPlant: Plant
    let laneCount: Int
    @ScaledMetric(relativeTo: .body) private var laneWidth: CGFloat = 22
    @ScaledMetric(relativeTo: .body) private var nodeY: CGFloat = 22

    private var gutter: CGFloat { laneWidth * CGFloat(max(laneCount, 1)) + 8 }

    var body: some View {
        content
            .padding(.leading, gutter)
            .padding(.trailing)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(alignment: .topLeading) {
                ThreadGutter(lanes: row.lanes, laneWidth: laneWidth, nodeY: nodeY)
                    .padding(.leading, 8)
            }
            .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var content: some View {
        switch row.kind {
        case .month(let date):
            Text(date.map { $0.formatted(.dateTime.month(.wide).year()) } ?? "Unknown date")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
        case .log(let entry):
            LogContent(entry: entry, viewedPlant: viewedPlant)
        case .merge(let merge):
            MergeContent(merge: merge)
        }
    }
}

/// Watches the log so an undo or a change from the other phone shows right away.
private struct LogContent: View {
    let entry: CareHistory.Entry
    let viewedPlant: Plant
    @ObservedObject private var log: CareLog
    @ObservedObject private var source: Plant

    init(entry: CareHistory.Entry, viewedPlant: Plant) {
        self.entry = entry
        self.viewedPlant = viewedPlant
        _log = ObservedObject(wrappedValue: entry.log)
        _source = ObservedObject(wrappedValue: entry.source)
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title)
                if let who = log.doneBy?.trimmingCharacters(in: .whitespacesAndNewlines), !who.isEmpty {
                    Text("by \(who)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if source != viewedPlant {
                    Text("For \(source.displayName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(log.doneAt.map(Lineage.format) ?? "Unknown date")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

private struct MergeContent: View {
    let merge: CareHistory.Merge
    @ObservedObject private var output: Plant

    init(merge: CareHistory.Merge) {
        self.merge = merge
        _output = ObservedObject(wrappedValue: merge.output)
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(merge.title).font(.headline)
                Text(merge.kind == .staple
                     ? merge.inputs.map(\.displayName).joined(separator: " + ") + " → " + output.displayName
                     : (merge.inputs.first?.displayName ?? "A plant") + " → " + output.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(merge.date.map(Lineage.format) ?? "Unknown date")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

/// The lanes' lines and dots for one row. Lines grow in the first time the
/// row appears; the merge node pops in and its joins draw toward it.
private struct ThreadGutter: View {
    let lanes: [CareHistory.LaneMark]
    let laneWidth: CGFloat
    let nodeY: CGFloat
    @State private var revealed = false

    private let dot: CGFloat = 10
    private let lineWidth: CGFloat = 3

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(lanes.indices, id: \.self) { lane in
                laneView(lane, mark: lanes[lane])
            }
        }
        .frame(width: laneWidth * CGFloat(max(lanes.count, 1)))
        .frame(maxHeight: .infinity, alignment: .top)
        .revealsOnAppear($revealed)
        .accessibilityHidden(true)
    }

    private func x(_ lane: Int) -> CGFloat { laneWidth * (CGFloat(lane) + 0.5) }

    @ViewBuilder private func laneView(_ lane: Int, mark: CareHistory.LaneMark) -> some View {
        let color = ThreadPalette.color(lane)
        let progress: CGFloat = revealed ? 1 : 0
        GeometryReader { proxy in
            let height = proxy.size.height
            // Line coming in from above, down to the node (or the row's end).
            if mark.lineAbove {
                Path { p in
                    p.move(to: CGPoint(x: x(lane), y: 0))
                    p.addLine(to: CGPoint(x: x(lane), y: (mark.dot || mark.joinsLane != nil) ? nodeY : height))
                }
                .trim(from: 0, to: progress)
                .stroke(color.opacity(0.85), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            }
            // Line carrying on below.
            if mark.lineBelow {
                let startY: CGFloat = (mark.dot || mark.joinsLane != nil) ? nodeY : 0
                Path { p in
                    p.move(to: CGPoint(x: x(lane), y: startY))
                    p.addLine(to: CGPoint(x: x(lane), y: height))
                }
                .trim(from: 0, to: progress)
                .stroke(color.opacity(0.85), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            }
            // An original curving into the combined plant's lane.
            if let into = mark.joinsLane {
                Path { p in
                    p.move(to: CGPoint(x: x(lane), y: nodeY + laneWidth))
                    p.addQuadCurve(to: CGPoint(x: x(into), y: nodeY), control: CGPoint(x: x(lane), y: nodeY))
                }
                .trim(from: 0, to: progress)
                .stroke(color.opacity(0.85), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            }
            if mark.dot {
                Circle()
                    .fill(color)
                    .frame(width: mark.isMergeNode ? dot * 1.8 : dot, height: mark.isMergeNode ? dot * 1.8 : dot)
                    .overlay {
                        if mark.isMergeNode {
                            Image(systemName: "arrow.triangle.merge")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.background)
                        }
                    }
                    .scaleEffect(progress)
                    .position(x: x(lane), y: nodeY)
            }
        }
    }
}

extension View {
    /// The history list is built from the plant's tasks and their logs, which
    /// the plant doesn't observe: marking a task done, undoing it, or a log
    /// arriving from the other phone wouldn't redraw it.
    func redrawsOnCareLogChanges(_ plant: Plant) -> some View {
        onReceive(NotificationCenter.default.publisher(for: .NSManagedObjectContextObjectsDidChange)) { note in
            let keys = [NSInsertedObjectsKey, NSUpdatedObjectsKey, NSDeletedObjectsKey, NSRefreshedObjectsKey]
            let changed = keys.contains { key in
                (note.userInfo?[key] as? Set<NSManagedObject>)?.contains { $0 is CareLog || $0 is CareTask || $0 is Plant } ?? false
            }
            if changed { plant.objectWillChange.send() }
        }
    }
}
