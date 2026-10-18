import CoreData

// Hand-written NSManagedObject subclasses for the entities in GreenhouseModel.
// `@objc(Name)` pins the Objective-C class name so the model can find the class.
//
// The identifier attribute is `uuid`, not `id`: NSManagedObject already has an
// `id` (from Identifiable) that SwiftUI lists rely on.

enum PlantSetting: String, CaseIterable, Identifiable {
    case indoor, outdoor, seasonal

    var id: Self { self }

    var label: String {
        switch self {
        case .indoor: "Indoor"
        case .outdoor: "Outdoor"
        case .seasonal: "Moves seasonally"
        }
    }
}

/// Where a plant's light comes from.
enum LightSource: String, CaseIterable, Identifiable {
    case southWindow, eastWindow, westWindow, northWindow, skylight, growLight, awayFromWindows
    case fullSun, partShade, shade

    var id: Self { self }

    var label: String {
        switch self {
        case .southWindow: "South-facing window"
        case .eastWindow: "East-facing window"
        case .westWindow: "West-facing window"
        case .northWindow: "North-facing window"
        case .skylight: "Skylight"
        case .growLight: "Grow light"
        case .awayFromWindows: "Away from windows"
        case .fullSun: "Full sun outdoors"
        case .partShade: "Part shade outdoors"
        case .shade: "Shade outdoors"
        }
    }
}

enum PlantStatus: String {
    /// On the home screen.
    case active
    /// Combined into another plant; kept for history.
    case stapled
    /// Divided into new plants; kept for history.
    case split
}

enum LineageKind: String {
    case staple, split
}

enum IntervalUnit: String, CaseIterable, Identifiable {
    case day, week, month

    var id: Self { self }

    func label(count: Int) -> String {
        count == 1 ? rawValue : rawValue + "s"
    }
}

@objc(Household)
final class Household: NSManagedObject {
    @NSManaged var uuid: UUID?
    @NSManaged var name: String?
    @NSManaged var createdAt: Date?
    @NSManaged var zip: String?
    /// USDA hardiness zone, e.g. "7b". Not `zone`: NSObject already has a `zone` method that hides it.
    @NSManaged var hardinessZone: String?
    @NSManaged var plants: Set<Plant>?
    @NSManaged var tasks: Set<CareTask>?
    @NSManaged var lineageEvents: Set<LineageEvent>?
    @NSManaged var collections: Set<PlantCollection>?
    @NSManaged var wishlist: Set<WishlistItem>?
    @NSManaged var projects: Set<Project>?

    var sortedCollections: [PlantCollection] {
        (collections ?? []).sorted { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }
    }

    /// Name of the throwaway household the debug schema step shares and then
    /// deletes. Filtered out everywhere, so a leftover one never shows up.
    static let schemaCheckName = "Schema check (deleted automatically)"

    static func all() -> NSFetchRequest<Household> {
        let request = NSFetchRequest<Household>(entityName: "Household")
        request.predicate = NSPredicate(format: "name == nil OR name != %@", schemaCheckName)
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
        return request
    }
}

@objc(Plant)
final class Plant: NSManagedObject {
    @NSManaged var uuid: UUID?
    @NSManaged var scientificName: String?
    @NSManaged var commonName: String?
    @NSManaged var nickname: String?
    /// The SpeciesCatalog entry this plant was picked from; nil for a typed-in name.
    @NSManaged var catalogID: String?
    @NSManaged var acquiredDate: Date?
    @NSManaged var location: String?
    @NSManaged var lightSource: String?
    @NSManaged var coverPhotoID: UUID?
    @NSManaged var setting: String?
    @NSManaged var status: String?
    @NSManaged var createdAt: Date?
    @NSManaged var household: Household?
    @NSManaged var photos: Set<Photo>?
    @NSManaged var tasks: Set<CareTask>?
    /// The staple or split that created this plant, if any.
    @NSManaged var producedBy: LineageEvent?
    /// The staple or split that retired this plant, if any.
    @NSManaged var consumedBy: LineageEvent?
    @NSManaged var collections: Set<PlantCollection>?
    @NSManaged var projects: Set<Project>?
    @NSManaged var milestones: Set<Milestone>?

    var displayName: String {
        if let nickname, !nickname.trimmingCharacters(in: .whitespaces).isEmpty { return nickname }
        return commonName ?? scientificName ?? "Unnamed plant"
    }

    var settingValue: PlantSetting {
        get { PlantSetting(rawValue: setting ?? "") ?? .indoor }
        set { setting = newValue.rawValue }
    }

    var statusValue: PlantStatus {
        get { PlantStatus(rawValue: status ?? "") ?? .active }
        set { status = newValue.rawValue }
    }

    var isActive: Bool { statusValue == .active }

    var lightSourceValue: LightSource? {
        get { lightSource.flatMap(LightSource.init(rawValue:)) }
        set { lightSource = newValue?.rawValue }
    }

    var species: Species? { SpeciesCatalog.shared.species(id: catalogID) }

    /// Live care tasks, watering first.
    var activeTasks: [CareTask] {
        (tasks ?? []).filter { !$0.isArchived }.sorted {
            if $0.isWatering != $1.isWatering { return $0.isWatering }
            return ($0.name ?? "") < ($1.name ?? "")
        }
    }

    var wateringTask: CareTask? { activeTasks.first { $0.isWatering } }
}

@objc(Photo)
final class Photo: NSManagedObject {
    @NSManaged var uuid: UUID?
    @NSManaged var takenAt: Date?
    @NSManaged var caption: String?
    @NSManaged var imageData: Data?
    @NSManaged var plant: Plant?
}

/// Something that happened to a plant, written down by hand: a new pot, a
/// repot, its first bloom. Shown in the plant's History.
@objc(Milestone)
final class Milestone: NSManagedObject {
    @NSManaged var uuid: UUID?
    @NSManaged var title: String?
    @NSManaged var date: Date?
    @NSManaged var notes: String?
    @NSManaged var addedBy: String?
    @NSManaged var createdAt: Date?
    @NSManaged var plant: Plant?
}

@objc(LineageEvent)
final class LineageEvent: NSManagedObject {
    @NSManaged var uuid: UUID?
    @NSManaged var kind: String?
    @NSManaged var date: Date?
    @NSManaged var inputs: Set<Plant>?
    @NSManaged var outputs: Set<Plant>?
    @NSManaged var household: Household?

    var kindValue: LineageKind { LineageKind(rawValue: kind ?? "") ?? .staple }
}

@objc(CareTask)
final class CareTask: NSManagedObject {
    @NSManaged var uuid: UUID?
    @NSManaged var name: String?
    @NSManaged var intervalCount: Int64
    @NSManaged var intervalUnit: String?
    /// Due date until the first time it's done; after that, the last log decides.
    @NSManaged var firstDue: Date?
    @NSManaged var isWatering: Bool
    /// Retired by a staple or split; kept so its logs stay in history.
    @NSManaged var isArchived: Bool
    @NSManaged var createdAt: Date?
    /// Empty means a household-wide task, like "clean the grow lights".
    @NSManaged var plants: Set<Plant>?
    @NSManaged var logs: Set<CareLog>?
    @NSManaged var household: Household?

    var unit: IntervalUnit {
        get { IntervalUnit(rawValue: intervalUnit ?? "") ?? .day }
        set { intervalUnit = newValue.rawValue }
    }

    var lastLog: CareLog? { (logs ?? []).max { ($0.doneAt ?? .distantPast) < ($1.doneAt ?? .distantPast) } }

    /// Plants still on the home screen, sorted by name.
    var activePlants: [Plant] {
        (plants ?? []).filter(\.isActive).sorted { $0.displayName < $1.displayName }
    }

    /// False once every plant it was for has been stapled or split away.
    var isRelevant: Bool { (plants ?? []).isEmpty || !activePlants.isEmpty }

    var title: String {
        if isWatering {
            let names = activePlants.map(\.displayName)
            return names.isEmpty ? "Water" : "Water " + names.joined(separator: ", ")
        }
        return name ?? "Care task"
    }
}

@objc(CareLog)
final class CareLog: NSManagedObject {
    @NSManaged var uuid: UUID?
    @NSManaged var doneAt: Date?
    @NSManaged var doneBy: String?
    @NSManaged var task: CareTask?
}

/// A named group of plants, like "Succulents" or "Outdoor greenhouse". A plant
/// can be in several. Wishlist items and projects can belong to one, so each
/// collection has its own plans.
@objc(PlantCollection)
final class PlantCollection: NSManagedObject {
    @NSManaged var uuid: UUID?
    @NSManaged var name: String?
    @NSManaged var createdAt: Date?
    @NSManaged var household: Household?
    @NSManaged var plants: Set<Plant>?
    @NSManaged var wishlist: Set<WishlistItem>?
    @NSManaged var projects: Set<Project>?
}

/// A plant you'd like to get.
@objc(WishlistItem)
final class WishlistItem: NSManagedObject {
    @NSManaged var uuid: UUID?
    @NSManaged var scientificName: String?
    @NSManaged var commonName: String?
    @NSManaged var catalogID: String?
    @NSManaged var notes: String?
    @NSManaged var addedBy: String?
    @NSManaged var createdAt: Date?
    @NSManaged var household: Household?
    @NSManaged var collection: PlantCollection?

    var species: Species? { SpeciesCatalog.shared.species(id: catalogID) }
    var displayName: String { commonName ?? scientificName ?? "Unnamed plant" }
}

/// Something to build or do for the plants, like "spray paint a new greenhouse".
@objc(Project)
final class Project: NSManagedObject {
    @NSManaged var uuid: UUID?
    @NSManaged var title: String?
    @NSManaged var notes: String?
    @NSManaged var targetDate: Date?
    @NSManaged var isDone: Bool
    @NSManaged var doneAt: Date?
    @NSManaged var createdAt: Date?
    @NSManaged var household: Household?
    @NSManaged var collection: PlantCollection?
    @NSManaged var plants: Set<Plant>?
}

// Classes get `Identifiable` for free from their object identity, which is what
// SwiftUI lists and sheets need.
extension Household: Identifiable {}
extension Plant: Identifiable {}
extension Photo: Identifiable {}
extension Milestone: Identifiable {}
extension LineageEvent: Identifiable {}
extension CareTask: Identifiable {}
extension CareLog: Identifiable {}
extension PlantCollection: Identifiable {}
extension WishlistItem: Identifiable {}
extension Project: Identifiable {}
