import CoreData

/// The Plans tab: plants you want, and projects for the plants you have.
enum Plans {
    @discardableResult
    static func addWish(
        species: Species?,
        scientificName: String,
        notes: String?,
        by name: String,
        collection: PlantCollection?,
        household: Household,
        context: NSManagedObjectContext,
        persistence: Persistence = .shared
    ) -> WishlistItem {
        let item = persistence.insert(WishlistItem.self, alongside: household, in: context)
        item.uuid = UUID()
        item.createdAt = .now
        item.scientificName = species?.latin ?? scientificName.trimmingCharacters(in: .whitespaces)
        item.commonName = species?.primaryCommonName
        item.catalogID = species?.id
        item.notes = nonEmpty(notes)
        item.addedBy = nonEmpty(name)
        item.household = household
        item.collection = collection
        return item
    }

    /// A wish came true: the new plant joins the wish's collection and the
    /// wish comes off the list.
    static func fulfill(_ item: WishlistItem, with plant: Plant, context: NSManagedObjectContext) {
        if let collection = item.collection {
            plant.mutableSetValue(forKey: "collections").add(collection)
        }
        context.delete(item)
    }

    @discardableResult
    static func addProject(
        title: String,
        notes: String?,
        targetDate: Date?,
        plants: [Plant],
        collection: PlantCollection?,
        household: Household,
        context: NSManagedObjectContext,
        persistence: Persistence = .shared
    ) -> Project {
        let project = persistence.insert(Project.self, alongside: household, in: context)
        project.uuid = UUID()
        project.createdAt = .now
        project.household = household
        project.collection = collection
        update(project, title: title, notes: notes, targetDate: targetDate, plants: plants)
        return project
    }

    static func update(_ project: Project, title: String, notes: String?, targetDate: Date?, plants: [Plant]) {
        project.title = title.trimmingCharacters(in: .whitespaces)
        project.notes = nonEmpty(notes)
        project.targetDate = targetDate
        let set = project.mutableSetValue(forKey: "plants")
        set.removeAllObjects()
        set.addObjects(from: plants)
    }

    static func setDone(_ project: Project, _ done: Bool, at date: Date = .now) {
        project.isDone = done
        project.doneAt = done ? date : nil
    }

    /// Open projects first (soonest target date, then oldest), then finished
    /// ones, most recently finished first.
    static func sorted(_ projects: [Project]) -> [Project] {
        projects.sorted { a, b in
            if a.isDone != b.isDone { return !a.isDone }
            if a.isDone { return (a.doneAt ?? .distantPast) > (b.doneAt ?? .distantPast) }
            let aTarget = a.targetDate ?? .distantFuture
            let bTarget = b.targetDate ?? .distantFuture
            if aTarget != bTarget { return aTarget < bTarget }
            return (a.createdAt ?? .distantPast) < (b.createdAt ?? .distantPast)
        }
    }

    private static func nonEmpty(_ text: String?) -> String? {
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}
