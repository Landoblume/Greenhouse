import XCTest
@testable import Greenhouse

/// #2: plant records and the species list.
final class PlantRecordTests: XCTestCase {
    func testSearchingAloeFindsAloeVeraFirst() {
        XCTAssertEqual(SpeciesCatalog.shared.search("aloe").first?.latin, "Aloe vera")
        XCTAssertEqual(SpeciesCatalog.shared.search("Aloe").first?.latin, "Aloe vera")
    }

    func testSearchMatchesCommonNames() {
        XCTAssertEqual(SpeciesCatalog.shared.search("snake plant").first?.latin, "Dracaena trifasciata")
        XCTAssertEqual(SpeciesCatalog.shared.search("pothos").first?.latin, "Epipremnum aureum")
    }

    func testCultivarsAreSearchable() {
        let results = SpeciesCatalog.shared.search("marble queen")
        XCTAssertEqual(results.first?.latin, "Epipremnum aureum 'Marble Queen'")
        // A plain "pothos" search lists it too.
        let pothos = SpeciesCatalog.shared.search("pothos").map(\.latin)
        XCTAssertTrue(pothos.contains("Epipremnum aureum 'Marble Queen'"))
    }

    func testCatalogEntriesAreSane() {
        let all = SpeciesCatalog.shared.species
        XCTAssertGreaterThan(all.count, 80)
        XCTAssertEqual(Set(all.map(\.id)).count, all.count, "duplicate ids")
        for entry in all {
            XCTAssertLessThanOrEqual(entry.zoneMin, entry.zoneMax, entry.latin)
            XCTAssertTrue((1...13).contains(entry.zoneMin), entry.latin)
            XCTAssertGreaterThan(entry.waterDays, 0, entry.latin)
        }
    }

    func testTwoAloesAreDistinctRecords() {
        let store = TestStore()
        let first = store.plant(acquired: day(2026, 3, 26))
        let second = store.plant(acquired: day(2026, 7, 24))
        XCTAssertNotEqual(first.objectID, second.objectID)
        XCTAssertEqual(first.scientificName, "Aloe vera")
        XCTAssertEqual(second.scientificName, "Aloe vera")
        XCTAssertNotEqual(first.acquiredDate, second.acquiredDate)
    }

    func testTypedInSpeciesSavesWithoutCareData() {
        let store = TestStore()
        let plant = store.plant(nil, acquired: day(2026, 1, 1))
        XCTAssertEqual(plant.scientificName, "Testus plantus")
        XCTAssertNil(plant.species)
        XCTAssertEqual(Hardiness.advice(setting: .outdoor, zone: "7a", species: plant.species), .noData)
    }

    func testNewPlantGetsWateringScheduleFromInterval() {
        let store = TestStore()
        let plant = store.plant(acquired: day(2026, 10, 1), waterEvery: 21, now: day(2026, 10, 17))
        let watering = try! XCTUnwrap(plant.wateringTask)
        XCTAssertEqual(watering.intervalCount, 21)
        XCTAssertEqual(CareSchedule.nextDue(for: watering), Calendar.current.startOfDay(for: day(2026, 11, 7)))
    }

    func testTimelineIsOldestFirst() {
        let store = TestStore()
        let plant = store.plant(acquired: day(2026, 3, 26), photo: true)
        PlantFactory.addPhoto(Data([0x02]), takenAt: day(2026, 9, 1), to: plant, household: store.household, context: store.context, persistence: store.persistence)
        PlantFactory.addPhoto(Data([0x03]), takenAt: day(2026, 5, 1), to: plant, household: store.household, context: store.context, persistence: store.persistence)
        store.save()
        let dates = Lineage.timeline(for: plant).compactMap(\.photo.takenAt)
        XCTAssertEqual(dates, dates.sorted())
        XCTAssertEqual(dates.count, 3)
    }

    func testAgeLabel() {
        XCTAssertEqual(PlantDetailView.age(since: day(2026, 3, 26), now: day(2026, 10, 27)), "7 months")
        XCTAssertEqual(PlantDetailView.age(since: day(2026, 10, 1), now: day(2026, 10, 17)), "under a month")
    }
}
