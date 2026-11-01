import CoreData
import SwiftUI

/// "All · Succulents · Outdoor · +" chips at the top of Plants, Care and
/// Plans. Picking one filters all three tabs.
struct CollectionBar: View {
    @ObservedObject var household: Household
    @AppStorage(Collections.selectedKey) private var selected = ""
    @Environment(\.managedObjectContext) private var context
    @State private var naming: Naming?
    @State private var draft = ""
    @State private var deleting: PlantCollection?

    private enum Naming: Identifiable {
        case new
        case newGroup(PlantCollection)
        case rename(PlantCollection)
        var id: String {
            switch self {
            case .new: "new"
            case .newGroup(let parent): "group-" + parent.objectID.uriRepresentation().absoluteString
            case .rename(let collection): collection.objectID.uriRepresentation().absoluteString
            }
        }
    }

    var body: some View {
        let current = Collections.find(selected, in: household)
        let openParent = current?.parent ?? current
        VStack(alignment: .leading, spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    chip("All", isOn: current == nil) { selected = "" }
                    ForEach(Collections.topLevel(in: household)) { collection in
                        chip(collection.name ?? "Untitled", isOn: openParent == collection) { pick(collection) }
                            .contextMenu { menu(for: collection) }
                    }
                    Button { start(.new) } label: {
                        Label("Collection", systemImage: "plus")
                            .font(.subheadline)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .overlay(Capsule().strokeBorder(Color.secondary.opacity(0.4)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("New collection")
                }
                .padding(.horizontal)
            }
            // The groups only take up room once their collection is open.
            if let openParent, !Collections.groups(of: openParent).isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        chip("All \(openParent.name ?? "")", isOn: current == openParent) { pick(openParent) }
                        ForEach(Collections.groups(of: openParent)) { group in
                            chip(group.name ?? "Untitled", isOn: current == group) { pick(group) }
                                .contextMenu { menu(for: group) }
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
        .redrawsOnCollectionChanges(household)
        .alert(alertTitle, isPresented: Binding(get: { naming != nil }, set: { if !$0 { naming = nil } })) {
            TextField("Name (e.g. Succulents)", text: $draft)
            Button("Cancel", role: .cancel) { naming = nil }
            Button("Save", action: saveName)
        }
        .confirmationDialog("Delete \(deleting?.name ?? "collection")?",
                            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let deleting {
                    if selected == deleting.uuid?.uuidString { selected = "" }
                    Collections.delete(deleting, context: context)
                    Persistence.shared.save(context)
                }
                deleting = nil
            }
        } message: {
            Text("Its plants, wishlist and projects stay; they just stop being grouped. To only hide it, use Archive.")
        }
    }

    @ViewBuilder
    private func menu(for collection: PlantCollection) -> some View {
        Button { start(.rename(collection)) } label: { Label("Rename", systemImage: "pencil") }
        if collection.parent == nil {
            Button { start(.newGroup(collection)) } label: { Label("Add group", systemImage: "plus") }
        }
        let homes = Collections.topLevel(in: household).filter { $0 != collection.parent && Collections.canNest(collection, under: $0) }
        if !homes.isEmpty {
            Menu {
                ForEach(homes) { home in
                    Button(home.name ?? "Untitled") { move(collection, to: home) }
                }
            } label: {
                Label(collection.parent == nil ? "Move into" : "Move to", systemImage: "folder")
            }
        }
        if let parent = collection.parent {
            Button { move(collection, to: nil) } label: {
                Label("Move out of \(parent.name ?? "collection")", systemImage: "arrow.up.left")
            }
        }
        Button {
            collection.isArchived = true
            Persistence.shared.save(context)
            if Collections.find(selected, in: household) == nil { selected = "" }
        } label: {
            Label("Archive", systemImage: "archivebox")
        }
        Button(role: .destructive) { deleting = collection } label: { Label("Delete collection", systemImage: "trash") }
    }

    private func pick(_ collection: PlantCollection) {
        selected = collection.uuid?.uuidString ?? ""
    }

    private func move(_ collection: PlantCollection, to parent: PlantCollection?) {
        Collections.setParent(of: collection, to: parent)
        Persistence.shared.save(context)
    }

    private var alertTitle: String {
        switch naming {
        case .rename: "Rename collection"
        case .newGroup(let parent): "New group in \(parent.name ?? "collection")"
        default: "New collection"
        }
    }

    private func start(_ mode: Naming) {
        if case .rename(let collection) = mode { draft = collection.name ?? "" } else { draft = "" }
        naming = mode
    }

    private func saveName() {
        let name = draft.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        switch naming {
        case .rename(let collection):
            collection.name = name
        case .new:
            let collection = Collections.create(name: name, household: household, context: context)
            Persistence.shared.save(context)
            selected = collection.uuid?.uuidString ?? ""
        case .newGroup(let parent):
            let group = Collections.create(name: name, parent: parent, household: household, context: context)
            Persistence.shared.save(context)
            selected = group.uuid?.uuidString ?? ""
        case nil:
            break
        }
        Persistence.shared.save(context)
        naming = nil
    }

    private func chip(_ title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        CollectionChip(title: title, isOn: isOn, action: action)
    }
}

/// A pill to pick a collection, green when it's the one picked.
struct CollectionChip: View {
    let title: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(isOn ? .semibold : .regular))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isOn ? Color.accentColor : Color(.tertiarySystemFill), in: Capsule())
                .foregroundStyle(isOn ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// Which collections a plant is in, as toggles, plus a button to make a new
/// one without leaving the form. A new collection starts switched on.
struct CollectionToggles: View {
    @ObservedObject var household: Household
    @Binding var selection: Set<PlantCollection>
    @Environment(\.managedObjectContext) private var context
    @State private var naming = false
    @State private var draft = ""

    var body: some View {
        Section("Collections") {
            // An archived collection isn't listed, but a plant stays in it.
            ForEach(Collections.pickable(in: household)) { collection in
                Toggle(collection.path, isOn: Binding(
                    get: { selection.contains(collection) },
                    set: { on in
                        if on { selection.insert(collection) } else { selection.remove(collection) }
                    }
                ))
            }
            Button {
                draft = ""
                naming = true
            } label: {
                Label("New collection", systemImage: "plus")
            }
        }
        .alert("New collection", isPresented: $naming) {
            TextField("Name (e.g. Succulents)", text: $draft)
            Button("Cancel", role: .cancel) {}
            Button("Add", action: create)
        }
    }

    private func create() {
        let name = draft.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let collection = Collections.create(name: name, household: household, context: context)
        Persistence.shared.save(context)
        selection.insert(collection)
    }
}

/// Settings → Archived collections: bring one back.
struct ArchivedCollectionsView: View {
    @ObservedObject var household: Household
    @Environment(\.managedObjectContext) private var context

    var body: some View {
        let archived = Collections.archived(in: household)
        List {
            Section {
                ForEach(archived) { collection in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(collection.path)
                            let count = (collection.plants ?? []).filter(\.isActive).count
                            Text(count == 1 ? "1 plant" : "\(count) plants")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Unarchive") {
                            collection.isArchived = false
                            Persistence.shared.save(context)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            } footer: {
                Text("Archived collections leave the chips at the top of each tab. Their plants, wishlist and projects stay, and still show under All.")
            }
        }
        .overlay {
            if archived.isEmpty {
                ContentUnavailableView("Nothing archived", systemImage: "archivebox",
                                       description: Text("Press and hold a collection at the top of the Plants tab → Archive."))
            }
        }
        .navigationTitle("Archived collections")
        .redrawsOnCollectionChanges(household)
    }
}

extension View {
    /// A view watching the household isn't told when one of its collections
    /// changes, here or on the other phone. This tells it, which also redraws
    /// the tabs that filter by the picked collection.
    func redrawsOnCollectionChanges(_ household: Household) -> some View {
        onReceive(NotificationCenter.default.publisher(for: .NSManagedObjectContextObjectsDidChange)) { note in
            let keys = [NSInsertedObjectsKey, NSUpdatedObjectsKey, NSDeletedObjectsKey, NSRefreshedObjectsKey]
            let changed = keys.contains { key in
                (note.userInfo?[key] as? Set<NSManagedObject>)?.contains { $0 is PlantCollection } ?? false
            }
            if changed { household.objectWillChange.send() }
        }
    }
}

/// Pick which plants are in a collection, from the Plants tab.
struct CollectionPlantsSheet: View {
    @ObservedObject var collection: PlantCollection
    let household: Household
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Set<NSManagedObjectID> = []

    var body: some View {
        NavigationStack {
            PlantChecklist(household: household, selected: $selected)
                .navigationTitle(collection.name ?? "Collection")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            let set = collection.mutableSetValue(forKey: "plants")
                            for plant in (collection.plants ?? []) where plant.isActive && !selected.contains(plant.objectID) {
                                set.remove(plant)
                            }
                            for plant in household.plants ?? [] where selected.contains(plant.objectID) {
                                set.add(plant)
                            }
                            Persistence.shared.save(context)
                            dismiss()
                        }
                    }
                }
                .onAppear { selected = Set((collection.plants ?? []).map(\.objectID)) }
        }
    }
}

/// Active plants with checkmarks; used for collections and projects.
struct PlantChecklist: View {
    @ObservedObject var household: Household
    @Binding var selected: Set<NSManagedObjectID>
    @FetchRequest private var plants: FetchedResults<Plant>
    /// Narrows a long list while picking. Only for this sheet, so it doesn't
    /// change the collection picked on the tabs.
    @State private var filter: PlantCollection?

    init(household: Household, selected: Binding<Set<NSManagedObjectID>>) {
        self.household = household
        _selected = selected
        let request = NSFetchRequest<Plant>(entityName: "Plant")
        request.predicate = NSPredicate(format: "household == %@ AND status == %@", household, PlantStatus.active.rawValue)
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
        _plants = FetchRequest(fetchRequest: request)
    }

    var body: some View {
        List {
            if !Collections.pickable(in: household).isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        CollectionChip(title: "All", isOn: filter == nil) { filter = nil }
                        ForEach(Collections.pickable(in: household)) { collection in
                            CollectionChip(title: collection.name ?? "Untitled", isOn: filter == collection) { filter = collection }
                        }
                    }
                    .padding(.horizontal)
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
            // Ticked plants outside the filter stay ticked; they're just hidden.
            ForEach(plants.filter { Collections.contains(filter, $0) }) { plant in
                PlantCheckRow(plant: plant, isOn: selected.contains(plant.objectID)) {
                    if selected.contains(plant.objectID) { selected.remove(plant.objectID) } else { selected.insert(plant.objectID) }
                }
            }
        }
        .overlay {
            if plants.isEmpty {
                ContentUnavailableView("No plants yet", systemImage: "leaf")
            }
        }
    }
}

struct PlantCheckRow: View {
    @ObservedObject var plant: Plant
    let isOn: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack {
                PlantPhotoView(photo: PlantPhotos.cover(for: plant), maxPixel: 120)
                    .frame(width: 36, height: 36)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                Text(plant.displayName).foregroundStyle(.primary)
                Spacer()
                if isOn {
                    Image(systemName: "checkmark").foregroundStyle(.tint)
                }
            }
        }
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
