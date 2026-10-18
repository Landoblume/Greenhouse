import CoreData
import SwiftUI

struct AddPhotoSheet: View {
    let plant: Plant
    let household: Household
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?
    @State private var takenAt = Date()
    @State private var dateFromPhoto = false
    @State private var caption = ""
    @State private var milestone: MilestoneSelection = .none
    @State private var newMilestoneTitle = ""
    @AppStorage(SettingsKey.myName) private var myName = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    PhotoInput(image: $image) { date in
                        takenAt = date ?? Date()
                        dateFromPhoto = date != nil
                    }
                }
                Section {
                    DatePicker("Taken on", selection: $takenAt, in: ...Date(), displayedComponents: .date)
                    TextField("Caption (optional)", text: $caption)
                } footer: {
                    if dateFromPhoto {
                        Text("Date read from the photo. Change it if it's wrong.")
                    }
                }
                MilestonePicker(plant: plant, selection: $milestone, newTitle: $newMilestoneTitle)
            }
            .navigationTitle("Add photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let data = image.flatMap({ ImageTools.preparedJPEG(from: $0) }) {
                            let photo = PlantFactory.addPhoto(data, takenAt: takenAt, caption: caption, to: plant, household: household, context: context)
                            Milestones.attach(photo, to: milestone.choice(newTitle: newMilestoneTitle), by: myName,
                                              plant: plant, household: household, context: context)
                            Persistence.shared.save(context)
                        }
                        dismiss()
                    }
                    .disabled(image == nil)
                }
            }
        }
    }
}

/// First photo next to the latest one: "look how it's grown".
struct ThenNowView: View {
    let plant: Plant

    var body: some View {
        let timeline = Lineage.timeline(for: plant)
        ScrollView {
            VStack(spacing: 16) {
                if let since = Lineage.effectiveAcquiredDate(of: plant) {
                    Text("\(PlantDetailView.age(since: since).capitalizedFirst) since you got it")
                        .font(.title2.bold())
                }
                HStack(alignment: .top, spacing: 12) {
                    column("Then", timeline.first)
                    column("Now", timeline.last)
                }
            }
            .padding()
        }
        .navigationTitle("Then vs now")
    }

    private func column(_ title: String, _ item: Lineage.TimelinePhoto?) -> some View {
        VStack(spacing: 6) {
            Text(title).font(.headline)
            PlantPhotoView(photo: item?.photo, maxPixel: 1200)
                .frame(height: 260)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            Text(item?.photo.takenAt.map(Lineage.format) ?? "")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// Combine one plant with others into a single new plant (two pots potted
/// together, say). Opened from the plant's page or by pressing and holding it.
struct CombineSheet: View {
    let plant: Plant
    let household: Household
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var others: Set<NSManagedObjectID> = []
    @State private var nickname: String
    @State private var date = Date()

    init(plant: Plant, household: Household) {
        self.plant = plant
        self.household = household
        _nickname = State(initialValue: plant.displayName)
    }

    private var candidates: [Plant] {
        (household.plants ?? [])
            .filter { $0.isActive && $0 != plant }
            .sorted { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }
    }

    private var chosen: [Plant] {
        [plant] + candidates.filter { others.contains($0.objectID) }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(candidates) { other in
                        PlantCheckRow(plant: other, isOn: others.contains(other.objectID)) {
                            if others.contains(other.objectID) { others.remove(other.objectID) } else { others.insert(other.objectID) }
                        }
                    }
                } header: {
                    Text("Combine \(plant.displayName) with")
                } footer: {
                    Text("They become one plant with one tile. Their photos, history and care carry over, and the originals stay reachable from History.")
                }
                Section("New plant") {
                    TextField("Nickname (optional)", text: $nickname)
                    DatePicker("Combined on", selection: $date, in: ...Date(), displayedComponents: .date)
                }
            }
            .overlay {
                if candidates.isEmpty {
                    ContentUnavailableView("Nothing to combine with", systemImage: "leaf",
                                           description: Text("Add another plant first."))
                }
            }
            .navigationTitle("Combine plants")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Combine") {
                        Lineage.staple(chosen, nickname: nickname, date: date, household: household, context: context)
                        Persistence.shared.save(context)
                        NotificationPlanner.reschedule()
                        dismiss()
                    }
                    .disabled(others.isEmpty)
                }
            }
        }
    }
}

struct SplitSheet: View {
    let plant: Plant
    let household: Household
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var names: [String] = []
    @State private var date = Date()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper("\(names.count) new plants", value: Binding(
                        get: { names.count },
                        set: { resize(to: $0) }
                    ), in: 2...12)
                    ForEach(names.indices, id: \.self) { index in
                        TextField("Plant \(index + 1)", text: $names[index])
                    }
                } footer: {
                    Text("\(plant.displayName) is retired and each new plant links back to it. Divisions and pups work this way. Keeping \(plant.displayName) and just taking a cutting? Use Take a cutting instead.")
                }
                Section {
                    DatePicker("Split on", selection: $date, in: ...Date(), displayedComponents: .date)
                }
            }
            .navigationTitle("Split \(plant.displayName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Split") {
                        let finalNames = names.enumerated().map { index, name in
                            name.trimmingCharacters(in: .whitespaces).isEmpty ? defaultName(index) : name
                        }
                        Lineage.split(plant, names: finalNames, date: date, household: household, context: context)
                        Persistence.shared.save(context)
                        NotificationPlanner.reschedule()
                        dismiss()
                    }
                }
            }
            .onAppear { if names.isEmpty { resize(to: 2) } }
        }
    }

    private func defaultName(_ index: Int) -> String { "\(plant.displayName) #\(index + 1)" }

    private func resize(to count: Int) {
        if count > names.count {
            names += (names.count..<count).map(defaultName)
        } else {
            names = Array(names.prefix(count))
        }
    }
}

/// A new plant from a cutting; the parent stays as it is.
struct CuttingSheet: View {
    let plant: Plant
    let household: Household
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var nickname: String
    @State private var date = Date()

    init(plant: Plant, household: Household) {
        self.plant = plant
        self.household = household
        _nickname = State(initialValue: "\(plant.displayName) cutting")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Nickname (optional)", text: $nickname)
                    DatePicker("Taken on", selection: $date, in: ...Date(), displayedComponents: .date)
                } footer: {
                    Text(footer)
                }
            }
            .navigationTitle("Take a cutting")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        Lineage.takeCutting(from: plant, nickname: nickname, date: date, household: household, context: context)
                        Persistence.shared.save(context)
                        NotificationPlanner.reschedule()
                        dismiss()
                    }
                }
            }
        }
    }

    private var footer: String {
        var text = "\(plant.displayName) stays as it is. The cutting gets its own tile and watering schedule, and each links to the other in History."
        if let since = Lineage.effectiveAcquiredDate(of: plant) {
            text += " Had since shows \(Lineage.format(since)) for both."
        }
        return text
    }
}

/// One photo full size, with edit, main-photo and delete.
struct PhotoDetailView: View {
    @ObservedObject var photo: Photo
    let plant: Plant
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var editing = false
    @State private var cropping = false
    @State private var confirmingDelete = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                PlantPhotoView(photo: photo, maxPixel: 2048)
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                if let caption = photo.caption {
                    Text(caption).font(.body)
                }
                if let milestone = photo.milestone {
                    Label(milestone.title ?? "Milestone", systemImage: "flag.fill")
                        .font(.subheadline)
                        .foregroundStyle(.tint)
                }
                if PlantPhotos.isCover(photo, of: plant) {
                    Label("Main photo", systemImage: "star.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
        }
        .navigationTitle(photo.takenAt.map(Lineage.format) ?? "Photo")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Menu {
                Button { editing = true } label: { Label("Edit date, caption or milestone", systemImage: "pencil") }
                Button { cropping = true } label: { Label("Crop photo", systemImage: "crop") }
                if !PlantPhotos.isCover(photo, of: plant) {
                    Button {
                        PlantPhotos.setCover(photo, of: plant)
                        Persistence.shared.save(context)
                    } label: { Label("Use as main photo", systemImage: "star") }
                }
                Button(role: .destructive) { confirmingDelete = true } label: { Label("Delete photo", systemImage: "trash") }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .accessibilityLabel("Photo options")
        }
        .sheet(isPresented: $editing) { EditPhotoSheet(photo: photo, plant: plant) }
        .fullScreenCover(isPresented: $cropping) {
            if let data = photo.imageData, let image = UIImage(data: data) {
                CropView(image: image) { cropped in
                    PlantPhotos.replaceImage(of: photo, with: cropped)
                    Persistence.shared.save(context)
                }
            }
        }
        .confirmationDialog("Delete this photo?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                dismiss()
                PlantPhotos.delete(photo, context: context)
                Persistence.shared.save(context)
            }
        } message: {
            Text("It's removed from both phones.")
        }
    }
}

struct EditPhotoSheet: View {
    @ObservedObject var photo: Photo
    /// The plant whose page it was opened from; its milestones (and its
    /// originals') are the ones offered.
    let plant: Plant
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKey.myName) private var myName = ""
    @State private var caption: String
    @State private var takenAt: Date
    @State private var milestone: MilestoneSelection
    @State private var newMilestoneTitle = ""

    // Starting values are set here, not in onAppear: a date picker that first
    // draws with today and is then changed can keep showing today, and saving
    // would write that back.
    init(photo: Photo, plant: Plant) {
        _photo = ObservedObject(wrappedValue: photo)
        self.plant = plant
        _caption = State(initialValue: photo.caption ?? "")
        _takenAt = State(initialValue: photo.takenAt ?? Date())
        _milestone = State(initialValue: MilestoneSelection(photo.milestone))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Taken on", selection: $takenAt, in: ...Date(), displayedComponents: .date)
                    TextField("Caption", text: $caption, axis: .vertical)
                }
                MilestonePicker(plant: plant, selection: $milestone, newTitle: $newMilestoneTitle)
            }
            .navigationTitle("Edit photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        PlantPhotos.update(photo, caption: caption, takenAt: takenAt)
                        if let household = plant.household {
                            // A new milestone goes on the plant the photo was taken of.
                            Milestones.attach(photo, to: milestone.choice(newTitle: newMilestoneTitle), by: myName,
                                              plant: photo.plant ?? plant, household: household, context: context)
                        }
                        Persistence.shared.save(context)
                        dismiss()
                    }
                }
            }
        }
    }
}

struct EditPlantView: View {
    @ObservedObject var plant: Plant
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var nickname: String
    @State private var location: String
    @State private var acquired: Date
    @State private var setting: PlantSetting
    @State private var light: LightSource?
    @State private var collections: Set<PlantCollection>
    @State private var projects: Set<Project>
    @State private var cuttingOf: Plant?

    // See EditPhotoSheet: start from the plant's values so the date picker
    // never shows a stale date.
    init(plant: Plant) {
        _plant = ObservedObject(wrappedValue: plant)
        _nickname = State(initialValue: plant.nickname ?? "")
        _location = State(initialValue: plant.location ?? "")
        _acquired = State(initialValue: plant.acquiredDate ?? Date())
        _setting = State(initialValue: plant.settingValue)
        _light = State(initialValue: plant.lightSourceValue)
        _collections = State(initialValue: plant.collections ?? [])
        _projects = State(initialValue: plant.projects ?? [])
        _cuttingOf = State(initialValue: plant.cuttingOf)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Nickname", text: $nickname)
                    TextField("Where it lives", text: $location)
                    DatePicker("Got it on", selection: $acquired, in: ...Date(), displayedComponents: .date)
                    Picker("Lives", selection: $setting) {
                        ForEach(PlantSetting.allCases) { Text($0.label).tag($0) }
                    }
                    LightSourcePicker(selection: $light)
                }
                if let household = plant.household {
                    // Combined or split plants already know where they came from.
                    if plant.producedBy == nil {
                        let parents = Lineage.cuttingParentChoices(for: plant, in: household)
                        if !parents.isEmpty {
                            Section {
                                Picker("Cutting of", selection: $cuttingOf) {
                                    Text("None").tag(Plant?.none)
                                    ForEach(parents) { parent in
                                        VStack(alignment: .leading) {
                                            Text(parent.displayName)
                                            Text(parentDetail(parent)).font(.caption).foregroundStyle(.secondary)
                                        }
                                        .tag(Plant?.some(parent))
                                    }
                                }
                                .pickerStyle(.navigationLink)
                            } header: {
                                Text("Started from")
                            } footer: {
                                if let cuttingOf {
                                    Text("Got it on is when the cutting was taken. Had since counts from \(cuttingOf.displayName)'s date.")
                                } else {
                                    Text("Started this plant as a cutting of one you already have? Pick it, and Had since counts from that plant's date.")
                                }
                            }
                        }
                    }
                    CollectionToggles(household: household, selection: $collections)
                    let choices = Plans.projectChoices(for: plant, in: household)
                    if !choices.isEmpty {
                        Section {
                            ForEach(choices) { project in
                                Toggle(isOn: Binding(
                                    get: { projects.contains(project) },
                                    set: { on in
                                        if on { projects.insert(project) } else { projects.remove(project) }
                                    }
                                )) {
                                    VStack(alignment: .leading) {
                                        Text(project.title ?? "Untitled project")
                                        if Plans.state(of: project) != .planned {
                                            Text(Plans.state(of: project).label).font(.caption).foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                        } header: {
                            Text("Projects")
                        }
                    }
                }
            }
            .navigationTitle("Edit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let trimmedNick = nickname.trimmingCharacters(in: .whitespaces)
                        let trimmedLocation = location.trimmingCharacters(in: .whitespaces)
                        plant.nickname = trimmedNick.isEmpty ? nil : trimmedNick
                        plant.location = trimmedLocation.isEmpty ? nil : trimmedLocation
                        plant.acquiredDate = acquired
                        plant.settingValue = setting
                        plant.lightSourceValue = light
                        Collections.setMembership(of: plant, to: collections)
                        Plans.setProjects(of: plant, to: projects)
                        Lineage.setCuttingParent(of: plant, to: cuttingOf)
                        Persistence.shared.save(context)
                        NotificationPlanner.reschedule()
                        dismiss()
                    }
                }
            }
        }
    }

    private func parentDetail(_ parent: Plant) -> String {
        let got = parent.acquiredDate.map { "got \(Lineage.format($0))" } ?? "no date"
        return parent.isActive ? got : "\(got) · retired"
    }
}
