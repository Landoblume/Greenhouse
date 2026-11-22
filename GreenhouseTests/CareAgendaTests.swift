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

    func testUsualDoerNeedsTwoEntries() {
        let store = TestStore()
        let water = task(store, "Water", firstDue: day(2026, 10, 1), count: 1, unit: .day)
        done(water, by: "Sam", at: day(2026, 10, 2), store)
        XCTAssertNil(CareAgenda.usualDoer(of: water), "one entry isn't a habit")
        done(water, by: "Sam", at: day(2026, 10, 3), store)
        XCTAssertEqual(CareAgenda.usualDoer(of: water), "Sam")
    }

    func testUsualDoerIsYouOnYourOwnPhone() {
        let store = TestStore()
        let water = task(store, "Water", firstDue: day(2026, 10, 1), count: 1, unit: .day)
        done(water, by: "Sam", at: day(2026, 10, 2), store)
        done(water, by: "Sam", at: day(2026, 10, 3), store)
        done(water, by: "Alex", at: day(2026, 10, 4), store)
        XCTAssertEqual(CareAgenda.usualDoer(of: water, viewer: "sam "), "you")
        XCTAssertEqual(CareAgenda.usualDoer(of: water, viewer: "Alex"), "Sam")
        XCTAssertEqual(CareAgenda.usualDoer(of: water, viewer: ""), "Sam")
        XCTAssertEqual(CareAgenda.usualDoer(of: water, viewer: nil), "Sam")
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
        XCTAssertEqual(CareAgenda.doneLine(doneAt: at, by: "Sam", canUndo: false, now: at.addingTimeInterval(20)), "Just now · Sam")
    }

    // MARK: - Undo takes back exactly the entry the Done circle made

    private func water(_ store: TestStore) -> CareTask {
        task(store, "Water", firstDue: day(2026, 11, 11), count: 7, unit: .day)
    }

    private func mark(_ task: CareTask, by name: String, at date: Date, _ store: TestStore) -> CareLog {
        CareSchedule.markDone(task, by: name, at: date, household: store.household, context: store.context, persistence: store.persistence)
    }

    func testUndoDeletesOnlyItsOwnEntryEvenWhenANewerOneSyncedIn() {
        let store = TestStore()
        let task = water(store)
        let mine = mark(task, by: "Sam", at: day(2026, 11, 18, hour: 9), store)
        // The other phone logs it a minute later; that entry syncs in and is now the latest.
        let theirs = mark(task, by: "Alex", at: day(2026, 11, 18, hour: 10), store)
        store.save()

        XCTAssertTrue(CareSchedule.undoDone(mine, now: day(2026, 11, 18, hour: 11), context: store.context))
        store.save()
        XCTAssertEqual(task.logs?.count, 1)
        XCTAssertEqual(task.lastLog, theirs)
        XCTAssertFalse(theirs.isDeleted)
    }

    func testUndoRefusesYesterdaysEntryPastMidnight() {
        let store = TestStore()
        let task = water(store)
        let log = mark(task, by: "Sam", at: day(2026, 11, 18, hour: 23), store)
        store.save()
        XCTAssertFalse(CareSchedule.undoDone(log, now: day(2026, 11, 19, hour: 0), context: store.context))
        XCTAssertEqual(task.logs?.count, 1)
        XCTAssertNil(CareSchedule.undoableLog(log.uuid, of: task, now: day(2026, 11, 19, hour: 0)))
        XCTAssertEqual(CareSchedule.undoableLog(log.uuid, of: task, now: day(2026, 11, 18, hour: 23)), log)
    }

    func testUndoableLogIgnoresEntriesItDidntMake() {
        let store = TestStore()
        let task = water(store)
        _ = mark(task, by: "Alex", at: day(2026, 11, 18, hour: 9), store)
        XCTAssertNil(CareSchedule.undoableLog(nil, of: task, now: day(2026, 11, 18)))
        XCTAssertNil(CareSchedule.undoableLog(UUID(), of: task, now: day(2026, 11, 18)))
    }

    func testUndoingAnOlderEntryKeepsTheLatestOverride() {
        let store = TestStore()
        let task = water(store)
        let mine = mark(task, by: "Sam", at: day(2026, 11, 18, hour: 9), store)
        _ = mark(task, by: "Alex", at: day(2026, 11, 18, hour: 10), store)
        task.dueOverride = day(2026, 11, 30)
        CareSchedule.undoDone(mine, now: day(2026, 11, 18, hour: 11), context: store.context)
        XCTAssertNotNil(task.dueOverride, "only the latest entry's override goes with it")
    }

    @MainActor
    func testUndoMemoryFindsTheEntryThisPhoneMade() {
        let store = TestStore()
        let task = water(store)
        let mine = mark(task, by: "Sam", at: .now, store)
        CareUndoMemory.remember(mine)
        _ = mark(task, by: "Alex", at: .now.addingTimeInterval(1), store)
        XCTAssertEqual(CareUndoMemory.undoableLog(for: task), mine)
        CareUndoMemory.forget(task)
        XCTAssertNil(CareUndoMemory.undoableLog(for: task))
    }

    func testSummary() {
        XCTAssertEqual(CareAgenda.summary(overdue: 1, today: 3), "1 overdue · 3 today")
        XCTAssertEqual(CareAgenda.summary(overdue: 0, today: 2), "2 today")
        XCTAssertNil(CareAgenda.summary(overdue: 0, today: 0))
    }
}
