import CoreData
import SwiftUI

/// One care reminder. On the Care tab (`.card`) it's a card with the plant's
/// photo; on a plant's own page (`.inline`, the default) it's a plain row.
struct TaskRow: View {
    enum Layout { case inline, card }

    /// How long a just-finished row celebrates in place ("Just now · <name> ·
    /// hold to undo") before it reads like any other row again. The Care tab
    /// keeps the row in its old section for the same time.
    static let celebration: Duration = .seconds(4)

    @ObservedObject var task: CareTask
    let household: Household
    var onEdit: () -> Void = {}
    /// Set where the row isn't already on the plant's own page (the Care tab):
    /// the plant's photo, its name chips and the context menu open that plant.
    var onOpenPlant: ((Plant) -> Void)? = nil
    var layout: Layout = .inline
    /// Called just before the task is marked done, so a list can keep the row in
    /// place while its celebration plays.
    var onDone: ((CareTask) -> Void)? = nil

    @Environment(\.managedObjectContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AppStorage(SettingsKey.myName) private var myName = ""
    @State private var choosingSnooze = false
    @State private var snoozeChoice: CareSchedule.SnoozeChoice?
    @State private var celebrate = 0
    @State private var undone = 0
    /// When this row's celebration ends; nil when it isn't celebrating.
    @State private var celebrationEnds: Date?
    /// Bumped at midnight (and on other clock jumps) so "done today" is redrawn.
    @State private var clock = Date.now

    private static let snoozeOptions: [(label: String, days: Int)] = [
        ("1 day", 1), ("2 days", 2), ("3 days", 3), ("1 week", 7),
    ]

    private var doneWord: String { task.isWatering ? task.wateringMedium.doneWord : "Done" }
    /// Done today: the circle is filled and the row tinted. Reads `clock` so a
    /// row drawn before midnight is drawn again after it.
    private var isDone: Bool { CareSchedule.canUndoDone(task, now: max(clock, .now)) }
    /// The entry this phone's Done made today, the only one hold-to-undo takes back.
    private var undoableLog: CareLog? { isDone ? CareUndoMemory.shared.undoableLog(for: task) : nil }
    private var isCelebrating: Bool { celebrationEnds.map { $0 > .now } ?? false }
    private var status: DueStatus? { CareSchedule.status(of: task) }
    private var isOverdue: Bool {
        if case .overdue = status { return true }
        return false
    }

    var body: some View {
        content
            .swipeActions(edge: .leading) {
                Button(action: onEdit) { Label("Edit", systemImage: "pencil") }
                    .tint(GH.Palette.swipeLeaf)
            }
            .swipeActions(edge: .trailing) {
                Button { choosingSnooze = true } label: { Label("Snooze", systemImage: "moon.zzz") }
                    .tint(GH.Palette.swipeSky)
            }
            // The title follows the plants' medium, which the task doesn't observe:
            // redraw when one of its plants changes (here or from the other phone).
            .onReceive(ContextChanges.publisher(for: task.managedObjectContext)) { note in
                let plants = task.plants ?? []
                if ContextChanges.touches(note, in: task.managedObjectContext, where: { ($0 as? Plant).map(plants.contains) ?? false }) {
                    task.objectWillChange.send()
                }
            }
            .sensoryFeedback(.success, trigger: celebrate)
            .sensoryFeedback(.impact(weight: .light), trigger: undone)
            .task(id: celebrationEnds) {
                guard let end = celebrationEnds else { return }
                try? await Task.sleep(for: .seconds(max(0, end.timeIntervalSinceNow)))
                // A newer Done (or an undo) replaced this one; its own task handles it.
                guard !Task.isCancelled, celebrationEnds == end else { return }
                withAnimation(reduceMotion ? GH.Motion.reduced : GH.Motion.enter) { celebrationEnds = nil }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
                clock = .now
            }
            .confirmationDialog("Snooze \(task.title)", isPresented: $choosingSnooze, titleVisibility: .visible) {
                ForEach(Self.snoozeOptions, id: \.days) { option in
                    Button(option.label) {
                        CareSchedule.snooze(task, days: option.days)
                        saveAndReschedule()
                    }
                }
            }
            .confirmationDialog(snoozeChoice?.title ?? "", isPresented: Binding(
                get: { snoozeChoice != nil },
                set: { if !$0 { snoozeChoice = nil } }
            ), titleVisibility: .visible, presenting: snoozeChoice) { choice in
                Button("Yes, next on \(Lineage.format(choice.keepDue))") { finish(keepNewTiming: true) }
                Button("No, next on \(Lineage.format(choice.originalDue))") { finish(keepNewTiming: false) }
            }
    }

    // MARK: Layouts

    @ViewBuilder private var content: some View {
        switch layout {
        case .card: card
        case .inline: inline
        }
    }

    private var cardInfo: some View {
        HStack(alignment: dynamicTypeSize.isAccessibilitySize ? .top : .center, spacing: GH.Space.s) {
            avatar
            textBlock
        }
        .contentShape(Rectangle())
    }

    private var card: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                // The Done circle drops under the text so the words get the full
                // width. Its word sits inside the same button, so it's one target
                // and VoiceOver reads it once.
                VStack(alignment: .leading, spacing: GH.Space.s) {
                    cardInfo
                    doneButton(showsWord: true)
                }
            } else {
                HStack(spacing: GH.Space.s) {
                    cardInfo
                    doneButton(showsWord: false)
                }
            }
        }
        .padding(.horizontal, GH.Space.s)
        .padding(.vertical, GH.Space.xs + 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 72)
        .background { CareCardBackground(isDone: isDone, isOverdue: isOverdue) }
        .animation(reduceMotion ? GH.Motion.reduced : GH.Motion.press, value: isDone)
    }

    private var inline: some View {
        HStack {
            textBlock
            doneButton(showsWord: false)
        }
        // A finished row tints leafSoft here too. The tint reaches a little past
        // the row so the words don't touch its edge, without moving them.
        .background {
            RoundedRectangle(cornerRadius: GH.Radius.chip, style: .continuous)
                .fill(isDone ? GH.Palette.leafSoft : .clear)
                .padding(.horizontal, -GH.Space.xs)
                .padding(.vertical, -GH.Space.xxs)
        }
        .animation(reduceMotion ? GH.Motion.reduced : GH.Motion.press, value: isDone)
    }

    @ViewBuilder private var avatar: some View {
        let plant = task.activePlants.first
        if let plant, let onOpenPlant {
            Button { onOpenPlant(plant) } label: { CarePlantAvatar(plant: plant) }
                .buttonStyle(.plain)
                .frame(minWidth: 46, minHeight: 46)
                .accessibilityLabel("Open \(plant.displayName)")
        } else {
            CarePlantAvatar(plant: plant)
        }
    }

    private func doneButton(showsWord: Bool) -> some View {
        CareDoneButton(isDone: isDone, canUndo: undoableLog != nil, word: doneWord, showsWord: showsWord,
                       celebrate: celebrate, onDone: tapDone, onUndo: undo)
    }

    private var textBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            Button(action: onEdit) {
                // Words wrap between words, never mid-word, and take as many lines as they need.
                VStack(alignment: .leading, spacing: 2) {
                    // The chevron says the row opens; testers didn't know tapping it edits.
                    (titleIcon
                     + Text(task.title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(isDone ? GH.Palette.leafInk : GH.Palette.ink)
                     + Text("  ")
                     + Text(Image(systemName: "chevron.right"))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(GH.Palette.ink2))
                        // VoiceOver reads the title only, not the chevron ("Forward").
                        .accessibilityLabel(task.title)
                    detailLine
                    if !task.isWatering || layout == .inline {
                        Text(CareSchedule.cadence(count: Int(task.intervalCount), unit: task.unit).capitalizedFirst
                             + (layout == .inline && !task.isWatering && !task.activePlants.isEmpty ? " · " + task.activePlants.map(\.displayName).joined(separator: ", ") : ""))
                            .font(.footnote)
                            .foregroundStyle(GH.Palette.ink2)
                    }
                    if let instructions = task.instructions {
                        Text(instructions)
                            .font(.footnote)
                            .foregroundStyle(GH.Palette.ink)
                            .lineLimit(3)
                    }
                }
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Edits the reminder")
            .accessibilityActions { if layout == .inline { accessibilityMenu } }
            // Separate buttons, outside the edit button: tapping the row still
            // edits; tapping a name opens the plant. A watering row already
            // names its plant (and the photo opens it), so it gets no chip.
            if let onOpenPlant, !task.isWatering, !task.activePlants.isEmpty {
                PlantNameLinks(plants: task.activePlants, onOpen: onOpenPlant)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // The menu lives on the words only, finished or not: on the Done circle
        // it would win the press-and-hold that undoes.
        .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: GH.Radius.chip, style: .continuous))
        .contextMenu { menu }
    }

    /// "Change water" rows lead with their own icon; every other row is as it was.
    private var titleIcon: Text {
        guard task.isWatering, task.wateringMedium != .soil else { return Text("") }
        return Text(Image(systemName: task.wateringMedium.careIcon)).font(.callout.weight(.semibold)).foregroundStyle(GH.Palette.skyInk)
            + Text(" ")
    }

    @ViewBuilder private var detailLine: some View {
        // "Just now · Sam · hold to undo" while it celebrates, then the usual
        // next-due line like any other row.
        if isDone, isCelebrating, let log = undoableLog ?? task.lastLog, let at = log.doneAt {
            Text(CareAgenda.doneLine(doneAt: at, by: log.doneBy, canUndo: undoableLog != nil))
                .font(.footnote)
                .foregroundStyle(GH.Palette.ink)
        } else if let status {
            let usual = CareAgenda.usualDoer(of: task, viewer: myName)
            (Text(status.label + (task.snoozedUntil == nil ? "" : " (snoozed)"))
                .foregroundStyle(status.needsAttention ? GH.Palette.terraInk : GH.Palette.ink2)
             + Text(usual.map { " · usually \($0)" } ?? "").foregroundStyle(GH.Palette.ink2))
                .font(.footnote.weight(status.needsAttention ? .semibold : .regular))
        }
    }

    // MARK: Menu

    @ViewBuilder private var menu: some View {
        Button(action: onEdit) { Label("Edit reminder", systemImage: "pencil") }
        if let onOpenPlant {
            let plants = task.activePlants
            ForEach(plants) { plant in
                Button { onOpenPlant(plant) } label: {
                    Label(plants.count == 1 ? "Open plant" : "Open \(plant.displayName)", systemImage: "leaf")
                }
            }
        }
        Button { choosingSnooze = true } label: { Label("Snooze…", systemImage: "moon.zzz") }
        if task.snoozedUntil != nil {
            Button(action: cancelSnooze) { Label("Cancel snooze", systemImage: "alarm") }
        }
    }

    /// The plant page has no List, so its rows can't swipe: VoiceOver gets the
    /// swipe actions here instead. (On the Care tab the List's swipes already
    /// show up as VoiceOver actions.)
    @ViewBuilder private var accessibilityMenu: some View {
        Button("Edit", action: onEdit)
        Button("Snooze") { choosingSnooze = true }
        if task.snoozedUntil != nil {
            Button("Cancel snooze", action: cancelSnooze)
        }
    }

    // MARK: Actions

    private func tapDone() {
        if let choice = CareSchedule.snoozeChoice(for: task) {
            snoozeChoice = choice
        } else {
            finish(keepNewTiming: true)
        }
    }

    private func finish(keepNewTiming: Bool) {
        onDone?(task)
        // The row tints, the check draws and the rings ripple inside this animation.
        withAnimation(reduceMotion ? GH.Motion.reduced : GH.Motion.press) {
            let log = CareSchedule.markDone(task, by: myName, keepNewTiming: keepNewTiming, household: household, context: context)
            CareUndoMemory.shared.remember(log)
            celebrate += 1
            celebrationEnds = .now.addingTimeInterval(Double(Self.celebration.components.seconds))
        }
        saveAndReschedule()
    }

    private func undo() {
        // Checked again now, not when the row was drawn: past midnight, or once
        // the entry is gone, there's nothing to take back.
        guard let log = CareUndoMemory.shared.undoableLog(for: task) else {
            // Its entry is gone (or it's a new day): drop the stale record.
            CareUndoMemory.shared.forget(task)
            return
        }
        withAnimation(reduceMotion ? GH.Motion.reduced : GH.Motion.press) {
            guard CareSchedule.undoDone(log, context: context) else { return }
            CareUndoMemory.shared.forget(task)
            celebrationEnds = nil
            undone += 1
        }
        saveAndReschedule()
    }

    private func cancelSnooze() {
        task.snoozedUntil = nil
        saveAndReschedule()
    }

    private func saveAndReschedule() {
        Persistence.shared.save(context)
        NotificationPlanner.reschedule()
    }
}
