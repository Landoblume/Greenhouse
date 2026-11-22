import CoreData
import XCTest
@testable import Greenhouse

/// Care tab: sections, who usually does a task, the "just done" line.
final class CareAgendaTests: XCTestCase {
    private let now = day(2026, 11, 18)

    private func task(_ store: TestStore, _ name: String, firstDue: Date, count: Int = 1, unit: IntervalUnit = .week) -> CareTask {
        CareSchedule.makeTask(name: name, count: count, unit: unit, firstDue: firstDue, plants: [], household: store.household,
                              context: store.context, persistence: store.persistence)
    }

    private func done(_ task: CareTask, by name: String, at date: Date, _ store: TestStore) {
        CareSchedule.markDone(task, by: name, at: date, household: store.household, context: store.context, persistence: store.persistence)
    }

    func testSectionsByDueStatus() {
        XCTAssertEqual(CareAgenda.section(for: .overdue(days: 3)), .overdue)
        XCTAssertEqual(CareAgenda.section(for: .today), .today)
        XCTAssertEqual(CareAgenda.section(for: .upcoming(days: 1)), .thisWeek)
        XCTAssertEqual(CareAgenda.section(for: .upcoming(days: 7)), .thisWeek)
        XCTAssertEqual(CareAgenda.section(for: .upcoming(days: 8)), .later)
    }

    func testGroupKeepsEverythingReachableAndSorted() {
        let store = TestStore()
        let later = task(store, "Rotate pot", firstDue: day(2026, 12, 20))
        let week2 = task(store, "Fertilize", firstDue: day(2026, 11, 22))
        let week1 = task(store, "Check pests", firstDue: day(2026, 11, 19))
        let todayTask = task(store, "Clean lights", firstDue: day(2026, 11, 18))
        let overdue = task(store, "Peroxide", firstDue: day(2026, 11, 10))

        let groups = CareAgenda.group([later, week2, week1, todayTask, overdue], now: now)
        XCTAssertEqual(groups.map(\.section), [.overdue, .today, .thisWeek, .later])
        XCTAssertEqual(groups[2].tasks.map(\.name), ["Check pests", "Fertilize"])
        XCTAssertEqual(groups.flatMap(\.tasks).count, 5)
    }

    func testEmptySectionsAreLeftOut() {
        let store = TestStore()
        let groups = CareAgenda.group([task(store, "Fertilize", firstDue: day(2026, 11, 20))], now: now)
        XCTAssertEqual(groups.map(\.section), [.thisWeek])
        XCTAssertTrue(CareAgenda.group([], now: now).isEmpty)
    }

    func testPinnedTaskStaysPutWhileItsCelebrationPlays() {
        let store = TestStore()
        let overdue = task(store, "Water", firstDue: day(2026, 11, 10))
        done(overdue, by: "Sam", at: now, store)
        // Done: next due Nov 25 (This week). Pinned: still in Overdue.
        XCTAssertEqual(CareAgenda.group([overdue], now: now).map(\.section), [.thisWeek])
        let pinned = CareAgenda.group([overdue], now: now, overrides: [overdue.objectID: (.overdue, day(2026, 11, 10))])
        XCTAssertEqual(pinned.map(\.section), [.overdue])
    }

    func testNextUpIsTheSoonestTaskNotDueYet() {
        let store = TestStore()
        let overdue = task(store, "Overdue", firstDue: day(2026, 11, 1))
        let soon = task(store, "Soon", firstDue: day(2026, 11, 20))
        let far = task(store, "Far", firstDue: day(2026, 12, 20))
        XCTAssertEqual(CareAgenda.nextUp(in: [far, overdue, soon], now: now)?.name, "Soon")
        XCTAssertNil(CareAgenda.nextUp(in: [overdue], now: now))
        XCTAssertNil(CareAgenda.nextUp(in: [], now: now))
    }

    func testUsualDoerIsTheMostFrequent() {
        let store = TestStore()
        let water = task(store, "Water", firstDue: day(2026, 10, 1), count: 1, unit: .day)
        XCTAssertNil(CareAgenda.usualDoer(of: water))
        done(water, by: "Sam", at: day(2026, 10, 2), store)
        done(water, by: "Alex", at: day(2026, 10, 3), store)
        done(water, by: "Sam", at: day(2026, 10, 4), store)
        XCTAssertEqual(CareAgenda.usualDoer(of: water), "Sam")
    }

    func testUsualDoerTieGoesToTheMostRecentAndIgnoresBlankNames() {
        let store = TestStore()
        let water = task(store, "Water", firstDue: day(2026, 10, 1), count: 1, unit: .day)
        done(water, by: "", at: day(2026, 10, 1), store)
        done(water, by: "  ", at: day(2026, 10, 2), store)
        XCTAssertNil(CareAgenda.usualDoer(of: water))
        done(water, by: "Alex", at: day(2026, 10, 3), store)
        done(water, by: "Sam", at: day(2026, 10, 4), store)
        XCTAssertEqual(CareAgenda.usualDoer(of: water), "Sam")
    }

    func testDoneLine() {
        let at = day(2026, 11, 18, hour: 9)
        XCTAssertEqual(CareAgenda.doneLine(doneAt: at, by: "Sam", now: at.addingTimeInterval(20)), "Just now · Sam · hold to undo")
        XCTAssertEqual(CareAgenda.doneLine(doneAt: at, by: nil, now: at.addingTimeInterval(20)), "Just now · hold to undo")
        XCTAssertTrue(CareAgenda.doneLine(doneAt: at, by: "Sam", now: at.addingTimeInterval(3600)).hasSuffix(" · Sam · hold to undo"))
        XCTAssertFalse(CareAgenda.doneLine(doneAt: at, by: "Sam", now: at.addingTimeInterval(3600)).hasPrefix("Just now"))
    }

    func testSummary() {
        XCTAssertEqual(CareAgenda.summary(overdue: 1, today: 3), "1 overdue · 3 today")
        XCTAssertEqual(CareAgenda.summary(overdue: 0, today: 2), "2 today")
        XCTAssertNil(CareAgenda.summary(overdue: 0, today: 0))
    }
}
