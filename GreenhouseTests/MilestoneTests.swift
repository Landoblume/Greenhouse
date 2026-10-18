import CoreData
import XCTest
@testable import Greenhouse

/// Milestones written into a plant's History.
final class MilestoneTests: XCTestCase {
    func testAddingAndEditingAMilestone() throws {
        let store = TestStore()
        let aloe = store.plant(acquired: day(2026, 3, 1))
        let milestone = Milestones.add(title: " New pot ", date: day(2026, 4, 2), notes: "  ", by: "Sam", to: aloe,
                                       household: store.household, context: store.context, persistence: store.persistence)
        store.save()

        XCTAssertEqual(milestone.title, "New pot")
        XCTAssertNil(milestone.notes)
        XCTAssertEqual(milestone.addedBy, "Sam")
        XCTAssertEqual(Milestones.history(for: aloe).map(\.milestone), [milestone])

        Milestones.update(milestone, title: "Terracotta pot", date: day(2026, 4, 3), notes: "From the nursery")
        XCTAssertEqual(milestone.title, "Terracotta pot")
        XCTAssertEqual(milestone.notes, "From the nursery")
    }

    func testCombinedPlantShowsItsOriginalsMilestonesOldestFirst() {
        let store = TestStore()
        let march = store.plant(acquired: day(2026, 3, 1))
        let july = store.plant(acquired: day(2026, 7, 1))
        let bloom = Milestones.add(title: "First bloom", date: day(2026, 8, 1), notes: nil, by: "Sam", to: july,
                                   household: store.household, context: store.context, persistence: store.persistence)
        let pot = Milestones.add(title: "New pot", date: day(2026, 4, 1), notes: nil, by: "Sam", to: march,
                                 household: store.household, context: store.context, persistence: store.persistence)
        let merged = Lineage.staple([march, july], nickname: nil, date: day(2026, 9, 1), household: store.household,
                                    context: store.context, persistence: store.persistence)
        let repot = Milestones.add(title: "Repotted", date: day(2026, 9, 2), notes: nil, by: "Sam", to: merged,
                                   household: store.household, context: store.context, persistence: store.persistence)
        store.save()

        let history = Milestones.history(for: merged)
        XCTAssertEqual(history.map(\.milestone), [pot, bloom, repot])
        XCTAssertEqual(history.map(\.source), [march, july, merged])
    }

    func testDeletingAPlantDeletesItsMilestones() {
        let store = TestStore()
        let aloe = store.plant(acquired: day(2026, 3, 1))
        Milestones.add(title: "New pot", date: day(2026, 4, 1), notes: nil, by: "Sam", to: aloe,
                       household: store.household, context: store.context, persistence: store.persistence)
        store.save()

        Lineage.delete(aloe, context: store.context)
        store.save()

        let count = try? store.context.count(for: NSFetchRequest<Milestone>(entityName: "Milestone"))
        XCTAssertEqual(count, 0)
    }

    func testMovingHouseholdsBringsMilestones() throws {
        let store = TestStore()
        let joined = store.persistence.createHousehold(name: "Joined", in: store.context)
        let aloe = store.plant(nickname: "Aloe", acquired: day(2026, 3, 1))
        Milestones.add(title: "New pot", date: day(2026, 4, 1), notes: "Blue glaze", by: "Sam", to: aloe,
                       household: store.household, context: store.context, persistence: store.persistence)
        store.save()

        HouseholdMerge.move(store.household, into: joined, context: store.context, persistence: store.persistence)
        store.save()

        let moved = try XCTUnwrap(joined.plants?.first)
        XCTAssertEqual(moved.milestones?.map(\.title), ["New pot"])
        XCTAssertEqual(moved.milestones?.first?.notes, "Blue glaze")
    }

    // MARK: Photos linked to milestones

    func testNewMilestoneFromAPhotoTakesThePhotosDate() throws {
        let store = TestStore()
        let aloe = store.plant(acquired: day(2026, 3, 1))
        let photo = PlantFactory.addPhoto(Data([1]), takenAt: day(2026, 5, 4), to: aloe, household: store.household,
                                          context: store.context, persistence: store.persistence)

        let made = try XCTUnwrap(Milestones.attach(photo, to: .new(title: "First bloom"), by: "Sam", plant: aloe,
                                                   household: store.household, context: store.context, persistence: store.persistence))
        store.save()

        XCTAssertEqual(made.title, "First bloom")
        XCTAssertEqual(made.date, day(2026, 5, 4))
        XCTAssertEqual(made.plant, aloe)
        XCTAssertEqual(Milestones.photos(of: made), [photo])
    }

    func testLinkingUnlinkingAndBlankNewTitle() {
        let store = TestStore()
        let aloe = store.plant(acquired: day(2026, 3, 1))
        let pot = Milestones.add(title: "New pot", date: day(2026, 4, 1), notes: nil, by: "Sam", to: aloe,
                                 household: store.household, context: store.context, persistence: store.persistence)
        let photo = PlantFactory.addPhoto(Data([1]), takenAt: day(2026, 4, 1), to: aloe, household: store.household,
                                          context: store.context, persistence: store.persistence)
        func attach(_ choice: Milestones.Choice) {
            Milestones.attach(photo, to: choice, by: "Sam", plant: aloe, household: store.household,
                              context: store.context, persistence: store.persistence)
        }

        attach(.existing(pot))
        XCTAssertEqual(photo.milestone, pot)
        attach(.none)
        XCTAssertNil(photo.milestone)
        attach(.new(title: "   "))
        XCTAssertNil(photo.milestone)
        XCTAssertEqual(aloe.milestones?.count, 1, "a blank title makes no milestone")
    }

    func testDeletingAMilestoneKeepsItsPhotos() {
        let store = TestStore()
        let aloe = store.plant(acquired: day(2026, 3, 1))
        let photo = PlantFactory.addPhoto(Data([1]), takenAt: day(2026, 4, 1), to: aloe, household: store.household,
                                          context: store.context, persistence: store.persistence)
        let pot = Milestones.attach(photo, to: .new(title: "New pot"), by: "Sam", plant: aloe, household: store.household,
                                    context: store.context, persistence: store.persistence)
        store.save()

        store.context.delete(pot!)
        store.save()

        XCTAssertEqual(aloe.photos, [photo])
        XCTAssertNil(photo.milestone)
    }

    func testMovingHouseholdsKeepsPhotoLinks() throws {
        let store = TestStore()
        let joined = store.persistence.createHousehold(name: "Joined", in: store.context)
        let aloe = store.plant(nickname: "Aloe", acquired: day(2026, 3, 1))
        let photo = PlantFactory.addPhoto(Data([1]), takenAt: day(2026, 4, 1), to: aloe, household: store.household,
                                          context: store.context, persistence: store.persistence)
        Milestones.attach(photo, to: .new(title: "New pot"), by: "Sam", plant: aloe, household: store.household,
                          context: store.context, persistence: store.persistence)
        store.save()

        HouseholdMerge.move(store.household, into: joined, context: store.context, persistence: store.persistence)
        store.save()

        let moved = try XCTUnwrap(joined.plants?.first)
        let movedPhoto = try XCTUnwrap(moved.photos?.first)
        XCTAssertEqual(movedPhoto.milestone?.title, "New pot")
        XCTAssertEqual(movedPhoto.milestone?.plant, moved)
    }

    // MARK: Quick picks

    func testQuickPicksIncludeCombinedAndCanBeChangedWithoutTouchingSavedMilestones() {
        let store = TestStore()
        let aloe = store.plant(acquired: day(2026, 3, 1))
        XCTAssertTrue(Milestones.suggestions(for: store.household).contains("Combined"))
        let pot = Milestones.add(title: "New pot", date: day(2026, 4, 1), notes: nil, by: "Sam", to: aloe,
                                 household: store.household, context: store.context, persistence: store.persistence)

        Milestones.setSuggestions(["Terracotta pot", "  ", "Combined"], for: store.household)
        XCTAssertEqual(Milestones.suggestions(for: store.household), ["Terracotta pot", "Combined"])
        XCTAssertEqual(pot.title, "New pot")

        Milestones.setSuggestions(Milestones.defaultSuggestions, for: store.household)
        XCTAssertNil(store.household.milestoneSuggestions, "the original list is stored as nothing, so future defaults apply")
    }
}
