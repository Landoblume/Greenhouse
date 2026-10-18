import CoreData
import XCTest
@testable import Greenhouse

/// #1: the parts of sharing that can run without iCloud. The invite and sync
/// itself needs two real phones (see README → Testing sharing).
final class HouseholdTests: XCTestCase {
    func testModelFollowsCloudKitRules() {
        for entity in GreenhouseModel.shared.entities {
            for (name, attribute) in entity.attributesByName {
                XCTAssertTrue(attribute.isOptional || attribute.defaultValue != nil, "\(entity.name!).\(name)")
            }
            for (name, relationship) in entity.relationshipsByName {
                XCTAssertTrue(relationship.isOptional, "\(entity.name!).\(name)")
                XCTAssertNotNil(relationship.inverseRelationship, "\(entity.name!).\(name) needs an inverse")
                XCTAssertNotEqual(relationship.deleteRule, .denyDeleteRule, "\(entity.name!).\(name)")
                XCTAssertFalse(relationship.isOrdered, "\(entity.name!).\(name)")
            }
            XCTAssertTrue(entity.uniquenessConstraints.isEmpty, entity.name!)
        }
    }

    func testEverythingLandsInTheHouseholdsStore() {
        let store = TestStore()
        let plant = store.plant(acquired: day(2026, 3, 26), photo: true)
        let householdStore = store.household.objectID.persistentStore
        XCTAssertNotNil(householdStore)
        XCTAssertEqual(plant.objectID.persistentStore, householdStore)
        XCTAssertEqual(plant.photos?.first?.objectID.persistentStore, householdStore)
        XCTAssertEqual(plant.wateringTask?.objectID.persistentStore, householdStore)
    }

    func testCurrentHouseholdIsFoundAfterCreation() {
        let store = TestStore()
        XCTAssertEqual(store.persistence.currentHousehold(in: store.context), store.household)
    }
}
