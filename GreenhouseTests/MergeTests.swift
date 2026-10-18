import CoreData
import XCTest
@testable import Greenhouse

/// v1.1: bringing your own plants into a household you joined.
final class MergeTests: XCTestCase {
    func testMovingCarriesPlantsPhotosTasksAndHistory() {
        let store = TestStore()
        let mine = store.household
        mine.hardinessZone = "7b"
        let joined = store.persistence.createHousehold(name: "Joined", in: store.context)

        let a = store.plant(nickname: "Aloe A", acquired: day(2026, 3, 26), photo: true)
        let b = store.plant(nickname: "Aloe B", acquired: day(2026, 7, 24), photo: true)
        a.lightSourceValue = .eastWindow
        let merged = Lineage.staple([a, b], nickname: "Big aloe", date: day(2026, 9, 1),
                                    household: mine, context: store.context, persistence: store.persistence)
        CareSchedule.markDone(try! XCTUnwrap(merged.wateringTask), by: "Sam", at: day(2026, 9, 5),
                              household: mine, context: store.context, persistence: store.persistence)
        CareSchedule.makeTask(name: "Fertilize", count: 1, unit: .month, firstDue: day(2026, 10, 1),
                              plants: [merged], household: mine, context: store.context, persistence: store.persistence)
        store.save()

        let shown = HouseholdMerge.move(mine, into: joined, context: store.context, persistence: store.persistence)
        store.save()

        XCTAssertEqual(shown, 1, "only the stapled plant is on the home screen")
        XCTAssertTrue(mine.isDeleted || mine.managedObjectContext == nil)
        let plants = Array(joined.plants ?? [])
        XCTAssertEqual(plants.count, 3)
        let bigAloe = try! XCTUnwrap(plants.first { $0.displayName == "Big aloe" })
        XCTAssertEqual(Set(Lineage.parents(of: bigAloe).map(\.displayName)), ["Aloe A", "Aloe B"])
        XCTAssertEqual(Lineage.timeline(for: bigAloe).count, 2, "originals' photos still show")
        XCTAssertEqual(plants.first { $0.displayName == "Aloe A" }?.lightSourceValue, .eastWindow)
        XCTAssertEqual(bigAloe.wateringTask?.lastLog?.doneBy, "Sam")
        XCTAssertEqual(bigAloe.activeTasks.map(\.title).sorted(), ["Fertilize", "Water Big aloe"])
        XCTAssertEqual(joined.hardinessZone, "7b", "adopts the zone when the joined household has none")
        XCTAssertEqual(store.persistence.currentHousehold(in: store.context), joined)
    }

    func testMovingCarriesCollectionsWishlistAndProjects() throws {
        let store = TestStore()
        let mine = store.household
        let joined = store.persistence.createHousehold(name: "Joined", in: store.context)
        let aloe = store.plant(nickname: "Aloe", acquired: day(2026, 3, 1))
        let group = Collections.create(name: "Succulents", plants: [aloe], household: mine,
                                       context: store.context, persistence: store.persistence)
        Plans.addWish(species: nil, scientificName: "Haworthia", notes: nil, by: "Sam", collection: group,
                      household: mine, context: store.context, persistence: store.persistence)
        Plans.addProject(title: "Repot", notes: nil, targetDate: nil, plants: [aloe], collection: group,
                         household: mine, context: store.context, persistence: store.persistence)
        store.save()

        HouseholdMerge.move(mine, into: joined, context: store.context, persistence: store.persistence)
        store.save()

        let movedGroup = try XCTUnwrap(joined.collections?.first)
        XCTAssertEqual(movedGroup.name, "Succulents")
        XCTAssertEqual(movedGroup.plants?.map(\.displayName), ["Aloe"])
        XCTAssertEqual(joined.wishlist?.first?.collection, movedGroup)
        let project = try XCTUnwrap(joined.projects?.first)
        XCTAssertEqual(project.collection, movedGroup)
        XCTAssertEqual(project.plants?.map(\.displayName), ["Aloe"])
        XCTAssertTrue(group.isDeleted || group.managedObjectContext == nil)
    }

    func testOnlyOwnNonEmptyHouseholdsAreOffered() {
        let store = TestStore()
        let joined = store.persistence.createHousehold(name: "Joined", in: store.context)
        let empty = store.persistence.createHousehold(name: "Empty", in: store.context)
        XCTAssertTrue(HouseholdMerge.candidates(for: joined, in: [store.household, joined, empty], persistence: store.persistence).isEmpty)

        store.plant(acquired: day(2026, 1, 1))
        XCTAssertEqual(HouseholdMerge.candidates(for: joined, in: [store.household, joined, empty], persistence: store.persistence),
                       [store.household])
        XCTAssertTrue(HouseholdMerge.candidates(for: store.household, in: [store.household], persistence: store.persistence).isEmpty)
    }
}
