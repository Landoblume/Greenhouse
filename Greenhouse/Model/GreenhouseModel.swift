import CoreData

/// The Core Data model, built in code instead of an .xcdatamodeld so the whole
/// schema reads in one place.
///
/// CloudKit sync puts rules on it: every attribute is optional or has a
/// default, every relationship is optional and has an inverse, and nothing uses
/// unique constraints or the Deny delete rule.
enum GreenhouseModel {
    /// Built once per process. Two model instances describing the same classes
    /// make Core Data unsure which entity a class belongs to, which bites tests
    /// that create several in-memory stores.
    static let shared: NSManagedObjectModel = build()

    /// Changes whenever an entity, attribute or relationship does. The debug
    /// build re-uploads the CloudKit schema when this differs from the last
    /// upload, so a model change is never left out of Production by accident.
    static var fingerprint: String {
        shared.entityVersionHashesByName
            .sorted { $0.key < $1.key }
            .map { "\($0.key):\($0.value.base64EncodedString())" }
            .joined(separator: ",")
            .hashValueStable
    }

    private static func build() -> NSManagedObjectModel {
        let household = entity(Household.self, [
            attr("uuid", .uuid),
            attr("name", .string),
            attr("createdAt", .date),
            attr("zip", .string),
            attr("hardinessZone", .string),
            /// The milestone quick picks, one per line; nil means the built-in list.
            attr("milestoneSuggestions", .string),
        ])
        let plant = entity(Plant.self, [
            attr("uuid", .uuid),
            attr("scientificName", .string),
            attr("commonName", .string),
            attr("nickname", .string),
            attr("catalogID", .string),
            attr("acquiredDate", .date),
            attr("location", .string),
            attr("lightSource", .string),
            attr("notes", .string),
            /// The photo shown on the tile and at the top of the plant's page;
            /// nil means the newest one.
            attr("coverPhotoID", .uuid),
            attr("setting", .string, default: PlantSetting.indoor.rawValue),
            attr("status", .string, default: PlantStatus.active.rawValue),
            attr("createdAt", .date),
        ])
        let photo = entity(Photo.self, [
            attr("uuid", .uuid),
            attr("takenAt", .date),
            attr("caption", .string),
            // Stored beside the database rather than in it, and synced as a
            // CloudKit asset rather than inline record data.
            attr("imageData", .binaryData, external: true),
        ])
        let milestone = entity(Milestone.self, [
            attr("uuid", .uuid),
            attr("title", .string),
            attr("date", .date),
            attr("notes", .string),
            attr("addedBy", .string),
            attr("createdAt", .date),
        ])
        let event = entity(LineageEvent.self, [
            attr("uuid", .uuid),
            attr("kind", .string),
            attr("date", .date),
        ])
        let task = entity(CareTask.self, [
            attr("uuid", .uuid),
            attr("name", .string),
            attr("intervalCount", .integer64, default: NSNumber(value: 7)),
            attr("intervalUnit", .string, default: IntervalUnit.day.rawValue),
            attr("firstDue", .date),
            attr("isWatering", .boolean, default: NSNumber(value: false)),
            attr("isArchived", .boolean, default: NSNumber(value: false)),
            attr("createdAt", .date),
        ])
        let log = entity(CareLog.self, [
            attr("uuid", .uuid),
            attr("doneAt", .date),
            attr("doneBy", .string),
        ])

        let projectItem = entity(ProjectItem.self, [
            attr("uuid", .uuid),
            attr("kind", .string, default: ProjectItemKind.step.rawValue),
            attr("title", .string),
            attr("isDone", .boolean, default: NSNumber(value: false)),
            attr("cost", .double, default: NSNumber(value: 0)),
            attr("createdAt", .date),
        ])
        let collection = entity(PlantCollection.self, [
            attr("uuid", .uuid),
            attr("name", .string),
            attr("createdAt", .date),
        ])
        let wish = entity(WishlistItem.self, [
            attr("uuid", .uuid),
            attr("scientificName", .string),
            attr("commonName", .string),
            attr("catalogID", .string),
            attr("notes", .string),
            attr("addedBy", .string),
            attr("createdAt", .date),
        ])
        let project = entity(Project.self, [
            attr("uuid", .uuid),
            attr("title", .string),
            attr("notes", .string),
            attr("targetDate", .date),
            attr("isDone", .boolean, default: NSNumber(value: false)),
            attr("doneAt", .date),
            /// Set while the project is underway; nil means just planned.
            attr("startedAt", .date),
            /// 0 means no budget set.
            attr("budget", .double, default: NSNumber(value: 0)),
            attr("place", .string),
            attr("link", .string),
            attr("createdAt", .date),
        ])

        relate(household, "plants", many: true, plant, "household", many: false)
        relate(household, "tasks", many: true, task, "household", many: false)
        relate(household, "lineageEvents", many: true, event, "household", many: false)
        relate(plant, "photos", many: true, photo, "plant", many: false, deleteRule: .cascadeDeleteRule)
        relate(plant, "milestones", many: true, milestone, "plant", many: false, deleteRule: .cascadeDeleteRule)
        relate(milestone, "photos", many: true, photo, "milestone", many: false)
        relate(plant, "tasks", many: true, task, "plants", many: true)
        relate(plant, "producedBy", many: false, event, "outputs", many: true)
        relate(plant, "consumedBy", many: false, event, "inputs", many: true)
        relate(task, "logs", many: true, log, "task", many: false, deleteRule: .cascadeDeleteRule)
        relate(household, "collections", many: true, collection, "household", many: false)
        relate(household, "wishlist", many: true, wish, "household", many: false)
        relate(household, "projects", many: true, project, "household", many: false)
        relate(collection, "plants", many: true, plant, "collections", many: true)
        relate(collection, "wishlist", many: true, wish, "collection", many: false)
        relate(collection, "projects", many: true, project, "collection", many: false)
        relate(project, "plants", many: true, plant, "projects", many: true)
        relate(project, "items", many: true, projectItem, "project", many: false, deleteRule: .cascadeDeleteRule)

        let model = NSManagedObjectModel()
        model.entities = [household, plant, photo, milestone, event, task, log, collection, wish, project, projectItem]
        return model
    }

    private static func entity<T: NSManagedObject>(_ type: T.Type, _ attributes: [NSAttributeDescription]) -> NSEntityDescription {
        let entity = NSEntityDescription()
        entity.name = String(describing: type)
        entity.managedObjectClassName = NSStringFromClass(type)
        entity.properties = attributes
        return entity
    }

    private static func attr(
        _ name: String,
        _ type: NSAttributeDescription.AttributeType,
        default value: Any? = nil,
        external: Bool = false
    ) -> NSAttributeDescription {
        let attribute = NSAttributeDescription()
        attribute.name = name
        attribute.type = type
        attribute.isOptional = true
        attribute.defaultValue = value
        attribute.allowsExternalBinaryDataStorage = external
        return attribute
    }

    /// Adds a relationship and its inverse in one go.
    private static func relate(
        _ a: NSEntityDescription, _ aName: String, many aMany: Bool,
        _ b: NSEntityDescription, _ bName: String, many bMany: Bool,
        deleteRule: NSDeleteRule = .nullifyDeleteRule
    ) {
        let forward = NSRelationshipDescription()
        forward.name = aName
        forward.destinationEntity = b
        forward.minCount = 0
        forward.maxCount = aMany ? 0 : 1
        forward.isOptional = true
        forward.deleteRule = deleteRule

        let inverse = NSRelationshipDescription()
        inverse.name = bName
        inverse.destinationEntity = a
        inverse.minCount = 0
        inverse.maxCount = bMany ? 0 : 1
        inverse.isOptional = true
        inverse.deleteRule = .nullifyDeleteRule

        forward.inverseRelationship = inverse
        inverse.inverseRelationship = forward
        a.properties.append(forward)
        b.properties.append(inverse)
    }
}

private extension String {
    /// FNV-1a, because Swift's own hashValue changes on every launch.
    var hashValueStable: String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return String(hash, radix: 16)
    }
}
