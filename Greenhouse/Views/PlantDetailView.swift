import CoreData
import SwiftUI

struct PlantDetailView: View {
    @ObservedObject var plant: Plant
    let household: Household
    @Environment(\.managedObjectContext) private var context
    @AppStorage(SettingsKey.myName) private var myName = ""
    @State private var showingAddPhoto = false
    @State private var showingSplit = false
    @State private var showingCombine = false
    @State private var showingEdit = false
    @State private var showingNewTask = false
    @State private var editingTask: CareTask?

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

            ZoneSection(plant: plant, household: household)

            if plant.isActive {
                Section("Care") {
                    ForEach(plant.activeTasks) { task in
                        TaskRow(task: task, household: household) { editingTask = task }
                    }
                    Button { showingNewTask = true } label: {
                        Label("Add a care reminder", systemImage: "plus")
                    }
                }
            }

            Section("Photos") {
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

            Section("History") {
                ForEach(Lineage.history(of: plant)) { line in
                    Group {
                        if let other = line.plant {
                            NavigationLink(value: other) { Text(line.text) }
                        } else {
                            Text(line.text)
                        }
                    }
                    .padding(.leading, CGFloat(line.depth) * 16)
                }
            }

            if plant.isActive {
                Section {
                    Button { showingCombine = true } label: {
                        Label("Combine with other plants…", systemImage: "arrow.triangle.merge")
                    }
                    Button { showingSplit = true } label: {
                        Label("Split into new plants…", systemImage: "arrow.triangle.branch")
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
        .sheet(isPresented: $showingSplit) { SplitSheet(plant: plant, household: household) }
        .sheet(isPresented: $showingCombine) { CombineSheet(plant: plant, household: household) }
        .sheet(isPresented: $showingEdit) { EditPlantView(plant: plant) }
        .sheet(isPresented: $showingNewTask) { TaskEditorView(household: household, task: nil, preselected: [plant]) }
        .sheet(item: $editingTask) { TaskEditorView(household: household, task: $0, preselected: []) }
        .redrawsOnPhotoChanges(plant)
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
            Section("Grow zone") {
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
                    Text(task.title).foregroundStyle(.primary)
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
    }
}

extension View {
    /// A plant view only watches the plant itself, so editing one of its photos
    /// (a new date, a caption, here or on the other phone) wouldn't redraw it.
    /// This redraws it whenever any photo changes, which also re-sorts the
    /// timeline and re-picks the newest photo.
    func redrawsOnPhotoChanges(_ plant: Plant) -> some View {
        onReceive(NotificationCenter.default.publisher(for: .NSManagedObjectContextObjectsDidChange)) { note in
            let keys = [NSInsertedObjectsKey, NSUpdatedObjectsKey, NSDeletedObjectsKey, NSRefreshedObjectsKey]
            let changedPhoto = keys.contains { key in
                (note.userInfo?[key] as? Set<NSManagedObject>)?.contains { $0 is Photo } ?? false
            }
            if changedPhoto { plant.objectWillChange.send() }
        }
    }
}

extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
