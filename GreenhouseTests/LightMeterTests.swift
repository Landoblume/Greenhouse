import XCTest
@testable import Greenhouse

/// v1.2: camera light meter math.
final class LightMeterTests: XCTestCase {
    func testExposureValueAndLux() {
        // "Sunny 16": f/16, 1/100 s, ISO 100 is about EV 15, full daylight.
        let ev = LightMeter.ev100(aperture: 16, exposureSeconds: 1.0 / 100, iso: 100)
        XCTAssertEqual(ev, 14.64, accuracy: 0.01)
        XCTAssertEqual(LightMeter.lux(ev100: 0), 2.5)
        XCTAssertEqual(LightMeter.lux(ev100: 10), 2560)
        // Doubling ISO at the same shutter means half the light.
        let bright = LightMeter.lux(aperture: 1.8, exposureSeconds: 1.0 / 60, iso: 100)
        let dimmer = LightMeter.lux(aperture: 1.8, exposureSeconds: 1.0 / 60, iso: 200)
        XCTAssertEqual(bright / dimmer, 2, accuracy: 0.0001)
        XCTAssertEqual(LightMeter.footCandles(lux: 10_764), 1000, accuracy: 0.01)
    }

    func testEveryCatalogLightDescriptionHasARange() {
        let missing = Set(SpeciesCatalog.shared.species.map(\.light)).filter { LightMeter.range(for: $0) == nil }
        XCTAssertEqual(missing, [])
    }

    func testLevelsAgainstWhatTheSpeciesLikes() {
        XCTAssertEqual(LightMeter.level(lux: 1_500, for: "Bright, indirect"), .tooDim)
        XCTAssertEqual(LightMeter.level(lux: 15_000, for: "Bright, indirect"), .aboutRight)
        XCTAssertEqual(LightMeter.level(lux: 80_000, for: "Bright, indirect"), .tooBright)
        XCTAssertEqual(LightMeter.level(lux: 1_000, for: "Low to medium, indirect"), .aboutRight)
        XCTAssertNil(LightMeter.level(lux: 1_000, for: "Moonlight"))
        XCTAssertEqual(LightMeter.describe(lux: 300), "Very dim")
        XCTAssertEqual(LightMeter.describe(lux: 60_000), "Direct sun")
    }
}
