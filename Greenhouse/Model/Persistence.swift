import CloudKit
import CoreData

/// Owns the Core Data stack.
///
/// Two stores, both mirrored to the same iCloud container:
/// - **private**: households you created. Sharing one moves it into its own
///   CloudKit zone, still in your private database.
/// - **shared**: households someone else shared with you, which live in their
///   iCloud and show up here after you accept the invite.
///
/// A new object has to live in the same store as the household it belongs to
/// (relationships can't cross stores), which is what `insert(_:alongside:in:)`
/// takes care of.
final class Persistence {
    static let containerID = "iCloud.com.landenblume.greenhouse"

    /// Unit tests run inside the app, so the app's own stack must not touch
    /// iCloud or the on-disk stores when XCTest is loaded.
    static let isRunningTests = NSClassFromString("XCTestCase") != nil

    static let shared = Persistence(inMemory: isRunningTests)

    let container: NSPersistentContainer
    private(set) var privateStore: NSPersistentStore?
    private(set) var sharedStore: NSPersistentStore?
    private(set) var loadError: Error?

    var viewContext: NSManagedObjectContext { container.viewContext }
    var cloudKit: NSPersistentCloudKitContainer? { container as? NSPersistentCloudKitContainer }
    var ckContainer: CKContainer { CKContainer(identifier: Self.containerID) }

    init(inMemory: Bool) {
        if inMemory {
            container = NSPersistentContainer(name: "Greenhouse", managedObjectModel: GreenhouseModel.shared)
            let description = NSPersistentStoreDescription()
            description.type = NSInMemoryStoreType
            container.persistentStoreDescriptions = [description]
        } else {
            let cloudKit = NSPersistentCloudKitContainer(name: "Greenhouse", managedObjectModel: GreenhouseModel.shared)
            let directory = NSPersistentContainer.defaultDirectoryURL()
            cloudKit.persistentStoreDescriptions = [
                Self.storeDescription(url: directory.appendingPathComponent("private.sqlite"), scope: .private),
                Self.storeDescription(url: directory.appendingPathComponent("shared.sqlite"), scope: .shared),
            ]
            container = cloudKit
        }

        container.loadPersistentStores { [self] description, error in
            if let error {
                loadError = error
                print("Greenhouse: store failed to load: \(error)")
                return
            }
            guard let url = description.url,
                  let store = container.persistentStoreCoordinator.persistentStore(for: url) else { return }
            if description.cloudKitContainerOptions?.databaseScope == .shared {
                sharedStore = store
            } else {
                privateStore = store
            }
        }
        if inMemory { privateStore = container.persistentStoreCoordinator.persistentStores.first }

        // Changes synced in from the other phone land in a background context;
        // this merges them into the UI's context automatically.
        viewContext.automaticallyMergesChangesFromParent = true
        viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }

    private static func storeDescription(url: URL, scope: CKDatabase.Scope) -> NSPersistentStoreDescription {
        let description = NSPersistentStoreDescription(url: url)
        let options = NSPersistentCloudKitContainerOptions(containerIdentifier: containerID)
        options.databaseScope = scope
        description.cloudKitContainerOptions = options
        // Both required for CloudKit mirroring: a change log to sync from, and
        // a notification when the other phone's changes arrive.
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        return description
    }

    // MARK: - Households

    /// The household this phone works in. A shared one (you were invited) wins
    /// over one you started yourself, so accepting an invite switches you over.
    func pickHousehold(from households: [Household]) -> Household? {
        households.first { isShared($0) } ?? households.first
    }

    func currentHousehold(in context: NSManagedObjectContext) -> Household? {
        pickHousehold(from: (try? context.fetch(Household.all())) ?? [])
    }

    func isShared(_ object: NSManagedObject) -> Bool {
        guard let sharedStore else { return false }
        return object.objectID.persistentStore == sharedStore
    }

    @discardableResult
    func createHousehold(name: String, in context: NSManagedObjectContext) -> Household {
        let household = Household(entity: entityDescription(Household.self), insertInto: context)
        if let privateStore { context.assign(household, to: privateStore) }
        household.uuid = UUID()
        household.name = name
        household.createdAt = .now
        // Saved right away so it gets a permanent ID, which tells later inserts
        // which store to go to.
        save(context)
        return household
    }

    /// Inserts a new object into the same store as `household`.
    func insert<T: NSManagedObject>(_ type: T.Type, alongside household: Household, in context: NSManagedObjectContext) -> T {
        let object = T(entity: entityDescription(type), insertInto: context)
        if let store = household.objectID.persistentStore {
            context.assign(object, to: store)
        }
        return object
    }

    func save(_ context: NSManagedObjectContext) {
        guard context.hasChanges else { return }
        do {
            try context.save()
        } catch {
            print("Greenhouse: save failed: \(error)")
            context.rollback()
        }
    }

    private func entityDescription<T: NSManagedObject>(_ type: T.Type) -> NSEntityDescription {
        GreenhouseModel.shared.entitiesByName[String(describing: type)]!
    }

    // MARK: - CloudKit schema

    static let schemaStatusKey = "cloudKitSchemaStatus"

    /// TestFlight builds talk to CloudKit's Production environment, which only
    /// knows record types that were deployed from Development. This pushes the
    /// full schema to Development once, from a debug build on a signed-in
    /// phone; deploying it is a button in the CloudKit Console (see README).
    func initializeCloudKitSchemaIfNeeded(force: Bool = false) {
        #if DEBUG
        guard let cloudKit else { return }
        let defaults = UserDefaults.standard
        if !force, defaults.string(forKey: Self.schemaStatusKey)?.hasPrefix("Ready") == true { return }
        defaults.set("Uploading…", forKey: Self.schemaStatusKey)
        DispatchQueue.global(qos: .utility).async {
            do {
                try cloudKit.initializeCloudKitSchema(options: [])
                defaults.set("Ready (\(Date.now.formatted(date: .abbreviated, time: .shortened)))", forKey: Self.schemaStatusKey)
            } catch {
                // localizedDescription is just "A Core Data error occurred";
                // the useful part is in userInfo.
                let detail = "\(error as NSError)"
                print("Greenhouse: CloudKit schema setup failed: \(detail)")
                defaults.set("Failed: \(detail.prefix(500))", forKey: Self.schemaStatusKey)
            }
        }
        #endif
    }
}
