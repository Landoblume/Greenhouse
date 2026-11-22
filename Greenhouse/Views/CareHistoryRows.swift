import CoreData
import SwiftUI
import UIKit

/// What a row can ask the screen to do.
struct CareHistoryActions {
    /// Zoom into one plant's thread.
    var focus: (Plant) -> Void = { _ in }
    /// Ask before taking back one log.
    var undo: (CareHistory.Entry) -> Void = { _ in }
    /// Open the folded branches.
    var expand: () -> Void = {}
}

/// One row of the history at one zoom level: its words or card, with the
/// threads drawn beside it. The words grow in and soften while scrolling;
/// the threads don't move, so they stay joined up row to row.
struct CareHistoryRowView: View {
    let row: CareHistory.Row
    let level: CareHistoryLevel
    let timeline: CareHistory.Timeline
    let geometry: LaneGeometry
    let viewedPlant: Plant
    var focusPlant: Plant?
    let timing: CareHistory.DrawSchedule.RowTiming?
    let clock: HistoryDrawClock
    let namespace: Namespace.ID
    let bloom: HistoryBloomLedger
    let actions: CareHistoryActions

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    /// All threads: a labeled row's height (a bare watering is shorter).
    @ScaledMetric(relativeTo: .caption) private var chipRow: CGFloat = 28
    @ScaledMetric(relativeTo: .caption) private var pillHeight: CGFloat = 26

    var body: some View {
        content
            .modifier(HistoryLoadIn(delay: clock.animates(timing) ? timing?.label : nil, clock: clock, reduceMotion: reduceMotion))
            .id(level)
            .scrollSoftening()
            .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .topLeading)
            .background(alignment: .topLeading) {
                HistoryThreadGutter(
                    rowID: row.id,
                    lanes: row.lanes,
                    threads: timeline.threads,
                    geometry: geometry,
                    nodeY: nodeY,
                    focusLane: level == .onePlant ? focusLane : nil,
                    joinedColor: joinedColor,
                    timing: timing,
                    clock: clock,
                    reduceMotion: reduceMotion,
                    namespace: namespace,
                    bloom: bloom
                )
            }
            .modifier(HistoryRowAccessibility(row: row, viewedPlant: viewedPlant, focus: focusTarget, actions: actions))
    }

    // MARK: Geometry

    private var focusLane: Int? {
        guard let focusPlant else { return 0 }
        return timeline.threads.first { $0.plant == focusPlant }?.lane
    }

    /// The node points at where the plant went (the first new plant of a split).
    private var joinedColor: Int? {
        guard case .joined(let into, _, _, _) = row.kind, let first = into.first else { return nil }
        return CareHistory.colorOrder(for: viewedPlant)[first.objectID]
    }

    private var isAccessibilitySize: Bool { typeSize.isAccessibilitySize }

    private var nodeY: CGFloat {
        switch level {
        case .allThreads:
            if case .merge = row.kind { return 16 }
            return isBareWatering ? 9 : chipRow / 2
        case .log, .onePlant:
            // Level with the middle of the title's first line. Only the text
            // grows with the text size, not the padding above it, so the dot
            // stays on the title instead of sliding down onto the date.
            let cards = level == .onePlant
            switch row.kind {
            case .merge, .joined:
                return CareHistoryStyle.titleMiddle(below: LeafCardMetrics.titleTop, style: .headline, size: typeSize)
            case .milestone(let mark) where cards:
                let photo = Milestones.photos(of: mark.milestone).isEmpty ? 0 : HistoryMilestoneCard.photoBlock
                return CareHistoryStyle.titleMiddle(below: GH.Space.xs + HistoryMilestoneCard.padding + photo,
                                                    style: .headline, size: typeSize)
            case .cutting where cards:
                return CareHistoryStyle.titleMiddle(below: HistoryCuttingLink.cardMargin + HistoryLogLine.titleTop,
                                                    style: .body, size: typeSize)
            default:
                return CareHistoryStyle.titleMiddle(below: HistoryLogLine.titleTop, style: .body, size: typeSize)
            }
        }
    }

    private var minHeight: CGFloat {
        guard level == .allThreads else { return 0 }
        switch row.kind {
        case .month: return 26
        case .merge: return 16 + CareHistoryStyle.branch + pillHeight / 2 + 4
        case .showEarlier: return 44
        default: return isBareWatering ? 18 : chipRow
        }
    }

    private var isBareWatering: Bool {
        if case .log(let entry) = row.kind { return entry.isWatering }
        return false
    }

    /// The plant VoiceOver's "zoom into" action goes to.
    private var focusTarget: Plant? {
        guard let plant = row.plant, plant != (focusPlant ?? viewedPlant) || level != .onePlant else { return nil }
        return plant
    }

    private func color(of plant: Plant) -> Color {
        CareHistoryStyle.color(timeline.threads.first { $0.plant == plant }?.color ?? 0)
    }

    // MARK: Content

    @ViewBuilder private var content: some View {
        switch level {
        case .allThreads: allThreadsContent
        case .log: logContent(cards: false)
        case .onePlant: logContent(cards: true)
        }
    }

    /// The log and one plant: words beside the gutter. One plant opens rows into cards.
    @ViewBuilder private func logContent(cards: Bool) -> some View {
        Group {
            switch row.kind {
            case .month(let date):
                Text(CareHistory.monthLabel(date))
                    .font(.ghEyebrow)
                    .tracking(0.7)
                    .textCase(.uppercase)
                    .foregroundStyle(GH.Palette.ink2)
                    .padding(.top, GH.Space.m)
                    .padding(.bottom, GH.Space.xxs)
                    .accessibilityAddTraits(.isHeader)
            case .log(let entry):
                HistoryLogLine(
                    title: entry.title,
                    date: entry.doneAt,
                    by: entry.doneBy,
                    tag: cards || entry.source == viewedPlant ? nil : (entry.sourceLabel, color(of: entry.source)),
                    onTag: { actions.focus(entry.source) }
                )
                .modifier(HistoryUndoSwipe { actions.undo(entry) })
                .contextMenu {
                    if entry.source != (cards ? (focusPlant ?? viewedPlant) : viewedPlant) {
                        Button { actions.focus(entry.source) } label: { Label("Zoom into \(entry.source.displayName)", systemImage: "scope") }
                    }
                    Button(role: .destructive) { actions.undo(entry) } label: {
                        Label("Undo this log…", systemImage: "arrow.uturn.backward")
                    }
                }
            case .milestone(let mark):
                if cards {
                    HistoryMilestoneCard(mark: mark, photoDelay: clock.animates(timing) ? (timing?.label ?? 0) + 0.15 : nil, clock: clock)
                        .padding(.vertical, GH.Space.xs)
                } else {
                    HistoryLogLine(
                        title: "Milestone · \(mark.title)",
                        date: mark.date,
                        by: mark.addedBy,
                        tag: mark.source == viewedPlant ? nil : (mark.source.displayName, color(of: mark.source)),
                        onTag: { actions.focus(mark.source) }
                    )
                }
            case .merge(let merge):
                HistoryMergeCard(merge: merge, focus: cards ? (focusPlant ?? viewedPlant) : nil)
            case .joined(let into, let with, let date, let kind):
                HistoryJoinedCard(into: into, with: with, date: date, kind: kind)
            case .cutting(let mark):
                HistoryCuttingLink(mark: mark, card: cards)
            case .showEarlier(let count, _):
                HistoryEarlierPill(count: count, action: actions.expand)
                    .padding(.vertical, GH.Space.xs)
            }
        }
        .padding(.leading, geometry.contentLeading)
        .padding(.trailing, GH.Space.screen)
    }

    /// Zoomed out: dots on wide lanes, with short labels beside the ones
    /// that aren't waterings.
    @ViewBuilder private var allThreadsContent: some View {
        switch row.kind {
        case .month(let date):
            HStack(spacing: GH.Space.xs) {
                Text(CareHistory.monthLabel(date, short: true))
                    .font(.ghEyebrow)
                    .tracking(0.7)
                    .textCase(.uppercase)
                    .foregroundStyle(GH.Palette.ink2)
                    .lineLimit(1)
                    .frame(width: CareHistoryStyle.monthColumn - GH.Space.m - GH.Space.xs, alignment: .leading)
                Rectangle().fill(GH.Palette.line).frame(height: 1)
            }
            .padding(.leading, GH.Space.m)
            .frame(minHeight: 26)
            .accessibilityAddTraits(.isHeader)
        case .log(let entry):
            if entry.isWatering {
                Color.clear.frame(height: 18)
            } else {
                chip(entry.title, plant: entry.source)
            }
        case .milestone(let mark):
            chip(mark.title, plant: mark.source)
        case .cutting(let mark):
            chip(mark.direction == .taken ? "Cutting" : "From \(mark.parent.displayName)", plant: mark.source)
        case .joined(let into, _, _, let kind):
            // One plant to go to: the label opens its history.
            chip(HistoryJoinedCard.title(into: into, kind: kind), plant: viewedPlant, leaf: true,
                 opens: into.count == 1 ? into.first : nil)
        case .merge(let merge):
            mergeLanes(merge)
        case .showEarlier(let count, let under):
            HistoryEarlierPill(count: count, action: actions.expand)
                .padding(.leading, max(lane(of: under) - 60, GH.Space.m))
                .frame(minHeight: 44)
        }
    }

    private func lane(of plant: Plant) -> CGFloat {
        geometry.x(timeline.threads.first { $0.plant == plant }?.column ?? 0)
    }

    /// A label pinned just right of its dot, always: the lanes leave room
    /// for it on the right (`CareHistoryStyle.labelRoom(at:)`).
    @ViewBuilder private func chip(_ text: String, plant: Plant, leaf: Bool = false, opens: Plant? = nil) -> some View {
        let label = HStack(spacing: 3) {
            Text(text).lineLimit(1)
            if opens != nil {
                Image(systemName: "chevron.right").font(.caption2.weight(.heavy)).accessibilityHidden(true)
            }
        }
        .font(.caption.weight(.bold))
        .foregroundStyle(leaf ? GH.Palette.leafInk : GH.Palette.ink)
        .padding(.horizontal, GH.Space.xs)
        .frame(minHeight: 22)
        .background(leaf ? GH.Palette.leafSoft : GH.Palette.surface, in: Capsule(style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 3, y: 1)
        Group {
            if let opens {
                NavigationLink(value: CareHistoryRoute(plant: opens)) {
                    // 44 pt to tap, without making the row taller.
                    label.padding(.vertical, 11).contentShape(Rectangle()).padding(.vertical, -11)
                }
                .buttonStyle(.plain)
            } else {
                label
            }
        }
        .padding(.leading, lane(of: plant) + CareHistoryStyle.labelGap)
        .padding(.trailing, GH.Space.xs)
        .frame(maxWidth: .infinity, minHeight: chipRow, alignment: .leading)
    }

    /// The combine node with its date, and a name pill on each original's
    /// lane right where it splits off. Tapping a pill zooms into that plant.
    private func mergeLanes(_ merge: CareHistory.Merge) -> some View {
        let shown = merge.inputs.filter { input in timeline.threads.contains { $0.plant == input } }
        return ZStack(alignment: .topLeading) {
            Text("\(merge.title) · \(merge.date.map { $0.formatted(.dateTime.month(.abbreviated).day()) } ?? "?")")
                .font(.caption.weight(.bold))
                .lineLimit(1)
                .foregroundStyle(GH.Palette.leafInk)
                .padding(.horizontal, GH.Space.xs)
                .frame(minHeight: 22)
                .background(GH.Palette.leafSoft, in: Capsule(style: .continuous))
                .padding(.leading, lane(of: merge.output) + CareHistoryStyle.node / 2 + 6)
                .padding(.trailing, GH.Space.xs)
                .padding(.top, 16 - 11)
            ForEach(shown, id: \.objectID) { input in
                HistoryNamePill(name: input.displayName, color: color(of: input), maxWidth: max(geometry.spacing - 6, 56)) {
                    actions.focus(input)
                }
                .position(x: lane(of: input), y: 16 + CareHistoryStyle.branch)
            }
        }
        .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .topLeading)
    }
}

// MARK: - Pieces

/// A log line: what, when ("Fri 14"), who, and, before a combine, whose.
/// The date sits beside the title, and under it at accessibility sizes.
private struct HistoryLogLine: View {
    /// Space above the title.
    static let titleTop: CGFloat = 10

    let title: String
    let date: Date?
    let by: String?
    let tag: (String, Color)?
    let onTag: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            if typeSize.isAccessibilitySize {
                Text(title).font(.body.weight(.semibold)).foregroundStyle(GH.Palette.ink)
                Text(CareHistory.dayLabel(date)).font(.subheadline).foregroundStyle(GH.Palette.ink2)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: GH.Space.xs) {
                    Text(title).font(.body.weight(.semibold)).foregroundStyle(GH.Palette.ink)
                    Spacer(minLength: GH.Space.xs)
                    Text(CareHistory.dayLabel(date)).font(.subheadline).foregroundStyle(GH.Palette.ink2)
                }
            }
            if tag != nil || by != nil {
                let layout = typeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                    : AnyLayout(HStackLayout(spacing: 6))
                layout {
                    if let tag { HistoryNameTag(name: tag.0, color: tag.1, action: onTag) }
                    if let by { Text("by \(by)").font(.subheadline).foregroundStyle(GH.Palette.ink2) }
                }
            }
        }
        .padding(.vertical, Self.titleTop)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

/// The plant's name with its thread color, on rows from before a combine.
/// A button: tapping it zooms into that plant.
private struct HistoryNameTag: View {
    let name: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Circle().fill(color).frame(width: 7, height: 7)
                Text(name).font(.caption.weight(.bold)).foregroundStyle(GH.Palette.ink).lineLimit(1)
            }
            .padding(.horizontal, 7)
            .frame(minHeight: 20)
            .background(GH.Palette.surface2, in: Capsule(style: .continuous))
            // 44 pt to tap, without making the row taller.
            .padding(.vertical, 12)
            .contentShape(Rectangle())
            .padding(.vertical, -12)
        }
        .buttonStyle(.plain)
    }
}

/// A lane's name, where it splits off in the zoomed-out view.
struct HistoryNamePill: View {
    let name: String
    let color: Color
    let maxWidth: CGFloat
    /// The viewed plant's own pill is leafSoft.
    var leaf = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Circle().fill(color).frame(width: 7, height: 7)
                Text(name).font(.caption.weight(.heavy)).foregroundStyle(leaf ? GH.Palette.leafInk : GH.Palette.ink).lineLimit(1)
            }
            .padding(.horizontal, 9)
            .frame(minHeight: 24)
            .background(leaf ? GH.Palette.leafSoft : GH.Palette.surface, in: Capsule(style: .continuous))
            .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
            .frame(maxWidth: maxWidth)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
            .padding(.vertical, -10)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Zoom into \(name)")
    }
}

/// "Show 3 earlier plants": opens the folded branches in place.
private struct HistoryEarlierPill: View {
    let count: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(count == 1 ? "Show 1 earlier plant" : "Show \(count) earlier plants", systemImage: "chevron.down")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(GH.Palette.leafInk)
                .padding(.horizontal, GH.Space.m)
                .frame(minHeight: 44)
                .background(GH.Palette.leafSoft, in: Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

/// A leaf card's padding: outside it, then inside it, above the title.
private enum LeafCardMetrics {
    static let margin: CGFloat = 6
    static let inset: CGFloat = 9
    /// For lining a dot up with the title.
    static var titleTop: CGFloat { margin + inset }
}

/// leafSoft card: a combine, or where a plant went.
private struct HistoryLeafCard<Extra: View>: View {
    let title: String
    let detail: String
    /// A chevron: the whole card opens something.
    var opens = false
    @ViewBuilder var extra: Extra

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: GH.Space.xs) {
                Text(title)
                    .font(.ghRounded(.headline))
                    .foregroundStyle(GH.Palette.leafInk)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if opens {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(GH.Palette.leafInk)
                        .accessibilityHidden(true)
                }
            }
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(GH.Palette.ink)
            extra
        }
        .padding(.vertical, LeafCardMetrics.inset)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GH.Palette.leafSoft, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .padding(.vertical, LeafCardMetrics.margin)
    }
}

extension HistoryLeafCard where Extra == EmptyView {
    init(title: String, detail: String, opens: Bool = false) {
        self.init(title: title, detail: detail, opens: opens) { EmptyView() }
    }
}

/// At the top of a plant that went into another: "Became part of The Trio"
/// opens The Trio's history. A split names every new plant, and each gets
/// its own link.
private struct HistoryJoinedCard: View {
    let into: [Plant]
    let with: [Plant]
    let date: Date?
    let kind: LineageKind

    static func title(into: [Plant], kind: LineageKind) -> String {
        "\(kind == .split ? "Split into" : "Became part of") \(CareHistory.names(into))"
    }

    private var detail: String {
        [with.isEmpty ? nil : "With \(CareHistory.names(with))", CareHistory.dayLabel(date)]
            .compactMap { $0 }.joined(separator: " · ")
    }

    var body: some View {
        if into.count == 1, let only = into.first {
            NavigationLink(value: CareHistoryRoute(plant: only)) {
                HistoryLeafCard(title: Self.title(into: into, kind: kind), detail: detail, opens: true)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens \(only.displayName)'s history")
        } else {
            HistoryLeafCard(title: Self.title(into: into, kind: kind), detail: detail) {
                ForEach(into, id: \.objectID) { plant in
                    NavigationLink(value: CareHistoryRoute(plant: plant)) {
                        HStack(spacing: GH.Space.xs) {
                            Text("\(plant.displayName)'s history")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(GH.Palette.leafInk)
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.bold))
                                .foregroundStyle(GH.Palette.leafInk)
                                .accessibilityHidden(true)
                        }
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

/// "Combined into The Trio · Rosie, Spike & Lulu · Sun 12". Zoomed into one
/// of the originals it reads "Became part of The Trio · With Rosie & Spike".
private struct HistoryMergeCard: View {
    let merge: CareHistory.Merge
    /// One plant: whose point of view.
    let focus: Plant?
    @ObservedObject private var output: Plant

    init(merge: CareHistory.Merge, focus: Plant?) {
        self.merge = merge
        self.focus = focus
        _output = ObservedObject(wrappedValue: merge.output)
    }

    var body: some View {
        let day = CareHistory.dayLabel(merge.date)
        if merge.kind == .split {
            HistoryLeafCard(title: "Split from \(CareHistory.names(merge.inputs))",
                            detail: "Became \(CareHistory.names(merge.outputs.isEmpty ? [output] : merge.outputs)) · \(day)")
        } else if let focus, merge.inputs.contains(focus) {
            let others = merge.inputs.filter { $0 != focus }
            HistoryLeafCard(title: "Became part of \(output.displayName)",
                     detail: others.isEmpty ? day : "With \(CareHistory.names(others)) · \(day)")
        } else if focus != nil {
            HistoryLeafCard(title: "Combined from \(CareHistory.names(merge.inputs))", detail: day)
        } else {
            HistoryLeafCard(title: "Combined into \(output.displayName)", detail: "\(CareHistory.names(merge.inputs)) · \(day)")
        }
    }
}

/// "Cutting taken → Pip Jr." Opens that plant's own history.
private struct HistoryCuttingLink: View {
    /// Space above a card (one-plant level).
    static let cardMargin: CGFloat = 6

    let mark: CareHistory.CuttingMark
    let card: Bool

    var body: some View {
        NavigationLink(value: CareHistoryRoute(plant: mark.linked)) {
            HStack(spacing: GH.Space.s) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(mark.direction == .taken ? "Cutting taken → \(mark.cutting.displayName)" : "Cutting from \(mark.parent.displayName)")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(GH.Palette.ink)
                    Text("\(CareHistory.dayLabel(mark.date)) · opens its history")
                        .font(.subheadline)
                        .foregroundStyle(GH.Palette.ink2)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(GH.Palette.ink2)
            }
            .padding(.vertical, HistoryLogLine.titleTop)
            .padding(.horizontal, card ? 14 : 0)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background {
                if card {
                    RoundedRectangle(cornerRadius: 20, style: .continuous).fill(GH.Palette.surface)
                        .shadow(color: .black.opacity(0.06), radius: 6, y: 3)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, card ? Self.cardMargin : 0)
    }
}

/// One plant: a milestone opens into a card with its photo and note.
private struct HistoryMilestoneCard: View {
    static let padding: CGFloat = 10
    static let photoHeight: CGFloat = 140
    static let photoGap: CGFloat = 5
    /// How far a photo pushes the title down.
    static var photoBlock: CGFloat { photoHeight + photoGap }

    let mark: CareHistory.MilestoneMark
    let photoDelay: Double?
    let clock: HistoryDrawClock

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            if let photo = Milestones.photos(of: mark.milestone).first {
                HistoryPhoto(photo: photo, delay: photoDelay, clock: clock)
                    .frame(height: Self.photoHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .padding(.bottom, Self.photoGap)
                    .accessibilityLabel("Photo of \(mark.source.displayName)'s \(mark.title.lowercased())")
            }
            Text(mark.title)
                .font(.ghRounded(.headline))
                .foregroundStyle(GH.Palette.ink)
            Text((["Milestone", CareHistory.dayLabel(mark.date)] + [mark.addedBy].compactMap { $0 }).joined(separator: " · "))
                .font(.subheadline)
                .foregroundStyle(GH.Palette.ink2)
            if let notes = mark.notes {
                Text(notes).font(.subheadline).foregroundStyle(GH.Palette.ink)
            }
        }
        .padding(Self.padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GH.Palette.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 6, y: 3)
    }
}

/// A photo that starts as a plain placeholder and crossfades in once it's
/// decoded (off the main thread) and its row has grown in.
private struct HistoryPhoto: View {
    let photo: Photo
    let delay: Double?
    let clock: HistoryDrawClock
    @State private var image: UIImage?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Rectangle().fill(GH.Palette.surface2)
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .transition(.opacity)
            }
        }
        .task(id: photo.objectID) {
            guard let data = photo.imageData else { return }
            let decoded = await Task.detached(priority: .userInitiated) {
                UIImage(data: data)?.preparingThumbnail(of: CGSize(width: 900, height: 900))
            }.value
            let wait = max(0, (delay ?? 0) - clock.elapsed)
            if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
            withAnimation(.easeInOut(duration: reduceMotion ? 0.2 : 0.3)) { image = decoded }
        }
    }
}

// MARK: - Motion and gestures

/// Words and cards grow in on the draw-in's timing (a fade under Reduce
/// Motion). Rows created after their moment show at once.
private struct HistoryLoadIn: ViewModifier {
    let delay: Double?
    let clock: HistoryDrawClock
    let reduceMotion: Bool
    @State private var shown: Bool

    init(delay: Double?, clock: HistoryDrawClock, reduceMotion: Bool) {
        self.delay = delay
        self.clock = clock
        self.reduceMotion = reduceMotion
        _shown = State(initialValue: delay == nil)
    }

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .scaleEffect(shown || reduceMotion ? 1 : 0.96)
            .offset(y: shown || reduceMotion ? 0 : 10)
            .onAppear {
                guard !shown, let delay else { return }
                let wait = max(0, delay - clock.elapsed)
                withAnimation((reduceMotion ? GH.Motion.reduced : GH.Motion.enter).delay(wait)) { shown = true }
            }
    }
}

/// Decides once per drag whether it's a sideways swipe or a scroll, so a
/// diagonal scroll never nudges the row back and forth.
struct SwipeAxisLock {
    enum Axis { case horizontal, vertical }

    /// How far a drag goes before its direction is decided.
    static let decideAfter: CGFloat = 10
    /// Sideways only when clearly more across than down.
    static let ratio: CGFloat = 1.5

    private(set) var axis: Axis?
    /// Where the drag being decided started. A drag from somewhere else is
    /// a new one: the scroll view can cancel a drag without it ever ending,
    /// so the next one mustn't inherit its direction.
    private var start: CGPoint?

    /// The drag's direction, decided on the first movement big enough to tell.
    mutating func update(_ translation: CGSize, from origin: CGPoint) -> Axis? {
        if origin != start {
            axis = nil
            start = origin
        }
        if axis == nil, max(abs(translation.width), abs(translation.height)) >= Self.decideAfter {
            axis = abs(translation.width) > abs(translation.height) * Self.ratio ? .horizontal : .vertical
        }
        return axis
    }

    mutating func reset() {
        axis = nil
        start = nil
    }
}

/// Swipe a log row left to show Undo. The row's words move; the threads stay.
private struct HistoryUndoSwipe: ViewModifier {
    let onUndo: () -> Void
    @State private var offset: CGFloat = 0
    @State private var isOpen = false
    @State private var lock = SwipeAxisLock()
    /// True while a drag is live. Falls back to false when the drag ends
    /// or is cancelled (the scroll view took it), which `onEnded` misses.
    @GestureState private var dragging = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let reveal: CGFloat = 92

    func body(content: Content) -> some View {
        content
            .offset(x: offset)
            .background(alignment: .trailing) {
                if offset < 0 {
                    Button {
                        close()
                        onUndo()
                    } label: {
                        Label("Undo", systemImage: "arrow.uturn.backward")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(GH.Palette.terraInk)
                            .frame(width: max(-offset - 8, 0))
                            .frame(maxHeight: .infinity)
                            .background(GH.Palette.terraSoft, in: RoundedRectangle(cornerRadius: GH.Radius.chip, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 4)
                    .accessibilityHidden(true)
                }
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 20)
                    .updating($dragging) { _, state, _ in state = true }
                    .onChanged { value in
                        guard lock.update(value.translation, from: value.startLocation) == .horizontal else { return }
                        offset = min(0, max((isOpen ? -reveal : 0) + value.translation.width, -reveal * 1.4))
                    }
                    .onEnded { _ in
                        defer { lock.reset() }
                        // A scroll leaves the row exactly as it was.
                        guard lock.axis == .horizontal else { return }
                        settle()
                    }
            )
            .onChange(of: dragging) { _, live in
                // Cancelled rather than ended: onEnded never ran, so let go
                // here. (After a normal end the lock is already reset.)
                guard !live, lock.axis != nil else { return }
                if lock.axis == .horizontal { settle() }
                lock.reset()
            }
    }

    /// Snap open or shut, whichever is nearer.
    private func settle() {
        let open = offset < -reveal / 2
        withAnimation(reduceMotion ? GH.Motion.reduced : GH.Motion.fold) {
            isOpen = open
            offset = open ? -reveal : 0
        }
    }

    private func close() {
        withAnimation(reduceMotion ? GH.Motion.reduced : GH.Motion.fold) {
            isOpen = false
            offset = 0
        }
    }
}

/// The graph is hidden from VoiceOver, so each row reads as one sentence,
/// with zoom and undo as actions.
private struct HistoryRowAccessibility: ViewModifier {
    let row: CareHistory.Row
    let viewedPlant: Plant
    let focus: Plant?
    let actions: CareHistoryActions

    func body(content: Content) -> some View {
        switch row.kind {
        case .showEarlier, .cutting:
            // Real buttons and links: keep them as they are.
            content.accessibilityElement(children: .combine)
                .accessibilityLabel(CareHistory.spokenLabel(for: row, viewedPlant: viewedPlant))
        case .joined(let into, _, _, _) where into.count == 1:
            // A link to that plant's history.
            content.accessibilityElement(children: .combine)
                .accessibilityLabel(CareHistory.spokenLabel(for: row, viewedPlant: viewedPlant))
        case .joined:
            // A split: the card's words, then a link per new plant.
            content.accessibilityElement(children: .contain)
        case .month:
            content.accessibilityElement(children: .combine).accessibilityAddTraits(.isHeader)
        default:
            content
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(CareHistory.spokenLabel(for: row, viewedPlant: viewedPlant))
                .modifier(HistoryZoomAction(plant: focus, actions: actions))
                .modifier(HistoryUndoAction(row: row, actions: actions))
        }
    }
}

private struct HistoryZoomAction: ViewModifier {
    let plant: Plant?
    let actions: CareHistoryActions
    func body(content: Content) -> some View {
        if let plant {
            content.accessibilityAction(named: "Zoom into \(plant.displayName)") { actions.focus(plant) }
        } else {
            content
        }
    }
}

private struct HistoryUndoAction: ViewModifier {
    let row: CareHistory.Row
    let actions: CareHistoryActions
    func body(content: Content) -> some View {
        if case .log(let entry) = row.kind {
            content.accessibilityAction(named: "Undo this log") { actions.undo(entry) }
        } else {
            content
        }
    }
}
