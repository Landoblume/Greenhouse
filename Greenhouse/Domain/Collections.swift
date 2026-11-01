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
        parent: PlantCollection? = nil,
        household: Household,
        context: NSManagedObjectContext,
        persistence: Persistence = .shared
    ) -> PlantCollection {
        let collection = persistence.insert(PlantCollection.self, alongside: household, in: context)
        collection.uuid = UUID()
        collection.name = name.trimmingCharacters(in: .whitespaces)
        collection.createdAt = .now
        collection.household = household
        collection.parent = parent?.parent ?? parent
        collection.mutableSetValue(forKey: "plants").addObjects(from: plants)
        return collection
    }

    /// Deleting a collection only removes the grouping. Its plants stay, its
    /// wishlist items and projects move to "All", and its groups become
    /// collections of their own.
    static func delete(_ collection: PlantCollection, context: NSManagedObjectContext) {
        context.delete(collection)
    }

    /// The collection stored under `selectedKey`, if it still exists here and
    /// isn't archived (possibly on the other phone).
    static func find(_ id: String, in household: Household) -> PlantCollection? {
        guard let uuid = UUID(uuidString: id) else { return nil }
        return (household.collections ?? []).first { $0.uuid == uuid && isVisible($0) }
    }

    static func isVisible(_ collection: PlantCollection) -> Bool {
        !collection.isArchived && collection.parent?.isArchived != true
    }

    // MARK: - Groups

    /// What the top row of chips shows.
    static func topLevel(in household: Household) -> [PlantCollection] {
        household.sortedCollections.filter { $0.parent == nil && !$0.isArchived }
    }

    static func groups(of collection: PlantCollection) -> [PlantCollection] {
        (collection.groups ?? []).filter { !$0.isArchived }
            .sorted { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }
    }

    /// Everything that can be picked, each collection followed by its groups.
    /// `keeping` stays listed even if archived, so a form that already points
    /// at it doesn't lose the value.
    static func pickable(in household: Household, keeping current: PlantCollection? = nil) -> [PlantCollection] {
        var list = topLevel(in: household).flatMap { [$0] + groups(of: $0) }
        if let current, !list.contains(current) { list.append(current) }
        return list
    }

    /// Nesting stops at one level: a group can't hold groups of its own.
    static func canNest(_ collection: PlantCollection, under parent: PlantCollection) -> Bool {
        collection != parent && parent.parent == nil && (collection.groups ?? []).isEmpty
    }

    /// Moves a collection into `parent`, or back out with nil. Returns false
    /// when that would nest too deep.
    @discardableResult
    static func setParent(of collection: PlantCollection, to parent: PlantCollection?) -> Bool {
        if let parent, !canNest(collection, under: parent) { return false }
        collection.parent = parent
        return true
    }

    // MARK: - Archive

    /// Archived collections at the top level of Settings → Archived
    /// collections. A group under an archived collection comes back with it.
    static func archived(in household: Household) -> [PlantCollection] {
        household.sortedCollections.filter { $0.isArchived && $0.parent?.isArchived != true }
    }

    /// The collection and the groups showing inside it.
    private static func members(of collection: PlantCollection) -> Set<PlantCollection> {
        Set(groups(of: collection)).union([collection])
    }

    static func setMembership(of plant: Plant, to collections: Set<PlantCollection>) {
        let set = plant.mutableSetValue(forKey: "collections")
        set.removeAllObjects()
        set.addObjects(from: Array(collections))
    }

    static func contains(_ collection: PlantCollection?, _ plant: Plant) -> Bool {
        guard let collection else { return true }
        return !(plant.collections ?? []).isDisjoint(with: members(of: collection))
    }

    /// Care for a collection is the reminders that cover at least one of its
    /// plants. Household-wide reminders only show under "All".
    static func contains(_ collection: PlantCollection?, _ task: CareTask) -> Bool {
        guard collection != nil else { return true }
        return task.activePlants.contains { contains(collection, $0) }
    }

    static func contains(_ collection: PlantCollection?, _ item: WishlistItem) -> Bool {
        guard let collection else { return true }
        return item.collection.map(members(of: collection).contains) ?? false
    }

    static func contains(_ collection: PlantCollection?, _ project: Project) -> Bool {
        guard let collection else { return true }
        return project.collection.map(members(of: collection).contains) ?? false
    }

    /// New plants from a staple or split stay in their originals' collections.
    static func inherit(from sources: [Plant], to plants: [Plant]) {
        let union = sources.reduce(into: Set<PlantCollection>()) { $0.formUnion($1.collections ?? []) }
        for plant in plants {
            plant.mutableSetValue(forKey: "collections").addObjects(from: Array(union))
        }
    }
}
