import CoreData
import SwiftUI

/// Pushed from a plant's page with a value link, so it works alongside the
/// other value links in the stack (see CLAUDE.md, Navigation).
struct CareHistoryRoute: Hashable {
    let plant: Plant
}

/// Works the history out once, and again only when a saved change touches
/// this plant's family (its tasks, logs, milestones, cuttings or combines).
/// Another plant's watering, or a project, leaves it alone.
final class CareHistoryModel: ObservableObject {
    let plant: Plant
    @Published private(set) var timeline: CareHistory.Timeline = .empty
    @Published private(set) var stats: CareHistory.Stats?
    @Published private(set) var hasLogs = false
    /// The folded branches are open.
    @Published var expanded = false {
        didSet { if expanded != oldValue { rebuild() } }
    }
    /// What the history was built from; worked out alongside it.
    private var footprint: CareHistory.Footprint?
    private var focusCache: (plant: NSManagedObjectID, timeline: CareHistory.Timeline)?
    /// How many times the history has been worked out (tests check it stays put).
    private(set) var builds = 0

    init(plant: Plant) {
        self.plant = plant
        rebuild()
    }

    func rebuild() {
        let entries = CareHistory.entries(for: plant)
        timeline = CareHistory.timeline(for: plant, entries: entries, expanded: expanded)
        stats = CareHistory.stats(of: entries)
        hasLogs = !entries.isEmpty
        footprint = CareHistory.Footprint(plant: plant)
        focusCache = nil
        builds += 1
    }

    /// One plant's rows, kept until the history changes.
    func timeline(focusedOn focus: Plant) -> CareHistory.Timeline {
        if let focusCache, focusCache.plant == focus.objectID { return focusCache.timeline }
        let focused = timeline.focused(on: focus)
        focusCache = (focus.objectID, focused)
        return focused
    }

    /// From `NSManagedObjectContextObjectsDidChange`. Only the plant's own
    /// context counts: a background context (a sync, an import) posts on its
    /// own thread, and its objects can't be read from here. Its changes reach
    /// this context by merging, which posts again on the main thread.
    func contextChanged(_ note: Notification) {
        guard let context = plant.managedObjectContext, (note.object as? NSManagedObjectContext) === context else { return }
        let keys = [NSInsertedObjectsKey, NSUpdatedObjectsKey, NSDeletedObjectsKey, NSRefreshedObjectsKey]
        let objects = keys.flatMap { (note.userInfo?[$0] as? Set<NSManagedObject>) ?? [] }
        if footprint?.isAffected(by: objects) ?? true { rebuild() }
    }
}

/// Every time something was done for this plant: what, when, and by whom.
/// Each plant it came from is its own colored thread, and the threads join
/// where the plants were combined. Three zoom levels (all threads, the log,
/// one plant) reflow the same rows; pinch, the segmented control, or a
/// lane's name switch between them.
struct CareHistoryView: View {
    let plant: Plant
    @StateObject private var model: CareHistoryModel
    @AppStorage(SettingsKey.myName) private var myName = ""
    @Environment(\.managedObjectContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var level: CareHistoryLevel = .log
    @State private var focus: Plant?
    @State private var clock = HistoryDrawClock()
    @State private var appeared = false
    @State private var viewport = CGSize(width: 390, height: 700)
    @State private var bloom = HistoryBloomLedger()
    @State private var pendingUndo: CareHistory.Entry?
    @State private var addingReminder = false
    @Namespace private var dots

    /// Opens on the log unless told otherwise.
    init(plant: Plant, level: CareHistoryLevel = .log, focus: Plant? = nil) {
        self.plant = plant
        _model = StateObject(wrappedValue: CareHistoryModel(plant: plant))
        _level = State(initialValue: level)
        _focus = State(initialValue: focus)
    }

    private var focusPlant: Plant { focus ?? plant }

    /// The context the plant (and so its logs) lives in.
    private var store: NSManagedObjectContext { plant.managedObjectContext ?? context }

    /// Under Reduce Motion the whole list crossfades when this changes.
    private var levelKey: String {
        level == .onePlant ? "one-\(focusPlant.objectID.uriRepresentation())" : "level-\(level.rawValue)"
    }

    private var shown: CareHistory.Timeline {
        level == .onePlant ? model.timeline(focusedOn: focusPlant) : model.timeline
    }

    /// About a screenful of rows: only those animate in.
    private var window: Int { Int(viewport.height / level.shortestRow) + 2 }

    var body: some View {
        let timeline = shown
        let geometry = LaneGeometry.make(level: level, columns: timeline.columnCount, width: viewport.width,
                                         tight: typeSize.isAccessibilitySize)
        let schedule = CareHistory.drawSchedule(for: timeline, window: window)
        let actions = CareHistoryActions(
            focus: { zoom(into: $0) },
            undo: { pendingUndo = $0 },
            expand: { withAnimation(reduceMotion ? GH.Motion.reduced : GH.Motion.enter) { model.expanded = true } }
        )
        ScrollView {
            // A ZStack so that, under Reduce Motion, the old level and the new
            // one overlap while they crossfade instead of stacking up.
            ZStack(alignment: .top) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    header
                    if level == .allThreads, let root = timeline.threads.first, !timeline.rows.isEmpty {
                        rootPill(root, geometry: geometry)
                    }
                    ForEach(Array(timeline.rows.enumerated()), id: \.element.id) { index, row in
                        CareHistoryRowView(
                            row: row,
                            level: level,
                            timeline: timeline,
                            geometry: geometry,
                            viewedPlant: plant,
                            focusPlant: level == .onePlant ? focusPlant : nil,
                            timing: schedule.timing(forRow: index),
                            clock: clock,
                            namespace: dots,
                            bloom: bloom,
                            actions: actions
                        )
                    }
                }
                .padding(.bottom, GH.Space.xl)
                .id(reduceMotion ? levelKey : "moving")
                .transition(.opacity)
            }
        }
        .scrollIndicators(.hidden)
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear { viewport = proxy.size }
                    .onChange(of: proxy.size) { _, size in viewport = size }
            }
        }
        .simultaneousGesture(
            MagnifyGesture(minimumScaleDelta: 0.05).onEnded { value in
                // Snap to the nearest level: a bigger pinch goes two levels.
                let scale = value.magnification
                let steps = scale > 2.4 ? 2 : scale > 1.25 ? 1 : scale < 0.42 ? -2 : scale < 0.8 ? -1 : 0
                if steps != 0 { setLevel(level.zoomed(by: steps)) }
            }
        )
        .safeAreaInset(edge: .top, spacing: 0) {
            HistoryLevelPicker(selection: level) { setLevel($0) }
                .padding(.horizontal, GH.Space.screen)
                .padding(.vertical, GH.Space.xs)
                .background(GH.Palette.paper)
        }
        .ghTabBarClearance()
        .background(GH.Palette.paper.ignoresSafeArea())
        .navigationTitle(level == .onePlant ? focusPlant.displayName : "Care history")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) { titleView(timeline) }
        }
        .onAppear {
            // Lines and dots draw in once per visit to the screen, and again
            // on coming back to it.
            if appeared {
                clock.replay()
                bloom.reset()
            }
            appeared = true
        }
        // Only the plant's own (main-thread) context: see `contextChanged`.
        .onReceive(NotificationCenter.default.publisher(for: .NSManagedObjectContextObjectsDidChange,
                                                        object: store)) { note in
            model.contextChanged(note)
        }
        .onChange(of: model.builds) {
            // The other phone took this log back while we were asking.
            if let pending = pendingUndo, CareHistory.live(pending.log, in: store) == nil { pendingUndo = nil }
        }
        .confirmationDialog(
            "Undo this log?",
            isPresented: Binding(get: { pendingUndo != nil }, set: { if !$0 { pendingUndo = nil } }),
            titleVisibility: .visible,
            presenting: pendingUndo
        ) { entry in
            Button("Undo log", role: .destructive) { undo(entry) }
            Button("Keep it", role: .cancel) {}
        } message: { entry in
            Text("\(entry.title), \(CareHistory.dayLabel(entry.doneAt)). Only this one log is removed; the rest of the history stays.")
        }
        .sheet(isPresented: $addingReminder) {
            if let household = plant.household {
                TaskEditorView(household: household, task: nil, preselected: [plant])
            }
        }
    }

    // MARK: Header

    @ViewBuilder private var header: some View {
        if !model.hasLogs {
            EmptyHistoryCard(plant: plant) { addingReminder = true }
                .padding(.horizontal, GH.Space.screen)
                .padding(.vertical, GH.Space.xs)
                .growIn()
        } else if level == .log, let stats = model.stats {
            CareStatsHeader(stats: stats, viewerName: myName)
                .padding(.horizontal, GH.Space.screen)
                .padding(.vertical, GH.Space.xs)
                .growIn()
        }
    }

    /// Zoomed out, the viewed plant's name sits on top of its lane.
    private func rootPill(_ root: CareHistory.CareThread, geometry: LaneGeometry) -> some View {
        let x = geometry.x(root.column)
        return ZStack(alignment: .topLeading) {
            Path { p in
                p.move(to: CGPoint(x: x, y: 26))
                p.addLine(to: CGPoint(x: x, y: 40))
            }
            .stroke(CareHistoryStyle.color(root.color), style: StrokeStyle(lineWidth: CareHistoryStyle.thread, lineCap: .round))
            .accessibilityHidden(true)
            HistoryNamePill(name: root.plant.displayName, color: CareHistoryStyle.color(root.color), maxWidth: 200, leaf: true) {
                zoom(into: root.plant)
            }
            .position(x: x, y: 14)
        }
        .frame(maxWidth: .infinity, minHeight: 40, alignment: .topLeading)
        .padding(.top, GH.Space.xs)
    }

    @ViewBuilder private func titleView(_ timeline: CareHistory.Timeline) -> some View {
        VStack(spacing: 0) {
            Text(subtitle(timeline))
                .font(.caption)
                .foregroundStyle(GH.Palette.ink2)
                .lineLimit(1)
            HStack(spacing: 6) {
                if level == .onePlant, let thread = timeline.threads.first(where: { $0.plant == focusPlant }) {
                    Circle().fill(CareHistoryStyle.color(thread.color)).frame(width: 10, height: 10)
                        .accessibilityHidden(true)
                }
                Text(level == .onePlant ? focusPlant.displayName : "Care history")
                    .font(.ghRounded(.headline))
                    .foregroundStyle(GH.Palette.ink)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private func subtitle(_ timeline: CareHistory.Timeline) -> String {
        switch level {
        case .allThreads:
            let count = timeline.threads.count
            return "\(plant.displayName) · \(count == 1 ? "1 thread" : "\(count) threads")"
        case .log:
            guard let latin = CareHistory.cleaned(plant.scientificName), latin != plant.displayName else { return plant.displayName }
            return "\(plant.displayName) · \(latin)"
        case .onePlant:
            guard focusPlant != plant else { return Lineage.ancestors(of: plant).isEmpty ? "Its whole story" : "Since the Combine" }
            let word = focusPlant.consumedBy?.kindValue == .split ? "split" : "Combine"
            return "\(plant.displayName) › \(focusPlant.displayName) · before the \(word)"
        }
    }

    // MARK: Actions

    private func setLevel(_ new: CareHistoryLevel) {
        guard new != level else { return }
        changeLevel { level = new }
    }

    private func zoom(into target: Plant) {
        guard target != focus || level != .onePlant else { return }
        changeLevel {
            focus = target
            level = .onePlant
        }
    }

    /// Moving: the rows reflow, dots glide to their new spots, and the lines
    /// draw in again. Reduce Motion: the old level crossfades into the new
    /// one, already drawn.
    private func changeLevel(_ change: () -> Void) {
        if reduceMotion {
            withAnimation(GH.Motion.reduced, change)
        } else {
            withAnimation(GH.Motion.zoom) {
                change()
                clock.restart()
            }
        }
    }

    private func undo(_ entry: CareHistory.Entry) {
        pendingUndo = nil
        if CareHistory.undo(entry.log, context: store) {
            Persistence.shared.save(store)
            NotificationPlanner.reschedule()
        }
    }
}

// MARK: - Header pieces

/// "Watered 23 times since May 2023 · mostly by Sam 💚", with the big number
/// and a little party on round numbers.
struct CareStatsHeader: View {
    let stats: CareHistory.Stats
    var viewerName: String?
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            let layout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
                : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 10))
            layout {
                GHDisplayNumber(value: "\(stats.lead.count)")
                    .accessibilityHidden(true)
                Text(stats.headline(viewerName: viewerName))
                    .font(.subheadline)
                    .foregroundStyle(GH.Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let celebration = stats.celebration() {
                Text(celebration)
                    .font(.ghRounded(.subheadline, weight: .bold))
                    .foregroundStyle(GH.Palette.terraInk)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(GH.Space.m)
        .ghCard()
        .accessibilityElement(children: .combine)
    }
}

/// Nothing logged yet: a warm hello, and a way to set up the first reminder.
private struct EmptyHistoryCard: View {
    @ObservedObject var plant: Plant
    let addReminder: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: GH.Space.s) {
            Text("Fresh start. \(plant.displayName)'s story begins the first time you mark something done 🌱")
                .font(.body)
                .foregroundStyle(GH.Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
            if plant.isActive, plant.activeTasks.isEmpty, plant.household != nil {
                Button("Add a care reminder", action: addReminder)
                    .buttonStyle(.ghProminent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(GH.Space.m)
        .ghCard()
    }
}

/// All threads / Log / One plant. The no-pinch and VoiceOver way to zoom.
private struct HistoryLevelPicker: View {
    let selection: CareHistoryLevel
    let select: (CareHistoryLevel) -> Void
    @Namespace private var pill

    var body: some View {
        HStack(spacing: 0) {
            ForEach(CareHistoryLevel.allCases) { level in
                let selected = level == selection
                Button { select(level) } label: {
                    Text(level.title)
                        .font(selected ? .subheadline.weight(.heavy) : .subheadline.weight(.semibold))
                        .foregroundStyle(selected ? GH.Palette.ink : GH.Palette.ink2)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 4)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background {
                            if selected {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(GH.Palette.surface)
                                    .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
                                    .matchedGeometryEffect(id: "selected", in: pill)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? [.isSelected] : [])
            }
        }
        .padding(3)
        .background(GH.Palette.surface2, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Zoom level")
    }
}
