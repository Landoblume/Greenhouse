import CoreData
import SwiftUI

struct PlantDetailView: View {
    @ObservedObject var plant: Plant
    let household: Household
    @Environment(\.managedObjectContext) private var context
    @AppStorage(SettingsKey.myName) private var myName = ""
    @State private var showingAddPhoto = false
    @State private var showingCombine = false
    @State private var showingCutting = false
    @State private var showingEdit = false
    @State private var showingNewTask = false
    @State private var editingTask: CareTask?
    @State private var addingMilestone = false
    @State private var editingMilestone: Milestone?

    private var timeline: [Lineage.TimelinePhoto] { Lineage.timeline(for: plant) }

    var body: some View {
        List {
            Section {
                PlantPhotoView(photo: PlantPhotos.cover(for: plant), maxPixel: 1200)
                    .frame(height: 260)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .listRowInsets(EdgeInsets())
                if let latin = plant.scientificName {
                    LabeledContent("Species") { Text(latin).italic() }
                }
                LabeledContent("Lives", value: plant.settingValue.label)
                if let location = plant.location {
                    LabeledContent("Where", value: location)
                }
                LabeledContent("Light") {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(plant.lightSourceValue?.label ?? "Not set")
                        if let species = plant.species {
                            Text("Likes: \(species.light.lowercased())")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                if plant.isActive {
                    NavigationLink {
                        LightMeterView(plant: plant)
                    } label: {
                        Label("Measure the light here", systemImage: "light.max")
                    }
                }
                if !(plant.collections ?? []).isEmpty {
                    LabeledContent("Collections", value: (plant.collections ?? []).compactMap(\.name).sorted().joined(separator: ", "))
                }
                if let since = Lineage.effectiveAcquiredDate(of: plant) {
                    LabeledContent("Had since", value: "\(Lineage.format(since)) (\(Self.age(since: since)))")
                }
            }

            if !plant.isActive {
                Section {
                    Label("This plant is retired: it was \(plant.statusValue == .stapled ? "combined into another" : "split into new plants"). See History below.", systemImage: "archivebox")
                        .font(.callout)
                }
            }

            PlantNotesSection(plant: plant)

            ZoneSection(plant: plant, household: household)

            if plant.isActive {
                CollapsibleSection("Care", summary: "\(plant.activeTasks.count)") {
                    ForEach(plant.activeTasks) { task in
                        TaskRow(task: task, household: household) { editingTask = task }
                    }
                    Button { showingNewTask = true } label: {
                        Label("Add a care reminder", systemImage: "plus")
                    }
                }
            }

            let projects = Plans.sorted(Array(plant.projects ?? []))
            if !projects.isEmpty {
                CollapsibleSection("Projects", summary: "\(projects.count)") {
                    ForEach(projects) { ProjectRow(project: $0, household: household) }
                }
            }

            CollapsibleSection("Photos", summary: "\(timeline.count)") {
                if plant.isActive {
                    Button { showingAddPhoto = true } label: { Label("Add photo", systemImage: "camera") }
                }
                if timeline.count >= 2 {
                    NavigationLink {
                        ThenNowView(plant: plant)
                    } label: {
                        Label("Then vs now", systemImage: "rectangle.split.2x1")
                    }
                }
                ForEach(timeline) { item in
                    NavigationLink {
                        PhotoDetailView(photo: item.photo, plant: plant)
                    } label: {
                        HStack {
                            PlantPhotoView(photo: item.photo, maxPixel: 160)
                                .frame(width: 56, height: 56)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            VStack(alignment: .leading) {
                                HStack(spacing: 4) {
                                    Text(item.photo.takenAt.map(Lineage.format) ?? "Unknown date")
                                    if PlantPhotos.isCover(item.photo, of: plant) {
                                        Image(systemName: "star.fill")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .accessibilityLabel("Main photo")
                                    }
                                }
                                if let milestone = item.photo.milestone {
                                    Label(milestone.title ?? "Milestone", systemImage: "flag.fill")
                                        .font(.caption)
                                        .foregroundStyle(.tint)
                                }
                                if let caption = item.photo.caption {
                                    Text(caption)
                                        .font(.caption)
                                        .lineLimit(2)
                                }
                                if item.source != plant {
                                    Text("From \(item.source.displayName) (acq. \(item.source.acquiredDate.map(Lineage.format) ?? "?"))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }

            CollapsibleSection("History") {
                ForEach(Milestones.history(for: plant)) { item in
                    Button { editingMilestone = item.milestone } label: {
                        MilestoneRow(item: item, viewedPlant: plant)
                    }
                    .foregroundStyle(.primary)
                }
                if plant.isActive {
                    Button { addingMilestone = true } label: {
                        Label("Add milestone", systemImage: "flag")
                    }
                }
                ForEach(Lineage.history(of: plant)) { line in
                    Group {
                        if let other = line.plant {
                            NavigationLink(value: other) { Text(line.text) }
                        } else {
                            Text(line.text)
                        }
                    }
                    .padding(.leading, CGFloat(line.depth) * 16)
                    .swipeActions {
                        if let cutting = line.unlinks {
                            Button("Unlink", role: .destructive) {
                                Lineage.setCuttingParent(of: cutting, to: nil)
                                Persistence.shared.save(context)
                            }
                        }
                    }
                }
            }

            if plant.isActive {
                Section {
                    Button { showingCombine = true } label: {
                        Label("Combine with other plants…", systemImage: "arrow.triangle.merge")
                    }
                    Button { showingCutting = true } label: {
                        Label("Take a cutting…", systemImage: "scissors")
                    }
                }
            }
        }
        .navigationTitle(plant.displayName)
        .toolbar {
            if plant.isActive {
                Button("Edit") { showingEdit = true }
            }
        }
        .sheet(isPresented: $showingAddPhoto) { AddPhotoSheet(plant: plant, household: household) }
        .sheet(isPresented: $showingCombine) { CombineSheet(plant: plant, household: household) }
        .sheet(isPresented: $showingCutting) { CuttingSheet(plant: plant, household: household) }
        .sheet(isPresented: $addingMilestone) { MilestoneEditorView(plant: plant, household: household, milestone: nil) }
        .sheet(item: $editingMilestone) { MilestoneEditorView(plant: plant, household: household, milestone: $0) }
        .sheet(isPresented: $showingEdit) { EditPlantView(plant: plant) }
        .sheet(isPresented: $showingNewTask) { TaskEditorView(household: household, task: nil, preselected: [plant]) }
        .sheet(item: $editingTask) { TaskEditorView(household: household, task: $0, preselected: []) }
        .redrawsOnRelatedChanges(plant)
    }

    static func age(since date: Date, now: Date = .now) -> String {
        let months = Calendar.current.dateComponents([.month], from: date, to: now).month ?? 0
        if months < 1 { return "under a month" }
        if months < 24 { return months == 1 ? "1 month" : "\(months) months" }
        let years = months / 12
        let rest = months % 12
        return rest == 0 ? "\(years) years" : "\(years) yr \(rest) mo"
    }
}

struct ZoneSection: View {
    @ObservedObject var plant: Plant
    @ObservedObject var household: Household

    var body: some View {
        let advice = Hardiness.advice(setting: plant.settingValue, zone: household.hardinessZone, species: plant.species)
        if advice != .none {
            CollapsibleSection("Grow zone") {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(advice.message)
                        if let detail = advice.detail {
                            Text(detail).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                } icon: {
                    Image(systemName: advice.isWarning ? "snowflake" : "thermometer.sun")
                        .foregroundStyle(advice.isWarning ? .orange : .green)
                }
                if let species = plant.species {
                    LabeledContent("Light", value: species.light)
                    LabeledContent("Frost", value: species.frost)
                    Group {
                        if species.verified == true, let source = species.source, let url = URL(string: source) {
                            Link("Zones from \(species.sourceHost ?? "source")", destination: url)
                        } else {
                            Text("Zone range not yet checked against a reference.")
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct TaskRow: View {
    @ObservedObject var task: CareTask
    let household: Household
    var onEdit: () -> Void = {}
    @Environment(\.managedObjectContext) private var context
    @AppStorage(SettingsKey.myName) private var myName = ""

    var body: some View {
        HStack {
            Button(action: onEdit) {
                VStack(alignment: .leading, spacing: 4) {
                    // The chevron says the row opens; testers didn't know
                    // tapping it edits the schedule.
                    HStack(spacing: 4) {
                        Text(task.title).foregroundStyle(.primary)
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    Text(CareSchedule.cadence(count: Int(task.intervalCount), unit: task.unit).capitalizedFirst
                         + (task.isWatering || task.activePlants.isEmpty ? "" : " · " + task.activePlants.map(\.displayName).joined(separator: ", ")))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    DueBadge(task: task)
                }
            }
            .buttonStyle(.plain)
            Spacer()
            Button {
                CareSchedule.markDone(task, by: myName, household: household, context: context)
                Persistence.shared.save(context)
                NotificationPlanner.reschedule()
            } label: {
                Text(task.isWatering ? "Watered" : "Done")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .swipeActions(edge: .leading) {
            Button(action: onEdit) { Label("Edit", systemImage: "pencil") }
                .tint(.accentColor)
        }
        .contextMenu {
            Button(action: onEdit) { Label("Edit reminder", systemImage: "pencil") }
        }
    }
}

/// Notes typed right on the plant's page; saved when you leave the field.
struct PlantNotesSection: View {
    @ObservedObject var plant: Plant
    @Environment(\.managedObjectContext) private var context
    @State private var notes: String
    @FocusState private var focused: Bool

    init(plant: Plant) {
        _plant = ObservedObject(wrappedValue: plant)
        _notes = State(initialValue: plant.notes ?? "")
    }

    // The modifiers go on the field, not the section: a List section applies
    // its modifiers to the header and the row separately, which added the
    // keyboard's Done button twice.
    var body: some View {
        CollapsibleSection("Notes") {
            TextField("Anything worth remembering: quirks, where it came from, what it likes…", text: $notes, axis: .vertical)
                .lineLimit(2...)
                .focused($focused)
                .onChange(of: focused) { _, isFocused in if !isFocused { save() } }
                .onDisappear(perform: save)
                .onChange(of: plant.notes) { _, saved in
                    // Changed on the other phone.
                    if !focused { notes = saved ?? "" }
                }
                .toolbar {
                    if focused {
                        ToolbarItem(placement: .keyboard) { Button("Done") { focused = false } }
                    }
                }
        }
    }

    private func save() {
        let value = PlantFactory.cleanNotes(notes)
        guard plant.managedObjectContext != nil, value != plant.notes else { return }
        plant.notes = value
        Persistence.shared.save(context)
    }
}

extension View {
    /// A plant view only watches the plant itself, so editing one of its photos,
    /// milestones or projects (a new date, a fixed note, a project started,
    /// here or on the other phone) wouldn't redraw it. This redraws it whenever
    /// any of those change, which also re-sorts the timeline and History.
    func redrawsOnRelatedChanges(_ plant: Plant) -> some View {
        onReceive(NotificationCenter.default.publisher(for: .NSManagedObjectContextObjectsDidChange)) { note in
            let keys = [NSInsertedObjectsKey, NSUpdatedObjectsKey, NSDeletedObjectsKey, NSRefreshedObjectsKey]
            let changed = keys.contains { key in
                (note.userInfo?[key] as? Set<NSManagedObject>)?.contains { $0 is Photo || $0 is Milestone || $0 is Project } ?? false
            }
            if changed { plant.objectWillChange.send() }
        }
    }
}

extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
