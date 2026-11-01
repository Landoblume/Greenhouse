import CoreData
import XCTest
@testable import Greenhouse

/// v1.4: nested groups, archived collections, reminder instructions, snooze
/// and undoing a Done.
final class V14Tests: XCTestCase {
    private func collection(_ name: String, plants: [Plant] = [], parent: PlantCollection? = nil, in store: TestStore) -> PlantCollection {
        Collections.create(name: name, plants: plants, parent: parent, household: store.household,
                           context: store.context, persistence: store.persistence)
    }

    private func sod(_ date: Date) -> Date { Calendar.current.startOfDay(for: date) }

    // MARK: - Groups

    func testParentIncludesItsGroupsButAGroupOnlyItself() {
        let store = TestStore()
        let a = store.plant(nickname: "Break room plant", acquired: day(2026, 1, 1))
        let b = store.plant(nickname: "Office plant", acquired: day(2026, 1, 1))
        let business = collection("Business A", in: store)
        let breakRoom = collection("Break Room", plants: [a], parent: business, in: store)
        let office = collection("Office", plants: [b], parent: business, in: store)
        let project = Plans.addProject(title: "Shelves", notes: nil, targetDate: nil, plants: [], collection: office,
                                       household: store.household, context: store.context, persistence: store.persistence)

        XCTAssertTrue(Collections.contains(business, a))
        XCTAssertTrue(Collections.contains(business, b))
        XCTAssertTrue(Collections.contains(breakRoom, a))
        XCTAssertFalse(Collections.contains(breakRoom, b))
        XCTAssertTrue(Collections.contains(business, try! XCTUnwrap(a.wateringTask)))
        XCTAssertTrue(Collections.contains(business, project))
        XCTAssertFalse(Collections.contains(breakRoom, project))
        XCTAssertEqual(Collections.topLevel(in: store.household), [business])
        XCTAssertEqual(breakRoom.path, "Business A › Break Room")
    }

    func testNestingStopsAtOneLevel() {
        let store = TestStore()
        let top = collection("Top", in: store)
        let group = collection("Group", parent: top, in: store)
        let other = collection("Other", in: store)

        XCTAssertFalse(Collections.setParent(of: other, to: group), "a group can't hold groups")
        XCTAssertFalse(Collections.setParent(of: top, to: other), "a collection with groups can't become one")
        XCTAssertFalse(Collections.setParent(of: other, to: other))
        XCTAssertTrue(Collections.setParent(of: other, to: top))
        XCTAssertEqual(other.parent, top)
        XCTAssertTrue(Collections.setParent(of: other, to: nil))
        XCTAssertNil(other.parent)

        let nested = collection("Nested", parent: group, in: store)
        XCTAssertEqual(nested.parent, top, "a new group under a group lands beside it")
    }

    func testDeletingAParentKeepsItsGroupsAsCollections() {
        let store = TestStore()
        let top = collection("Top", in: store)
        let group = collection("Group", parent: top, in: store)
        store.save()

        Collections.delete(top, context: store.context)
        store.save()

        XCTAssertFalse(group.isDeleted)
        XCTAssertNil(group.parent)
        XCTAssertEqual(Collections.topLevel(in: store.household), [group])
    }

    func testMovingHouseholdsKeepsGroupsNested() {
        let store = TestStore()
        let target = store.persistence.createHousehold(name: "Joined", in: store.context)
        let top = collection("Top", in: store)
        _ = collection("Group", parent: top, in: store)
        store.plant(acquired: day(2026, 1, 1))
        store.save()

        HouseholdMerge.move(store.household, into: target, context: store.context, persistence: store.persistence)
        store.save()

        let copy = (target.collections ?? []).first { $0.name == "Group" }
        XCTAssertEqual(copy?.parent?.name, "Top")
        XCTAssertEqual(copy?.parent?.household, target)
    }

    // MARK: - Archive

    func testArchivedCollectionLeavesThePickersAndKeepsItsPlants() {
        let store = TestStore()
        let aloe = store.plant(acquired: day(2026, 1, 1))
        let old = collection("Old", plants: [aloe], in: store)
        let kept = collection("Kept", in: store)
        let id = old.uuid!.uuidString
        XCTAssertEqual(Collections.find(id, in: store.household), old)

        old.isArchived = true
        store.save()

        XCTAssertEqual(Collections.topLevel(in: store.household), [kept])
        XCTAssertEqual(Collections.pickable(in: store.household), [kept])
        XCTAssertEqual(Collections.pickable(in: store.household, keeping: old), [kept, old])
        XCTAssertEqual(Collections.archived(in: store.household), [old])
        XCTAssertNil(Collections.find(id, in: store.household), "a phone with it picked falls back to All")
        XCTAssertTrue(aloe.collections?.contains(old) == true)
        XCTAssertTrue(Collections.contains(nil, aloe))

        old.isArchived = false
        XCTAssertEqual(Collections.find(id, in: store.household), old)
    }

    func testArchivingAParentHidesItsGroupsAndAnArchivedGroupLeavesItsParent() {
        let store = TestStore()
        let aloe = store.plant(acquired: day(2026, 1, 1))
        let top = collection("Top", in: store)
        let group = collection("Group", plants: [aloe], parent: top, in: store)

        group.isArchived = true
        XCTAssertFalse(Collections.contains(top, aloe))
        XCTAssertEqual(Collections.archived(in: store.household), [group])
        group.isArchived = false

        top.isArchived = true
        XCTAssertNil(Collections.find(group.uuid!.uuidString, in: store.household))
        XCTAssertEqual(Collections.archived(in: store.household), [top], "the group comes back with its parent")
    }

    // MARK: - Instructions

    func testCombiningCarriesWateringInstructions() {
        let store = TestStore()
        let a = store.plant(nickname: "A", acquired: day(2026, 1, 1), waterEvery: 14)
        let b = store.plant(nickname: "B", acquired: day(2026, 1, 1), waterEvery: 7)
        a.wateringTask?.instructions = "Bottom-water"

        let merged = Lineage.staple([a, b], nickname: "AB", date: day(2026, 10, 1), household: store.household,
                                    context: store.context, persistence: store.persistence)

        XCTAssertEqual(merged.wateringTask?.instructions, "Bottom-water")
    }

    // MARK: - Snooze

    /// Waters every 7 days, due Sunday Oct 25, 2026.
    private func sundayWatering(_ store: TestStore) -> CareTask {
        let plant = store.plant(acquired: day(2026, 10, 18), waterEvery: 7, now: day(2026, 10, 18))
        return plant.wateringTask!
    }

    private func done(_ task: CareTask, at date: Date, keep: Bool = true, _ store: TestStore) {
        CareSchedule.markDone(task, by: "Sam", at: date, keepNewTiming: keep, household: store.household,
                              context: store.context, persistence: store.persistence)
    }

    func testSnoozeMovesTheDueDateAndTheNotification() {
        let store = TestStore()
        let task = sundayWatering(store)
        XCTAssertEqual(CareSchedule.nextDue(for: task), sod(day(2026, 10, 25)))

        CareSchedule.snooze(task, days: 2, now: day(2026, 10, 25))

        XCTAssertEqual(CareSchedule.nextDue(for: task), sod(day(2026, 10, 27)))
        XCTAssertEqual(CareSchedule.status(of: task, now: day(2026, 10, 25)), .upcoming(days: 2))
        let dates = NotificationPlanner.plan(household: store.household, now: day(2026, 10, 25)).filter { $0.id.hasPrefix("water-") }.map(\.date)
        XCTAssertEqual(dates.map(sod), [sod(day(2026, 10, 27))])
    }

    func testSnoozeCountsFromTodayWhenOverdueAndAddsUp() {
        let store = TestStore()
        let task = sundayWatering(store)
        CareSchedule.snooze(task, days: 1, now: day(2026, 10, 29))
        XCTAssertEqual(CareSchedule.nextDue(for: task), sod(day(2026, 10, 30)))
        CareSchedule.snooze(task, days: 1, now: day(2026, 10, 29))
        XCTAssertEqual(CareSchedule.nextDue(for: task), sod(day(2026, 10, 31)))
    }

    func testSundayToTuesdayKeepingTheNewDay() {
        let store = TestStore()
        let task = sundayWatering(store)
        CareSchedule.snooze(task, days: 2, now: day(2026, 10, 25))

        let choice = CareSchedule.snoozeChoice(for: task, doneAt: day(2026, 10, 27))
        XCTAssertEqual(choice?.title, "Keep Tuesdays going forward?")
        XCTAssertEqual(choice?.keepDue, sod(day(2026, 11, 3)))
        XCTAssertEqual(choice?.originalDue, sod(day(2026, 11, 1)))

        done(task, at: day(2026, 10, 27), keep: true, store)
        XCTAssertNil(task.snoozedUntil)
        XCTAssertEqual(CareSchedule.nextDue(for: task), sod(day(2026, 11, 3)))
        done(task, at: day(2026, 11, 3), store)
        XCTAssertEqual(CareSchedule.nextDue(for: task), sod(day(2026, 11, 10)), "stays on Tuesdays")
    }

    func testSundayToTuesdayAsAOneOffGoesBackToSundays() {
        let store = TestStore()
        let task = sundayWatering(store)
        CareSchedule.snooze(task, days: 2, now: day(2026, 10, 25))

        done(task, at: day(2026, 10, 27), keep: false, store)
        XCTAssertNil(task.snoozedUntil)
        XCTAssertEqual(CareSchedule.nextDue(for: task), sod(day(2026, 11, 1)))

        done(task, at: day(2026, 11, 1), store)
        XCTAssertNil(task.dueOverride)
        XCTAssertEqual(CareSchedule.nextDue(for: task), sod(day(2026, 11, 8)))
    }

    func testOneOffSnoozeNeverLandsInThePast() {
        let store = TestStore()
        let task = sundayWatering(store)
        CareSchedule.snooze(task, days: 2, now: day(2026, 10, 25))

        // Done long after: the original day has come around twice since.
        let choice = CareSchedule.snoozeChoice(for: task, doneAt: day(2026, 11, 9))
        XCTAssertEqual(choice?.originalDue, sod(day(2026, 11, 15)))
    }

    func testNoQuestionWhenThereIsNothingToChoose() {
        let store = TestStore()
        let task = sundayWatering(store)
        XCTAssertNil(CareSchedule.snoozeChoice(for: task), "not snoozed")

        CareSchedule.snooze(task, days: 2, now: day(2026, 10, 25))
        XCTAssertNil(CareSchedule.snoozeChoice(for: task, doneAt: day(2026, 10, 25)), "done on the original day anyway")

        let once = CareSchedule.makeTask(name: "Repot", count: 1, unit: .once, firstDue: day(2026, 10, 25), plants: [],
                                         household: store.household, context: store.context, persistence: store.persistence)
        CareSchedule.snooze(once, days: 2, now: day(2026, 10, 25))
        XCTAssertEqual(CareSchedule.nextDue(for: once), sod(day(2026, 10, 27)))
        XCTAssertNil(CareSchedule.snoozeChoice(for: once, doneAt: day(2026, 10, 27)))
    }

    func testChoiceTitleWhenTheIntervalIsNotWeekly() {
        let store = TestStore()
        let task = store.plant(acquired: day(2026, 10, 18), waterEvery: 5, now: day(2026, 10, 18)).wateringTask!
        CareSchedule.snooze(task, days: 1, now: day(2026, 10, 23))
        XCTAssertEqual(CareSchedule.snoozeChoice(for: task, doneAt: day(2026, 10, 24))?.title, "Keep this new timing?")
    }

    // MARK: - Undo

    func testUndoDoneRestoresTheDueDateTheSameDayOnly() {
        let store = TestStore()
        let task = sundayWatering(store)
        XCTAssertFalse(CareSchedule.canUndoDone(task, now: day(2026, 10, 25)), "nothing done yet")

        done(task, at: day(2026, 10, 25), store)
        store.save()
        XCTAssertEqual(CareSchedule.nextDue(for: task), sod(day(2026, 11, 1)))
        XCTAssertTrue(CareSchedule.canUndoDone(task, now: day(2026, 10, 25)))
        XCTAssertFalse(CareSchedule.canUndoDone(task, now: day(2026, 10, 26)))

        CareSchedule.undoDone(task, context: store.context)
        store.save()
        XCTAssertNil(task.lastLog)
        XCTAssertEqual(CareSchedule.nextDue(for: task), sod(day(2026, 10, 25)))
    }

    func testUndoFallsBackToTheEarlierLog() {
        let store = TestStore()
        let task = sundayWatering(store)
        done(task, at: day(2026, 10, 25), store)
        done(task, at: day(2026, 11, 1), store)
        store.save()

        CareSchedule.undoDone(task, context: store.context)
        store.save()
        XCTAssertEqual(CareSchedule.nextDue(for: task), sod(day(2026, 11, 1)))
    }

    func testOneTimeTaskCantBeUndone() {
        let store = TestStore()
        let once = CareSchedule.makeTask(name: "Repot", count: 1, unit: .once, firstDue: day(2026, 10, 25), plants: [],
                                         household: store.household, context: store.context, persistence: store.persistence)
        done(once, at: day(2026, 10, 25), store)
        XCTAssertFalse(CareSchedule.canUndoDone(once, now: day(2026, 10, 25)))
    }
}
