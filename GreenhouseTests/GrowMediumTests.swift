import XCTest
@testable import Greenhouse

final class GrowMediumTests: XCTestCase {
    private let acquired = day(2026, 11, 1)

    func testSoilIsTheDefaultAndStoredAsNothing() {
        let store = TestStore()
        let plant = store.plant(acquired: acquired)
        XCTAssertNil(plant.medium)
        XCTAssertEqual(plant.mediumValue, .soil)
        let task = plant.wateringTask
        XCTAssertEqual(task?.name, "Water")
        XCTAssertEqual(task?.intervalCount, 7)
        XCTAssertEqual(task?.title, "Water Aloe vera")
        plant.mediumValue = .leca
        XCTAssertEqual(plant.medium, "leca")
        plant.mediumValue = .soil
        XCTAssertNil(plant.medium)
        plant.medium = "nonsense"
        XCTAssertEqual(plant.mediumValue, .soil)
    }

    func testNonSoilPlantGetsChangeWaterEvery21Days() {
        let store = TestStore()
        let plant = PlantFactory.create(
            scientificName: "Epipremnum aureum", species: nil, nickname: "Pothos cutting",
            acquired: acquired, location: nil, setting: .indoor, medium: .water, photo: nil,
            now: acquired, household: store.household, context: store.context, persistence: store.persistence)
        XCTAssertEqual(plant.mediumValue, .water)
        let task = try! XCTUnwrap(plant.wateringTask)
        XCTAssertEqual(task.name, "Change water")
        XCTAssertEqual(task.intervalCount, 21)
        XCTAssertEqual(task.unit, .day)
        XCTAssertEqual(task.title, "Change water Pothos cutting")
        XCTAssertEqual(task.wateringMedium, .water)
    }

    func testExplicitIntervalWinsOverTheMediumDefault() {
        let store = TestStore()
        let plant = PlantFactory.create(
            scientificName: "Testus plantus", species: nil, nickname: nil,
            acquired: acquired, location: nil, setting: .indoor, medium: .sphagnum, waterEvery: 10, photo: nil,
            now: acquired, household: store.household, context: store.context, persistence: store.persistence)
        XCTAssertEqual(plant.wateringTask?.intervalCount, 10)
        XCTAssertEqual(plant.wateringTask?.name, "Change water")
    }

    func testMediumDefaults() {
        XCTAssertNil(GrowMedium.soil.defaultIntervalDays)
        for medium in GrowMedium.allCases where medium != .soil {
            XCTAssertEqual(medium.defaultIntervalDays, 21)
            XCTAssertEqual(medium.careTaskName, "Change water")
            XCTAssertNotEqual(medium.careIcon, GrowMedium.soil.careIcon)
        }
        XCTAssertEqual(GrowMedium.soil.careTaskName, "Water")
        XCTAssertEqual(Set(GrowMedium.allCases.map(\.icon)).count, 4, "each medium has its own picker icon")
    }

    func testChipLabelsPerMedium() {
        XCTAssertEqual(WateringChip.make(for: .upcoming(days: 5), medium: .soil),
                       WateringChip(label: "In 5 days", shortLabel: "in 5d", tone: .later))
        let water = WateringChip.make(for: .upcoming(days: 5), medium: .water)
        XCTAssertEqual(water?.label, "Change water in 5 days")
        XCTAssertEqual(water?.shortLabel, "in 5d")
        XCTAssertNotEqual(water?.icon, WateringChip.make(for: .upcoming(days: 5))?.icon, "a different icon from soil")
        XCTAssertEqual(WateringChip.make(for: .today, medium: .leca)?.label, "Change water today")
        XCTAssertEqual(WateringChip.make(for: .today, medium: .leca)?.tone, .due)
        XCTAssertEqual(WateringChip.make(for: .upcoming(days: 1), medium: .sphagnum)?.label, "Change water tomorrow")
        XCTAssertEqual(WateringChip.make(for: .overdue(days: 2), medium: .water)?.label, "Overdue · 2 days")
        XCTAssertNil(WateringChip.make(for: nil, medium: .water))
        // A soil chip is exactly what it always was, icon included.
        XCTAssertEqual(WateringChip.make(for: .today)?.icon, "drop.fill")
    }

    func testChangingMediumRenamesADefaultNamedTaskAndKeepsTheInterval() {
        let store = TestStore()
        let plant = store.plant(acquired: acquired, waterEvery: 9)
        let task = try! XCTUnwrap(plant.wateringTask)

        GrowMedium.apply(.water, to: plant)
        XCTAssertEqual(plant.mediumValue, .water)
        XCTAssertEqual(task.name, "Change water")
        XCTAssertEqual(task.intervalCount, 9, "the interval never changes")

        GrowMedium.apply(.leca, to: plant)
        XCTAssertEqual(task.name, "Change water")

        GrowMedium.apply(.soil, to: plant)
        XCTAssertNil(plant.medium)
        XCTAssertEqual(task.name, "Water")
        XCTAssertEqual(task.intervalCount, 9)
    }

    func testChangingMediumKeepsACustomTaskName() {
        let store = TestStore()
        let plant = store.plant(acquired: acquired)
        let task = try! XCTUnwrap(plant.wateringTask)
        task.name = "Top up the jar"
        GrowMedium.apply(.water, to: plant)
        XCTAssertEqual(task.name, "Top up the jar")
        XCTAssertEqual(task.intervalCount, 7)
        GrowMedium.apply(.soil, to: plant)
        XCTAssertEqual(task.name, "Top up the jar")
    }

    func testChangingMediumLeavesOtherTasksAlone() {
        let store = TestStore()
        let plant = store.plant(acquired: acquired)
        let other = CareSchedule.makeTask(name: "Water", count: 30, unit: .day, firstDue: acquired,
                                          plants: [plant], household: store.household,
                                          context: store.context, persistence: store.persistence)
        GrowMedium.apply(.water, to: plant)
        XCTAssertEqual(other.name, "Water", "only the watering reminder is renamed")
        XCTAssertEqual(plant.wateringTask?.name, "Change water")
    }

    func testTaskTitleFollowsItsPlantsMedium() {
        let store = TestStore()
        let a = store.plant(nickname: "Alpha", acquired: acquired)
        let b = store.plant(nickname: "Beta", acquired: acquired)
        XCTAssertEqual(a.wateringTask?.title, "Water Alpha")
        GrowMedium.apply(.water, to: a)
        XCTAssertEqual(a.wateringTask?.title, "Change water Alpha")
        XCTAssertEqual(b.wateringTask?.title, "Water Beta")
    }
}
