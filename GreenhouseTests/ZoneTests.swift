import XCTest
@testable import Greenhouse

/// #6: care tailored to the grow zone.
final class ZoneTests: XCTestCase {
    private let aloe = SpeciesCatalog.shared.species(id: "aloe-vera")
    private let hosta = SpeciesCatalog.shared.species(id: "hosta")

    func testAloeOutdoorsIn7aIsNotHardy() {
        let advice = Hardiness.advice(setting: .outdoor, zone: "7a", species: aloe)
        XCTAssertEqual(advice.message, "Not hardy in 7a: bring inside before the first frost")
        XCTAssertTrue(advice.isWarning)
        XCTAssertEqual(Hardiness.advice(setting: .seasonal, zone: "7a", species: aloe).message, advice.message)
    }

    func testHardyOutdoorPlant() {
        XCTAssertEqual(Hardiness.advice(setting: .outdoor, zone: "7a", species: hosta).message, "Hardy in your zone ✓")
    }

    func testIndoorPlantsGetNoWarning() {
        XCTAssertEqual(Hardiness.advice(setting: .indoor, zone: "7a", species: aloe), .none)
        XCTAssertEqual(Hardiness.advice(setting: .indoor, zone: nil, species: aloe), .none)
    }

    func testNoZoneAsksForZipInsteadOfGuessing() {
        XCTAssertEqual(Hardiness.advice(setting: .outdoor, zone: nil, species: aloe).message, "Set your ZIP for zone advice")
        XCTAssertEqual(Hardiness.advice(setting: .outdoor, zone: "garbage", species: aloe), .setZip)
    }

    func testTooWarm() {
        XCTAssertEqual(Hardiness.advice(setting: .outdoor, zone: "11b", species: hosta), .tooWarm(zone: "11b", range: "zones 3–8"))
    }

    func testZoneParsing() {
        XCTAssertEqual(USDAZone("10b")?.number, 10)
        XCTAssertEqual(USDAZone("7")?.label, "7")
        XCTAssertNil(USDAZone("14a"))
        XCTAssertNil(USDAZone("7c"))
        XCTAssertEqual(USDAZone.all.count, 26)
    }

    func testWateringDefaultsFromCatalog() {
        let store = TestStore()
        let plant = store.plant("aloe-vera", acquired: day(2026, 1, 1), waterEvery: aloe!.waterDays)
        XCTAssertEqual(plant.wateringTask?.intervalCount, 21)
    }

    func testZoneIsSharedOnTheHousehold() {
        let store = TestStore()
        store.household.zip = "84101"
        store.household.hardinessZone = "7b"
        store.save()
        let plant = store.plant(acquired: day(2026, 1, 1), setting: .outdoor)
        XCTAssertEqual(Hardiness.advice(setting: plant.settingValue, zone: plant.household?.hardinessZone, species: plant.species).message,
                       "Not hardy in 7b: bring inside before the first frost")
    }

    func testInvalidZIPIsRejectedBeforeAnyNetworkCall() async {
        do {
            _ = try await ZoneLookup.zone(forZIP: "12")
            XCTFail("expected invalid ZIP")
        } catch {
            XCTAssertEqual(error as? ZoneLookup.Failure, .invalidZIP)
        }
    }
}
