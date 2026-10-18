import CoreData
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import Greenhouse

/// v1.2: changing photos after they're added.
final class PhotoTests: XCTestCase {
    func testFirstPhotoAddedStaysMainUntilAnotherIsPicked() throws {
        let store = TestStore()
        let plant = store.plant(acquired: day(2026, 3, 1))
        let first = PlantFactory.addPhoto(Data([1]), takenAt: day(2026, 6, 1), to: plant, household: store.household,
                                          context: store.context, persistence: store.persistence)
        let newer = PlantFactory.addPhoto(Data([2]), takenAt: day(2026, 9, 1), to: plant, household: store.household,
                                          context: store.context, persistence: store.persistence)
        let olderFromLibrary = PlantFactory.addPhoto(Data([3]), takenAt: day(2026, 3, 1), to: plant, household: store.household,
                                                     context: store.context, persistence: store.persistence)
        XCTAssertEqual(PlantPhotos.cover(for: plant), first, "later photos, newer or older, don't take over")

        PlantPhotos.setCover(newer, of: plant)
        XCTAssertEqual(PlantPhotos.cover(for: plant), newer)
        XCTAssertTrue(PlantPhotos.isCover(newer, of: plant))
        XCTAssertFalse(PlantPhotos.isCover(olderFromLibrary, of: plant))
    }

    func testPlantCreatedWithAPhotoUsesItAsMain() throws {
        let store = TestStore()
        let plant = store.plant(acquired: day(2026, 3, 1), photo: true)
        let photo = try XCTUnwrap(plant.photos?.first)
        XCTAssertEqual(plant.coverPhotoID, photo.uuid)
    }

    func testPlantsWithoutAPickedMainPhotoShowTheOldest() {
        let store = TestStore()
        let plant = store.plant(acquired: day(2026, 3, 1))
        let late = PlantFactory.addPhoto(Data([1]), takenAt: day(2026, 9, 1), to: plant, household: store.household,
                                         context: store.context, persistence: store.persistence)
        let early = PlantFactory.addPhoto(Data([2]), takenAt: day(2026, 4, 1), to: plant, household: store.household,
                                          context: store.context, persistence: store.persistence)
        plant.coverPhotoID = nil  // like plants saved before main photos were set on upload
        XCTAssertEqual(PlantPhotos.cover(for: plant), early)
        XCTAssertNotEqual(PlantPhotos.cover(for: plant), late)
    }

    func testDeletingTheMainPhotoFallsBackToOldest() throws {
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

    // MARK: Cropping

    func testUncroppedWindowCoversTheWholeImage() {
        let image = CGSize(width: 4000, height: 3000)
        let window = ImageCrop.window(ratio: ImageCrop.Aspect.original.ratio(for: image), in: CGSize(width: 400, height: 800))
        XCTAssertEqual(window, CGSize(width: 400, height: 300))
        XCTAssertEqual(ImageCrop.rect(imageSize: image, window: window, zoom: 1, offset: .zero),
                       CGRect(x: 0, y: 0, width: 4000, height: 3000))
    }

    func testSquareCropOfALandscapePhotoTakesTheMiddle() {
        let image = CGSize(width: 4000, height: 3000)
        let window = CGSize(width: 300, height: 300)
        XCTAssertEqual(ImageCrop.rect(imageSize: image, window: window, zoom: 1, offset: .zero),
                       CGRect(x: 500, y: 0, width: 3000, height: 3000))
    }

    func testZoomingAndDraggingMovesTheCrop() {
        let image = CGSize(width: 4000, height: 3000)
        let window = CGSize(width: 400, height: 300)  // 0.1 pt per pixel at zoom 1
        // Zoom 2 shows the middle half.
        XCTAssertEqual(ImageCrop.rect(imageSize: image, window: window, zoom: 2, offset: .zero),
                       CGRect(x: 1000, y: 750, width: 2000, height: 1500))
        // Dragging the image right by 50 pt (250 px at 0.2 pt/px) shows more of its left side.
        XCTAssertEqual(ImageCrop.rect(imageSize: image, window: window, zoom: 2, offset: CGSize(width: 50, height: 0)),
                       CGRect(x: 750, y: 750, width: 2000, height: 1500))
        // Dragging too far stops at the image's edge.
        XCTAssertEqual(ImageCrop.rect(imageSize: image, window: window, zoom: 2, offset: CGSize(width: 9999, height: -9999)),
                       CGRect(x: 0, y: 1500, width: 2000, height: 1500))
    }
}
