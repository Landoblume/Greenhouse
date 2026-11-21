import CoreData
import XCTest
@testable import Greenhouse

/// v1.5: a weekly nudge to photograph plants nobody has photographed in a while.
final class PhotoNudgeTests: XCTestCase {
    private let calendar = Calendar.current

    private func checkIns(_ planned: [PlannedNotification]) -> [PlannedNotification] {
        planned.filter { $0.id.hasPrefix(NotificationPlanner.photoCheckInPrefix) }
    }

    private func addPhoto(_ store: TestStore, to plant: Plant, takenAt: Date) {
        PlantFactory.addPhoto(Data([1]), takenAt: takenAt, to: plant, household: store.household,
                              context: store.context, persistence: store.persistence)
        store.save()
    }

    // MARK: N1: the setting

    func testSettingDefaultsToSixMonthsAndPersists() throws {
        let suite = "PhotoNudgeTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertEqual(NotificationPlanner.photoCheckInMonths(in: defaults), 6, "on by default")
        defaults.set(2, forKey: NotificationPlanner.photoCheckInKey)
        XCTAssertEqual(NotificationPlanner.photoCheckInMonths(in: defaults), 2)
        defaults.set(0, forKey: NotificationPlanner.photoCheckInKey)
        XCTAssertEqual(NotificationPlanner.photoCheckInMonths(in: defaults), 0, "Off is stored, not reset to the default")
        XCTAssertEqual(NotificationPlanner.photoCheckInOptions, [0, 2, 3, 6])
    }

    // MARK: N2: when and what

    func testStalePhotoNudgesAtTheReminderTime() throws {
        let store = TestStore()
        let plant = store.plant(nickname: "Aloe", acquired: day(2026, 1, 10))
        addPhoto(store, to: plant, takenAt: day(2026, 3, 15))

        let planned = NotificationPlanner.plan(household: store.household, now: day(2026, 10, 1), hour: 8, minute: 30,
                                               photoCheckInMonths: 6, calendar: calendar)
        let first = try XCTUnwrap(checkIns(planned).first)
        XCTAssertEqual(first.body, "Haven't seen Aloe in a while, how's it coming? 📸")
        XCTAssertEqual(first.plantID, plant.uuid)
        XCTAssertTrue(first.id.hasPrefix("photo-\(plant.uuid!.uuidString)-"))
        XCTAssertEqual(calendar.component(.hour, from: first.date), 8)
        XCTAssertEqual(calendar.component(.minute, from: first.date), 30)
        // Threshold Sep 15, then weekly: Sep 22, 29, Oct 6 is the first one after now.
        XCTAssertTrue(calendar.isDate(first.date, inSameDayAs: day(2026, 10, 6)))
    }

    func testNewestPhotoByTakenAtIsTheStartingPoint() throws {
        let store = TestStore()
        let plant = store.plant(nickname: "Aloe", acquired: day(2026, 1, 10))
        addPhoto(store, to: plant, takenAt: day(2026, 8, 1))
        addPhoto(store, to: plant, takenAt: day(2026, 2, 1))  // added later, dated earlier from the library

        let planned = NotificationPlanner.plan(household: store.household, now: day(2026, 9, 1), photoCheckInMonths: 2)
        let first = try XCTUnwrap(checkIns(planned).first)
        XCTAssertTrue(calendar.isDate(first.date, inSameDayAs: day(2026, 10, 1)), "Aug 1 + 2 months")
    }

    func testRecentPhotoMeansNoNudgeYet() throws {
        let store = TestStore()
        let plant = store.plant(nickname: "Aloe", acquired: day(2026, 1, 10))
        addPhoto(store, to: plant, takenAt: day(2026, 9, 20))
        let planned = NotificationPlanner.plan(household: store.household, now: day(2026, 10, 1), photoCheckInMonths: 6)
        // Slots are free, so it's planned ahead, but not before Sep 20 + 6 months.
        let first = try XCTUnwrap(checkIns(planned).first)
        XCTAssertTrue(calendar.isDate(first.date, inSameDayAs: day(2027, 3, 20)))
    }

    func testNoPhotosStartsFromAcquiredDate() throws {
        let store = TestStore()
        store.plant(nickname: "Fern", acquired: day(2026, 4, 1))
        let planned = NotificationPlanner.plan(household: store.household, now: day(2026, 6, 15), photoCheckInMonths: 3)
        let first = try XCTUnwrap(checkIns(planned).first)
        XCTAssertTrue(calendar.isDate(first.date, inSameDayAs: day(2026, 7, 1)), "Apr 1 + 3 months")
        XCTAssertEqual(first.body, "Haven't seen Fern in a while, how's it coming? 📸")
    }

    func testNoPhotosAndNoAcquiredDateFallsBackToCreatedAt() throws {
        let store = TestStore()
        let plant = store.plant(nickname: "Fern", acquired: day(2026, 4, 1))
        plant.acquiredDate = nil
        plant.createdAt = day(2026, 5, 1)
        store.save()
        let planned = NotificationPlanner.plan(household: store.household, now: day(2026, 6, 15), photoCheckInMonths: 2)
        let first = try XCTUnwrap(checkIns(planned).first)
        XCTAssertTrue(calendar.isDate(first.date, inSameDayAs: day(2026, 7, 1)), "May 1 + 2 months")
    }

    func testOffPlansNoCheckIns() {
        let store = TestStore()
        store.plant(nickname: "Fern", acquired: day(2025, 1, 1))
        let planned = NotificationPlanner.plan(household: store.household, now: day(2026, 10, 1), photoCheckInMonths: 0)
        XCTAssertTrue(checkIns(planned).isEmpty)
    }

    func testInactivePlantsAreNotNudged() {
        let store = TestStore()
        let plant = store.plant(nickname: "Fern", acquired: day(2025, 1, 1))
        plant.statusValue = .stapled
        store.save()
        let planned = NotificationPlanner.plan(household: store.household, now: day(2026, 10, 1), photoCheckInMonths: 2)
        XCTAssertTrue(checkIns(planned).isEmpty)
    }

    // MARK: N3: weekly, deterministic, stops after a newer photo

    func testRepeatsWeeklyNeverDaily() {
        let store = TestStore()
        store.plant(nickname: "Fern", acquired: day(2025, 1, 1))
        let planned = checkIns(NotificationPlanner.plan(household: store.household, now: day(2026, 10, 1), photoCheckInMonths: 2))
        XCTAssertGreaterThan(planned.count, 1)
        for (a, b) in zip(planned, planned.dropFirst()) {
            XCTAssertEqual(calendar.dateComponents([.day], from: a.date, to: b.date).day, 7)
        }
    }

    func testScheduleIsTheSameWhicheverDayItIsPlanned() {
        // Threshold Mar 1, 2025 (Jan 1 + 2 months), then whole weeks from it,
        // whatever day the plan is made, so both phones and every reschedule agree.
        let store = TestStore()
        store.plant(nickname: "Fern", acquired: day(2025, 1, 1))
        let threshold = calendar.startOfDay(for: day(2025, 3, 1))
        let tuesday = checkIns(NotificationPlanner.plan(household: store.household, now: day(2026, 10, 6), photoCheckInMonths: 2))
        let weekLater = checkIns(NotificationPlanner.plan(household: store.household, now: day(2026, 10, 13), photoCheckInMonths: 2))
        let thursday = checkIns(NotificationPlanner.plan(household: store.household, now: day(2026, 10, 8), photoCheckInMonths: 2))

        for item in tuesday + weekLater + thursday {
            let days = calendar.dateComponents([.day], from: threshold, to: calendar.startOfDay(for: item.date)).day ?? -1
            XCTAssertEqual(days % 7, 0, "\(item.date) is not a whole number of weeks from the threshold")
        }
        XCTAssertEqual(tuesday.map(\.id), thursday.map(\.id), "same nudges planned mid-week")
        XCTAssertEqual(Set(tuesday.map(\.id)).intersection(weekLater.map(\.id)).count, tuesday.count - 1,
                       "a week on, the same ids minus the one that fired, so a reschedule doesn't duplicate them")
    }

    func testANewerPhotoStopsTheNudges() {
        let store = TestStore()
        let plant = store.plant(nickname: "Fern", acquired: day(2025, 1, 1))
        let now = day(2026, 10, 1)
        XCTAssertFalse(checkIns(NotificationPlanner.plan(household: store.household, now: now, photoCheckInMonths: 2)).isEmpty)

        // The other phone's photo syncs in; the next plan has nothing soon.
        addPhoto(store, to: plant, takenAt: day(2026, 9, 30))
        let after = checkIns(NotificationPlanner.plan(household: store.household, now: now, photoCheckInMonths: 2))
        XCTAssertTrue(after.allSatisfy { $0.date >= day(2026, 11, 30, hour: 0) })
    }

    // MARK: N5: only leftover slots

    func testCheckInsFillOnlyLeftoverSlots() {
        let store = TestStore()
        // 59 plants, each acquired on a different day long ago, each with its
        // own anniversary: with weekly check-ins for each, well over the limit.
        for index in 0..<59 {
            store.plant(nickname: "Plant \(index)", acquired: day(2024, 11, 1).addingTimeInterval(Double(index) * 86_400))
        }
        let planned = NotificationPlanner.plan(household: store.household, now: day(2026, 10, 1), photoCheckInMonths: 2)
        let others = planned.filter { !$0.id.hasPrefix(NotificationPlanner.photoCheckInPrefix) }
        let withoutCheckIns = NotificationPlanner.plan(household: store.household, now: day(2026, 10, 1), photoCheckInMonths: 0)

        XCTAssertLessThan(withoutCheckIns.count, NotificationPlanner.limit, "leaves some slots over")
        XCTAssertEqual(planned.count, NotificationPlanner.limit)
        XCTAssertEqual(Set(others.map(\.id)), Set(withoutCheckIns.map(\.id)), "check-ins never push anything else out")
        XCTAssertEqual(checkIns(planned).count, NotificationPlanner.limit - withoutCheckIns.count)
    }

    func testCheckInsDontDisplaceEvenLaterReminders() {
        let store = TestStore()
        // 60 anniversaries, all later than every check-in.
        for index in 0..<60 {
            store.plant(nickname: "Plant \(index)", acquired: day(2025, 12, 1))
        }
        let planned = NotificationPlanner.plan(household: store.household, now: day(2026, 10, 1), photoCheckInMonths: 2)
        XCTAssertEqual(planned.count, NotificationPlanner.limit)
        XCTAssertTrue(checkIns(planned).isEmpty)
    }
}
