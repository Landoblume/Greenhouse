import SwiftUI

/// "2 of 5 steps · $40 of $120 spent" under a project's title.
struct ProjectSummary: View {
    @ObservedObject var project: Project

    var body: some View {
        let parts = Self.parts(for: project)
        if !parts.isEmpty {
            Text(parts.joined(separator: " · "))
        }
    }

    static func parts(for project: Project) -> [String] {
        var parts: [String] = []
        let progress = Plans.stepProgress(of: project)
        if progress.total > 0 { parts.append("\(progress.done) of \(progress.total) steps") }
        let spent = Plans.spent(on: project)
        if project.budget > 0 {
            parts.append("\(money(spent)) of \(money(project.budget)) spent")
        } else if Plans.estimatedCost(of: project) > 0 {
            parts.append("\(money(spent)) spent")
        }
        return parts
    }

    static func money(_ amount: Double) -> String {
        amount.formatted(.currency(code: Plans.currencyCode).precision(.fractionLength(amount.rounded() == amount ? 0 : 2)))
    }
}

/// Everything about one project: where it stands, its plants, steps,
/// supplies and costs, and notes.
struct ProjectDetailView: View {
    @ObservedObject var project: Project
    let household: Household
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var editing = false
    @State private var newStep = ""
    @State private var newSupply = ""
    @State private var newSupplyCost: Double?
    @State private var notes: String
    @FocusState private var notesFocused: Bool

    init(project: Project, household: Household) {
        _project = ObservedObject(wrappedValue: project)
        self.household = household
        _notes = State(initialValue: project.notes ?? "")
    }

    var body: some View {
        List {
            Section {
                Picker("State", selection: Binding(
                    get: { Plans.state(of: project) },
                    set: {
                        Plans.setState(project, $0)
                        Persistence.shared.save(context)
                    }
                )) {
                    ForEach(ProjectState.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                if let started = project.startedAt {
                    LabeledContent("Started", value: Lineage.format(started))
                }
                if let target = project.targetDate {
                    LabeledContent("Target", value: Lineage.format(target))
                }
                if let done = project.doneAt, project.isDone {
                    LabeledContent("Finished", value: Lineage.format(done))
                }
                if let place = project.place {
                    LabeledContent("Where", value: place)
                }
                if let link = project.link, let url = URL(string: link.contains("://") ? link : "https://\(link)") {
                    Link(destination: url) {
                        Label(url.host() ?? link, systemImage: "link")
                    }
                }
                if let collection = project.collection?.name {
                    LabeledContent("Collection", value: collection)
                }
            }

            let plants = (project.plants ?? []).filter(\.isActive).sorted { $0.displayName < $1.displayName }
            if !plants.isEmpty {
                Section("Plants") {
                    ForEach(plants) { plant in
                        NavigationLink(value: plant) {
                            HStack {
                                PlantPhotoView(photo: PlantPhotos.cover(for: plant), maxPixel: 120)
                                    .frame(width: 36, height: 36)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                Text(plant.displayName)
                            }
                        }
                    }
                }
            }

            Section {
                ForEach(Plans.items(.step, of: project)) { step in
                    ItemRow(item: step)
                }
                .onDelete { delete(Plans.items(.step, of: project), at: $0) }
                HStack {
                    TextField("Add a step", text: $newStep)
                        .onSubmit(addStep)
                    Button("Add", action: addStep)
                        .disabled(newStep.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } header: {
                let progress = Plans.stepProgress(of: project)
                Text(progress.total > 0 ? "Steps (\(progress.done) of \(progress.total) done)" : "Steps")
            }

            Section {
                ForEach(Plans.items(.supply, of: project)) { supply in
                    ItemRow(item: supply)
                }
                .onDelete { delete(Plans.items(.supply, of: project), at: $0) }
                HStack {
                    TextField("Add a supply", text: $newSupply)
                        .onSubmit(addSupply)
                    TextField("Cost", value: $newSupplyCost, format: .currency(code: Plans.currencyCode))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 90)
                    Button("Add", action: addSupply)
                        .disabled(newSupply.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } header: {
                Text("Supplies")
            } footer: {
                costFooter
            }

            Section("Notes") {
                TextField("Ideas, measurements, colors, what worked…", text: $notes, axis: .vertical)
                    .lineLimit(4...)
                    .focused($notesFocused)
            }
        }
        .navigationTitle(project.title ?? "Project")
        .toolbar {
            ToolbarItem(placement: .primaryAction) { Button("Edit") { editing = true } }
            if notesFocused {
                ToolbarItem(placement: .keyboard) { Button("Done") { notesFocused = false } }
            }
        }
        .onChange(of: notesFocused) { _, focused in if !focused { saveNotes() } }
        .onDisappear(perform: saveNotes)
        .onChange(of: project.notes) { _, saved in
            // Edited in the editor sheet or on the other phone.
            if !notesFocused { notes = saved ?? "" }
        }
        .sheet(isPresented: $editing, onDismiss: {
            // Deleted from the editor: nothing left to show.
            if project.isDeleted || project.managedObjectContext == nil { dismiss() }
        }) {
            ProjectEditorView(household: household, project: project)
        }
    }

    @ViewBuilder private var costFooter: some View {
        let estimated = Plans.estimatedCost(of: project)
        let spent = Plans.spent(on: project)
        if estimated > 0 || project.budget > 0 {
            VStack(alignment: .leading, spacing: 2) {
                Text("Supplies add up to \(ProjectSummary.money(estimated)); \(ProjectSummary.money(spent)) bought so far.")
                if project.budget > 0 {
                    let left = project.budget - estimated
                    Text(left >= 0
                         ? "Budget \(ProjectSummary.money(project.budget)): \(ProjectSummary.money(left)) to spare."
                         : "Budget \(ProjectSummary.money(project.budget)): \(ProjectSummary.money(-left)) over.")
                        .foregroundStyle(left >= 0 ? Color.secondary : Color.orange)
                }
            }
        } else {
            Text("Tick a supply once it's bought.")
        }
    }

    private func addStep() {
        Plans.addItem(.step, title: newStep, to: project, household: household, context: context)
        Persistence.shared.save(context)
        newStep = ""
    }

    private func addSupply() {
        Plans.addItem(.supply, title: newSupply, cost: newSupplyCost ?? 0, to: project, household: household, context: context)
        Persistence.shared.save(context)
        newSupply = ""
        newSupplyCost = nil
    }

    private func delete(_ items: [ProjectItem], at offsets: IndexSet) {
        offsets.map { items[$0] }.forEach(context.delete)
        Persistence.shared.save(context)
    }

    private func saveNotes() {
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = trimmed.isEmpty ? nil : trimmed
        guard project.managedObjectContext != nil, value != project.notes else { return }
        project.notes = value
        Persistence.shared.save(context)
    }
}

/// A step or supply: tap the circle to tick it off.
private struct ItemRow: View {
    @ObservedObject var item: ProjectItem
    @Environment(\.managedObjectContext) private var context

    var body: some View {
        HStack {
            Button {
                item.isDone.toggle()
                Persistence.shared.save(context)
            } label: {
                Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(item.isDone ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.isDone ? "Mark not done" : (item.kindValue == .supply ? "Mark bought" : "Mark done"))
            Text(item.title ?? "")
                .strikethrough(item.isDone)
                .foregroundStyle(item.isDone ? .secondary : .primary)
            Spacer()
            if item.kindValue == .supply, item.cost > 0 {
                Text(ProjectSummary.money(item.cost))
                    .foregroundStyle(.secondary)
            }
        }
    }
}
