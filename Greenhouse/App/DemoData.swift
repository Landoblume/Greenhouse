#if DEBUG
import CoreData
import SwiftUI
import UIKit

/// Sample plants for looking at screens in the simulator, where there's no
/// one to tap through setup. Debug builds only:
///
///     xcrun simctl launch booted com.landenblume.greenhouse -demoData YES -openTab 2
///
/// `-demoData` fills an empty store once; `-openTab` picks the starting tab
/// (0 Plants, 1 Care, 2 Plans, 3 Settings). Add `-demoEmpty YES` to seed a
/// household with no plants, and `-demoGenus Monstera` to open Plants with
/// that genus filter on. `-demoMany YES` adds 100 more plants.
enum DemoData {
    static var openTab: Int { UserDefaults.standard.integer(forKey: "openTab") }
    static var startingGenus: String? { UserDefaults.standard.string(forKey: "demoGenus") }

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
        // `-demoEmpty YES`: a household with no plants, for the empty states.
        if defaults.bool(forKey: "demoEmpty") {
            persistence.save(context)
            return
        }
        let catalog = SpeciesCatalog.shared
        let calendar = Calendar.current
        func ago(months: Int = 0, days: Int = 0, years: Int = 0) -> Date {
            var date = calendar.date(byAdding: .year, value: -years, to: .now)!
            date = calendar.date(byAdding: .month, value: -months, to: date)!
            return calendar.date(byAdding: .day, value: -days, to: date)!
        }
        // The one bundled sample picture stands in for every plant photo.
        let samplePhoto = UIImage(named: "SampleMonstera").flatMap { ImageTools.preparedJPEG(from: $0) }
        func plant(_ id: String, _ nickname: String, monthsAgo: Int, acquired: Date? = nil,
                   photoTakenAt: Date? = nil, waterEvery: Int = 7) -> Plant {
            let acquired = acquired ?? ago(months: monthsAgo)
            return PlantFactory.create(scientificName: "", species: catalog.species(id: id), nickname: nickname,
                                       acquired: acquired, location: nil, setting: .indoor, waterEvery: waterEvery,
                                       photo: photoTakenAt == nil ? nil : samplePhoto, photoTakenAt: photoTakenAt,
                                       now: acquired, household: household, context: context)
        }
        func water(_ plant: Plant, by name: String, at date: Date) {
            guard let task = plant.wateringTask else { return }
            CareSchedule.markDone(task, by: name, at: date, household: household, context: context)
        }
        let aloe = plant("aloe-vera", "Spike", monthsAgo: 7, photoTakenAt: ago(months: 6))
        let pothos = plant("nephrolepis-exaltata", "Fernando", monthsAgo: 3, photoTakenAt: ago(months: 2))
        _ = plant("aloe-vera", "Little aloe", monthsAgo: 1)
        let succulents = Collections.create(name: "Succulents", plants: [aloe], household: household, context: context)
        Collections.create(name: "Bathroom", plants: [pothos], household: household, context: context)
        Plans.addWish(species: catalog.search("marble queen").first, scientificName: "", notes: "Saw one at the farmers market",
                      by: "Sam", collection: nil, household: household, context: context)
        Plans.addWish(species: nil, scientificName: "Haworthia cooperi", notes: nil, by: "Sam",
                      collection: succulents, household: household, context: context)
        let paint = Plans.addProject(title: "Spray paint the new greenhouse", notes: "Matte black, two coats",
                                     targetDate: Calendar.current.date(byAdding: .day, value: 10, to: .now), plants: [aloe],
                                     collection: nil, household: household, context: context)
        Plans.setState(paint, .inProgress)
        Plans.updateDetails(paint, budget: 60, place: "Back patio", link: "https://example.com/greenhouse-paint")
        Plans.addItem(.step, title: "Sand the frame", to: paint, household: household, context: context)?.isDone = true
        Plans.addItem(.step, title: "Two coats of primer", to: paint, household: household, context: context)
        Plans.addItem(.supply, title: "Matte black spray paint ×4", cost: 32, to: paint, household: household, context: context)?.isDone = true
        Plans.addItem(.supply, title: "Drop cloth", cost: 12, to: paint, household: household, context: context)
        let done = Plans.addProject(title: "Repot the fern", notes: nil, targetDate: nil, plants: [pothos],
                                    collection: nil, household: household, context: context)
        Plans.setDone(done, true)
        Milestones.add(title: "New pot", date: Calendar.current.date(byAdding: .day, value: -20, to: .now) ?? .now,
                       notes: "Terracotta from the garden center", by: "Sam", to: aloe, household: household, context: context)
        Milestones.add(title: "First bloom", date: Calendar.current.date(byAdding: .day, value: -3, to: .now) ?? .now,
                       notes: nil, by: "Sam", to: aloe, household: household, context: context)

        // --- Fixtures other screens need for screenshots (placeholder names only) ---

        // A plant whose anniversary is today, with a photo taken one year ago today:
        // the birthday banner and the Plants-tab "On this day" card.
        let birthday = plant("monstera-deliciosa", "Birdie", monthsAgo: 0, acquired: ago(years: 2),
                             photoTakenAt: ago(years: 1), waterEvery: 7)
        water(birthday, by: "Alex", at: ago(days: 5))
        water(birthday, by: "Sam", at: ago(days: 12))

        // Nested Combine: A + B -> AB, then AB + C -> ABC, with care logged by
        // two people on every source before it merged.
        let rosetteA = plant("echeveria-elegans", "Rosette A", monthsAgo: 0, acquired: ago(months: 7), photoTakenAt: ago(months: 7))
        let rosetteB = plant("echeveria-elegans", "Rosette B", monthsAgo: 0, acquired: ago(months: 6))
        for (index, source) in [rosetteA, rosetteB].enumerated() {
            water(source, by: "Alex", at: ago(months: 5, days: 10 + index))
            water(source, by: "Sam", at: ago(months: 5, days: 3 + index))
        }
        let rosetteAB = Lineage.staple([rosetteA, rosetteB], nickname: "Rosette AB", date: ago(months: 4),
                                       household: household, context: context)
        water(rosetteAB, by: "Alex", at: ago(months: 3, days: 20))
        water(rosetteAB, by: "Sam", at: ago(months: 3, days: 12))
        let rosetteC = plant("echeveria-elegans", "Rosette C", monthsAgo: 0, acquired: ago(months: 3))
        water(rosetteC, by: "Sam", at: ago(months: 2, days: 20))
        water(rosetteC, by: "Alex", at: ago(months: 2, days: 14))
        let trio = Lineage.staple([rosetteAB, rosetteC], nickname: "The Trio", date: ago(months: 2),
                                  household: household, context: context)
        water(trio, by: "Alex", at: ago(days: 9))

        // A plant with no photos at all.
        _ = plant("ocimum-basilicum", "Bare Basil", monthsAgo: 1)

        // A plant with 100+ waterings, alternating between the two people.
        let veteran = plant("ficus-lyrata", "Centurion", monthsAgo: 0, acquired: ago(years: 3), photoTakenAt: ago(months: 2))
        for week in 0..<110 {
            water(veteran, by: week.isMultiple(of: 2) ? "Alex" : "Sam", at: ago(days: week * 7 + 2))
        }

        // A combined plant that is also in a project: its tile shows the hammer and
        // the Combined badge together.
        paint.mutableSetValue(forKey: "plants").add(trio)

        // `-demoMany YES`: about 100 more plants, to see how the grid scrolls.
        if defaults.bool(forKey: "demoMany") {
            let species = ["monstera-deliciosa", "ficus-lyrata", "pilea-peperomioides", "epipremnum-aureum",
                           "aloe-vera", "echeveria-elegans", "ocimum-basilicum", "ficus-elastica"]
            for number in 1...100 {
                let id = species[number % species.count]
                let hasPhoto = number % 3 != 0
                let added = plant(id, "Plant \(String(format: "%03d", number))", monthsAgo: number % 18,
                                  photoTakenAt: hasPhoto ? ago(months: number % 18, days: number % 28) : nil,
                                  waterEvery: 3 + number % 10)
                if number % 2 == 0 { water(added, by: number % 4 == 0 ? "Alex" : "Sam", at: ago(days: number % 9)) }
            }
        }

        persistence.save(context)
    }
}
#endif
