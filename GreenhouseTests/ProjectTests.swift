import CoreData
import XCTest
@testable import Greenhouse

/// Project pages: steps, supplies, costs and details.
final class ProjectTests: XCTestCase {
    private func project(_ store: TestStore) -> Project {
        Plans.addProject(title: "Paint the greenhouse", notes: nil, targetDate: nil, plants: [], collection: nil,
                         household: store.household, context: store.context, persistence: store.persistence)
    }

    func testStepsAndSuppliesAddUp() {
        let store = TestStore()
        let paint = project(store)
        func add(_ kind: ProjectItemKind, _ title: String, cost: Double = 0) -> ProjectItem? {
            Plans.addItem(kind, title: title, cost: cost, to: paint, household: store.household,
                          context: store.context, persistence: store.persistence)
        }
        let sand = add(.step, "Sand the frame")
        _ = add(.step, "Prime")
        XCTAssertNil(add(.step, "   "), "blank lines aren't added")
        let paintCans = add(.supply, "Spray paint", cost: 32)
        _ = add(.supply, "Drop cloth", cost: 12.5)
        sand?.isDone = true
        paintCans?.isDone = true

        XCTAssertEqual(Plans.items(.step, of: paint).map(\.title), ["Sand the frame", "Prime"])
        XCTAssertEqual(Plans.stepProgress(of: paint).done, 1)
        XCTAssertEqual(Plans.stepProgress(of: paint).total, 2)
        XCTAssertEqual(Plans.estimatedCost(of: paint), 44.5)
        XCTAssertEqual(Plans.spent(on: paint), 32)

        Plans.updateDetails(paint, budget: 60, place: "  Back patio ", link: "")
        XCTAssertEqual(ProjectSummary.parts(for: paint), ["1 of 2 steps", "\(ProjectSummary.money(32)) of \(ProjectSummary.money(60)) spent"])
        XCTAssertEqual(paint.place, "Back patio")
        XCTAssertNil(paint.link)
    }

    func testDeletingAProjectDeletesItsItems() {
        let store = TestStore()
        let paint = project(store)
        Plans.addItem(.step, title: "Sand", to: paint, household: store.household, context: store.context, persistence: store.persistence)
        store.save()

        store.context.delete(paint)
        store.save()

        XCTAssertEqual(try store.context.count(for: NSFetchRequest<ProjectItem>(entityName: "ProjectItem")), 0)
    }

    func testMovingHouseholdsBringsStepsAndDetails() throws {
        let store = TestStore()
        let joined = store.persistence.createHousehold(name: "Joined", in: store.context)
        let paint = project(store)
        Plans.updateDetails(paint, budget: 60, place: "Patio", link: "example.com")
        Plans.addItem(.supply, title: "Paint", cost: 32, to: paint, household: store.household,
                      context: store.context, persistence: store.persistence)
        store.save()

        HouseholdMerge.move(store.household, into: joined, context: store.context, persistence: store.persistence)
        store.save()

        let moved = try XCTUnwrap(joined.projects?.first)
        XCTAssertEqual(moved.budget, 60)
        XCTAssertEqual(moved.place, "Patio")
        XCTAssertEqual(Plans.items(.supply, of: moved).map(\.title), ["Paint"])
        XCTAssertEqual(Plans.estimatedCost(of: moved), 32)
    }
}
