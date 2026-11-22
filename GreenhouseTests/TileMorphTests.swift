import Combine
import CoreData
import XCTest
@testable import Greenhouse

/// v1.5.1 connect: how a tile opens its plant page, and change listeners
/// that only hear the main-thread context.
final class TileMorphTests: XCTestCase {
    func testStylePicksZoomOverlayOrCrossfade() {
        XCTAssertEqual(TileMorph.style(zoomAvailable: true, reduceMotion: false), .zoom)
        XCTAssertEqual(TileMorph.style(zoomAvailable: false, reduceMotion: false), .overlay, "iOS 17 has no zoom")
        XCTAssertEqual(TileMorph.style(zoomAvailable: true, reduceMotion: false, forceOverlay: true), .overlay)
        XCTAssertEqual(TileMorph.style(zoomAvailable: true, reduceMotion: true), .crossfade)
        XCTAssertEqual(TileMorph.style(zoomAvailable: false, reduceMotion: true), .crossfade)
        XCTAssertEqual(TileMorph.style(zoomAvailable: true, reduceMotion: true, forceOverlay: true), .crossfade,
                       "Reduce Motion always wins")
    }

    func testTheHeroWaitsForTheOverlayAndFadesOnlyUnderReduceMotion() {
        XCTAssertEqual(TileMorph.zoom.heroEntrance, .shown)
        XCTAssertEqual(TileMorph.overlay.heroEntrance, .afterFlight, "or the photo would show twice")
        XCTAssertEqual(TileMorph.crossfade.heroEntrance, .fadeIn)
    }

    func testHeroRectIsTheTopOfTheScreenInTheOverlaysSpace() {
        let screen = CGRect(x: 0, y: 0, width: 390, height: 844)
        XCTAssertEqual(TileMorph.heroRect(in: screen), CGRect(x: 0, y: 0, width: 390, height: GH.PlantPage.heroHeight))
        // An overlay that starts lower (inside a safe area) reaches up to the top.
        let inset = CGRect(x: 0, y: 59, width: 390, height: 785)
        XCTAssertEqual(TileMorph.heroRect(in: inset), CGRect(x: 0, y: -59, width: 390, height: GH.PlantPage.heroHeight))
    }

    func testTileRoutesAreThePlant() {
        let store = TestStore()
        let a = store.plant(nickname: "A", acquired: .now)
        let b = store.plant(nickname: "B", acquired: .now)
        XCTAssertEqual(PlantTileRoute(plant: a), PlantTileRoute(plant: a))
        XCTAssertNotEqual(PlantTileRoute(plant: a), PlantTileRoute(plant: b))
        XCTAssertEqual(PlantTileRoute(plant: a).entrance, .fadeIn, "no flight: the hero fades in on its own")
        XCTAssertNotEqual(PlantTileRoute(plant: a, entrance: .afterFlight), PlantTileRoute(plant: a, entrance: .fadeIn))
    }

    // MARK: ContextChanges

    func testTouchesReadsOnlyTheGivenContext() {
        let store = TestStore()
        let collection = Collections.create(name: "Succulents", plants: [], household: store.household,
                                            context: store.context, persistence: store.persistence)
        let background = store.persistence.container.newBackgroundContext()
        func note(from context: NSManagedObjectContext) -> Notification {
            Notification(name: .NSManagedObjectContextObjectsDidChange, object: context,
                         userInfo: [NSUpdatedObjectsKey: Set<NSManagedObject>([collection])])
        }
        let isCollection: (NSManagedObject) -> Bool = { $0 is PlantCollection }
        XCTAssertTrue(ContextChanges.touches(note(from: store.context), in: store.context, where: isCollection))
        XCTAssertFalse(ContextChanges.touches(note(from: background), in: store.context, where: isCollection),
                       "another context's note is never read")
        XCTAssertFalse(ContextChanges.touches(note(from: store.context), in: store.context, where: { $0 is Plant }))
        XCTAssertFalse(ContextChanges.touches(note(from: store.context), in: nil, where: isCollection),
                       "a deleted object has no context to listen to")
    }

    /// A save on a background context (like a CloudKit import) reaches the
    /// listener only through the merge into the main context, on the main
    /// thread: never from the background queue itself.
    func testBackgroundSavesArriveOnTheMainThreadOnly() throws {
        let store = TestStore()
        store.save()
        let householdID = store.household.objectID
        var notes: [(main: Bool, collection: Bool)] = []
        let merged = expectation(description: "merged into the main context")
        let token = ContextChanges.publisher(for: store.context).sink { note in
            let collection = ContextChanges.touches(note, in: store.context, where: { $0 is PlantCollection })
            notes.append((Thread.isMainThread, collection))
            if collection { merged.fulfill() }
        }
        defer { token.cancel() }

        let persistence = store.persistence
        let background = persistence.container.newBackgroundContext()
        background.perform {
            guard let household = try? background.existingObject(with: householdID) as? Household else { return }
            Collections.create(name: "From the other phone", household: household, context: background, persistence: persistence)
            try? background.save()
        }
        wait(for: [merged], timeout: 5)
        XCTAssertFalse(notes.isEmpty)
        XCTAssertTrue(notes.allSatisfy(\.main), "every note arrived on the main thread")
    }

    func testNoContextMeansNoNotes() {
        var count = 0
        let token = ContextChanges.publisher(for: nil).sink { _ in count += 1 }
        NotificationCenter.default.post(name: .NSManagedObjectContextObjectsDidChange, object: nil)
        token.cancel()
        XCTAssertEqual(count, 0)
    }
}
