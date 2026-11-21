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

    private func plan(_ store: TestStore, now: Date, months: Int, hour: Int = 9, minute: Int = 0,
                      lastNudged: [String: Date] = [:]) -> [PlannedNotification] {
        NotificationPlanner.plan(household: store.household, now: now, hour: hour, minute: minute,
                                 photoCheckInMonths: months, calendar: calendar, lastNudged: lastNudged)
    }

    private func checkIns(_ plants: [Plant], now: Date, months: Int = 6, lastNudged: [String: Date] = [:]) -> [PlannedNotification] {
        NotificationPlanner.photoCheckIns(for: plants, months: months, after: now, hour: 9, minute: 0,
                                          calendar: calendar, lastNudged: lastNudged)
    }

    /// What the app does on every reschedule: plan, then remember the plan.
    private func reschedule(_ plants: [Plant], now: Date, months: Int = 6, ledger: inout [String: Date]) -> [PlannedNotification] {
        let planned = checkIns(plants, now: now, months: months, lastNudged: ledger)
        ledger = NotificationPlanner.updatedLastNudged(ledger, scheduled: planned,
                                                       activePlantIDs: Set(plants.compactMap(\.uuid)), calendar: calendar)
        return planned
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
        XCTAssertEqual(first.title, "Photo check-in 📸")
        // Last seen Mar 15, nudged Oct 3: 6 months and a bit.
        XCTAssertTrue((0..<NotificationPlanner.photoCheckInPhrasingCount).map {
            NotificationPlanner.photoCheckInBody(plantName: "Aloe", gapMonths: 6, variant: $0)
        }.contains(first.body), first.body)
        XCTAssertTrue(first.body.contains("6 months"), first.body)
        XCTAssertEqual(first.plantID, plant.uuid)
        XCTAssertTrue(first.id.hasPrefix("photo-\(plant.uuid!.uuidString)-"))
        XCTAssertEqual(calendar.component(.hour, from: first.date), 8)
        XCTAssertEqual(calendar.component(.minute, from: first.date), 30)
        // Overdue since Sep 15, so the first slot day (Tue, Thu, Sat) after now: Sat Oct 3.
        XCTAssertTrue(calendar.isDate(first.date, inSameDayAs: day(2026, 10, 3)))
    }

    func testNewestPhotoByTakenAtIsTheStartingPoint() throws {
        let store = TestStore()
        let plant = store.plant(nickname: "Aloe", acquired: day(2026, 1, 10))
        addPhoto(store, to: plant, takenAt: day(2026, 8, 1))
        addPhoto(store, to: plant, takenAt: day(2026, 2, 1))  // added later, dated earlier from the library

        let planned = plan(store, now: day(2026, 9, 1), months: 2)
        let first = try XCTUnwrap(checkIns(planned).first)
        XCTAssertTrue(first.date >= day(2026, 10, 1, hour: 0) && first.date < day(2026, 10, 8, hour: 0), "Aug 1 + 2 months: \(first.date)")
    }

    func testRecentPhotoMeansNoNudgeYet() throws {
        let store = TestStore()
        let plant = store.plant(nickname: "Aloe", acquired: day(2026, 1, 10))
        addPhoto(store, to: plant, takenAt: day(2026, 9, 20))
        // Nothing within the next quarter...
        XCTAssertTrue(checkIns(plan(store, now: day(2026, 10, 1), months: 6)).isEmpty)
        // ...and once Sep 20 + 6 months is in reach, not before it.
        let planned = plan(store, now: day(2027, 3, 1), months: 6)
        let first = try XCTUnwrap(checkIns(planned).first)
        XCTAssertTrue(first.date >= day(2027, 3, 20, hour: 0) && first.date < day(2027, 3, 27, hour: 0),
                      "Sep 20 + 6 months, on that week's slot day: \(first.date)")
    }

    func testNoPhotosStartsFromAcquiredDate() throws {
        let store = TestStore()
        store.plant(nickname: "Fern", acquired: day(2026, 4, 1))
        let planned = plan(store, now: day(2026, 6, 15), months: 3)
        let first = try XCTUnwrap(checkIns(planned).first)
        XCTAssertTrue(first.date >= day(2026, 7, 1, hour: 0) && first.date < day(2026, 7, 8, hour: 0), "Apr 1 + 3 months: \(first.date)")
        XCTAssertTrue(first.body.contains("Fern"))
        XCTAssertTrue(first.body.contains("3 months"), first.body)
    }

    func testNoPhotosAndNoAcquiredDateFallsBackToCreatedAt() throws {
        let store = TestStore()
        let plant = store.plant(nickname: "Fern", acquired: day(2026, 4, 1))
        plant.acquiredDate = nil
        plant.createdAt = day(2026, 5, 1)
        store.save()
        let planned = plan(store, now: day(2026, 6, 15), months: 2)
        let first = try XCTUnwrap(checkIns(planned).first)
        XCTAssertTrue(first.date >= day(2026, 7, 1, hour: 0) && first.date < day(2026, 7, 8, hour: 0), "May 1 + 2 months: \(first.date)")
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

    func testReschedulingKeepsWhatIsAlreadyPlanned() throws {
        let store = TestStore()
        let fern = store.plant(nickname: "Fern", acquired: day(2025, 1, 1))
        var ledger: [String: Date] = [:]

        let tuesday = reschedule([fern], now: day(2026, 10, 6), months: 2, ledger: &ledger)
        let thursday = reschedule([fern], now: day(2026, 10, 8, hour: 6), months: 2, ledger: &ledger)
        let weekLater = reschedule([fern], now: day(2026, 10, 13), months: 2, ledger: &ledger)

        // The window slides a day, so there may be one more at the end, but nothing planned moves.
        XCTAssertTrue(Set(tuesday.map(\.id)).isSubset(of: thursday.map(\.id)), "same nudges planned mid-week, even the morning one is kept")
        XCTAssertEqual(tuesday.first?.id, thursday.first?.id)
        XCTAssertTrue(Set(thursday.dropFirst().map(\.id)).isSubset(of: weekLater.map(\.id)),
                      "a week on, the same ids minus the one that fired, so a reschedule doesn't duplicate them")
        XCTAssertFalse(weekLater.map(\.id).contains(try XCTUnwrap(thursday.first?.id)), "the one that fired is gone")
    }

    func testAPhoneWithNoLedgerPlansTheSameWhenAskedTwice() {
        let store = TestStore()
        let plants = (0..<5).map { store.plant(nickname: "Plant \($0)", acquired: day(2025, 1, 1).addingTimeInterval(Double($0) * 86_400)) }
        let now = day(2026, 10, 6)
        XCTAssertEqual(checkIns(plants, now: now).map(\.id), checkIns(plants.reversed(), now: now).map(\.id), "not by fetch order")
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
        XCTAssertTrue(first.date >= day(2026, 11, 1, hour: 0) && first.date < day(2026, 11, 8, hour: 0), "Sep 1 + 2 months, not right away: \(first.date)")
    }

    // MARK: About three a week, oldest waiting first

    /// 15 plants added the same day, none photographed since.
    private func sameDayPlants(_ store: TestStore) -> [Plant] {
        (0..<15).map { store.plant(nickname: "Plant \($0)", acquired: day(2026, 3, 1)) }
    }

    private func perWeek(_ planned: [PlannedNotification]) -> [Date: [PlannedNotification]] {
        Dictionary(grouping: planned) { calendar.dateInterval(of: .weekOfYear, for: $0.date)!.start }
    }

    func testAtMostThreeCheckInsAWeekTheRestRollOver() {
        let store = TestStore()
        let plants = sameDayPlants(store)
        let now = day(2026, 4, 20)
        let planned = NotificationPlanner.photoCheckIns(for: plants, months: 2, after: now,
                                                        hour: 9, minute: 0, calendar: calendar)
        let weeks = perWeek(planned).sorted { $0.key < $1.key }
        XCTAssertTrue(weeks.allSatisfy { $0.value.count <= 3 }, weeks.map { $0.value.count }.description)
        XCTAssertTrue(weeks.dropFirst().dropLast().allSatisfy { $0.value.count == 3 }, "three in every full week")
        let days = Set(planned.map { calendar.startOfDay(for: $0.date) })
        XCTAssertEqual(days.count, planned.count, "one a day, never two together")
        XCTAssertTrue(planned.allSatisfy { calendar.component(.hour, from: $0.date) == 9 })
        // May 1 is the threshold for all 15: nothing sooner, and 3 in the first week.
        XCTAssertGreaterThanOrEqual(planned.map(\.date).min()!, day(2026, 5, 1, hour: 0))
        XCTAssertEqual(planned.filter { $0.date < day(2026, 5, 9, hour: 0) }.count, 3)
        // Everyone gets a turn before anyone gets a second, and a plant never waits less than a week.
        XCTAssertEqual(Set(planned.prefix(15).compactMap(\.plantID)), Set(plants.compactMap(\.uuid)))
        for plant in plants {
            let dates = planned.filter { $0.plantID == plant.uuid }.map(\.date).sorted()
            for (a, b) in zip(dates, dates.dropFirst()) {
                XCTAssertGreaterThanOrEqual(calendar.dateComponents([.day], from: a, to: b).day ?? 0, 7)
            }
        }
    }

    func testOldestWaitingGoesFirst() {
        let store = TestStore()
        // Thresholds (acquired + 2 months) a day apart, newest created first so
        // that creation order and fetch order can't be what decides.
        let newest = store.plant(nickname: "Newest", acquired: day(2026, 3, 5))
        let middle = store.plant(nickname: "Middle", acquired: day(2026, 3, 3))
        let oldest = store.plant(nickname: "Oldest", acquired: day(2026, 3, 1))
        let planned = NotificationPlanner.photoCheckIns(for: [newest, middle, oldest], months: 2, after: day(2026, 4, 20),
                                                        hour: 9, minute: 0, calendar: calendar)
        XCTAssertEqual(planned.prefix(3).compactMap(\.plantID), [oldest, middle, newest].compactMap(\.uuid))
    }

    func testABacklogOf30IsSpreadOverTheFollowingWeeks() {
        let store = TestStore()
        // 30 plants nobody has photographed for a year and a half, thresholds a day apart.
        let plants = (0..<30).map { store.plant(nickname: "Plant \($0)", acquired: day(2025, 1, 1).addingTimeInterval(Double($0) * 86_400)) }
        let now = day(2026, 11, 21)
        let planned = NotificationPlanner.photoCheckIns(for: plants, months: 6, after: now,
                                                        hour: 9, minute: 0, calendar: calendar)
        XCTAssertTrue(planned.allSatisfy { $0.date > now })
        XCTAssertTrue(perWeek(planned).values.allSatisfy { $0.count <= 3 }, perWeek(planned).mapValues(\.count).description)
        XCTAssertEqual(perWeek(planned).count, NotificationPlanner.checkInWeeksAhead, "every coming week, not one burst")
        // The first 30 are 30 different plants (10 weeks), and the first lands within days.
        XCTAssertEqual(Set(planned.prefix(30).compactMap(\.plantID)).count, 30)
        XCTAssertLessThan(planned[0].date, day(2026, 11, 29))

        // And the full plan, with its 60-slot cap and the plants' anniversaries, keeps the same limits.
        let full = checkIns(plan(store, now: now, months: 6))
        XCTAssertFalse(full.isEmpty)
        XCTAssertTrue(perWeek(full).values.allSatisfy { $0.count <= 3 })
    }

    // MARK: Stable across reschedules (the ledger)

    private func backlog(_ store: TestStore, count: Int) -> [Plant] {
        (0..<count).map { store.plant(nickname: "Plant \($0)", acquired: day(2025, 1, 1).addingTimeInterval(Double($0) * 86_400)) }
    }

    /// Reschedules every morning from `from` up to `through`, returning the days each plant's nudge fired
    /// (a nudge counts as fired once its time has passed).
    private func runDays(_ plants: [Plant], from: Date, through: Date, ledger: inout [String: Date]) -> [String: [Date]] {
        var fired: [String: [Date]] = [:]
        var morning = calendar.startOfDay(for: from).addingTimeInterval(6 * 3600)
        var seen: Set<String> = []
        while morning <= through {
            for item in reschedule(plants, now: morning, ledger: &ledger) where item.date < morning.addingTimeInterval(24 * 3600) && seen.insert(item.id).inserted {
                fired[item.plantID!.uuidString, default: []].append(item.date)
            }
            morning = calendar.date(byAdding: .day, value: 1, to: morning)!
        }
        return fired
    }

    func testAPhotoNeverBringsAnEarlierPlantBackWithinAWeek() throws {
        for count in [8, 12] {
            let store = TestStore()
            let plants = backlog(store, count: count)
            var ledger: [String: Date] = [:]
            let start = day(2026, 11, 21)

            // Run until the 5th plant has been nudged.
            let first = reschedule(plants, now: start, ledger: &ledger)
            let fifth = try XCTUnwrap(first.prefix(5).last)
            let fifthPlant = try XCTUnwrap(plants.first { $0.uuid == fifth.plantID })
            let fired = runDays(plants, from: start, through: fifth.date, ledger: &ledger)
            XCTAssertEqual(fired.count, 5, "five plants have been nudged by now")

            // A photo of the 5th arrives (or a new plant is added) and everything is planned again.
            let now = fifth.date.addingTimeInterval(3 * 3600)
            let planTheDayBefore = reschedule(plants, now: now, ledger: &ledger)
            addPhoto(store, to: fifthPlant, takenAt: now)
            let newPlant = store.plant(nickname: "New", acquired: day(2020, 1, 1))
            let after = reschedule(plants + [newPlant], now: now, ledger: &ledger)

            for (key, dates) in fired {
                let last = try XCTUnwrap(dates.max())
                for item in after where item.plantID?.uuidString == key {
                    XCTAssertGreaterThanOrEqual(calendar.dateComponents([.day], from: last, to: item.date).day ?? 0, 7,
                                                "\(count) plants: nudged \(last), planned again \(item.date)")
                }
            }
            XCTAssertFalse(after.contains { $0.plantID == fifthPlant.uuid && $0.date < now.addingTimeInterval(86_400 * 150) },
                           "the photographed plant isn't nudged again for months")
            // What was planned for the plants still waiting their first turn didn't move.
            let planned = Dictionary(grouping: planTheDayBefore, by: { $0.plantID })
            let plannedAfter = Dictionary(grouping: after, by: { $0.plantID })
            for plant in plants where plant.uuid != fifthPlant.uuid && fired[plant.uuid!.uuidString] == nil {
                XCTAssertEqual(planned[plant.uuid]?.first?.id, plannedAfter[plant.uuid]?.first?.id, "\(count) plants")
            }
            XCTAssertTrue(perWeek(after).values.allSatisfy { $0.count <= 3 })
        }
    }

    func testAddingAnOldPlantDoesNotReshuffleWhatIsPlanned() throws {
        let store = TestStore()
        let plants = backlog(store, count: 6)
        var ledger: [String: Date] = [:]
        let now = day(2026, 11, 21)
        let before = reschedule(plants, now: now, ledger: &ledger)

        let newcomer = store.plant(nickname: "Newcomer", acquired: day(2019, 1, 1))
        let after = reschedule(plants + [newcomer], now: now, ledger: &ledger)

        // Everyone keeps the day of their next check-in...
        for plant in plants {
            XCTAssertEqual(before.first { $0.plantID == plant.uuid }?.id, after.first { $0.plantID == plant.uuid }?.id)
        }
        // ...and the newcomer waits its turn for a free day, still within three weeks.
        let newcomerFirst = try XCTUnwrap(after.first { $0.plantID == newcomer.uuid })
        XCTAssertFalse(before.prefix(6).contains { calendar.isDate($0.date, inSameDayAs: newcomerFirst.date) })
        XCTAssertTrue(perWeek(after).values.allSatisfy { $0.count <= 3 })
    }

    func testTheUpgradeSpreadHoldsWithAnEmptyLedger() {
        let store = TestStore()
        let plants = backlog(store, count: 30)
        var ledger: [String: Date] = [:]
        let planned = reschedule(plants, now: day(2026, 11, 21), ledger: &ledger)
        XCTAssertEqual(Set(planned.prefix(30).compactMap(\.plantID)).count, 30, "30 plants, 30 different turns")
        XCTAssertTrue(perWeek(planned).values.allSatisfy { $0.count <= 3 })
        XCTAssertEqual(ledger.count, 30, "every plant is in the ledger")
        // The next reschedule, with the ledger, is the same plan.
        XCTAssertEqual(reschedule(plants, now: day(2026, 11, 21, hour: 13), ledger: &ledger).map(\.id), planned.map(\.id))
    }

    func testLedgerKeepsOnlyRealPlantsAndSurvivesUserDefaults() throws {
        let suite = "PhotoNudgeTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let kept = UUID(), gone = UUID()
        let ledger = [kept.uuidString: day(2026, 11, 24), gone.uuidString: day(2026, 11, 20)]
        XCTAssertTrue(NotificationPlanner.lastNudged(in: defaults).isEmpty)
        NotificationPlanner.saveLastNudged(ledger, in: defaults)
        XCTAssertEqual(NotificationPlanner.lastNudged(in: defaults), ledger)
        XCTAssertEqual(NotificationPlanner.updatedLastNudged(ledger, scheduled: [], activePlantIDs: [kept], calendar: calendar),
                       [kept.uuidString: day(2026, 11, 24)])
    }

    // MARK: Wording

    func testBodyNamesThePlantAndTheRealGap() {
        XCTAssertEqual(NotificationPlanner.photoCheckInBody(plantName: "Aloe", gapMonths: 7, variant: 0),
                       "It's been 7 months since Aloe's last close-up. Show off the new growth? 📸")
        for variant in 0..<NotificationPlanner.photoCheckInPhrasingCount {
            XCTAssertTrue(NotificationPlanner.photoCheckInBody(plantName: "Aloe", gapMonths: 7, variant: variant).contains("7 months"))
            XCTAssertTrue(NotificationPlanner.photoCheckInBody(plantName: "Aloe", gapMonths: 7, variant: variant).contains("Aloe"))
            XCTAssertTrue(NotificationPlanner.photoCheckInBody(plantName: "Aloe", gapMonths: 7, variant: variant).hasSuffix("📸"))
        }
        XCTAssertEqual(NotificationPlanner.gapText(months: 2), "2 months")
        XCTAssertEqual(NotificationPlanner.gapText(months: 12), "a year")
        XCTAssertEqual(NotificationPlanner.gapText(months: 14), "over a year")
        XCTAssertEqual(NotificationPlanner.gapText(months: 24), "2 years")
        XCTAssertEqual(NotificationPlanner.gapText(months: 30), "over 2 years")
        XCTAssertEqual(NotificationPlanner.photoCheckInBody(plantName: "Pothos", gapMonths: 12, variant: 2),
                       "A year since Pothos' last portrait. Time for a fresh one? 📸")
    }

    func testBodyRotatesAcrossAPlantsSuccessiveNudgesAndStaysTheSameOnEveryPlan() {
        // Same plant, different weeks: the phrasing changes.
        let weeks = (0..<12).map { NotificationPlanner.photoCheckInVariant(key: "7E1A6F3C-0D5B-4B0C-9E55-1C2D3E4F5A6B", week: $0) }
        XCTAssertGreaterThan(Set(weeks).count, 1)
        XCTAssertTrue(weeks.allSatisfy { (0..<NotificationPlanner.photoCheckInPhrasingCount).contains($0) })
        XCTAssertEqual(weeks, (0..<12).map { NotificationPlanner.photoCheckInVariant(key: "7E1A6F3C-0D5B-4B0C-9E55-1C2D3E4F5A6B", week: $0) })

        // Twelve plants over twelve weeks: some plant is nudged several times and hears it differently.
        let store = TestStore()
        let plants = backlog(store, count: 12)
        let now = day(2026, 11, 21)
        let planned = checkIns(plants, now: now)
        XCTAssertEqual(planned.map(\.body), checkIns(plants.reversed(), now: now).map(\.body), "deterministic")
        let bodies = Dictionary(grouping: planned, by: \.plantID).mapValues { Set($0.map(\.body)).count }
        XCTAssertTrue(bodies.values.contains { $0 > 1 }, bodies.description)
        XCTAssertTrue(planned.allSatisfy { $0.title == "Photo check-in 📸" })
    }

    func testPlantsWithNoPhotoGetTheirOwnLines() throws {
        let store = TestStore()
        let bare = store.plant(nickname: "Aloe", acquired: day(2026, 3, 1))
        let shot = store.plant(nickname: "Fern", acquired: day(2026, 3, 1))
        addPhoto(store, to: shot, takenAt: day(2026, 3, 2))
        let planned = checkIns([bare, shot], now: day(2026, 10, 1), months: 2)

        let bareBodies = Set(planned.filter { $0.plantID == bare.uuid }.map(\.body))
        let shotBodies = Set(planned.filter { $0.plantID == shot.uuid }.map(\.body))
        XCTAssertFalse(bareBodies.isEmpty)
        XCTAssertTrue(bareBodies.allSatisfy {
            $0.contains("Aloe") && $0.contains(" months") && $0.hasSuffix("📸")
                && ($0.contains("no close-up yet") || $0.contains("without a single photo") || $0.contains("No photos of"))
        }, "\(bareBodies)")
        XCTAssertTrue(shotBodies.allSatisfy { $0.contains("Fern") && !$0.contains("no close-up yet") && !$0.contains("without a single photo") && !$0.contains("No photos") }, "\(shotBodies)")
        XCTAssertEqual(NotificationPlanner.photoCheckInBody(plantName: "Aloe", gapMonths: 7, hasPhoto: false, variant: 0),
                       "You've had Aloe 7 months and no close-up yet. Show it off? 📸")
        XCTAssertGreaterThan(NotificationPlanner.photoCheckInNoPhotoPhrasingCount, 1)
        XCTAssertGreaterThan(Set((0..<12).map { NotificationPlanner.photoCheckInVariant(key: "k", week: $0, count: NotificationPlanner.photoCheckInNoPhotoPhrasingCount) }).count, 1)
        XCTAssertEqual(NotificationPlanner.lastSeen(of: bare)?.hasPhoto, false)
        XCTAssertEqual(NotificationPlanner.lastSeen(of: shot)?.hasPhoto, true)
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
