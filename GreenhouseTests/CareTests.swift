import XCTest
@testable import Greenhouse

/// #4 recurring care reminders and #5 anniversaries.
final class CareTests: XCTestCase {
    func testStatusLabels() {
        let now = day(2026, 10, 17)
        XCTAssertEqual(CareSchedule.status(nextDue: day(2026, 10, 17, hour: 0), now: now).label, "Due today")
        XCTAssertEqual(CareSchedule.status(nextDue: day(2026, 10, 20), now: now).label, "In 3 days")
        XCTAssertEqual(CareSchedule.status(nextDue: day(2026, 10, 15), now: now).label, "Overdue by 2 days")
        XCTAssertEqual(CareSchedule.status(nextDue: day(2026, 10, 18), now: now).label, "Due tomorrow")
    }

    func testMarkingDoneMovesNextDueAndRecordsWho() {
        let store = TestStore()
        let plant = store.plant(acquired: day(2026, 10, 1), waterEvery: 7, now: day(2026, 10, 1))
        let watering = try! XCTUnwrap(plant.wateringTask)
        CareSchedule.markDone(watering, by: "Sam", at: day(2026, 10, 9),
                              household: store.household, context: store.context, persistence: store.persistence)
        store.save()

        XCTAssertEqual(watering.lastLog?.doneBy, "Sam")
        XCTAssertEqual(CareSchedule.nextDue(for: watering), Calendar.current.startOfDay(for: day(2026, 10, 16)))
    }

    func testQuarterlyCustomTaskNotificationText() {
        let store = TestStore()
        let aloe = store.plant(nickname: "Aloe", acquired: day(2026, 3, 26))
        let pothos = store.plant("epipremnum-aureum", nickname: "Pothos", acquired: day(2026, 4, 1))
        let task = CareSchedule.makeTask(name: "Hydrogen peroxide treatment", count: 3, unit: .month, firstDue: day(2026, 11, 1),
                                         plants: [pothos, aloe], household: store.household,
                                         context: store.context, persistence: store.persistence)
        XCTAssertEqual(NotificationPlanner.taskBody(task), "Time for your quarterly hydrogen peroxide treatment: Aloe, Pothos")

        CareSchedule.markDone(task, by: "Alex", at: day(2026, 11, 1), household: store.household,
                              context: store.context, persistence: store.persistence)
        XCTAssertEqual(CareSchedule.nextDue(for: task), Calendar.current.startOfDay(for: day(2027, 2, 1)))
    }

    func testHouseholdWideTask() {
        let store = TestStore()
        let task = CareSchedule.makeTask(name: "Clean grow lights", count: 1, unit: .month, firstDue: day(2026, 11, 1),
                                         plants: [], household: store.household,
                                         context: store.context, persistence: store.persistence)
        XCTAssertTrue(task.isRelevant)
        XCTAssertEqual(NotificationPlanner.taskBody(task), "Time for your monthly clean grow lights")
        let planned = NotificationPlanner.plan(household: store.household, now: day(2026, 10, 17))
        XCTAssertTrue(planned.contains { $0.body == "Time for your monthly clean grow lights" })
    }

    func testWateringNotificationsGroupByDayAndSkipPast() {
        let store = TestStore()
        store.plant(nickname: "Aloe", acquired: day(2026, 10, 1), waterEvery: 7, now: day(2026, 10, 10))
        store.plant(nickname: "Fern", acquired: day(2026, 10, 1), waterEvery: 7, now: day(2026, 10, 10))
        store.plant(nickname: "Cactus", acquired: day(2026, 10, 1), waterEvery: 3, now: day(2026, 10, 10)) // due Oct 13: already past

        let planned = NotificationPlanner.plan(household: store.household, now: day(2026, 10, 15), hour: 9)
        let watering = planned.filter { $0.id.hasPrefix("water-") }
        XCTAssertEqual(watering.map(\.body), ["Time to water Aloe, Fern"])
        XCTAssertEqual(Calendar.current.component(.hour, from: watering[0].date), 9)
    }

    func testWateringByOnePersonClearsTheReminderForBoth() {
        // Both phones plan from the same data, so once the log syncs the
        // other phone's next plan no longer has that day's reminder.
        let store = TestStore()
        let plant = store.plant(nickname: "Aloe", acquired: day(2026, 10, 1), waterEvery: 7, now: day(2026, 10, 10))
        let before = NotificationPlanner.plan(household: store.household, now: day(2026, 10, 16))
        XCTAssertTrue(before.contains { $0.body == "Time to water Aloe" && Calendar.current.isDate($0.date, inSameDayAs: day(2026, 10, 17)) })

        CareSchedule.markDone(try! XCTUnwrap(plant.wateringTask), by: "Sam", at: day(2026, 10, 16),
                              household: store.household, context: store.context, persistence: store.persistence)
        let after = NotificationPlanner.plan(household: store.household, now: day(2026, 10, 16))
        XCTAssertFalse(after.contains { Calendar.current.isDate($0.date, inSameDayAs: day(2026, 10, 17)) && $0.id.hasPrefix("water-") })
        XCTAssertTrue(after.contains { Calendar.current.isDate($0.date, inSameDayAs: day(2026, 10, 23)) && $0.id.hasPrefix("water-") })
    }

    func testStaplingMovesTasksAndArchivesOldWatering() {
        let store = TestStore()
        let a = store.plant(nickname: "A", acquired: day(2026, 3, 26), waterEvery: 21)
        let b = store.plant(nickname: "B", acquired: day(2026, 7, 24), waterEvery: 14)
        let treatment = CareSchedule.makeTask(name: "Hydrogen peroxide treatment", count: 3, unit: .month, firstDue: day(2026, 11, 1),
                                              plants: [a, b], household: store.household,
                                              context: store.context, persistence: store.persistence)
        let oldWatering = [a.wateringTask!, b.wateringTask!]

        let merged = Lineage.staple([a, b], nickname: "AB", date: day(2026, 10, 17),
                                    household: store.household, context: store.context, persistence: store.persistence)

        XCTAssertTrue(oldWatering.allSatisfy(\.isArchived))
        XCTAssertEqual(merged.wateringTask?.intervalCount, 14, "takes the shorter schedule")
        XCTAssertEqual(treatment.plants, [merged])
        let bodies = NotificationPlanner.plan(household: store.household, now: day(2026, 10, 17)).map(\.body)
        XCTAssertTrue(bodies.contains("Time to water AB"), bodies.joined(separator: "\n"))
        XCTAssertTrue(bodies.contains("Time for your quarterly hydrogen peroxide treatment: AB"))
        XCTAssertFalse(bodies.contains { $0 == "Time to water A" || $0 == "Time to water B" })
    }

    func testSplitHandsTasksToEveryChild() {
        let store = TestStore()
        let mother = store.plant(nickname: "Mom", acquired: day(2025, 5, 1), waterEvery: 7)
        let fertilize = CareSchedule.makeTask(name: "Fertilize", count: 1, unit: .month, firstDue: day(2026, 11, 1),
                                              plants: [mother], household: store.household,
                                              context: store.context, persistence: store.persistence)
        let kids = Lineage.split(mother, names: ["K1", "K2"], date: day(2026, 10, 17),
                                 household: store.household, context: store.context, persistence: store.persistence)
        XCTAssertEqual(fertilize.plants, Set(kids))
        XCTAssertTrue(kids.allSatisfy { $0.wateringTask?.intervalCount == 7 })
    }

    func testAnniversaryUsesEarliestAncestorAndNotesStaple() {
        let store = TestStore()
        let a = store.plant(nickname: "Aloe", acquired: day(2025, 3, 26))
        let b = store.plant(nickname: "Aloe 2", acquired: day(2025, 7, 24))
        let merged = Lineage.staple([a, b], nickname: "Aloe", date: day(2026, 1, 5),
                                    household: store.household, context: store.context, persistence: store.persistence)

        let note = try! XCTUnwrap(NotificationPlanner.nextAnniversary(of: merged, after: day(2026, 2, 1), hour: 9, minute: 0, calendar: .current))
        XCTAssertTrue(Calendar.current.isDate(note.date, inSameDayAs: day(2026, 3, 26)))
        XCTAssertEqual(note.body, "You've had Aloe for 1 year 🎉 (stapled together Jan 5, 2026)")
    }

    func testAnniversaryRollsToNextYearAndHandlesFutureDates() {
        let store = TestStore()
        let plant = store.plant(nickname: "Fern", acquired: day(2024, 6, 1))
        let note = try! XCTUnwrap(NotificationPlanner.nextAnniversary(of: plant, after: day(2026, 10, 17), hour: 9, minute: 0, calendar: .current))
        XCTAssertTrue(Calendar.current.isDate(note.date, inSameDayAs: day(2027, 6, 1)))
        XCTAssertEqual(note.body, "You've had Fern for 3 years 🎉")

        let future = store.plant(nickname: "Later", acquired: day(2030, 1, 1))
        XCTAssertNil(NotificationPlanner.nextAnniversary(of: future, after: day(2026, 10, 17), hour: 9, minute: 0, calendar: .current))
    }

    func testCadenceWords() {
        XCTAssertEqual(CareSchedule.cadence(count: 3, unit: .month), "quarterly")
        XCTAssertEqual(CareSchedule.cadence(count: 1, unit: .week), "weekly")
        XCTAssertEqual(CareSchedule.cadence(count: 5, unit: .week), "every 5 weeks")
    }
}
