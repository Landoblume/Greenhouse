import CoreLocation
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

    // MARK: ZIPs too new for the USDA map

    private let newZIP = "00010"

    func testKnownZIPNeverAsksTheGeocoder() async throws {
        let match = try await ZoneLookup.zone(forZIP: "00001", fetch: { _ in "6b" }, geocoder: FakeMap(rings: [:]))
        XCTAssertEqual(match, .init(zone: "6b", nearbyZIP: nil))
    }

    func testNewZIPUsesTheNearestNeighbourTheMapKnows() async throws {
        // 2 km ring: the new ZIP itself and one the map doesn't have yet either;
        // 5 km ring: a known one; 10 km ring: another known one, further away.
        let map = FakeMap(rings: [2: [newZIP, "00011"], 5: ["00012"], 10: ["00013"]])
        let known = ["00012": "7a", "00013": "6b"]
        let match = try await ZoneLookup.zone(forZIP: newZIP, fetch: { known[$0] }, geocoder: map)
        XCTAssertEqual(match, .init(zone: "7a", nearbyZIP: "00012"))
    }

    func testLocationUsesTheZIPItsInWhenTheMapKnowsIt() async throws {
        let map = FakeMap(rings: [0: ["00020"], 2: ["00021"]])
        let known = ["00020": "6a", "00021": "7b"]
        let match = try await ZoneLookup.zone(near: FakeMap.center, fetch: { known[$0] }, geocoder: map)
        XCTAssertEqual(match, .init(zone: "6a", nearbyZIP: "00020"))
    }

    func testLocationInABrandNewZIPUsesTheNearestKnownOne() async throws {
        let map = FakeMap(rings: [0: [newZIP], 2: ["00021"], 5: ["00022"]])
        let match = try await ZoneLookup.zone(near: FakeMap.center, fetch: { $0 == "00022" ? "7a" : nil }, geocoder: map)
        XCTAssertEqual(match, .init(zone: "7a", nearbyZIP: "00022"))
    }

    func testNewZIPWithNoKnownNeighboursAsksForAZoneByHand() async {
        let map = FakeMap(rings: [2: ["00011"], 5: ["00011"], 10: [newZIP]])
        await assertNotFound { try await ZoneLookup.zone(forZIP: self.newZIP, fetch: { _ in nil }, geocoder: map) }
    }

    func testZIPTheGeocoderCantPlaceAsksForAZoneByHand() async {
        await assertNotFound { try await ZoneLookup.zone(forZIP: self.newZIP, fetch: { _ in nil }, geocoder: FakeMap(rings: [:], placesZIP: false)) }
    }

    func testOfflineStillReportsTheNetworkError() async {
        do {
            _ = try await ZoneLookup.zone(forZIP: newZIP, fetch: { _ in throw URLError(.notConnectedToInternet) }, geocoder: FakeMap(rings: [:]))
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual((error as? URLError)?.code, .notConnectedToInternet)
        }
    }

    func testSearchPointsGoNearestFirst() {
        let center = CLLocationCoordinate2D(latitude: 40, longitude: -100)
        let distances = ZoneLookup.searchPoints(around: center).map { FakeMap.km(from: center, to: $0) }
        XCTAssertEqual(distances.count, 25)
        XCTAssertTrue(zip(distances, distances.dropFirst()).allSatisfy { $0 <= $1 + 0.05 })
        XCTAssertEqual(distances.first ?? 1, 0, accuracy: 0.001)
        XCTAssertEqual(distances[1], 2, accuracy: 0.05)
        XCTAssertEqual(distances.last ?? 0, 10, accuracy: 0.1)
    }

    private func assertNotFound(_ lookup: () async throws -> ZoneLookup.Match) async {
        do {
            _ = try await lookup()
            XCTFail("expected notFound")
        } catch {
            XCTAssertEqual(error as? ZoneLookup.Failure, .notFound)
        }
    }
}

/// A pretend map: the ZIP sits at a fixed point, and each ring around it
/// (by distance in km) is made of the given ZIPs, handed out in turn.
private struct FakeMap: ZIPGeocoding {
    static let center = CLLocationCoordinate2D(latitude: 40, longitude: -100)
    let rings: [Double: [String]]
    var placesZIP = true

    func coordinate(forZIP zip: String) async throws -> CLLocationCoordinate2D? {
        placesZIP ? Self.center : nil
    }

    func postalCode(at coordinate: CLLocationCoordinate2D) async throws -> String? {
        let km = Self.km(from: Self.center, to: coordinate)
        guard let ring = rings.keys.min(by: { abs($0 - km) < abs($1 - km) }),
              abs(ring - km) < 0.5, let zips = rings[ring], !zips.isEmpty else { return nil }
        let bearing = atan2(coordinate.longitude - Self.center.longitude, coordinate.latitude - Self.center.latitude)
        let index = Int(((bearing * 180 / .pi + 360).truncatingRemainder(dividingBy: 360) / 45).rounded()) % 8
        return zips[index % zips.count]
    }

    static func km(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) -> Double {
        CLLocation(latitude: a.latitude, longitude: a.longitude)
            .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude)) / 1000
    }
}
