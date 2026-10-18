import CoreData
import SwiftUI

/// Plants you want and projects for the ones you have.
struct PlansView: View {
    @ObservedObject var household: Household
    @AppStorage(Collections.selectedKey) private var selectedCollection = ""
    @AppStorage("plansTab") private var tab = Tab.wishlist
    @FetchRequest private var wishes: FetchedResults<WishlistItem>
    @FetchRequest private var projects: FetchedResults<Project>
    @State private var addingWish = false
    @State private var editingWish: WishlistItem?
    @State private var buying: WishlistItem?
    @State private var addingProject = false

    enum Tab: String, CaseIterable, Identifiable {
        case wishlist, projects
        var id: Self { self }
        var label: String { self == .wishlist ? "Wishlist" : "Projects" }
    }

    init(household: Household) {
        self.household = household
        let wishRequest = NSFetchRequest<WishlistItem>(entityName: "WishlistItem")
        wishRequest.predicate = NSPredicate(format: "household == %@", household)
        wishRequest.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
        _wishes = FetchRequest(fetchRequest: wishRequest)
        let projectRequest = NSFetchRequest<Project>(entityName: "Project")
        projectRequest.predicate = NSPredicate(format: "household == %@", household)
        projectRequest.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
        _projects = FetchRequest(fetchRequest: projectRequest)
    }

    private var collection: PlantCollection? { Collections.find(selectedCollection, in: household) }
    private var shownWishes: [WishlistItem] { wishes.filter { Collections.contains(collection, $0) } }
    private var shownProjects: [Project] { Plans.sorted(projects.filter { Collections.contains(collection, $0) }) }

    var body: some View {
        NavigationStack {
            List {
                VStack(spacing: 10) {
                    Picker("Show", selection: $tab) {
                        ForEach(Tab.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    CollectionBar(household: household)
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                switch tab {
                case .wishlist:
                    ForEach(shownWishes) { item in
                        WishRow(item: item, household: household) { editingWish = item } onGotIt: { buying = item }
                    }
                case .projects:
                    ForEach(shownProjects) { project in
                        ProjectRow(project: project, household: household)
                    }
                }
            }
            .overlay { emptyState }
            .navigationTitle("Plans")
            .toolbar {
                Button {
                    if tab == .wishlist { addingWish = true } else { addingProject = true }
                } label: { Image(systemName: "plus") }
                    .accessibilityLabel(tab == .wishlist ? "Add to wishlist" : "Add project")
            }
            .sheet(isPresented: $addingWish) { WishEditorView(household: household, item: nil) }
            .sheet(item: $editingWish) { WishEditorView(household: household, item: $0) }
            .sheet(item: $buying) { AddPlantView(household: household, wish: $0) }
            .sheet(isPresented: $addingProject) { ProjectEditorView(household: household, project: nil) }
            .navigationDestination(for: Plant.self) { PlantDetailView(plant: $0, household: household) }
        }
    }

    @ViewBuilder private var emptyState: some View {
        let where_ = collection.map { " in \($0.name ?? "this collection")" } ?? ""
        switch tab {
        case .wishlist where shownWishes.isEmpty:
            ContentUnavailableView("Nothing on the wishlist\(where_)", systemImage: "heart",
                                   description: Text("Tap + to note a plant you'd like. When you get it, tap Got it and it becomes a plant."))
                .allowsHitTesting(false)
        case .projects where shownProjects.isEmpty:
            ContentUnavailableView("No projects\(where_)", systemImage: "hammer",
                                   description: Text("Tap + for things to build or do, like painting a new greenhouse."))
                .allowsHitTesting(false)
        default:
            EmptyView()
        }
    }
}

struct WishRow: View {
    @ObservedObject var item: WishlistItem
    @ObservedObject var household: Household
    let onEdit: () -> Void
    let onGotIt: () -> Void

    var body: some View {
        HStack(alignment: .top) {
            Button(action: onEdit) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.displayName).foregroundStyle(.primary)
                    if let latin = item.scientificName, latin != item.displayName {
                        Text(latin).font(.caption).italic().foregroundStyle(.secondary)
                    }
                    if let species = item.species {
                        Text(hint(for: species))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let notes = item.notes {
                        Text(notes).font(.caption).lineLimit(2)
                    }
                    if let by = item.addedBy {
                        Text("Added by \(by)").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)
            Spacer()
            Button("Got it", action: onGotIt)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
    }

    /// e.g. "Likes bright, indirect · Not winter-hardy in 7a"
    private func hint(for species: Species) -> String {
        var parts = ["Likes \(species.light.lowercased())"]
        if let zone = household.hardinessZone, let number = USDAZone(zone)?.number {
            if number < species.zoneMin {
                parts.append("Not winter-hardy in \(zone)")
            } else if number > species.zoneMax {
                parts.append("May be too warm in \(zone)")
            } else {
                parts.append("Hardy outdoors in \(zone)")
            }
        }
        return parts.joined(separator: " · ")
    }
}

struct ProjectRow: View {
    @ObservedObject var project: Project
    let household: Household
    @Environment(\.managedObjectContext) private var context

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button {
                Plans.setDone(project, !project.isDone)
                Persistence.shared.save(context)
            } label: {
                Image(systemName: project.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(project.isDone ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(project.isDone ? "Mark not done" : "Mark done")
            NavigationLink {
                ProjectDetailView(project: project, household: household)
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(project.title ?? "Untitled project")
                        .strikethrough(project.isDone)
                        .foregroundStyle(project.isDone ? .secondary : .primary)
                    if let started = project.startedAt, !project.isDone {
                        Label("In progress since \(Lineage.format(started))", systemImage: "hammer.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                    if let target = project.targetDate, !project.isDone {
                        Label("By \(Lineage.format(target))", systemImage: "calendar")
                            .font(.caption)
                            .foregroundStyle(target < Calendar.current.startOfDay(for: .now) ? Color.orange : Color.secondary)
                    }
                    if let done = project.doneAt, project.isDone {
                        Text("Done \(Lineage.format(done))").font(.caption).foregroundStyle(.secondary)
                    }
                    let names = (project.plants ?? []).filter(\.isActive).map(\.displayName).sorted()
                    if !names.isEmpty {
                        Text(names.joined(separator: ", ")).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    ProjectSummary(project: project)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let notes = project.notes {
                        Text(notes).font(.caption).lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

struct WishEditorView: View {
    @ObservedObject var household: Household
    let item: WishlistItem?
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKey.myName) private var myName = ""
    @AppStorage(Collections.selectedKey) private var selectedCollection = ""
    @State private var species: Species?
    @State private var customLatin = ""
    @State private var notes = ""
    @State private var collection: PlantCollection?
    @State private var showingSpeciesPicker = false
    @State private var confirmingDelete = false

    private var latinName: String { species?.latin ?? customLatin }

    var body: some View {
        NavigationStack {
            Form {
                Section("Plant") {
                    Button { showingSpeciesPicker = true } label: {
                        if let species {
                            VStack(alignment: .leading) {
                                Text(species.primaryCommonName).foregroundStyle(.primary)
                                Text(species.latin).font(.caption).italic().foregroundStyle(.secondary)
                            }
                        } else if !customLatin.isEmpty {
                            Text(customLatin).italic()
                        } else {
                            Label("Choose species…", systemImage: "magnifyingglass")
                        }
                    }
                }
                Section("Notes") {
                    TextField("Where you saw it, a price, which color…", text: $notes, axis: .vertical)
                }
                if !household.sortedCollections.isEmpty {
                    Section {
                        Picker("Collection", selection: $collection) {
                            Text("None").tag(PlantCollection?.none)
                            ForEach(household.sortedCollections) { Text($0.name ?? "Untitled").tag(Optional($0)) }
                        }
                    }
                }
                if let item {
                    Section {
                        Button("Remove from wishlist", role: .destructive) { confirmingDelete = true }
                    }
                    .confirmationDialog("Remove \(item.displayName)?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                        Button("Remove", role: .destructive) {
                            context.delete(item)
                            Persistence.shared.save(context)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(item == nil ? "Add to wishlist" : "Wishlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(latinName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .sheet(isPresented: $showingSpeciesPicker) {
                SpeciesPickerView { picked in
                    species = picked
                    customLatin = ""
                } onCustom: { typed in
                    species = nil
                    customLatin = typed
                }
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        if let item {
            species = item.species
            customLatin = item.species == nil ? (item.scientificName ?? "") : ""
            notes = item.notes ?? ""
            collection = item.collection
        } else {
            collection = Collections.find(selectedCollection, in: household)
        }
    }

    private func save() {
        if let item {
            item.scientificName = species?.latin ?? customLatin.trimmingCharacters(in: .whitespaces)
            item.commonName = species?.primaryCommonName
            item.catalogID = species?.id
            let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
            item.notes = trimmed.isEmpty ? nil : trimmed
            item.collection = collection
        } else {
            Plans.addWish(species: species, scientificName: customLatin, notes: notes, by: myName,
                          collection: collection, household: household, context: context)
        }
        Persistence.shared.save(context)
        dismiss()
    }
}

struct ProjectEditorView: View {
    @ObservedObject var household: Household
    let project: Project?
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    @AppStorage(Collections.selectedKey) private var selectedCollection = ""
    @State private var title = ""
    @State private var notes = ""
    @State private var place = ""
    @State private var link = ""
    @State private var budget: Double?
    @State private var state: ProjectState = .planned
    @State private var hasTarget = false
    @State private var target = Date()
    @State private var plantIDs: Set<NSManagedObjectID> = []
    @State private var collection: PlantCollection?
    @State private var choosingPlants = false
    @State private var confirmingDelete = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("What (e.g. Spray paint a new greenhouse)", text: $title)
                    TextField("Notes, supplies, measurements…", text: $notes, axis: .vertical)
                }
                Section {
                    Picker("State", selection: $state) {
                        ForEach(ProjectState.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                } footer: {
                    Text("While a project is in progress, its plants get a green edge on the Plants tab.")
                }
                Section {
                    TextField("Where (e.g. back patio)", text: $place)
                    TextField("Link (inspiration, how-to, product)", text: $link)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    LabeledContent("Budget") {
                        TextField("None", value: $budget, format: .currency(code: Plans.currencyCode))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                }
                Section {
                    Toggle("Target date", isOn: $hasTarget)
                    if hasTarget {
                        DatePicker("By", selection: $target, displayedComponents: .date)
                    }
                }
                Section {
                    Button { choosingPlants = true } label: {
                        LabeledContent("For plants", value: plantIDs.isEmpty ? "None" : "\(plantIDs.count)")
                    }
                    .foregroundStyle(.primary)
                    if !household.sortedCollections.isEmpty {
                        Picker("Collection", selection: $collection) {
                            Text("None").tag(PlantCollection?.none)
                            ForEach(household.sortedCollections) { Text($0.name ?? "Untitled").tag(Optional($0)) }
                        }
                    }
                }
                if let project {
                    Section {
                        Button("Delete project", role: .destructive) { confirmingDelete = true }
                    }
                    .confirmationDialog("Delete \(project.title ?? "this project")?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                        Button("Delete", role: .destructive) {
                            context.delete(project)
                            Persistence.shared.save(context)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(project == nil ? "New project" : "Edit project")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .sheet(isPresented: $choosingPlants) {
                NavigationStack {
                    PlantChecklist(household: household, selected: $plantIDs)
                        .navigationTitle("Plants")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar { Button("Done") { choosingPlants = false } }
                }
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        if let project {
            title = project.title ?? ""
            notes = project.notes ?? ""
            state = Plans.state(of: project)
            place = project.place ?? ""
            link = project.link ?? ""
            budget = project.budget > 0 ? project.budget : nil
            hasTarget = project.targetDate != nil
            target = project.targetDate ?? Date()
            plantIDs = Set((project.plants ?? []).map(\.objectID))
            collection = project.collection
        } else {
            collection = Collections.find(selectedCollection, in: household)
        }
    }

    private func save() {
        let plants = (household.plants ?? []).filter { plantIDs.contains($0.objectID) }.sorted { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }
        if let project {
            Plans.update(project, title: title, notes: notes, targetDate: hasTarget ? target : nil, plants: plants)
            project.collection = collection
            Plans.setState(project, state)
            Plans.updateDetails(project, budget: budget ?? 0, place: place, link: link)
        } else {
            let project = Plans.addProject(title: title, notes: notes, targetDate: hasTarget ? target : nil, plants: plants,
                                           collection: collection, household: household, context: context)
            Plans.setState(project, state)
            Plans.updateDetails(project, budget: budget ?? 0, place: place, link: link)
        }
        Persistence.shared.save(context)
        dismiss()
    }
}
