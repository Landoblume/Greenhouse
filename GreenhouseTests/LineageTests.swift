import CoreData
import XCTest
@testable import Greenhouse

/// #3: staple and split, and the family tree.
final class LineageTests: XCTestCase {
    func testStaplingTwoAloesMakesOneActivePlant() {
        let store = TestStore()
        let march = store.plant(acquired: day(2026, 3, 26), photo: true)
        let july = store.plant(acquired: day(2026, 7, 24), photo: true)

        let merged = Lineage.staple([march, july], nickname: "Big aloe", date: day(2026, 10, 17),
                                    household: store.household, context: store.context, persistence: store.persistence)
        store.save()

        let active = (store.household.plants ?? []).filter(\.isActive)
        XCTAssertEqual(active, [merged])
        XCTAssertEqual(march.statusValue, .stapled)
        XCTAssertEqual(july.statusValue, .stapled)
        // Originals stay reachable through the event.
        XCTAssertEqual(Set(Lineage.parents(of: merged)), [march, july])
        XCTAssertEqual(march.consumedBy?.outputs, [merged])
    }

    func testStapleSummaryNamesBothOriginalsWithDates() {
        let store = TestStore()
        let march = store.plant(acquired: day(2026, 3, 26))
        let july = store.plant(acquired: day(2026, 7, 24))
        let merged = Lineage.staple([july, march], nickname: nil, date: day(2026, 10, 17),
                                    household: store.household, context: store.context, persistence: store.persistence)

        let summary = Lineage.summary(of: try! XCTUnwrap(merged.producedBy))
        XCTAssertTrue(summary.hasPrefix("Stapled from Aloe vera (acq. Mar 26, 2026) + Aloe vera (acq. Jul 24, 2026)"), summary)
        XCTAssertTrue(summary.hasSuffix("on Oct 17, 2026"), summary)
        let history = Lineage.history(of: merged)
        XCTAssertEqual(history.compactMap(\.plant), [march, july])
    }

    func testStapledPlantTimelineIncludesOriginalsPhotosWithSources() {
        let store = TestStore()
        let march = store.plant(acquired: day(2026, 3, 26), photo: true)
        let july = store.plant(acquired: day(2026, 7, 24), photo: true)
        let merged = Lineage.staple([march, july], nickname: nil, date: day(2026, 10, 17),
                                    household: store.household, context: store.context, persistence: store.persistence)
        PlantFactory.addPhoto(Data([0x09]), takenAt: day(2026, 10, 18), to: merged, household: store.household, context: store.context, persistence: store.persistence)

        let timeline = Lineage.timeline(for: merged)
        XCTAssertEqual(timeline.map(\.source), [march, july, merged])
    }

    func testSplitMakesLinkedChildren() {
        let store = TestStore()
        let mother = store.plant("epipremnum-aureum", nickname: "Mom's pothos", acquired: day(2025, 5, 1))
        let kids = Lineage.split(mother, names: ["Cutting A", "Cutting B", "Cutting C"], date: day(2026, 10, 17),
                                 household: store.household, context: store.context, persistence: store.persistence)

        XCTAssertEqual(kids.count, 3)
        XCTAssertEqual(mother.statusValue, .split)
        for kid in kids {
            XCTAssertTrue(kid.isActive)
            XCTAssertEqual(kid.scientificName, "Epipremnum aureum")
            XCTAssertEqual(Lineage.summary(of: try! XCTUnwrap(kid.producedBy)), "Split from Mom's pothos on Oct 17, 2026")
            // How long you've had it counts from the mother plant.
            XCTAssertEqual(Lineage.effectiveAcquiredDate(of: kid), day(2025, 5, 1))
        }
    }

    func testNestedLineageShowsTheWholeTree() {
        let store = TestStore()
        let mother = store.plant("epipremnum-aureum", nickname: "Mom", acquired: day(2025, 1, 10))
        let other = store.plant("epipremnum-aureum", nickname: "Store pothos", acquired: day(2026, 2, 1))
        let kids = Lineage.split(mother, names: ["Kid 1", "Kid 2"], date: day(2026, 4, 1),
                                 household: store.household, context: store.context, persistence: store.persistence)
        let merged = Lineage.staple([kids[0], other], nickname: "Full pot", date: day(2026, 9, 1),
                                    household: store.household, context: store.context, persistence: store.persistence)

        let history = Lineage.history(of: merged)
        let texts = history.map(\.text)
        XCTAssertTrue(texts[0].hasPrefix("Stapled from"))
        XCTAssertTrue(texts.contains("Split from Mom on Apr 1, 2026"), texts.joined(separator: "\n"))
        let mom = try! XCTUnwrap(history.first { $0.plant == mother })
        XCTAssertEqual(mom.depth, 3, "mother sits under the split, under Kid 1")
        XCTAssertEqual(Set(Lineage.ancestors(of: merged)), [kids[0], other, mother])
        XCTAssertEqual(Lineage.effectiveAcquiredDate(of: merged), day(2025, 1, 10))
    }

    func testRetiredPlantPointsToWhatItBecame() {
        let store = TestStore()
        let a = store.plant(acquired: day(2026, 3, 26))
        let b = store.plant(acquired: day(2026, 7, 24))
        let merged = Lineage.staple([a, b], nickname: "Together", date: day(2026, 10, 17),
                                    household: store.household, context: store.context, persistence: store.persistence)
        let history = Lineage.history(of: a)
        XCTAssertEqual(history.first?.text, "Stapled on Oct 17, 2026 into:")
        XCTAssertEqual(history.compactMap(\.plant).first, merged)
    }

    // MARK: Deleting plants

    func testDeletingAPlantRemovesItsPhotosAndOwnReminders() {
        let store = TestStore()
        let aloe = store.plant(acquired: day(2026, 3, 26), photo: true)
        let pothos = store.plant("epipremnum-aureum", acquired: day(2026, 4, 1))
        let shared = CareSchedule.makeTask(name: "Peroxide", count: 3, unit: .month, firstDue: day(2026, 11, 1),
                                           plants: [aloe, pothos], household: store.household,
                                           context: store.context, persistence: store.persistence)
        store.save()

        Lineage.delete(aloe, context: store.context)
        store.save()

        XCTAssertEqual(store.household.plants, [pothos])
        XCTAssertEqual(count(Photo.self, in: store), 0)
        // Its watering task goes; the shared task stays for the pothos.
        let tasks = (store.household.tasks ?? [])
        XCTAssertEqual(tasks.count, 2)
        XCTAssertTrue(tasks.contains(shared))
        XCTAssertEqual(shared.plants, [pothos])
    }

    func testDeletingAStapledPlantRemovesItsHiddenOriginals() {
        let store = TestStore()
        let march = store.plant(acquired: day(2026, 3, 26), photo: true)
        let july = store.plant(acquired: day(2026, 7, 24), photo: true)
        let merged = Lineage.staple([march, july], nickname: nil, household: store.household,
                                    context: store.context, persistence: store.persistence)
        store.save()

        Lineage.delete(merged, context: store.context)
        store.save()

        XCTAssertEqual(store.household.plants ?? [], [])
        XCTAssertEqual(count(Photo.self, in: store), 0)
        XCTAssertEqual(count(LineageEvent.self, in: store), 0)
        XCTAssertEqual(store.household.tasks ?? [], [])
    }

    func testDeletingOneHalfOfASplitKeepsTheParentForTheOtherHalf() {
        let store = TestStore()
        let parent = store.plant(acquired: day(2026, 3, 26), photo: true)
        let halves = Lineage.split(parent, names: ["Left", "Right"], household: store.household,
                                   context: store.context, persistence: store.persistence)
        store.save()

        Lineage.delete(halves[0], context: store.context)
        store.save()

        XCTAssertEqual(store.household.plants, [parent, halves[1]])
        XCTAssertEqual(Lineage.parents(of: halves[1]), [parent])
        XCTAssertEqual(parent.consumedBy?.outputs, [halves[1]])
        XCTAssertEqual(Lineage.timeline(for: halves[1]).count, 1)
    }

    private func count<T: NSManagedObject>(_ type: T.Type, in store: TestStore) -> Int {
        (try? store.context.count(for: NSFetchRequest<T>(entityName: String(describing: type)))) ?? -1
    }
}
