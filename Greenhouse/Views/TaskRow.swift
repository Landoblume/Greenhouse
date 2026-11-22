import CoreData
import SwiftUI

/// One care reminder. On the Care tab (`.card`) it's a card with the plant's
/// photo; on a plant's own page (`.inline`, the default) it's a plain list row.
struct TaskRow: View {
    enum Layout { case inline, card }

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

    private static let snoozeOptions: [(label: String, days: Int)] = [
        ("1 day", 1), ("2 days", 2), ("3 days", 3), ("1 week", 7),
    ]

    private var doneWord: String { task.isWatering ? "Watered" : "Done" }
    private var isDone: Bool { CareSchedule.canUndoDone(task) }
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
            .contextMenu { menu }
            .sensoryFeedback(.success, trigger: celebrate)
            .sensoryFeedback(.impact(weight: .light), trigger: undone)
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

    private var card: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                // The Done circle drops under the text so the words get the full width.
                VStack(alignment: .leading, spacing: GH.Space.s) {
                    HStack(alignment: .top, spacing: GH.Space.s) {
                        avatar
                        textBlock
                    }
                    HStack(spacing: GH.Space.s) {
                        doneButton
                        Text(isDone ? doneWord : "Mark \(doneWord.lowercased())")
                            .font(.ghRounded(.body, weight: .bold))
                            .foregroundStyle(isDone ? GH.Palette.leafInk : GH.Palette.ink)
                    }
                }
            } else {
                HStack(spacing: GH.Space.s) {
                    avatar
                    textBlock
                    doneButton
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
            doneButton
        }
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

    private var doneButton: some View {
        CareDoneButton(isDone: isDone, word: doneWord, celebrate: celebrate, onDone: tapDone, onUndo: undo)
    }

    private var textBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            Button(action: onEdit) {
                // Words wrap between words, never mid-word, and take as many lines as they need.
                VStack(alignment: .leading, spacing: 2) {
                    Text(task.title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(isDone ? GH.Palette.leafInk : GH.Palette.ink)
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
            // Separate buttons, outside the edit button: tapping the row still
            // edits; tapping a name opens the plant. A watering row already
            // names its plant (and the photo opens it), so it gets no chip.
            if let onOpenPlant, !task.isWatering, !task.activePlants.isEmpty {
                PlantNameLinks(plants: task.activePlants, onOpen: onOpenPlant)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var detailLine: some View {
        if isDone, let log = task.lastLog, let at = log.doneAt {
            Text(CareAgenda.doneLine(doneAt: at, by: log.doneBy))
                .font(.footnote)
                .foregroundStyle(GH.Palette.ink)
        } else if let status {
            let usual = CareAgenda.usualDoer(of: task)
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
            Button {
                task.snoozedUntil = nil
                saveAndReschedule()
            } label: {
                Label("Cancel snooze", systemImage: "alarm")
            }
        }
        if CareSchedule.canUndoDone(task) {
            Button(action: undo) { Label("Undo \(doneWord)", systemImage: "arrow.uturn.backward") }
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
            CareSchedule.markDone(task, by: myName, keepNewTiming: keepNewTiming, household: household, context: context)
            celebrate += 1
        }
        saveAndReschedule()
    }

    private func undo() {
        withAnimation(reduceMotion ? GH.Motion.reduced : GH.Motion.press) {
            CareSchedule.undoDone(task, context: context)
            undone += 1
        }
        saveAndReschedule()
    }

    private func saveAndReschedule() {
        Persistence.shared.save(context)
        NotificationPlanner.reschedule()
    }
}
