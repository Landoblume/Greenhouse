import XCTest
@testable import Greenhouse

/// The "then vs now" share card's words and photo picks.
final class ShareCardTests: XCTestCase {
    private func addPhoto(_ store: TestStore, to plant: Plant, takenAt: Date) {
        PlantFactory.addPhoto(Data([1]), takenAt: takenAt, to: plant, household: store.household,
                              context: store.context, persistence: store.persistence)
        store.save()
    }

    func testGrowthReadsInTheLargestSensibleUnit() {
        func growth(_ from: Date, _ to: Date) -> String {
            let g = ShareCard.growth(from: from, to: to)
            return "\(g.value) \(g.unit)"
        }
        XCTAssertEqual(growth(day(2026, 3, 10), day(2026, 11, 21)), "8 months of growth")
        XCTAssertEqual(growth(day(2026, 10, 21), day(2026, 11, 21)), "1 month of growth")
        XCTAssertEqual(growth(day(2026, 10, 30), day(2026, 11, 21)), "3 weeks of growth")
        XCTAssertEqual(growth(day(2026, 11, 20), day(2026, 11, 21)), "1 day of growth")
        XCTAssertEqual(growth(day(2026, 11, 21), day(2026, 11, 21)), "0 days of growth")
        XCTAssertEqual(growth(day(2024, 11, 1), day(2026, 11, 21)), "2 years of growth")
        XCTAssertEqual(growth(day(2025, 1, 1), day(2026, 11, 21)), "22 months of growth", "under 2 years stays in months")
    }

    func testGrownByListsEveryoneWithCareOrMilestonesMostFirst() throws {
        let store = TestStore()
        let plant = store.plant(nickname: "Monty", acquired: day(2026, 1, 1))
        let water = try XCTUnwrap(plant.tasks?.first)
        for (index, name) in ["Sam", "Alex", "Alex", "sam ", "Alex"].enumerated() {
            CareSchedule.markDone(water, by: name, at: day(2026, 2, 1 + index), household: store.household,
                                  context: store.context, persistence: store.persistence)
        }
        _ = Milestones.add(title: "New leaf", date: day(2026, 3, 1), notes: nil, by: "Jo", to: plant,
                       household: store.household, context: store.context, persistence: store.persistence)
        store.save()
        XCTAssertEqual(ShareCard.growers(for: plant), ["Alex", "Sam", "Jo"], "counted case-insensitively, most first")
        XCTAssertEqual(ShareCard.grownBy(["Alex", "Sam", "Jo"]), "Grown by Alex, Sam & Jo")
        XCTAssertEqual(ShareCard.grownBy(["Alex", "Sam"]), "Grown by Alex & Sam")
        XCTAssertEqual(ShareCard.grownBy(["Sam"]), "Grown by Sam")
        XCTAssertEqual(ShareCard.grownBy([]), "Grown with care")
    }

    func testCareOnPlantsItWasCombinedFromCounts() {
        let store = TestStore()
        let a = store.plant(nickname: "A", acquired: day(2026, 1, 1))
        let b = store.plant(nickname: "B", acquired: day(2026, 1, 1))
        CareSchedule.markDone(a.tasks!.first!, by: "Alex", at: day(2026, 2, 1), household: store.household,
                              context: store.context, persistence: store.persistence)
        CareSchedule.markDone(b.tasks!.first!, by: "Sam", at: day(2026, 2, 2), household: store.household,
                              context: store.context, persistence: store.persistence)
        let ab = Lineage.staple([a, b], nickname: "AB", date: day(2026, 3, 1), household: store.household,
                                context: store.context, persistence: store.persistence)
        store.save()
        XCTAssertEqual(Set(ShareCard.growers(for: ab)), ["Alex", "Sam"])
    }

    func testFirstAndLatestPhotosAndTheTimeBetween() {
        let store = TestStore()
        let plant = store.plant(nickname: "Monty", acquired: day(2026, 1, 1))
        addPhoto(store, to: plant, takenAt: day(2026, 6, 1))
        addPhoto(store, to: plant, takenAt: day(2026, 3, 1))
        addPhoto(store, to: plant, takenAt: day(2026, 11, 1))
        let content = ShareCard.content(for: plant, now: day(2026, 11, 21))
        XCTAssertEqual(content.name, "Monty")
        XCTAssertEqual(content.then?.takenAt, day(2026, 3, 1))
        XCTAssertEqual(content.now?.takenAt, day(2026, 11, 1))
        XCTAssertEqual(content.growth, ShareCard.Growth(value: 8, unit: "months of growth"))
    }

    func testOnePhotoIsNowAndThenIsWhenItArrived() {
        let store = TestStore()
        let plant = store.plant(nickname: "Pip", acquired: day(2026, 5, 1))
        addPhoto(store, to: plant, takenAt: day(2026, 11, 1))
        let content = ShareCard.content(for: plant, now: day(2026, 11, 21))
        XCTAssertNil(content.then, "seedling art stands in")
        XCTAssertEqual(content.thenDate, day(2026, 5, 1))
        XCTAssertEqual(content.now?.takenAt, day(2026, 11, 1))
        XCTAssertEqual(content.growth.value, 6)
    }

    func testNoPhotosCountsFromArrivalToToday() {
        let store = TestStore()
        let plant = store.plant(nickname: "Pip", acquired: day(2026, 8, 21))
        let content = ShareCard.content(for: plant, now: day(2026, 11, 21))
        XCTAssertNil(content.then)
        XCTAssertNil(content.now)
        XCTAssertEqual(content.growth, ShareCard.Growth(value: 3, unit: "months of growth"))
    }
}
