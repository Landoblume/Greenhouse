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
        case rename(PlantCollection)
        var id: String {
            switch self {
            case .new: "new"
            case .rename(let collection): collection.objectID.uriRepresentation().absoluteString
            }
        }
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("All", isOn: Collections.find(selected, in: household) == nil) { selected = "" }
                ForEach(household.sortedCollections) { collection in
                    chip(collection.name ?? "Untitled", isOn: selected == collection.uuid?.uuidString) {
                        selected = collection.uuid?.uuidString ?? ""
                    }
                    .contextMenu {
                        Button { start(.rename(collection)) } label: { Label("Rename", systemImage: "pencil") }
                        Button(role: .destructive) { deleting = collection } label: { Label("Delete collection", systemImage: "trash") }
                    }
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
            Text("Its plants, wishlist and projects stay; they just stop being grouped.")
        }
    }

    private var alertTitle: String {
        if case .rename = naming { return "Rename collection" }
        return "New collection"
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
        case nil:
            break
        }
        Persistence.shared.save(context)
        naming = nil
    }

    private func chip(_ title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
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
            ForEach(household.sortedCollections) { collection in
                Toggle(collection.name ?? "Untitled", isOn: Binding(
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
    let household: Household
    @Binding var selected: Set<NSManagedObjectID>
    @FetchRequest private var plants: FetchedResults<Plant>

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
            ForEach(plants) { plant in
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
