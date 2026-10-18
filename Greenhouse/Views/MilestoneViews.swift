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
                let photos = Milestones.photos(of: item.milestone)
                if !photos.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(photos.prefix(4)) { photo in
                            PlantPhotoView(photo: photo, maxPixel: 120)
                                .frame(width: 36, height: 36)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        if photos.count > 4 {
                            Text("+\(photos.count - 4)").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.top, 2)
                    .accessibilityLabel(photos.count == 1 ? "1 photo" : "\(photos.count) photos")
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
                        MilestoneSuggestions(title: $title, household: household)
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
            } message: {
                if !(milestone?.photos ?? []).isEmpty {
                    Text("Its photos stay on the plant.")
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

/// "New pot", "Repotted", … as tappable chips that fill in the title.
struct MilestoneSuggestions: View {
    @Binding var title: String
    let household: Household?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Milestones.suggestions(for: household), id: \.self) { suggestion in
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
}

/// What the milestone picker on the photo screens has selected.
enum MilestoneSelection: Hashable {
    case none
    case existing(Milestone)
    case new

    init(_ milestone: Milestone?) {
        self = milestone.map { .existing($0) } ?? .none
    }

    func choice(newTitle: String) -> Milestones.Choice {
        switch self {
        case .none: .none
        case .existing(let milestone): .existing(milestone)
        case .new: .new(title: newTitle)
        }
    }
}

/// Picks which milestone a photo goes with: none, one of the plant's, or a
/// new one that takes the photo's date.
struct MilestonePicker: View {
    let plant: Plant
    @Binding var selection: MilestoneSelection
    @Binding var newTitle: String

    var body: some View {
        Section {
            Picker("Milestone", selection: $selection) {
                Text("None").tag(MilestoneSelection.none)
                ForEach(Milestones.history(for: plant)) { item in
                    Text("\(item.milestone.title ?? "Milestone"), \(item.milestone.date.map(Lineage.format) ?? "")")
                        .tag(MilestoneSelection.existing(item.milestone))
                }
                Text("New milestone…").tag(MilestoneSelection.new)
            }
            if selection == .new {
                TextField("What happened (e.g. First bloom)", text: $newTitle)
                MilestoneSuggestions(title: $newTitle, household: plant.household)
            }
        } footer: {
            if selection == .new {
                Text("The new milestone gets the photo's date.")
            }
        }
    }
}

/// Settings → Milestone quick picks: the household's list of titles offered
/// when adding a milestone. Shared by both phones; editing it never changes
/// milestones already saved.
struct MilestoneOptionsView: View {
    @ObservedObject var household: Household
    @Environment(\.managedObjectContext) private var context
    @State private var newOption = ""
    @State private var renaming: Int?
    @State private var draft = ""

    private var options: [String] { Milestones.suggestions(for: household) }

    var body: some View {
        List {
            Section {
                ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                    Button(option) {
                        draft = option
                        renaming = index
                    }
                    .foregroundStyle(.primary)
                }
                .onDelete { offsets in
                    var list = options
                    list.remove(atOffsets: offsets)
                    save(list)
                }
                .onMove { from, to in
                    var list = options
                    list.move(fromOffsets: from, toOffset: to)
                    save(list)
                }
                HStack {
                    TextField("Add a quick pick", text: $newOption)
                        .onSubmit(add)
                    Button("Add", action: add)
                        .disabled(newOption.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } footer: {
                Text("These fill in a milestone's title when you tap them. Changing the list only affects new milestones; saved ones keep their titles. Both phones share it.")
            }
            Section {
                Button("Reset to the original list") { save(Milestones.defaultSuggestions) }
                    .disabled(household.milestoneSuggestions == nil)
            }
        }
        .navigationTitle("Milestone quick picks")
        .toolbar { EditButton() }
        .alert("Rename quick pick", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Title", text: $draft)
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                if let renaming, options.indices.contains(renaming) {
                    var list = options
                    list[renaming] = draft
                    save(list)
                }
            }
        }
    }

    private func add() {
        let trimmed = newOption.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        save(options + [trimmed])
        newOption = ""
    }

    private func save(_ list: [String]) {
        Milestones.setSuggestions(list, for: household)
        Persistence.shared.save(context)
    }
}
