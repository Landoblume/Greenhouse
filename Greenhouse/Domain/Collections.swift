import CoreData

/// Named groups of plants ("Succulents", "Outdoor greenhouse"). The picked
/// collection filters the Plants, Care and Plans tabs together, so each one
/// has its own to-dos, wishlist and projects.
enum Collections {
    /// Remembers the picked collection per phone (it's a view choice, not
    /// shared data).
    static let selectedKey = "selectedCollection"

    @discardableResult
    static func create(
        name: String,
        plants: [Plant] = [],
        household: Household,
        context: NSManagedObjectContext,
        persistence: Persistence = .shared
    ) -> PlantCollection {
        let collection = persistence.insert(PlantCollection.self, alongside: household, in: context)
        collection.uuid = UUID()
        collection.name = name.trimmingCharacters(in: .whitespaces)
        collection.createdAt = .now
        collection.household = household
        collection.mutableSetValue(forKey: "plants").addObjects(from: plants)
        return collection
    }

    /// Deleting a collection only removes the grouping. Its plants stay, and
    /// its wishlist items and projects move to "All".
    static func delete(_ collection: PlantCollection, context: NSManagedObjectContext) {
        context.delete(collection)
    }

    /// The collection stored under `selectedKey`, if it still exists here.
    static func find(_ id: String, in household: Household) -> PlantCollection? {
        guard let uuid = UUID(uuidString: id) else { return nil }
        return (household.collections ?? []).first { $0.uuid == uuid }
    }

    static func setMembership(of plant: Plant, to collections: Set<PlantCollection>) {
        let set = plant.mutableSetValue(forKey: "collections")
        set.removeAllObjects()
        set.addObjects(from: Array(collections))
    }

    static func contains(_ collection: PlantCollection?, _ plant: Plant) -> Bool {
        guard let collection else { return true }
        return (plant.collections ?? []).contains(collection)
    }

    /// Care for a collection is the reminders that cover at least one of its
    /// plants. Household-wide reminders only show under "All".
    static func contains(_ collection: PlantCollection?, _ task: CareTask) -> Bool {
        guard let collection else { return true }
        return task.activePlants.contains { ($0.collections ?? []).contains(collection) }
    }

    static func contains(_ collection: PlantCollection?, _ item: WishlistItem) -> Bool {
        collection == nil || item.collection == collection
    }

    static func contains(_ collection: PlantCollection?, _ project: Project) -> Bool {
        collection == nil || project.collection == collection
    }

    /// New plants from a staple or split stay in their originals' collections.
    static func inherit(from sources: [Plant], to plants: [Plant]) {
        let union = sources.reduce(into: Set<PlantCollection>()) { $0.formUnion($1.collections ?? []) }
        for plant in plants {
            plant.mutableSetValue(forKey: "collections").addObjects(from: Array(union))
        }
    }
}
