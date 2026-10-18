#if DEBUG
import CoreData
import SwiftUI

/// Sample plants for looking at screens in the simulator, where there's no
/// one to tap through setup. Debug builds only:
///
///     xcrun simctl launch booted com.landenblume.greenhouse -demoData YES -openTab 2
///
/// `-demoData` fills an empty store once; `-openTab` picks the starting tab
/// (0 Plants, 1 Care, 2 Plans, 3 Settings).
enum DemoData {
    static var openTab: Int { UserDefaults.standard.integer(forKey: "openTab") }

    static func seedIfRequested(persistence: Persistence = .shared) {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: "demoData") else { return }
        let context = persistence.viewContext
        guard persistence.currentHousehold(in: context) == nil else { return }
        if (defaults.string(forKey: SettingsKey.myName) ?? "").isEmpty {
            defaults.set("Sam", forKey: SettingsKey.myName)
        }
        let household = persistence.createHousehold(name: "Demo household", in: context)
        household.hardinessZone = "7a"
        let catalog = SpeciesCatalog.shared
        func plant(_ id: String, _ nickname: String, monthsAgo: Int) -> Plant {
            let acquired = Calendar.current.date(byAdding: .month, value: -monthsAgo, to: .now)!
            return PlantFactory.create(scientificName: "", species: catalog.species(id: id), nickname: nickname,
                                       acquired: acquired, location: nil, setting: .indoor, waterEvery: 7,
                                       photo: nil, now: acquired, household: household, context: context)
        }
        let aloe = plant("aloe-vera", "Spike", monthsAgo: 7)
        let pothos = plant("nephrolepis-exaltata", "Fernando", monthsAgo: 3)
        _ = plant("aloe-vera", "Little aloe", monthsAgo: 1)
        let succulents = Collections.create(name: "Succulents", plants: [aloe], household: household, context: context)
        Collections.create(name: "Bathroom", plants: [pothos], household: household, context: context)
        Plans.addWish(species: catalog.search("marble queen").first, scientificName: "", notes: "Saw one at the farmers market",
                      by: "Sam", collection: nil, household: household, context: context)
        Plans.addWish(species: nil, scientificName: "Haworthia cooperi", notes: nil, by: "Sam",
                      collection: succulents, household: household, context: context)
        Plans.addProject(title: "Spray paint the new greenhouse", notes: "Matte black, two coats",
                         targetDate: Calendar.current.date(byAdding: .day, value: 10, to: .now), plants: [aloe],
                         collection: nil, household: household, context: context)
        let done = Plans.addProject(title: "Repot the fern", notes: nil, targetDate: nil, plants: [pothos],
                                    collection: nil, household: household, context: context)
        Plans.setDone(done, true)
        persistence.save(context)
    }
}
#endif
