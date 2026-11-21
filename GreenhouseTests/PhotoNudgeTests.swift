import CoreData
import XCTest
@testable import Greenhouse

/// v1.5: a weekly nudge to photograph plants nobody has photographed in a while.
final class PhotoNudgeTests: XCTestCase {
    /// Fixed, so results don't depend on the machine's calendar or zone. A
    /// zone with daylight saving, so weekly steps cross a change (Nov 1, 2026).
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Denver")!
        return calendar
    }()

    private func day(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private func plan(_ store: TestStore, now: Date, months: Int, hour: Int = 9, minute: Int = 0) -> [PlannedNotification] {
        NotificationPlanner.plan(household: store.household, now: now, hour: hour, minute: minute,
                                 photoCheckInMonths: months, calendar: calendar)
    }

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

        let planned = plan(store, now: day(2026, 10, 1), months: 6, hour: 8, minute: 30)
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

        let planned = plan(store, now: day(2026, 9, 1), months: 2)
        let first = try XCTUnwrap(checkIns(planned).first)
        XCTAssertTrue(calendar.isDate(first.date, inSameDayAs: day(2026, 10, 1)), "Aug 1 + 2 months")
    }

    func testRecentPhotoMeansNoNudgeYet() throws {
        let store = TestStore()
        let plant = store.plant(nickname: "Aloe", acquired: day(2026, 1, 10))
        addPhoto(store, to: plant, takenAt: day(2026, 9, 20))
        let planned = plan(store, now: day(2026, 10, 1), months: 6)
        // Slots are free, so it's planned ahead, but not before Sep 20 + 6 months.
        let first = try XCTUnwrap(checkIns(planned).first)
        XCTAssertTrue(calendar.isDate(first.date, inSameDayAs: day(2027, 3, 20)))
    }

    func testNoPhotosStartsFromAcquiredDate() throws {
        let store = TestStore()
        store.plant(nickname: "Fern", acquired: day(2026, 4, 1))
        let planned = plan(store, now: day(2026, 6, 15), months: 3)
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
        let planned = plan(store, now: day(2026, 6, 15), months: 2)
        let first = try XCTUnwrap(checkIns(planned).first)
        XCTAssertTrue(calendar.isDate(first.date, inSameDayAs: day(2026, 7, 1)), "May 1 + 2 months")
    }

    func testOffPlansNoCheckIns() {
        let store = TestStore()
        store.plant(nickname: "Fern", acquired: day(2025, 1, 1))
        let planned = plan(store, now: day(2026, 10, 1), months: 0)
        XCTAssertTrue(checkIns(planned).isEmpty)
    }

    func testInactivePlantsAreNotNudged() {
        let store = TestStore()
        let plant = store.plant(nickname: "Fern", acquired: day(2025, 1, 1))
        plant.statusValue = .stapled
        store.save()
        let planned = plan(store, now: day(2026, 10, 1), months: 2)
        XCTAssertTrue(checkIns(planned).isEmpty)
    }

    // MARK: N3: weekly, deterministic, stops after a newer photo

    func testRepeatsWeeklyNeverDaily() {
        let store = TestStore()
        store.plant(nickname: "Fern", acquired: day(2025, 1, 1))
        let planned = checkIns(plan(store, now: day(2026, 10, 1), months: 2))
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
        let tuesday = checkIns(plan(store, now: day(2026, 10, 6), months: 2))
        let weekLater = checkIns(plan(store, now: day(2026, 10, 13), months: 2))
        let thursday = checkIns(plan(store, now: day(2026, 10, 8), months: 2))

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
        XCTAssertFalse(checkIns(plan(store, now: now, months: 2)).isEmpty)

        // The other phone's photo syncs in; the next plan has nothing soon.
        addPhoto(store, to: plant, takenAt: day(2026, 9, 30))
        let after = checkIns(plan(store, now: now, months: 2))
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
        let planned = plan(store, now: day(2026, 10, 1), months: 2)
        let others = planned.filter { !$0.id.hasPrefix(NotificationPlanner.photoCheckInPrefix) }
        let withoutCheckIns = plan(store, now: day(2026, 10, 1), months: 0)

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
        let planned = plan(store, now: day(2026, 10, 1), months: 2)
        XCTAssertEqual(planned.count, NotificationPlanner.limit)
        XCTAssertTrue(checkIns(planned).isEmpty)
    }

    func testAnOldLibraryPhotoOnANewPlantCountsFromWhenItArrived() throws {
        let store = TestStore()
        let plant = store.plant(nickname: "Aloe", acquired: day(2026, 9, 1))
        addPhoto(store, to: plant, takenAt: day(2025, 3, 1))  // from the library, dated last year
        let planned = plan(store, now: day(2026, 9, 15), months: 2)
        let first = try XCTUnwrap(checkIns(planned).first)
        XCTAssertTrue(calendar.isDate(first.date, inSameDayAs: day(2026, 11, 1)), "Sep 1 + 2 months, not right away")
    }

    // MARK: At most two a day

    /// 15 plants added the same day, none photographed since.
    private func sameDayPlants(_ store: TestStore) -> [Plant] {
        (0..<15).map { store.plant(nickname: "Plant \($0)", acquired: day(2026, 3, 1)) }
    }

    func testAtMostTwoCheckInsADayTheRestRollOver() {
        let store = TestStore()
        let plants = sameDayPlants(store)
        let planned = checkIns(plan(store, now: day(2026, 4, 20), months: 2))

        let perDay = Dictionary(grouping: planned) { calendar.startOfDay(for: $0.date) }
        XCTAssertTrue(perDay.values.allSatisfy { $0.count <= NotificationPlanner.checkInsPerDay },
                      perDay.mapValues(\.count).description)
        // May 1 is the threshold for all 15: two that day, the rest on the next days.
        let first = planned.filter { calendar.isDate($0.date, inSameDayAs: day(2026, 5, 1)) }
        XCTAssertEqual(first.count, 2)
        XCTAssertEqual(Set(planned.compactMap(\.plantID)), Set(plants.compactMap(\.uuid)), "everyone gets theirs")
        XCTAssertTrue(planned.allSatisfy { calendar.component(.hour, from: $0.date) == 9 })

        // Each plant still waits at least a week between check-ins, never daily.
        // (Straight from the check-in planner: in the full plan the last few
        // only get the slots the anniversaries leave.)
        let all = NotificationPlanner.photoCheckIns(for: plants, months: 2, after: day(2026, 4, 20),
                                                    hour: 9, minute: 0, calendar: calendar)
        XCTAssertTrue(Dictionary(grouping: all) { calendar.startOfDay(for: $0.date) }.values.allSatisfy { $0.count <= 2 })
        for plant in plants {
            let dates = all.filter { $0.plantID == plant.uuid }.map(\.date).sorted()
            XCTAssertEqual(dates.count, NotificationPlanner.checkInsPerPlant)
            for (a, b) in zip(dates, dates.dropFirst()) {
                XCTAssertGreaterThanOrEqual(calendar.dateComponents([.day], from: a, to: b).day ?? 0, 7)
            }
        }
    }

    func testRolledOverDaysAreTheSameOnEveryReschedule() {
        let store = TestStore()
        let plants = sameDayPlants(store)
        func checkIns(now: Date) -> [PlannedNotification] {
            NotificationPlanner.photoCheckIns(for: plants, months: 2, after: now, hour: 9, minute: 0, calendar: calendar)
        }
        let early = checkIns(now: day(2026, 4, 20))
        let later = checkIns(now: day(2026, 5, 9))
        let shuffled = NotificationPlanner.photoCheckIns(for: plants.reversed(), months: 2, after: day(2026, 4, 20),
                                                         hour: 9, minute: 0, calendar: calendar)

        XCTAssertEqual(Set(early.map(\.id)), Set(shuffled.map(\.id)), "doesn't depend on fetch order")
        let stillAhead = early.filter { $0.date > day(2026, 5, 9) }.map(\.id)
        XCTAssertFalse(stillAhead.isEmpty)
        XCTAssertTrue(Set(stillAhead).isSubset(of: later.map(\.id)),
                      "a later reschedule keeps the same days for what hasn't fired yet")
    }

    // MARK: N4: which plant a tap opens

    func testTapOpensTheActivePlantItWasCombinedInto() throws {
        let store = TestStore()
        let a = store.plant(nickname: "A", acquired: day(2026, 1, 1))
        let b = store.plant(nickname: "B", acquired: day(2026, 2, 1))
        let c = store.plant(nickname: "C", acquired: day(2026, 3, 1))
        XCTAssertEqual(NotificationPlanner.photoCheckInTarget(plantID: try XCTUnwrap(a.uuid), in: store.household), a)

        let ab = Lineage.staple([a, b], nickname: "AB", date: day(2026, 6, 1), household: store.household,
                                context: store.context, persistence: store.persistence)
        let abc = Lineage.staple([ab, c], nickname: "ABC", date: day(2026, 7, 1), household: store.household,
                                 context: store.context, persistence: store.persistence)
        store.save()

        XCTAssertEqual(NotificationPlanner.photoCheckInTarget(plantID: try XCTUnwrap(a.uuid), in: store.household), abc)
        XCTAssertEqual(NotificationPlanner.photoCheckInTarget(plantID: try XCTUnwrap(ab.uuid), in: store.household), abc)
        XCTAssertNil(NotificationPlanner.photoCheckInTarget(plantID: UUID(), in: store.household))
    }
}
