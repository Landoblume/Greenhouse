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
                .listRowBackground(GH.Palette.surface)
                Section {
                    DatePicker("Taken on", selection: $takenAt, in: ...Date(), displayedComponents: .date)
                    .tint(GH.Palette.leafDeep)
                    TextField("Caption (optional)", text: $caption)
                } footer: {
                    if dateFromPhoto {
                        Text("Date read from the photo. Change it if it's wrong.")
                    }
                }
                .listRowBackground(GH.Palette.surface)
                MilestonePicker(plant: plant, selection: $milestone, newTitle: $newMilestoneTitle)
            }
            .ghScreen()
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
            VStack(spacing: GH.Space.m) {
                if let since = Lineage.effectiveAcquiredDate(of: plant) {
                    Text("\(PlantDetailView.age(since: since).capitalizedFirst) since you got it")
                        .font(.ghRounded(.title2))
                        .foregroundStyle(GH.Palette.ink)
                        .multilineTextAlignment(.center)
                        .growIn()
                }
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: GH.Space.s) {
                        column("Then", timeline.first, index: 1)
                        column("Now", timeline.last, index: 2)
                    }
                    VStack(spacing: GH.Space.m) {
                        column("Then", timeline.first, index: 1)
                        column("Now", timeline.last, index: 2)
                    }
                }
            }
            .padding(GH.Space.screen)
        }
        .ghTabBarClearance()
        .background(GH.Palette.paper.ignoresSafeArea())
        .navigationTitle("Then vs now")
    }

    private func column(_ title: String, _ item: Lineage.TimelinePhoto?, index: Int) -> some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.ghRounded(.headline))
                .foregroundStyle(GH.Palette.ink)
            Color.clear
                .frame(minWidth: 140, maxWidth: .infinity)
                .frame(height: 260)
                .overlay { PlantPhotoView(photo: item?.photo, maxPixel: 1200) }
                .clipShape(RoundedRectangle(cornerRadius: GH.Radius.tile, style: .continuous))
                .ghCard(radius: GH.Radius.tile)
            Text(item?.photo.takenAt.map(Lineage.format) ?? "")
                .font(.caption)
                .foregroundStyle(GH.Palette.ink2)
        }
        .accessibilityElement(children: .combine)
        .growIn(index: index)
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
                .listRowBackground(GH.Palette.surface)
                Section("New plant") {
                    TextField("Nickname (optional)", text: $nickname)
                    DatePicker("Combined on", selection: $date, in: ...Date(), displayedComponents: .date)
                    .tint(GH.Palette.leafDeep)
                }
                .listRowBackground(GH.Palette.surface)
            }
            .ghScreen()
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

/// A new plant from a cutting, without a photo (Skip photo, or no camera);
/// the parent stays as it is. CuttingCameraView is the usual way in.
struct CuttingSheet: View {
    let plant: Plant
    let household: Household
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var nickname: String
    @State private var date = Date()
    @State private var medium: GrowMedium

    init(plant: Plant, household: Household) {
        self.plant = plant
        self.household = household
        _nickname = State(initialValue: CuttingDefaults.name(for: plant))
        _medium = State(initialValue: CuttingDefaults.medium(for: plant))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Nickname (optional)", text: $nickname)
                    DatePicker("Taken on", selection: $date, in: ...Date(), displayedComponents: .date)
                    .tint(GH.Palette.leafDeep)
                } footer: {
                    Text(footer)
                }
                .listRowBackground(GH.Palette.surface)
                Section("Grown in") {
                    GrowMediumPicker(selection: $medium)
                }
                .listRowBackground(GH.Palette.surface)
            }
            .ghScreen()
            .navigationTitle("Take a cutting")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        Lineage.takeCutting(from: plant, nickname: nickname, date: date, medium: medium,
                                            household: household, context: context)
                        Persistence.shared.save(context)
                        NotificationPlanner.reschedule()
                        dismiss()
                    }
                }
            }
        }
    }

    private var footer: String {
        "\(plant.displayName) stays as it is. The cutting gets its own tile and reminder, counts from the day it was taken, and each links to the other in History."
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
                    .tint(GH.Palette.leafDeep)
                    TextField("Caption", text: $caption, axis: .vertical)
                }
                .listRowBackground(GH.Palette.surface)
                MilestonePicker(plant: plant, selection: $milestone, newTitle: $newMilestoneTitle)
            }
            .ghScreen()
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
    @State private var medium: GrowMedium
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
        _medium = State(initialValue: plant.mediumValue)
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
                    .tint(GH.Palette.leafDeep)
                    Picker("Lives", selection: $setting) {
                        ForEach(PlantSetting.allCases) { Text($0.label).tag($0) }
                    }
                    LightSourcePicker(selection: $light)
                }
                .listRowBackground(GH.Palette.surface)
                Section {
                    GrowMediumPicker(selection: $medium)
                        .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                } header: {
                    Text("Grown in")
                } footer: {
                    Text("Changing this renames the watering reminder if it still has its usual name. How often stays as it is.")
                }
                .listRowBackground(GH.Palette.surface)
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
                                            Text(parentDetail(parent)).font(.caption).foregroundStyle(GH.Palette.ink2)
                                        }
                                        .tag(Plant?.some(parent))
                                    }
                                }
                                .pickerStyle(.navigationLink)
                            } header: {
                                Text("Started from")
                            } footer: {
                                if let cuttingOf {
                                    Text("Got it on is when the cutting was taken. History links it to \(cuttingOf.displayName).")
                                } else {
                                    Text("Started this plant as a cutting of one you already have? Pick it to link them in History.")
                                }
                            }
                            .listRowBackground(GH.Palette.surface)
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
                                            Text(Plans.state(of: project).label).font(.caption).foregroundStyle(GH.Palette.ink2)
                                        }
                                    }
                                }
                            }
                        } header: {
                            Text("Projects")
                        }
                        .listRowBackground(GH.Palette.surface)
                    }
                }
            }
            .ghScreen()
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
                        GrowMedium.apply(medium, to: plant)
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
