import XCTest
@testable import Greenhouse

/// v1.5.3: camera-first cuttings with a photo and a medium.
final class CuttingTests: XCTestCase {
    private func take(_ parent: Plant, in store: TestStore, medium: GrowMedium = .soil, photo: Data? = nil,
                      nickname: String? = "Pip cutting") -> Plant {
        let cutting = Lineage.takeCutting(from: parent, nickname: nickname, date: day(2026, 11, 26), medium: medium, photo: photo,
                                          household: store.household, context: store.context, persistence: store.persistence)
        store.save()
        return cutting
    }

    func testPhotoBecomesTheCuttingsFirstPhotoAndCover() throws {
        let store = TestStore()
        let parent = store.plant(nickname: "Pip", acquired: day(2025, 1, 1), photo: true)
        let jpeg = Data([0xFF, 0xD8, 0x01])
        let cutting = take(parent, in: store, medium: .water, photo: jpeg)

        let photo = try XCTUnwrap(cutting.photos?.first)
        XCTAssertEqual(cutting.photos?.count, 1)
        XCTAssertEqual(photo.imageData, jpeg)
        XCTAssertEqual(photo.takenAt, day(2026, 11, 26))
        XCTAssertEqual(cutting.coverPhotoID, photo.uuid)
        XCTAssertEqual(PlantPhotos.cover(for: cutting), photo)
        XCTAssertEqual(parent.photos?.count, 1, "the parent's photos stay on the parent")
        XCTAssertEqual(cutting.nickname, "Pip cutting")
        XCTAssertEqual(cutting.acquiredDate, day(2026, 11, 26))
        XCTAssertEqual(cutting.mediumValue, .water)
        XCTAssertEqual(cutting.cuttingOf, parent)
    }

    func testNoPhotoLeavesTheCuttingWithoutOne() {
        let store = TestStore()
        let parent = store.plant(acquired: day(2025, 1, 1), photo: true)
        let cutting = take(parent, in: store, medium: .leca)
        XCTAssertTrue(cutting.photos?.isEmpty ?? true)
        XCTAssertNil(cutting.coverPhotoID)
    }

    func testNonSoilCuttingChangesWaterEvery21DaysWhateverTheParentDoes() throws {
        let store = TestStore()
        let parent = store.plant(acquired: day(2025, 1, 1), waterEvery: 10)
        for medium in [GrowMedium.water, .leca, .sphagnum] {
            let cutting = take(parent, in: store, medium: medium)
            let task = try XCTUnwrap(cutting.wateringTask)
            XCTAssertEqual(task.name, "Change water", "\(medium)")
            XCTAssertEqual(task.intervalCount, 21)
            XCTAssertEqual(task.unit, .day)
            XCTAssertEqual(task.firstDue, day(2026, 12, 17, hour: 0), "21 days from the day it was taken")
            XCTAssertEqual(cutting.mediumValue, medium)
        }
    }

    func testSoilCuttingKeepsTheParentsWateringInterval() throws {
        let store = TestStore()
        let parent = store.plant(nickname: "Pip", acquired: day(2025, 1, 1), waterEvery: 14)
        let cutting = take(parent, in: store, medium: .soil)
        let task = try XCTUnwrap(cutting.wateringTask)
        XCTAssertEqual(task.name, "Water")
        XCTAssertEqual(task.intervalCount, 14)
        XCTAssertNil(cutting.medium, "soil is stored as nothing")
    }

    func testSoilCuttingOfAWaterGrownParentDoesNotInheritItsChangeWaterInterval() throws {
        let store = TestStore()
        let species = try XCTUnwrap(SpeciesCatalog.shared.species(id: "aloe-vera"))
        let parent = PlantFactory.create(
            scientificName: species.latin, species: species, nickname: "Pip", acquired: day(2025, 1, 1),
            location: nil, setting: .indoor, medium: .water, photo: nil, now: day(2025, 1, 1),
            household: store.household, context: store.context, persistence: store.persistence)
        XCTAssertEqual(parent.wateringTask?.intervalCount, 21)
        let cutting = take(parent, in: store, medium: .soil)
        let task = try XCTUnwrap(cutting.wateringTask)
        XCTAssertEqual(task.name, "Water")
        XCTAssertEqual(task.intervalCount, Int64(species.waterDays))
    }

    func testDefaultsPrefillTheNameAndStartInWater() {
        let store = TestStore()
        let parent = store.plant(nickname: "Pip", acquired: day(2025, 1, 1))
        XCTAssertEqual(CuttingDefaults.name(for: parent), "Pip cutting")
        XCTAssertEqual(CuttingDefaults.medium(for: parent), .water, "a soil parent's cutting starts in water")
        for medium in [GrowMedium.water, .leca, .sphagnum] {
            parent.mediumValue = medium
            XCTAssertEqual(CuttingDefaults.medium(for: parent), medium, "otherwise it starts like its parent")
        }
    }

    // MARK: Combine keeps the medium

    private func combine(_ media: [GrowMedium], in store: TestStore) -> Plant {
        let plants = media.map { medium -> Plant in
            let plant = store.plant(acquired: day(2025, 1, 1))
            GrowMedium.apply(medium, to: plant)
            return plant
        }
        let merged = Lineage.staple(plants, nickname: "Both", date: day(2026, 11, 26), household: store.household,
                                    context: store.context, persistence: store.persistence)
        store.save()
        return merged
    }

    func testCombiningPlantsInTheSameMediumKeepsIt() {
        let store = TestStore()
        let merged = combine([.water, .water], in: store)
        XCTAssertEqual(merged.mediumValue, .water)
        XCTAssertEqual(merged.wateringTask?.name, "Change water")
    }

    func testCombiningMixedMediaFallsBackToSoil() {
        let store = TestStore()
        let merged = combine([.water, .soil], in: store)
        XCTAssertNil(merged.medium)
        XCTAssertEqual(merged.wateringTask?.name, "Water")
    }
}
