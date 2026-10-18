import CoreData
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import Greenhouse

/// v1.2: changing photos after they're added.
final class PhotoTests: XCTestCase {
    func testMainPhotoDefaultsToNewestAndCanBePicked() throws {
        let store = TestStore()
        let plant = store.plant(acquired: day(2026, 3, 1))
        let first = PlantFactory.addPhoto(Data([1]), takenAt: day(2026, 3, 1), to: plant, household: store.household,
                                          context: store.context, persistence: store.persistence)
        let second = PlantFactory.addPhoto(Data([2]), takenAt: day(2026, 6, 1), to: plant, household: store.household,
                                           context: store.context, persistence: store.persistence)
        XCTAssertEqual(PlantPhotos.cover(for: plant), second)

        PlantPhotos.setCover(first, of: plant)
        XCTAssertEqual(PlantPhotos.cover(for: plant), first)
        XCTAssertTrue(PlantPhotos.isCover(first, of: plant))
    }

    func testDeletingTheMainPhotoFallsBackToNewest() throws {
        let store = TestStore()
        let plant = store.plant(acquired: day(2026, 3, 1))
        let test = PlantFactory.addPhoto(Data([1]), takenAt: day(2026, 10, 17), to: plant, household: store.household,
                                         context: store.context, persistence: store.persistence)
        let real = PlantFactory.addPhoto(Data([2]), takenAt: day(2026, 10, 1), to: plant, household: store.household,
                                         context: store.context, persistence: store.persistence)
        PlantPhotos.setCover(test, of: plant)
        store.save()

        PlantPhotos.delete(test, context: store.context)
        store.save()

        XCTAssertNil(plant.coverPhotoID)
        XCTAssertEqual(plant.photos?.count, 1)
        XCTAssertEqual(PlantPhotos.cover(for: plant), real)
    }

    func testEditingCaptionAndDateReordersTimeline() {
        let store = TestStore()
        let plant = store.plant(acquired: day(2026, 3, 1))
        let a = PlantFactory.addPhoto(Data([1]), takenAt: day(2026, 10, 17), to: plant, household: store.household,
                                      context: store.context, persistence: store.persistence)
        let b = PlantFactory.addPhoto(Data([2]), takenAt: day(2026, 5, 1), to: plant, household: store.household,
                                      context: store.context, persistence: store.persistence)
        XCTAssertEqual(Lineage.timeline(for: plant).map(\.photo), [b, a])

        PlantPhotos.update(a, caption: "  First bloom ", takenAt: day(2026, 4, 2))
        XCTAssertEqual(a.caption, "First bloom")
        XCTAssertEqual(Lineage.timeline(for: plant).map(\.photo), [a, b])

        PlantPhotos.update(a, caption: "   ", takenAt: day(2026, 4, 2))
        XCTAssertNil(a.caption)
    }

    func testCaptureDateComesFromExif() throws {
        let data = try jpeg(exifDate: "2026:04:12 15:30:02")
        let date = try XCTUnwrap(PlantPhotos.captureDate(from: data))
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        XCTAssertEqual([parts.year, parts.month, parts.day, parts.hour, parts.minute], [2026, 4, 12, 15, 30])
        XCTAssertNil(PlantPhotos.captureDate(from: try jpeg(exifDate: nil)))
        XCTAssertNil(PlantPhotos.captureDate(from: Data([1, 2, 3])))
    }

    func testFirstPhotoUsesItsOwnDate() {
        let store = TestStore()
        let plant = PlantFactory.create(
            scientificName: "Phalaenopsis", species: nil, nickname: "Orchid", acquired: day(2026, 1, 1),
            location: nil, setting: .indoor, waterEvery: 7, photo: Data([1]), photoTakenAt: day(2025, 12, 24),
            now: day(2026, 10, 17), household: store.household, context: store.context, persistence: store.persistence
        )
        XCTAssertEqual(plant.photos?.first?.takenAt, day(2025, 12, 24))
    }

    private func jpeg(exifDate: String?) throws -> Data {
        let size = 4
        let context = try XCTUnwrap(CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(CGColor(red: 0, green: 1, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: size, height: size))
        let image = try XCTUnwrap(context.makeImage())
        let output = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil))
        var properties: [CFString: Any] = [:]
        if let exifDate {
            properties[kCGImagePropertyExifDictionary] = [kCGImagePropertyExifDateTimeOriginal: exifDate]
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return output as Data
    }
}
