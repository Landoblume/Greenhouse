import SwiftUI

/// One milestone in a plant's History: date, title, note, and where it came
/// from if it was written on an original this plant was combined or split from.
struct MilestoneRow: View {
    let item: Milestones.Item
    let viewedPlant: Plant

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Image(systemName: "flag.fill")
                .font(.caption)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.milestone.title ?? "Milestone")
                if let notes = item.milestone.notes {
                    Text(notes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if item.source != viewedPlant {
                    Text("From \(item.source.displayName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(item.milestone.date.map(Lineage.format) ?? "")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

/// Add a milestone, or edit or delete one.
struct MilestoneEditorView: View {
    let plant: Plant
    let household: Household
    let milestone: Milestone?
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKey.myName) private var myName = ""
    @State private var title: String
    @State private var date: Date
    @State private var notes: String
    @State private var confirmingDelete = false

    // Starting values are set here rather than in onAppear so the date picker
    // never shows a stale date (see EditPhotoSheet).
    init(plant: Plant, household: Household, milestone: Milestone?) {
        self.plant = plant
        self.household = household
        self.milestone = milestone
        _title = State(initialValue: milestone?.title ?? "")
        _date = State(initialValue: milestone?.date ?? Date())
        _notes = State(initialValue: milestone?.notes ?? "")
    }

    private var trimmedTitle: String { title.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("What happened (e.g. New pot)", text: $title)
                    if milestone == nil {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(Milestones.suggestions, id: \.self) { suggestion in
                                    Button(suggestion) { title = suggestion }
                                        .font(.subheadline)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(title == suggestion ? Color.accentColor : Color(.tertiarySystemFill), in: Capsule())
                                        .foregroundStyle(title == suggestion ? Color.white : Color.primary)
                                        .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    DatePicker("Date", selection: $date, in: ...Date(), displayedComponents: .date)
                    TextField("Note (optional, e.g. where the pot's from)", text: $notes, axis: .vertical)
                } footer: {
                    if let by = milestone?.addedBy {
                        Text("Added by \(by)")
                    }
                }
                if milestone != nil {
                    Section {
                        Button("Delete milestone", role: .destructive) { confirmingDelete = true }
                    }
                }
            }
            .navigationTitle(milestone == nil ? "New milestone" : "Edit milestone")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(trimmedTitle.isEmpty)
                }
            }
            .confirmationDialog("Delete this milestone?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if let milestone { context.delete(milestone) }
                    Persistence.shared.save(context)
                    dismiss()
                }
            }
        }
    }

    private func save() {
        if let milestone {
            Milestones.update(milestone, title: trimmedTitle, date: date, notes: notes)
        } else {
            Milestones.add(title: trimmedTitle, date: date, notes: notes, by: myName, to: plant,
                           household: household, context: context)
        }
        Persistence.shared.save(context)
        dismiss()
    }
}
