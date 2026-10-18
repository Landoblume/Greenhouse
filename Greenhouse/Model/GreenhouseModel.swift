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

    private static func build() -> NSManagedObjectModel {
        let household = entity(Household.self, [
            attr("uuid", .uuid),
            attr("name", .string),
            attr("createdAt", .date),
            attr("zip", .string),
            attr("hardinessZone", .string),
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
            attr("setting", .string, default: PlantSetting.indoor.rawValue),
            attr("status", .string, default: PlantStatus.active.rawValue),
            attr("createdAt", .date),
        ])
        let photo = entity(Photo.self, [
            attr("uuid", .uuid),
            attr("takenAt", .date),
            // Stored beside the database rather than in it, and synced as a
            // CloudKit asset rather than inline record data.
            attr("imageData", .binaryData, external: true),
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

        relate(household, "plants", many: true, plant, "household", many: false)
        relate(household, "tasks", many: true, task, "household", many: false)
        relate(household, "lineageEvents", many: true, event, "household", many: false)
        relate(plant, "photos", many: true, photo, "plant", many: false, deleteRule: .cascadeDeleteRule)
        relate(plant, "tasks", many: true, task, "plants", many: true)
        relate(plant, "producedBy", many: false, event, "outputs", many: true)
        relate(plant, "consumedBy", many: false, event, "inputs", many: true)
        relate(task, "logs", many: true, log, "task", many: false, deleteRule: .cascadeDeleteRule)

        let model = NSManagedObjectModel()
        model.entities = [household, plant, photo, event, task, log]
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
