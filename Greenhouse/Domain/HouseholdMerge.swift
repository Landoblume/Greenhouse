import CoreData

/// Moves your own plants into a household you joined.
///
/// Accepting an invite never deletes anything, but the app switches to the
/// shared household, which would leave plants you'd already added out of
/// sight. This brings them along: plants, photos, care reminders with their
/// history, staple/split links, collections, the wishlist and projects.
///
/// Objects can't move between Core Data stores (your own household lives in
/// the private store, a joined one in the shared store), so everything is
/// copied into the target household's store and the originals are deleted.
enum HouseholdMerge {
    /// Your own households (not ones you joined) that still hold plants,
    /// other than `current`. Settings lists all of these.
    static func others(of current: Household, in households: [Household], persistence: Persistence = .shared) -> [Household] {
        households.filter { household in
            household != current
                && !persistence.isShared(household)
                && !(household.plants ?? []).isEmpty
        }
    }

    /// The ones offered automatically on the Plants tab: also nobody else has
    /// joined them, since moving would take the plants away from that person.
    /// An invite that was sent but never accepted doesn't count.
    static func candidates(for current: Household, in households: [Household], persistence: Persistence = .shared) -> [Household] {
        others(of: current, in: households, persistence: persistence).filter { persistence.joinedCount(for: $0) == 0 }
    }

    /// Returns how many plants now show on the home screen as a result.
    @discardableResult
    static func move(
        _ source: Household,
        into target: Household,
        context: NSManagedObjectContext,
        persistence: Persistence = .shared
    ) -> Int {
        let plants = Array(source.plants ?? [])
        let events = Array(source.lineageEvents ?? [])
        let tasks = Array(source.tasks ?? [])

        var copies: [NSManagedObjectID: Plant] = [:]
        for plant in plants {
            let copy = persistence.insert(Plant.self, alongside: target, in: context)
            copyAttributes(of: plant, to: copy)
            copy.household = target
            copies[plant.objectID] = copy
            for photo in plant.photos ?? [] {
                let photoCopy = persistence.insert(Photo.self, alongside: target, in: context)
                copyAttributes(of: photo, to: photoCopy)
                photoCopy.plant = copy
            }
        }

        for event in events {
            let copy = persistence.insert(LineageEvent.self, alongside: target, in: context)
            copyAttributes(of: event, to: copy)
            copy.household = target
            for input in event.inputs ?? [] { copies[input.objectID]?.consumedBy = copy }
            for output in event.outputs ?? [] { copies[output.objectID]?.producedBy = copy }
        }

        for task in tasks {
            let copy = persistence.insert(CareTask.self, alongside: target, in: context)
            copyAttributes(of: task, to: copy)
            copy.household = target
            copy.mutableSetValue(forKey: "plants").addObjects(from: (task.plants ?? []).compactMap { copies[$0.objectID] })
            for log in task.logs ?? [] {
                let logCopy = persistence.insert(CareLog.self, alongside: target, in: context)
                copyAttributes(of: log, to: logCopy)
                logCopy.task = copy
            }
        }

        var collectionCopies: [NSManagedObjectID: PlantCollection] = [:]
        let collections = Array(source.collections ?? [])
        for collection in collections {
            let copy = persistence.insert(PlantCollection.self, alongside: target, in: context)
            copyAttributes(of: collection, to: copy)
            copy.household = target
            copy.mutableSetValue(forKey: "plants").addObjects(from: (collection.plants ?? []).compactMap { copies[$0.objectID] })
            collectionCopies[collection.objectID] = copy
        }

        let wishes = Array(source.wishlist ?? [])
        for item in wishes {
            let copy = persistence.insert(WishlistItem.self, alongside: target, in: context)
            copyAttributes(of: item, to: copy)
            copy.household = target
            copy.collection = item.collection.flatMap { collectionCopies[$0.objectID] }
        }

        let projects = Array(source.projects ?? [])
        for project in projects {
            let copy = persistence.insert(Project.self, alongside: target, in: context)
            copyAttributes(of: project, to: copy)
            copy.household = target
            copy.collection = project.collection.flatMap { collectionCopies[$0.objectID] }
            copy.mutableSetValue(forKey: "plants").addObjects(from: (project.plants ?? []).compactMap { copies[$0.objectID] })
        }

        if target.hardinessZone == nil, let zone = source.hardinessZone {
            target.hardinessZone = zone
            target.zip = source.zip
        }

        // Tasks and plants cascade to their logs and photos.
        tasks.forEach(context.delete)
        events.forEach(context.delete)
        collections.forEach(context.delete)
        wishes.forEach(context.delete)
        projects.forEach(context.delete)
        plants.forEach(context.delete)
        context.delete(source)

        return copies.values.filter(\.isActive).count
    }

    /// Copies every attribute (not relationships), so fields added to the
    /// model later come along without touching this code.
    private static func copyAttributes(of source: NSManagedObject, to target: NSManagedObject) {
        for name in source.entity.attributesByName.keys {
            target.setValue(source.value(forKey: name), forKey: name)
        }
    }
}
