import XCTest
@testable import Greenhouse

/// v1.5.1: the plant page's hero covers its frame edge to edge, centered,
/// whatever the photo's shape (a portrait photo sat off to the right).
final class PlantHeroTests: XCTestCase {
    private let hero = CGSize(width: 393, height: GH.PlantPage.heroHeight)

    private func assertCovers(_ rect: CGRect, _ bounds: CGSize, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertLessThanOrEqual(rect.minX, 0.001, "left edge shows", file: file, line: line)
        XCTAssertLessThanOrEqual(rect.minY, 0.001, "top edge shows", file: file, line: line)
        XCTAssertGreaterThanOrEqual(rect.maxX, bounds.width - 0.001, "right edge shows", file: file, line: line)
        XCTAssertGreaterThanOrEqual(rect.maxY, bounds.height - 0.001, "bottom edge shows", file: file, line: line)
        XCTAssertEqual(rect.midX, bounds.width / 2, accuracy: 0.001, "not centered across", file: file, line: line)
        XCTAssertEqual(rect.midY, bounds.height / 2, accuracy: 0.001, "not centered down", file: file, line: line)
    }

    func testPortraitFillsTheWidthAndCropsTopAndBottomEvenly() {
        // A phone photo, 3:4 upright.
        let rect = PlantHeroGeometry.coverRect(imageSize: CGSize(width: 3024, height: 4032), in: hero)
        assertCovers(rect, hero)
        XCTAssertEqual(rect.minX, 0, accuracy: 0.001)
        XCTAssertEqual(rect.width, hero.width, accuracy: 0.001)
        XCTAssertEqual(rect.height, 524, accuracy: 0.001)
    }

    func testLandscapeFillsTheHeightAndCropsTheSidesEvenly() {
        let rect = PlantHeroGeometry.coverRect(imageSize: CGSize(width: 4032, height: 3024), in: hero)
        assertCovers(rect, hero)
        XCTAssertEqual(rect.height, hero.height, accuracy: 0.001)
        XCTAssertEqual(rect.minX, -(rect.width - hero.width) / 2, accuracy: 0.001)
    }

    func testSquareAndVeryTallAndVeryWidePhotosCover() {
        for size in [CGSize(width: 1200, height: 1200), CGSize(width: 900, height: 1600),
                     CGSize(width: 1600, height: 900), CGSize(width: 100, height: 3000), CGSize(width: 3000, height: 100)] {
            assertCovers(PlantHeroGeometry.coverRect(imageSize: size, in: hero), hero)
        }
    }

    func testStillCoversWhenTheHeroStretches() {
        // Pulled down, the hero grows taller (and on other phones, wider).
        for bounds in [CGSize(width: 393, height: 520), CGSize(width: 430, height: 380), CGSize(width: 320, height: 380)] {
            assertCovers(PlantHeroGeometry.coverRect(imageSize: CGSize(width: 696, height: 1239), in: bounds), bounds)
        }
    }

    func testEmptySizesDoNotProduceNaN() {
        XCTAssertEqual(PlantHeroGeometry.coverRect(imageSize: .zero, in: hero), CGRect(origin: .zero, size: hero))
        XCTAssertEqual(PlantHeroGeometry.coverRect(imageSize: CGSize(width: 10, height: 10), in: .zero), .zero)
    }
}
