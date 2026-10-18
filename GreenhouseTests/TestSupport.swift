import CoreData
import XCTest
@testable import Greenhouse

/// A fresh in-memory store per test, with one household in it.
struct TestStore {
    let persistence = Persistence(inMemory: true)
    let household: Household
    var context: NSManagedObjectContext { persistence.viewContext }

    init() {
        household = persistence.createHousehold(name: "Test", in: persistence.viewContext)
    }

    @discardableResult
    func plant(
        _ catalogID: String? = "aloe-vera",
        nickname: String? = nil,
        acquired: Date,
        setting: PlantSetting = .indoor,
        waterEvery: Int = 7,
        photo: Bool = false,
        now: Date? = nil
    ) -> Plant {
        let species = SpeciesCatalog.shared.species(id: catalogID)
        let plant = PlantFactory.create(
            scientificName: species?.latin ?? "Testus plantus",
            species: species,
            nickname: nickname,
            acquired: acquired,
            location: nil,
            setting: setting,
            waterEvery: waterEvery,
            photo: photo ? Data([0x01]) : nil,
            now: now ?? acquired,
            household: household,
            context: context,
            persistence: persistence
        )
        persistence.save(context)
        return plant
    }

    func save() { persistence.save(context) }
}

func day(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
    Calendar.current.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
}
