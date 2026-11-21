import XCTest
@testable import Greenhouse

/// Genus filter on the Plants tab.
final class GenusFilterTests: XCTestCase {
    private func plant(_ store: TestStore, latin: String?) -> Plant {
        let plant = store.plant(acquired: day(2026, 3, 1))
        plant.scientificName = latin
        return plant
    }

    func testGenusIsFirstWordCapitalized() {
        let store = TestStore()
        XCTAssertEqual(PlantFilter.genus(of: plant(store, latin: "Aloe vera")), "Aloe")
        XCTAssertEqual(PlantFilter.genus(of: plant(store, latin: "  epipremnum aureum")), "Epipremnum")
        XCTAssertEqual(PlantFilter.genus(of: plant(store, latin: "MONSTERA")), "Monstera")
        XCTAssertNil(PlantFilter.genus(of: plant(store, latin: nil)))
        XCTAssertNil(PlantFilter.genus(of: plant(store, latin: "   ")))
    }

    func testGeneraAreDistinctAndSorted() {
        let store = TestStore()
        let plants = [
            plant(store, latin: "Epipremnum aureum"),
            plant(store, latin: "aloe vera"),
            plant(store, latin: "Aloe arborescens"),
            plant(store, latin: nil),
        ]
        XCTAssertEqual(PlantFilter.genera(in: plants), ["Aloe", "Epipremnum"])
        XCTAssertEqual(PlantFilter.genera(in: []), [])
    }

    func testApplyAndIsFiltering() {
        let store = TestStore()
        let aloe = plant(store, latin: "Aloe vera")
        aloe.nickname = "Spiky"
        let aloe2 = plant(store, latin: "aloe arborescens")
        let pothos = plant(store, latin: "Epipremnum aureum")
        let plants = [aloe, aloe2, pothos]

        XCTAssertEqual(PlantFilter(genus: "Aloe").apply(to: plants), [aloe, aloe2])
        XCTAssertEqual(PlantFilter(genus: "Epipremnum").apply(to: plants), [pothos])
        XCTAssertEqual(PlantFilter(genus: "Ficus").apply(to: plants), [])
        XCTAssertEqual(PlantFilter().apply(to: plants), plants)
        XCTAssertTrue(PlantFilter(genus: "Aloe").isFiltering)
        XCTAssertFalse(PlantFilter().isFiltering)
        XCTAssertEqual(PlantFilter(query: "spiky", genus: "Aloe").apply(to: plants), [aloe], "combines with search")
    }

    func testPlantsWithoutScientificNameNeverMatch() {
        let store = TestStore()
        let nameless = plant(store, latin: nil)
        let aloe = plant(store, latin: "Aloe vera")
        XCTAssertEqual(PlantFilter(genus: "Aloe").apply(to: [nameless, aloe]), [aloe])
        XCTAssertEqual(PlantFilter(genus: "").apply(to: [nameless]), [])
        XCTAssertEqual(PlantFilter().apply(to: [nameless]), [nameless], "no filter keeps them")
    }
}
