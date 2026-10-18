import XCTest
@testable import Greenhouse

/// Search, filter and sort on the Plants tab.
final class PlantFilterTests: XCTestCase {
    func testSearchMatchesNicknameLatinCommonNameAndLocation() {
        let store = TestStore()
        let aloe = store.plant(nickname: "Spiky", acquired: day(2026, 3, 1))
        aloe.location = "Kitchen window"
        let pothos = store.plant("epipremnum-aureum", acquired: day(2026, 4, 1))
        let plants = [aloe, pothos]

        func search(_ text: String) -> [Plant] { PlantFilter(query: text).apply(to: plants) }
        XCTAssertEqual(search("spiky"), [aloe])
        XCTAssertEqual(search("ALOE"), [aloe])
        XCTAssertEqual(search("kitchen"), [aloe])
        XCTAssertEqual(search("epipremnum"), [pothos])
        XCTAssertEqual(search("aloe kitchen"), [aloe], "every word has to match")
        XCTAssertEqual(search(""), plants)
        XCTAssertEqual(search("fern"), [])
    }

    func testFilterBySettingAndNeedsWater() {
        let store = TestStore()
        let now = day(2026, 10, 17)
        let thirsty = store.plant(acquired: day(2026, 9, 1), setting: .outdoor, waterEvery: 3, now: day(2026, 10, 1))
        let fine = store.plant(acquired: day(2026, 9, 1), setting: .indoor, waterEvery: 30, now: day(2026, 10, 15))
        let plants = [thirsty, fine]

        XCTAssertEqual(PlantFilter(settings: [.outdoor]).apply(to: plants, now: now), [thirsty])
        XCTAssertEqual(PlantFilter(settings: [.indoor, .outdoor]).apply(to: plants, now: now), plants)
        XCTAssertEqual(PlantFilter(needsWater: true).apply(to: plants, now: now), [thirsty])
        XCTAssertFalse(PlantFilter().isFiltering)
        XCTAssertTrue(PlantFilter(needsWater: true).isFiltering)
    }

    func testSorts() {
        let store = TestStore()
        let zebra = store.plant(nickname: "Zebra", acquired: day(2026, 1, 1), waterEvery: 10, now: day(2026, 10, 1))
        let apple = store.plant(nickname: "apple", acquired: day(2026, 6, 1), waterEvery: 2, now: day(2026, 10, 1))
        let plants = [zebra, apple]

        XCTAssertEqual(PlantFilter(sort: .added).apply(to: plants), [zebra, apple])
        XCTAssertEqual(PlantFilter(sort: .name).apply(to: plants), [apple, zebra])
        XCTAssertEqual(PlantFilter(sort: .nextWatering).apply(to: plants), [apple, zebra])
        XCTAssertEqual(PlantFilter(sort: .newest).apply(to: plants), [apple, zebra])
    }
}
