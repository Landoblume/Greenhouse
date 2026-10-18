import CoreData
import XCTest
@testable import Greenhouse

/// v1.2: collections, the wishlist and projects.
final class CollectionTests: XCTestCase {
    func testCollectionsFilterPlantsCareAndPlans() throws {
        let store = TestStore()
        let aloe = store.plant(nickname: "Aloe", acquired: day(2026, 1, 1))
        let fern = store.plant("nephrolepis-exaltata", nickname: "Fern", acquired: day(2026, 1, 1))
        let succulents = Collections.create(name: " Succulents ", plants: [aloe], household: store.household,
                                            context: store.context, persistence: store.persistence)
        XCTAssertEqual(succulents.name, "Succulents")
        let chore = CareSchedule.makeTask(name: "Clean grow lights", count: 1, unit: .month, firstDue: day(2026, 2, 1),
                                          plants: [], household: store.household, context: store.context, persistence: store.persistence)
        let wish = Plans.addWish(species: nil, scientificName: "Haworthia", notes: nil, by: "Sam", collection: succulents,
                                 household: store.household, context: store.context, persistence: store.persistence)
        let project = Plans.addProject(title: "Paint greenhouse", notes: nil, targetDate: nil, plants: [], collection: nil,
                                       household: store.household, context: store.context, persistence: store.persistence)
        store.save()

        XCTAssertTrue(Collections.contains(succulents, aloe))
        XCTAssertFalse(Collections.contains(succulents, fern))
        XCTAssertTrue(Collections.contains(nil, fern), "All shows everything")
        XCTAssertTrue(Collections.contains(succulents, try XCTUnwrap(aloe.wateringTask)))
        XCTAssertFalse(Collections.contains(succulents, try XCTUnwrap(fern.wateringTask)))
        XCTAssertFalse(Collections.contains(succulents, chore), "household-wide chores only show under All")
        XCTAssertTrue(Collections.contains(succulents, wish))
        XCTAssertFalse(Collections.contains(succulents, project))
        XCTAssertEqual(Collections.find(succulents.uuid!.uuidString, in: store.household), succulents)
        XCTAssertNil(Collections.find("nope", in: store.household))
    }

    func testDeletingACollectionKeepsItsPlantsAndPlans() {
        let store = TestStore()
        let aloe = store.plant(acquired: day(2026, 1, 1))
        let group = Collections.create(name: "Desk", plants: [aloe], household: store.household,
                                       context: store.context, persistence: store.persistence)
        let wish = Plans.addWish(species: nil, scientificName: "Hoya", notes: nil, by: "", collection: group,
                                 household: store.household, context: store.context, persistence: store.persistence)
        store.save()

        Collections.delete(group, context: store.context)
        store.save()

        XCTAssertFalse(aloe.isDeleted)
        XCTAssertEqual(aloe.collections?.count, 0)
        XCTAssertFalse(wish.isDeleted)
        XCTAssertNil(wish.collection)
    }

    func testStapleAndSplitKeepCollections() {
        let store = TestStore()
        let a = store.plant(nickname: "A", acquired: day(2026, 1, 1))
        let b = store.plant(nickname: "B", acquired: day(2026, 2, 1))
        a.lightSourceValue = .southWindow
        let indoor = Collections.create(name: "Indoor", plants: [a], household: store.household,
                                        context: store.context, persistence: store.persistence)
        let gifts = Collections.create(name: "Gifts", plants: [b], household: store.household,
                                       context: store.context, persistence: store.persistence)
        let merged = Lineage.staple([a, b], nickname: "AB", household: store.household,
                                    context: store.context, persistence: store.persistence)
        XCTAssertEqual(merged.collections, [indoor, gifts])
        XCTAssertEqual(merged.lightSourceValue, .southWindow)

        let pieces = Lineage.split(merged, names: ["X", "Y"], household: store.household,
                                   context: store.context, persistence: store.persistence)
        XCTAssertTrue(pieces.allSatisfy { $0.collections == [indoor, gifts] })
    }

    func testFulfillingAWishFilesThePlantAndClearsTheWish() {
        let store = TestStore()
        let group = Collections.create(name: "Orchids", household: store.household,
                                       context: store.context, persistence: store.persistence)
        let species = SpeciesCatalog.shared.species(id: "aloe-vera")
        let wish = Plans.addWish(species: species, scientificName: "", notes: " near the window ", by: "Sam",
                                 collection: group, household: store.household, context: store.context, persistence: store.persistence)
        XCTAssertEqual(wish.scientificName, species?.latin)
        XCTAssertEqual(wish.notes, "near the window")
        XCTAssertEqual(wish.addedBy, "Sam")
        store.save()

        let plant = store.plant(acquired: day(2026, 10, 17))
        Plans.fulfill(wish, with: plant, context: store.context)
        store.save()

        XCTAssertTrue(plant.collections?.contains(group) == true)
        XCTAssertEqual(store.household.wishlist?.count, 0)
    }

    func testProjectsSortOpenBySoonestThenDone() {
        let store = TestStore()
        func project(_ title: String, target: Date?) -> Project {
            Plans.addProject(title: title, notes: nil, targetDate: target, plants: [], collection: nil,
                             household: store.household, context: store.context, persistence: store.persistence)
        }
        let someday = project("Someday", target: nil)
        let later = project("Later", target: day(2026, 12, 1))
        let soon = project("Soon", target: day(2026, 11, 1))
        let done = project("Done", target: day(2026, 10, 1))
        Plans.setDone(done, true, at: day(2026, 10, 2))
        XCTAssertEqual(Plans.sorted([someday, later, done, soon]), [soon, later, someday, done])

        Plans.setDone(done, false)
        XCTAssertNil(done.doneAt)
    }

    func testProjectStatesAndInProgressFirst() {
        let store = TestStore()
        let fern = store.plant("nephrolepis-exaltata", acquired: day(2026, 3, 1))
        let aloe = store.plant(acquired: day(2026, 3, 1))
        let soon = Plans.addProject(title: "Soon", notes: nil, targetDate: day(2026, 11, 1), plants: [aloe], collection: nil,
                                    household: store.household, context: store.context, persistence: store.persistence)
        let paint = Plans.addProject(title: "Paint", notes: nil, targetDate: nil, plants: [fern], collection: nil,
                                     household: store.household, context: store.context, persistence: store.persistence)
        XCTAssertEqual(Plans.state(of: paint), .planned)
        XCTAssertFalse(Plans.isInActiveProject(fern))

        Plans.setState(paint, .inProgress, at: day(2026, 10, 10))
        XCTAssertEqual(Plans.state(of: paint), .inProgress)
        XCTAssertTrue(Plans.isInActiveProject(fern))
        XCTAssertFalse(Plans.isInActiveProject(aloe))
        XCTAssertEqual(Plans.sorted([soon, paint]), [paint, soon], "in progress comes before planned")

        Plans.setState(paint, .inProgress, at: day(2026, 10, 20))
        XCTAssertEqual(paint.startedAt, day(2026, 10, 10), "re-picking In progress keeps the start")

        Plans.setState(paint, .done, at: day(2026, 10, 25))
        XCTAssertEqual(Plans.state(of: paint), .done)
        XCTAssertEqual(paint.startedAt, day(2026, 10, 10))
        XCTAssertFalse(Plans.isInActiveProject(fern))

        Plans.setState(paint, .planned)
        XCTAssertNil(paint.startedAt)
        XCTAssertNil(paint.doneAt)
    }
}
