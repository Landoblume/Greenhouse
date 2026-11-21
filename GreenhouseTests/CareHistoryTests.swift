import CoreData
import XCTest
@testable import Greenhouse

final class CareHistoryTests: XCTestCase {
    private func water(_ plant: Plant, on date: Date, by name: String, store: TestStore) {
        CareSchedule.markDone(plant.wateringTask!, by: name, at: date, household: store.household,
                              context: store.context, persistence: store.persistence)
    }

    func testNoLogsMeansNoEntries() {
        let store = TestStore()
        let plant = store.plant(acquired: day(2026, 1, 1))
        XCTAssertTrue(CareHistory.entries(for: plant).isEmpty)
    }

    func testEntriesAreNewestFirstWithWhoAndDate() {
        let store = TestStore()
        let plant = store.plant(acquired: day(2026, 1, 1))
        water(plant, on: day(2026, 2, 1), by: "Sam", store: store)
        water(plant, on: day(2026, 4, 1), by: "Alex", store: store)
        water(plant, on: day(2026, 3, 1), by: "  ", store: store)
        store.save()

        let entries = CareHistory.entries(for: plant)
        XCTAssertEqual(entries.map(\.doneAt), [day(2026, 4, 1), day(2026, 3, 1), day(2026, 2, 1)])
        XCTAssertEqual(entries.map(\.doneBy), ["Alex", nil, "Sam"])
        XCTAssertEqual(entries.map(\.title), ["Watered", "Watered", "Watered"])
        XCTAssertTrue(entries.allSatisfy { $0.source == plant })
    }

    func testSameDayLogsKeepAStableOrder() {
        let store = TestStore()
        let plant = store.plant(acquired: day(2026, 1, 1))
        water(plant, on: day(2026, 2, 1), by: "A", store: store)
        water(plant, on: day(2026, 2, 1), by: "B", store: store)
        store.save()
        let first = CareHistory.entries(for: plant).map(\.id)
        XCTAssertEqual(first.count, 2)
        XCTAssertEqual(CareHistory.entries(for: plant).map(\.id), first)
        let uuids = CareHistory.entries(for: plant).map { $0.log.uuid!.uuidString }
        XCTAssertEqual(uuids, uuids.sorted())
    }

    func testArchivedTasksStayInHistory() {
        let store = TestStore()
        let plant = store.plant(acquired: day(2026, 1, 1))
        let repot = CareSchedule.makeTask(name: "Repot", count: 1, unit: .once, firstDue: day(2026, 2, 1),
                                          plants: [plant], household: store.household, context: store.context,
                                          persistence: store.persistence)
        CareSchedule.markDone(repot, by: "Sam", at: day(2026, 2, 3), household: store.household,
                              context: store.context, persistence: store.persistence)
        store.save()
        XCTAssertTrue(repot.isArchived)
        XCTAssertFalse(plant.activeTasks.contains(repot))

        let entries = CareHistory.entries(for: plant)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.title, "Repot")
        XCTAssertEqual(entries.first?.doneBy, "Sam")
        XCTAssertEqual(entries.first?.doneAt, day(2026, 2, 3))
    }

    func testBlankTaskNameFallsBack() {
        let store = TestStore()
        let plant = store.plant(acquired: day(2026, 1, 1))
        let task = CareSchedule.makeTask(name: "  ", count: 1, unit: .week, firstDue: day(2026, 2, 1),
                                         plants: [plant], household: store.household, context: store.context,
                                         persistence: store.persistence)
        CareSchedule.markDone(task, by: "", at: day(2026, 2, 1), household: store.household,
                              context: store.context, persistence: store.persistence)
        store.save()
        XCTAssertEqual(CareHistory.entries(for: plant).first?.title, "Care task")
    }

    func testOtherPlantsLogsAreNotIncluded() {
        let store = TestStore()
        let a = store.plant(acquired: day(2026, 1, 1))
        let b = store.plant(acquired: day(2026, 1, 1))
        water(a, on: day(2026, 2, 1), by: "Sam", store: store)
        store.save()
        XCTAssertEqual(CareHistory.entries(for: a).count, 1)
        XCTAssertTrue(CareHistory.entries(for: b).isEmpty)
    }

    func testCombinedPlantShowsCareFromBothOriginals() {
        let store = TestStore()
        let a = store.plant(nickname: "Mom's", acquired: day(2026, 1, 1))
        let b = store.plant(nickname: "Shop", acquired: day(2026, 1, 5))
        water(a, on: day(2026, 2, 1), by: "Sam", store: store)
        water(b, on: day(2026, 3, 1), by: "Alex", store: store)
        let merged = Lineage.staple([a, b], nickname: "Both", date: day(2026, 3, 10), household: store.household,
                                    context: store.context, persistence: store.persistence)
        water(merged, on: day(2026, 3, 20), by: "Sam", store: store)
        store.save()

        let entries = CareHistory.entries(for: merged)
        XCTAssertEqual(entries.map(\.doneAt), [day(2026, 3, 20), day(2026, 3, 1), day(2026, 2, 1)])
        XCTAssertEqual(entries.map(\.source), [merged, b, a])
        XCTAssertEqual(entries.map(\.doneBy), ["Sam", "Alex", "Sam"])
        // The retired originals still show their own.
        XCTAssertEqual(CareHistory.entries(for: a).count, 1)
        XCTAssertEqual(CareHistory.entries(for: b).count, 1)
    }

    func testTransferredTaskLogsAreNotCountedTwice() {
        let store = TestStore()
        let a = store.plant(acquired: day(2026, 1, 1))
        let b = store.plant(acquired: day(2026, 1, 5))
        let mist = CareSchedule.makeTask(name: "Mist", count: 1, unit: .week, firstDue: day(2026, 2, 1),
                                         plants: [a, b], household: store.household, context: store.context,
                                         persistence: store.persistence)
        CareSchedule.markDone(mist, by: "Sam", at: day(2026, 2, 2), household: store.household,
                              context: store.context, persistence: store.persistence)
        let merged = Lineage.staple([a, b], nickname: nil, date: day(2026, 3, 1), household: store.household,
                                    context: store.context, persistence: store.persistence)
        store.save()
        // The mist task moved to the merged plant; its one log shows once.
        let entries = CareHistory.entries(for: merged)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.title, "Mist")
    }

    // MARK: - Threads (C4)

    func testPlantWithNoLineageHasOneThread() {
        let store = TestStore()
        let plant = store.plant(acquired: day(2026, 1, 1))
        water(plant, on: day(2026, 2, 1), by: "Sam", store: store)
        water(plant, on: day(2026, 3, 1), by: "Sam", store: store)
        store.save()

        let timeline = CareHistory.timeline(for: plant)
        XCTAssertEqual(timeline.threads.count, 1)
        XCTAssertNil(timeline.threads[0].end)
        XCTAssertTrue(CareHistory.merges(for: plant).isEmpty)
        // Month header, log, month header, log: the line runs the whole way down.
        XCTAssertEqual(timeline.rows.count, 4)
        guard case .month = timeline.rows[0].kind, case .log = timeline.rows[1].kind else { return XCTFail("order") }
        XCTAssertEqual(timeline.rows.map { $0.lanes[0].lineAbove }, [false, true, true, true])
        XCTAssertEqual(timeline.rows.map { $0.lanes[0].lineBelow }, [true, true, true, false])
        XCTAssertEqual(timeline.rows.map { $0.lanes[0].dot }, [false, true, false, true])
    }

    func testCombineJoinsTheThreads() {
        let store = TestStore()
        let a = store.plant(nickname: "A", acquired: day(2026, 1, 1))
        let b = store.plant(nickname: "B", acquired: day(2026, 1, 5))
        water(a, on: day(2026, 2, 1), by: "Sam", store: store)
        water(b, on: day(2026, 3, 1), by: "Alex", store: store)
        let merged = Lineage.staple([a, b], nickname: "AB", date: day(2026, 4, 1), household: store.household,
                                    context: store.context, persistence: store.persistence)
        water(merged, on: day(2026, 5, 1), by: "Sam", store: store)
        store.save()

        let timeline = CareHistory.timeline(for: merged)
        XCTAssertEqual(timeline.threads.map(\.plant), [merged, a, b])
        XCTAssertEqual(timeline.threads.map(\.lane), [0, 1, 2])
        XCTAssertNil(timeline.threads[0].end)
        XCTAssertEqual(timeline.threads[1].end, day(2026, 4, 1))
        XCTAssertEqual(timeline.threads[1].mergesInto, merged)
        XCTAssertEqual(timeline.threads[2].mergesInto, merged)
        XCTAssertEqual(timeline.threads[0].start, day(2026, 4, 1))
        XCTAssertEqual(timeline.threads[1].start, day(2026, 1, 1))

        // May header, May log, April header, merge, March header, B log, Feb header, A log.
        let kinds = timeline.rows.map(\.kind)
        XCTAssertEqual(kinds.count, 8)
        guard case .merge(let merge) = kinds[3] else { return XCTFail("merge row") }
        XCTAssertEqual(merge.title, "Combined")
        XCTAssertEqual(merge.output, merged)
        XCTAssertEqual(merge.inputs, [a, b])

        let mergeRow = timeline.rows[3].lanes
        XCTAssertTrue(mergeRow[0].isMergeNode && mergeRow[0].dot)
        XCTAssertTrue(mergeRow[0].lineAbove)
        XCTAssertFalse(mergeRow[0].lineBelow)
        XCTAssertEqual(mergeRow[1].joinsLane, 0)
        XCTAssertEqual(mergeRow[2].joinsLane, 0)
        XCTAssertFalse(mergeRow[1].lineAbove)
        XCTAssertTrue(mergeRow[1].lineBelow)

        // Above the merge only the combined plant's line runs; below it, only the originals'.
        XCTAssertTrue(timeline.rows[1].lanes[0].dot)
        XCTAssertTrue(timeline.rows[2].lanes[0].lineAbove && timeline.rows[2].lanes[0].lineBelow)
        XCTAssertTrue(timeline.rows[2].lanes[1].isEmpty && timeline.rows[2].lanes[2].isEmpty)
        XCTAssertTrue(timeline.rows[4].lanes[0].isEmpty)
        XCTAssertTrue(timeline.rows[5].lanes[2].dot)
        XCTAssertTrue(timeline.rows[5].lanes[1].lineAbove && timeline.rows[5].lanes[1].lineBelow)
        XCTAssertTrue(timeline.rows[7].lanes[1].dot)
        XCTAssertFalse(timeline.rows[7].lanes[1].lineBelow)
    }

    func testNestedCombineHasEveryThreadAndBothMerges() {
        let store = TestStore()
        let a = store.plant(nickname: "A", acquired: day(2026, 1, 1))
        let b = store.plant(nickname: "B", acquired: day(2026, 1, 2))
        let c = store.plant(nickname: "C", acquired: day(2026, 1, 3))
        water(a, on: day(2026, 2, 1), by: "Sam", store: store)
        let ab = Lineage.staple([a, b], nickname: "AB", date: day(2026, 3, 1), household: store.household,
                                context: store.context, persistence: store.persistence)
        water(c, on: day(2026, 3, 15), by: "Alex", store: store)
        water(ab, on: day(2026, 3, 20), by: "Sam", store: store)
        let abc = Lineage.staple([ab, c], nickname: "ABC", date: day(2026, 4, 1), household: store.household,
                                 context: store.context, persistence: store.persistence)
        store.save()

        let timeline = CareHistory.timeline(for: abc)
        XCTAssertEqual(timeline.threads.count, 5)
        XCTAssertEqual(timeline.threads[0].plant, abc)
        XCTAssertEqual(Set(timeline.threads.map(\.plant)), [abc, ab, c, a, b])
        let byPlant = Dictionary(uniqueKeysWithValues: timeline.threads.map { ($0.plant, $0) })
        XCTAssertEqual(byPlant[ab]?.mergesInto, abc)
        XCTAssertEqual(byPlant[c]?.mergesInto, abc)
        XCTAssertEqual(byPlant[a]?.mergesInto, ab)
        XCTAssertEqual(byPlant[b]?.mergesInto, ab)

        let merges = CareHistory.merges(for: abc)
        XCTAssertEqual(Set(merges.map(\.output)), [abc, ab])
        let mergeRows = timeline.rows.compactMap { row -> (CareHistory.Merge, [CareHistory.LaneMark])? in
            if case .merge(let merge) = row.kind { return (merge, row.lanes) }
            return nil
        }
        XCTAssertEqual(mergeRows.map { $0.0.output }, [abc, ab], "newest combine first")
        let abLane = byPlant[ab]!.lane
        // In the ABC combine, AB's thread joins lane 0; AB's own start is the second merge node.
        XCTAssertEqual(mergeRows[0].1[abLane].joinsLane, 0)
        XCTAssertEqual(mergeRows[0].1[byPlant[c]!.lane].joinsLane, 0)
        XCTAssertTrue(mergeRows[1].1[abLane].isMergeNode)
        XCTAssertEqual(mergeRows[1].1[byPlant[a]!.lane].joinsLane, abLane)
        XCTAssertEqual(mergeRows[1].1[byPlant[b]!.lane].joinsLane, abLane)
        // AB's thread runs between the two merges.
        XCTAssertTrue(mergeRows[0].1[abLane].lineBelow)
        XCTAssertTrue(mergeRows[1].1[abLane].lineAbove)
        XCTAssertFalse(mergeRows[1].1[abLane].lineBelow)
    }

    func testRowIDsAreUnique() {
        let store = TestStore()
        let a = store.plant(acquired: day(2026, 1, 1))
        let b = store.plant(acquired: day(2026, 1, 2))
        water(a, on: day(2026, 2, 1), by: "Sam", store: store)
        water(a, on: day(2026, 2, 1), by: "Sam", store: store)
        let m = Lineage.staple([a, b], nickname: nil, date: day(2026, 3, 1), household: store.household,
                               context: store.context, persistence: store.persistence)
        store.save()
        let ids = CareHistory.timeline(for: m).rows.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    // MARK: - Stats (C5)

    func testNoLogsMeansNoStats() {
        let store = TestStore()
        XCTAssertNil(CareHistory.stats(for: store.plant(acquired: day(2026, 1, 1))))
    }

    func testStatsCountKindsSinceAndMostlyBy() {
        let store = TestStore()
        let plant = store.plant(acquired: day(2026, 1, 1))
        water(plant, on: day(2026, 2, 1), by: "Sam", store: store)
        water(plant, on: day(2026, 2, 8), by: "Sam", store: store)
        water(plant, on: day(2026, 2, 15), by: "Sam", store: store)
        let mist = CareSchedule.makeTask(name: "Mist", count: 1, unit: .week, firstDue: day(2026, 2, 2),
                                         plants: [plant], household: store.household, context: store.context,
                                         persistence: store.persistence)
        CareSchedule.markDone(mist, by: "Alex", at: day(2026, 2, 3), household: store.household,
                              context: store.context, persistence: store.persistence)
        store.save()

        let stats = CareHistory.stats(for: plant)
        XCTAssertEqual(stats?.total, 4)
        XCTAssertEqual(stats?.counts.map(\.title), ["Watered", "Mist"])
        XCTAssertEqual(stats?.counts.map(\.count), [3, 1])
        XCTAssertEqual(stats?.since, day(2026, 2, 1))
        XCTAssertEqual(stats?.mostlyBy, "Sam")
        let since = day(2026, 2, 1).formatted(.dateTime.month(.abbreviated).year())
        XCTAssertEqual(stats?.headline, "Watered 3 times since \(since) \u{00B7} mostly by Sam \u{1F49A}")
        XCTAssertEqual(stats?.others, "Mist 1")
    }

    func testStatsOmitMostlyByWhenNobodyIsNamedAndSingularizes() {
        let store = TestStore()
        let plant = store.plant(acquired: day(2026, 1, 1))
        water(plant, on: day(2026, 2, 1), by: "", store: store)
        store.save()
        let stats = CareHistory.stats(for: plant)
        XCTAssertNil(stats?.mostlyBy)
        XCTAssertNil(stats?.others)
        XCTAssertTrue(stats?.headline.hasPrefix("Watered 1 time since ") ?? false)
        XCTAssertFalse(stats?.headline.contains("mostly") ?? true)
    }

    func testMostlyByTieGoesToFirstNameAlphabetically() {
        let store = TestStore()
        let plant = store.plant(acquired: day(2026, 1, 1))
        water(plant, on: day(2026, 2, 1), by: "Sam", store: store)
        water(plant, on: day(2026, 2, 2), by: "Alex", store: store)
        store.save()
        XCTAssertEqual(CareHistory.stats(for: plant)?.mostlyBy, "Alex")
    }

    func testStatsCoverCombinedPlantsOriginals() {
        let store = TestStore()
        let a = store.plant(acquired: day(2026, 1, 1))
        let b = store.plant(acquired: day(2026, 1, 5))
        water(a, on: day(2026, 2, 1), by: "Sam", store: store)
        water(b, on: day(2026, 3, 1), by: "Sam", store: store)
        let merged = Lineage.staple([a, b], nickname: nil, date: day(2026, 4, 1), household: store.household,
                                    context: store.context, persistence: store.persistence)
        store.save()
        XCTAssertEqual(CareHistory.stats(for: merged)?.counts.first?.count, 2)
        XCTAssertEqual(CareHistory.stats(for: merged)?.since, day(2026, 2, 1))
    }
}
