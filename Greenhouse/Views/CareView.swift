import CoreData
import SwiftUI

/// Every care task in the household, soonest first.
struct CareView: View {
    @ObservedObject var household: Household
    @AppStorage(Collections.selectedKey) private var selectedCollection = ""
    @FetchRequest private var tasks: FetchedResults<CareTask>
    @State private var showingNew = false
    @State private var editing: CareTask?

    init(household: Household) {
        self.household = household
        let request = NSFetchRequest<CareTask>(entityName: "CareTask")
        request.predicate = NSPredicate(format: "household == %@ AND isArchived == NO", household)
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
        _tasks = FetchRequest(fetchRequest: request)
    }

    private var sorted: [CareTask] {
        let collection = Collections.find(selectedCollection, in: household)
        return tasks.filter { $0.isRelevant && Collections.contains(collection, $0) }.sorted {
            (CareSchedule.nextDue(for: $0) ?? .distantFuture) < (CareSchedule.nextDue(for: $1) ?? .distantFuture)
        }
    }

    var body: some View {
        NavigationStack {
            let due = sorted.filter { CareSchedule.status(of: $0)?.needsAttention == true }
            let later = sorted.filter { CareSchedule.status(of: $0)?.needsAttention != true }
            List {
                CollectionBar(household: household)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                if !due.isEmpty {
                    Section("Due now") {
                        ForEach(due) { TaskRow(task: $0, household: household, onEdit: edit($0)) }
                    }
                }
                if !later.isEmpty {
                    Section("Coming up") {
                        ForEach(later) { TaskRow(task: $0, household: household, onEdit: edit($0)) }
                    }
                }
            }
            .overlay {
                if sorted.isEmpty {
                    ContentUnavailableView("Nothing scheduled", systemImage: "drop", description: Text("Plants get a watering schedule when you add them. Tap + for other reminders, like a quarterly treatment."))
                }
            }
            .navigationTitle("Care")
            .navigationDestination(for: Plant.self) { PlantDetailView(plant: $0, household: household) }
            .navigationDestination(for: Project.self) { ProjectDetailView(project: $0, household: household) }
            .toolbar {
                Button { showingNew = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Add care reminder")
            }
            .sheet(isPresented: $showingNew) { TaskEditorView(household: household, task: nil, preselected: []) }
            .sheet(item: $editing) { TaskEditorView(household: household, task: $0, preselected: []) }
        }
    }

    private func edit(_ task: CareTask) -> () -> Void {
        { editing = task }
    }
}

/// Create or edit a recurring reminder: a name, an interval, and the plants it
/// covers (none means the whole household).
struct TaskEditorView: View {
    let household: Household
    let task: CareTask?
    let preselected: [Plant]
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    @FetchRequest private var plants: FetchedResults<Plant>

    @State private var name = ""
    @State private var count = 1
    @State private var unit: IntervalUnit = .month
    @State private var firstDue = Date()
    @State private var selected: Set<NSManagedObjectID> = []
    @State private var confirmingDelete = false
    @FocusState private var nameFocused: Bool

    /// Common ones, so the usual cases are two taps.
    private static let presets: [(String, Int, IntervalUnit)] = [
        ("Hydrogen peroxide treatment", 3, .month),
        ("Fertilize", 1, .month),
        ("Rotate pot", 1, .week),
        ("Check for pests", 2, .week),
        ("Clean grow lights", 1, .month),
    ]

    init(household: Household, task: CareTask?, preselected: [Plant]) {
        self.household = household
        self.task = task
        self.preselected = preselected
        let request = NSFetchRequest<Plant>(entityName: "Plant")
        request.predicate = NSPredicate(format: "household == %@ AND status == %@", household, PlantStatus.active.rawValue)
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
        _plants = FetchRequest(fetchRequest: request)
    }

    private var isWatering: Bool { task?.isWatering == true }

    var body: some View {
        NavigationStack {
            Form {
                if !isWatering {
                    Section {
                        TextField("What (e.g. Hydrogen peroxide treatment)", text: $name)
                            .focused($nameFocused)
                        if task == nil {
                            Menu("Suggestions") {
                                ForEach(Self.presets, id: \.0) { preset in
                                    Button("\(preset.0) · \(CareSchedule.cadence(count: preset.1, unit: preset.2))") {
                                        name = preset.0
                                        count = preset.1
                                        unit = preset.2
                                    }
                                }
                            }
                        }
                    }
                }
                Section {
                    Stepper("Every \(count)", value: $count, in: 1...365)
                    Picker("Unit", selection: $unit) {
                        ForEach(IntervalUnit.allCases) { Text($0.label(count: count).capitalizedFirst).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    if task == nil {
                        DatePicker("First due", selection: $firstDue, displayedComponents: .date)
                    }
                } header: {
                    Text("Repeats")
                } footer: {
                    Text(CareSchedule.cadence(count: count, unit: unit).capitalizedFirst)
                }
                if !isWatering {
                    Section {
                        ForEach(plants) { plant in
                            Button {
                                if selected.contains(plant.objectID) { selected.remove(plant.objectID) } else { selected.insert(plant.objectID) }
                            } label: {
                                HStack {
                                    Text(plant.displayName).foregroundStyle(.primary)
                                    Spacer()
                                    if selected.contains(plant.objectID) {
                                        Image(systemName: "checkmark").foregroundStyle(.tint)
                                    }
                                }
                            }
                        }
                    } header: {
                        Text("For")
                    } footer: {
                        Text(selected.isEmpty ? "No plants picked: it's a household-wide reminder." : "\(selected.count) plant\(selected.count == 1 ? "" : "s")")
                    }
                }
                if let task, !isWatering {
                    Section {
                        Button("Delete reminder", role: .destructive) { confirmingDelete = true }
                    }
                    .confirmationDialog("Delete \(task.name ?? "this reminder")?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                        Button("Delete", role: .destructive) {
                            context.delete(task)
                            Persistence.shared.save(context)
                            NotificationPlanner.reschedule()
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(task == nil ? "New reminder" : (isWatering ? "Watering" : "Edit reminder"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(!isWatering && name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        if let task {
            name = task.name ?? ""
            count = Int(task.intervalCount)
            unit = task.unit
            selected = Set((task.plants ?? []).map(\.objectID))
        } else {
            selected = Set(preselected.map(\.objectID))
            // A new reminder starts with its name, so open the keyboard there.
            nameFocused = true
        }
    }

    private func save() {
        let chosen = plants.filter { selected.contains($0.objectID) }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if let task {
            if !isWatering {
                task.name = trimmed
                let targets = task.mutableSetValue(forKey: "plants")
                targets.removeAllObjects()
                targets.addObjects(from: chosen)
            }
            task.intervalCount = Int64(count)
            task.unit = unit
        } else {
            CareSchedule.makeTask(name: trimmed, count: count, unit: unit, firstDue: firstDue,
                                  plants: chosen, household: household, context: context)
        }
        Persistence.shared.save(context)
        NotificationPlanner.reschedule()
        dismiss()
    }
}
