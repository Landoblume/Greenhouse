import CoreData
import SwiftUI

struct TaskRow: View {
    @ObservedObject var task: CareTask
    let household: Household
    var onEdit: () -> Void = {}
    /// Set where the row isn't already on the plant's own page (the Care tab):
    /// the plant names under the reminder open that plant.
    var onOpenPlant: ((Plant) -> Void)? = nil
    @Environment(\.managedObjectContext) private var context
    @AppStorage(SettingsKey.myName) private var myName = ""
    @State private var choosingSnooze = false
    @State private var snoozeChoice: CareSchedule.SnoozeChoice?

    private static let snoozeOptions: [(label: String, days: Int)] = [
        ("1 day", 1), ("2 days", 2), ("3 days", 3), ("1 week", 7),
    ]

    private var doneWord: String { task.isWatering ? "Watered" : "Done" }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Button(action: onEdit) {
                    VStack(alignment: .leading, spacing: 4) {
                        // The chevron says the row opens; testers didn't know
                        // tapping it edits the schedule.
                        HStack(spacing: 4) {
                            Text(task.title).foregroundStyle(GH.Palette.ink)
                            Image(systemName: "chevron.right")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        Text(CareSchedule.cadence(count: Int(task.intervalCount), unit: task.unit).capitalizedFirst
                             + (task.isWatering || task.activePlants.isEmpty || onOpenPlant != nil ? "" : " · " + task.activePlants.map(\.displayName).joined(separator: ", ")))
                            .font(.caption)
                            .foregroundStyle(GH.Palette.ink2)
                        if let instructions = task.instructions {
                            Text(instructions)
                                .font(.caption)
                                .foregroundStyle(GH.Palette.ink)
                                .lineLimit(3)
                        }
                        DueBadge(task: task)
                    }
                }
                .buttonStyle(.plain)
                // Separate buttons, outside the edit button: tapping the row
                // still edits; tapping a name opens the plant.
                if let onOpenPlant, !task.activePlants.isEmpty {
                    PlantNameLinks(plants: task.activePlants, onOpen: onOpenPlant)
                }
            }
            Spacer()
            Button {
                if let choice = CareSchedule.snoozeChoice(for: task) {
                    snoozeChoice = choice
                } else {
                    finish(keepNewTiming: true)
                }
            } label: {
                Text(doneWord)
            }
            .buttonStyle(.ghProminent)
            .controlSize(.small)
        }
        .swipeActions(edge: .leading) {
            Button(action: onEdit) { Label("Edit", systemImage: "pencil") }
                .tint(GH.Palette.leaf)
        }
        .swipeActions(edge: .trailing) {
            Button { choosingSnooze = true } label: { Label("Snooze", systemImage: "moon.zzz") }
                .tint(GH.Palette.sky)
        }
        .contextMenu {
            Button(action: onEdit) { Label("Edit reminder", systemImage: "pencil") }
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
                Button {
                    CareSchedule.undoDone(task, context: context)
                    saveAndReschedule()
                } label: {
                    Label("Undo \(doneWord)", systemImage: "arrow.uturn.backward")
                }
            }
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

    private func finish(keepNewTiming: Bool) {
        CareSchedule.markDone(task, by: myName, keepNewTiming: keepNewTiming, household: household, context: context)
        saveAndReschedule()
    }

    private func saveAndReschedule() {
        Persistence.shared.save(context)
        NotificationPlanner.reschedule()
    }
}

/// Plant names under a reminder, each a button that opens that plant. Wraps
/// onto more lines when a reminder covers many plants.
struct PlantNameLinks: View {
    let plants: [Plant]
    let onOpen: (Plant) -> Void

    var body: some View {
        WrappingLayout(spacing: 12, lineSpacing: 4) {
            ForEach(plants) { plant in
                Button { onOpen(plant) } label: {
                    HStack(spacing: 2) {
                        Text(plant.displayName)
                        Image(systemName: "chevron.right").font(.system(size: 8, weight: .bold))
                    }
                    .font(.caption)
                }
                .buttonStyle(.borderless)
                .accessibilityHint("Opens the plant")
            }
        }
    }
}

/// Lays children out left to right, starting a new line when one won't fit.
struct WrappingLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(width: proposal.width ?? .infinity, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(width: bounds.width, subviews: subviews)
        for (subview, origin) in zip(subviews, result.origins) {
            subview.place(at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y), proposal: .unspecified)
        }
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> (size: CGSize, origins: [CGPoint]) {
        var origins: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        var widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            origins.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
            widest = max(widest, x - spacing)
        }
        return (CGSize(width: widest, height: y + lineHeight), origins)
    }
}
