import CoreData
import XCTest
@testable import Greenhouse

/// The plant page's birthday banner, confetti ledger, care teaser and stats.
final class PlantPageTests: XCTestCase {
    private let posix = Locale(identifier: "en_US_POSIX")

    private func water(_ plant: Plant, on date: Date, by name: String, store: TestStore) {
        CareSchedule.markDone(plant.wateringTask!, by: name, at: date, household: store.household,
                              context: store.context, persistence: store.persistence)
    }

    // MARK: Birthday

    func testBirthdayOnTheAnniversaryCountsYears() {
        let store = TestStore()
        let plant = store.plant(nickname: "Monty", acquired: day(2024, 11, 21))
        let birthday = PlantPage.birthday(of: plant, now: day(2026, 11, 21, hour: 8))
        XCTAssertEqual(birthday?.years, 2)
        XCTAssertEqual(birthday?.since, day(2024, 11, 21))
        XCTAssertEqual(PlantPage.birthdayTitle(name: plant.displayName, years: 2), "Monty turns 2 today")
    }

    func testNoBirthdayOnOtherDaysOrTheDayItArrived() {
        let store = TestStore()
        let plant = store.plant(acquired: day(2024, 11, 21))
        XCTAssertNil(PlantPage.birthday(of: plant, now: day(2026, 11, 20)))
        XCTAssertNil(PlantPage.birthday(of: plant, now: day(2026, 11, 22)))
        // Late in the evening is still the day.
        XCTAssertNotNil(PlantPage.birthday(of: plant, now: day(2026, 11, 21, hour: 23)))
        let new = store.plant(acquired: day(2026, 11, 21))
        XCTAssertNil(PlantPage.birthday(of: new, now: day(2026, 11, 21)))
    }

    func testLeapDayBirthdayFallsOnFeb28() {
        let store = TestStore()
        let plant = store.plant(acquired: day(2024, 2, 29))
        XCTAssertEqual(PlantPage.birthday(of: plant, now: day(2025, 2, 28))?.years, 1)
        XCTAssertNil(PlantPage.birthday(of: plant, now: day(2025, 3, 1)))
        XCTAssertEqual(PlantPage.birthday(of: plant, now: day(2028, 2, 29))?.years, 4)
        XCTAssertNil(PlantPage.birthday(of: plant, now: day(2028, 2, 28)))
    }

    func testCombinedPlantKeepsTheOldestBirthday() {
        let store = TestStore()
        let a = store.plant(nickname: "A", acquired: day(2023, 5, 1))
        let b = store.plant(nickname: "B", acquired: day(2025, 7, 24))
        let ab = Lineage.staple([a, b], nickname: "AB", date: day(2026, 1, 5),
                                household: store.household, context: store.context, persistence: store.persistence)
        XCTAssertEqual(PlantPage.birthday(of: ab, now: day(2026, 5, 1))?.years, 3)
        XCTAssertNil(PlantPage.birthday(of: ab, now: day(2026, 1, 5)))
    }

    // MARK: Confetti

    func testConfettiPlaysOncePerDayPerPlant() throws {
        let suite = "PlantPageTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let monty = UUID()
        let pip = UUID()
        let today = day(2026, 11, 21, hour: 9)

        XCTAssertTrue(PlantPage.ConfettiLedger.shouldPlay(plantID: monty, now: today, defaults: defaults))
        XCTAssertFalse(PlantPage.ConfettiLedger.shouldPlay(plantID: monty, now: day(2026, 11, 21, hour: 22), defaults: defaults))
        XCTAssertTrue(PlantPage.ConfettiLedger.shouldPlay(plantID: pip, now: today, defaults: defaults))
        XCTAssertFalse(PlantPage.ConfettiLedger.shouldPlay(plantID: pip, now: today, defaults: defaults))
        // A year on it plays again, and yesterday's entries are dropped.
        XCTAssertTrue(PlantPage.ConfettiLedger.shouldPlay(plantID: monty, now: day(2027, 11, 21), defaults: defaults))
        let stored = defaults.dictionary(forKey: PlantPage.ConfettiLedger.key) as? [String: String]
        XCTAssertEqual(stored?.keys.sorted(), [monty.uuidString])
        XCTAssertFalse(PlantPage.ConfettiLedger.shouldPlay(plantID: nil, now: today, defaults: defaults))
    }

    // MARK: Care teaser

    func testTeaserWordsForRecentAndOlderDates() {
        let now = day(2026, 11, 21) // a Saturday
        func teaser(_ date: Date, by: String? = "Alex", watering: Bool = true) -> String {
            PlantPage.careTeaser(title: watering ? "Watered" : "Fertilize", isWatering: watering, doneAt: date, doneBy: by,
                                 viewerName: "Sam", now: now, locale: posix)
        }
        XCTAssertEqual(teaser(day(2026, 11, 21, hour: 7)), "Watered today by Alex")
        XCTAssertEqual(teaser(day(2026, 11, 20)), "Watered yesterday by Alex")
        XCTAssertEqual(teaser(day(2026, 11, 17)), "Watered Tue by Alex")
        XCTAssertEqual(teaser(day(2026, 11, 14)), "Watered Nov 14 by Alex")
        XCTAssertEqual(teaser(day(2025, 12, 30)), "Watered Dec 30, 2025 by Alex")
        XCTAssertEqual(teaser(day(2026, 11, 17), watering: false), "Fertilize done Tue by Alex")
    }

    func testTeaserSaysYouAndSkipsMissingNames() {
        let now = day(2026, 11, 21)
        XCTAssertEqual(PlantPage.careTeaser(title: "Watered", isWatering: true, doneAt: day(2026, 11, 20), doneBy: " sam ",
                                            viewerName: "Sam", now: now, locale: posix), "Watered yesterday by you")
        XCTAssertEqual(PlantPage.careTeaser(title: "Watered", isWatering: true, doneAt: day(2026, 11, 20), doneBy: "  ",
                                            viewerName: "Sam", now: now, locale: posix), "Watered yesterday")
        XCTAssertEqual(PlantPage.careTeaser(title: "Watered", isWatering: true, doneAt: day(2026, 11, 20), doneBy: "Alex",
                                            viewerName: "", now: now, locale: posix), "Watered yesterday by Alex")
        XCTAssertEqual(PlantPage.careTeaser(latest: nil, viewerName: "Sam"), "No care logged yet")
    }

    func testTeaserUsesTheNewestLog() {
        let store = TestStore()
        let plant = store.plant(acquired: day(2026, 1, 1))
        water(plant, on: day(2026, 11, 10), by: "Sam", store: store)
        water(plant, on: day(2026, 11, 17), by: "Alex", store: store)
        store.save()
        let latest = CareHistory.entries(for: plant).first
        XCTAssertEqual(PlantPage.careTeaser(latest: latest, viewerName: "Sam", now: day(2026, 11, 21), locale: posix),
                       "Watered Tue by Alex")
    }

    // MARK: Stats

    func testStatsCountWateringsMilestonesAndPhotosAcrossACombine() {
        let store = TestStore()
        let a = store.plant(nickname: "A", acquired: day(2025, 1, 1), photo: true)
        let b = store.plant(nickname: "B", acquired: day(2025, 2, 1))
        water(a, on: day(2025, 3, 1), by: "Alex", store: store)
        water(b, on: day(2025, 3, 2), by: "Sam", store: store)
        Milestones.add(title: "New pot", date: day(2025, 4, 1), notes: nil, by: "Alex", to: a,
                       household: store.household, context: store.context, persistence: store.persistence)
        let ab = Lineage.staple([a, b], nickname: "AB", date: day(2025, 6, 1),
                                household: store.household, context: store.context, persistence: store.persistence)
        water(ab, on: day(2025, 7, 1), by: "Sam", store: store)
        let fertilize = CareSchedule.makeTask(name: "Fertilize", count: 1, unit: .month, firstDue: day(2025, 7, 1),
                                              plants: [ab], household: store.household,
                                              context: store.context, persistence: store.persistence)
        CareSchedule.markDone(fertilize, by: "Alex", at: day(2025, 7, 2), household: store.household,
                              context: store.context, persistence: store.persistence)
        store.save()

        let stats = PlantPage.stats(for: ab, entries: CareHistory.entries(for: ab))
        XCTAssertEqual(stats, PlantPage.Stats(waterings: 3, milestones: 1, photos: 1))
    }

    func testStripIsTheNewestThreeNewestFirst() {
        XCTAssertEqual(PlantPage.strip([1, 2, 3, 4, 5]), [5, 4, 3])
        XCTAssertEqual(PlantPage.strip([1, 2]), [2, 1])
        XCTAssertEqual(PlantPage.strip([Int]()), [])
    }
}
