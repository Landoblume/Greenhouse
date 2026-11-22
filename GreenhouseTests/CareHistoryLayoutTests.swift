import CoreData
import XCTest
@testable import Greenhouse

/// Lanes, folding, colors, the extra rows, one-plant zoom, draw-in timing,
/// change relevance and the words of the care history.
final class CareHistoryLayoutTests: XCTestCase {
    private let enUS = Locale(identifier: "en_US")

    private func water(_ plant: Plant, on date: Date, by name: String, store: TestStore) {
        CareSchedule.markDone(plant.wateringTask!, by: name, at: date, household: store.household,
                              context: store.context, persistence: store.persistence)
    }

    private func combine(_ plants: [Plant], _ name: String, on date: Date, store: TestStore) -> Plant {
        Lineage.staple(plants, nickname: name, date: date, household: store.household,
                       context: store.context, persistence: store.persistence)
    }

    /// A + B → AB (Mar), then AB + C → ABC (Apr), with care on each before.
    private struct Nested {
        let store = TestStore()
        let a: Plant, b: Plant, c: Plant, ab: Plant, abc: Plant

        init(test: CareHistoryLayoutTests) {
            a = store.plant(nickname: "A", acquired: day(2026, 1, 1))
            b = store.plant(nickname: "B", acquired: day(2026, 1, 2))
            c = store.plant(nickname: "C", acquired: day(2026, 1, 3))
            test.water(a, on: day(2026, 2, 1), by: "Sam", store: store)
            test.water(b, on: day(2026, 2, 2), by: "Alex", store: store)
            ab = test.combine([a, b], "AB", on: day(2026, 3, 1), store: store)
            test.water(c, on: day(2026, 3, 15), by: "Alex", store: store)
            test.water(ab, on: day(2026, 3, 20), by: "Sam", store: store)
            abc = test.combine([ab, c], "ABC", on: day(2026, 4, 1), store: store)
            test.water(abc, on: day(2026, 4, 10), by: "Sam", store: store)
            store.save()
        }
    }

    private func thread(_ timeline: CareHistory.Timeline, _ plant: Plant) -> CareHistory.CareThread {
        timeline.threads.first { $0.plant == plant }!
    }

    // MARK: - Columns

    func testThreeOriginalsTheMergedThreadTakesTheMiddle() {
        let store = TestStore()
        let a = store.plant(nickname: "A", acquired: day(2026, 1, 1))
        let b = store.plant(nickname: "B", acquired: day(2026, 1, 2))
        let c = store.plant(nickname: "C", acquired: day(2026, 1, 3))
        let abc = combine([a, b, c], "ABC", on: day(2026, 3, 1), store: store)
        store.save()
        let timeline = CareHistory.timeline(for: abc)
        XCTAssertEqual(timeline.columnCount, 3)
        XCTAssertEqual([a, b, c].map { thread(timeline, $0).column }, [0, 1, 2], "left to right by when they began")
        XCTAssertEqual(thread(timeline, abc).column, 1, "the middle lane")
    }

    func testTwoOriginalsTheMergedThreadTakesLeftOfMiddle() {
        let store = TestStore()
        let a = store.plant(nickname: "A", acquired: day(2026, 1, 1))
        let b = store.plant(nickname: "B", acquired: day(2026, 1, 2))
        let ab = combine([b, a], "AB", on: day(2026, 3, 1), store: store)
        store.save()
        let timeline = CareHistory.timeline(for: ab)
        XCTAssertEqual(timeline.columnCount, 2)
        XCTAssertEqual(thread(timeline, a).column, 0)
        XCTAssertEqual(thread(timeline, b).column, 1)
        XCTAssertEqual(thread(timeline, ab).column, 0)
    }

    func testOriginalsSitByWhenTheirThreadsBeganNotByAcquiredOrder() {
        let store = TestStore()
        // B was bought later but its first watering is older than A's purchase.
        let a = store.plant(nickname: "A", acquired: day(2026, 2, 1))
        let b = store.plant(nickname: "B", acquired: day(2026, 3, 1))
        water(b, on: day(2026, 1, 5), by: "Sam", store: store)
        let ab = combine([a, b], "AB", on: day(2026, 4, 1), store: store)
        store.save()
        let timeline = CareHistory.timeline(for: ab)
        XCTAssertEqual(thread(timeline, b).column, 0)
        XCTAssertEqual(thread(timeline, a).column, 1)
    }

    func testNestedCombineColumnsAreContiguousAndShared() {
        let nested = Nested(test: self)
        let timeline = CareHistory.timeline(for: nested.abc)
        XCTAssertEqual(timeline.columnCount, 3)
        XCTAssertEqual(thread(timeline, nested.a).column, 0)
        XCTAssertEqual(thread(timeline, nested.b).column, 1)
        XCTAssertEqual(thread(timeline, nested.ab).column, 0, "AB carries on A's column")
        XCTAssertEqual(thread(timeline, nested.c).column, 2)
        XCTAssertEqual(thread(timeline, nested.abc).column, 0, "left of middle of [AB, C]")
        XCTAssertEqual(timeline.hiddenCount, 0)
    }

    /// No two threads are on one column in the same stretch of a row, and no
    /// branch passes over a line that isn't part of its combine.
    private func assertLinesNeverCross(_ timeline: CareHistory.Timeline, file: StaticString = #filePath, line: UInt = #line) {
        let column = timeline.threads.map(\.column)
        for row in timeline.rows {
            let above = row.lanes.indices.filter { row.lanes[$0].lineAbove }.map { column[$0] }
            let below = row.lanes.indices.filter { row.lanes[$0].lineBelow }.map { column[$0] }
            XCTAssertEqual(Set(above).count, above.count, "two lines on one column above, row \(row.id)", file: file, line: line)
            XCTAssertEqual(Set(below).count, below.count, "two lines on one column below, row \(row.id)", file: file, line: line)
            guard case .merge = row.kind, let out = row.lanes.firstIndex(where: \.isMergeNode) else { continue }
            let joining = row.lanes.indices.filter { row.lanes[$0].joinsLane == out }
            for input in joining {
                let low = min(column[input], column[out]), high = max(column[input], column[out])
                for other in row.lanes.indices where other != out && !joining.contains(other) {
                    let mark = row.lanes[other]
                    guard mark.lineAbove || mark.lineBelow else { continue }
                    XCTAssertFalse(column[other] > low && column[other] < high,
                                   "a branch crosses lane \(other) in row \(row.id)", file: file, line: line)
                }
            }
        }
    }

    func testLinesNeverCrossInANestedCombine() {
        let nested = Nested(test: self)
        assertLinesNeverCross(CareHistory.timeline(for: nested.abc))
        assertLinesNeverCross(CareHistory.timeline(for: nested.ab))
    }

    func testLinesNeverCrossWhenANestedBranchSitsInTheMiddle() {
        // X + (Y + Z) + W: the nested one is in the middle and owns two columns.
        let store = TestStore()
        let x = store.plant(nickname: "X", acquired: day(2026, 1, 1))
        let y = store.plant(nickname: "Y", acquired: day(2026, 1, 2))
        let z = store.plant(nickname: "Z", acquired: day(2026, 1, 3))
        let w = store.plant(nickname: "W", acquired: day(2026, 1, 4))
        water(x, on: day(2026, 2, 1), by: "Sam", store: store)
        water(y, on: day(2026, 2, 2), by: "Sam", store: store)
        water(z, on: day(2026, 2, 3), by: "Sam", store: store)
        water(w, on: day(2026, 2, 4), by: "Sam", store: store)
        let yz = combine([y, z], "YZ", on: day(2026, 3, 1), store: store)
        water(yz, on: day(2026, 3, 10), by: "Sam", store: store)
        let all = combine([x, yz, w], "All", on: day(2026, 4, 1), store: store)
        store.save()
        let timeline = CareHistory.timeline(for: all)
        XCTAssertEqual(timeline.columnCount, 4)
        XCTAssertEqual([x, y, z, w].map { thread(timeline, $0).column }, [0, 1, 2, 3])
        XCTAssertEqual(thread(timeline, yz).column, 1)
        XCTAssertEqual(thread(timeline, all).column, 1, "the middle original, YZ")
        assertLinesNeverCross(timeline)
    }

    // MARK: - Folding

    private func tree(_ children: [[Int]], combined: [Date?]? = nil) -> CareHistory.FamilyTree {
        CareHistory.FamilyTree(children: children, combinedAt: combined ?? Array(repeating: nil, count: children.count))
    }

    func testFourColumnsNeverFold() {
        let flat = tree([[1, 2, 3, 4], [], [], [], []])
        XCTAssertEqual(CareHistory.columns(of: flat, hidden: []).count, 4)
        XCTAssertTrue(CareHistory.fold(flat).hidden.isEmpty)
    }

    func testTooManyOriginalsFoldTheOldestOnes() {
        let flat = tree([[1, 2, 3, 4, 5, 6], [], [], [], [], [], []])
        let folding = CareHistory.fold(flat)
        XCTAssertEqual(folding.hidden, [1, 2], "the first two began earliest")
        XCTAssertEqual(folding.folds, [0: 2])
        XCTAssertEqual(CareHistory.columns(of: flat, hidden: folding.hidden).count, 4)
    }

    func testTheOldestCombineFoldsFirst() {
        // 0 = X + Y; X (Mar) = a + b + c; Y (May) = d + e. Five columns.
        let nested = tree([[1, 2], [3, 4, 5], [6, 7], [], [], [], [], []],
                          combined: [day(2026, 6, 1), day(2026, 3, 1), day(2026, 5, 1), nil, nil, nil, nil, nil])
        XCTAssertEqual(CareHistory.columns(of: nested, hidden: []).count, 5)
        let folding = CareHistory.fold(nested)
        XCTAssertEqual(folding.hidden, [3, 4, 5])
        XCTAssertEqual(folding.folds, [1: 3])
        XCTAssertEqual(CareHistory.columns(of: nested, hidden: folding.hidden).count, 3)
    }

    func testFoldingKeepsGoingUntilItFits() {
        // Deep chain: 0 = 1 + 2 + 3; 1 = 4 + 5; 2 = 6 + 7; 3 = 8 + 9. Six columns.
        let wide = tree([[1, 2, 3], [4, 5], [6, 7], [8, 9], [], [], [], [], [], []],
                        combined: [day(2026, 9, 1), day(2026, 3, 1), day(2026, 4, 1), day(2026, 5, 1),
                                   nil, nil, nil, nil, nil, nil])
        let folding = CareHistory.fold(wide)
        XCTAssertEqual(folding.hidden, [4, 5, 6, 7], "the two oldest combines")
        XCTAssertEqual(folding.folds, [1: 2, 2: 2])
        XCTAssertEqual(CareHistory.columns(of: wide, hidden: folding.hidden).count, 4)
    }

    func testFoldedTimelineHasAPillAndExpandsInPlace() {
        // P + Q → PQ (Mar); R + S + T → RST (Apr); PQ + RST → Big (May): five columns.
        let store = TestStore()
        let names = ["P", "Q", "R", "S", "T"]
        let plants = names.enumerated().map { store.plant(nickname: $1, acquired: day(2026, 1, 1 + $0)) }
        for (index, plant) in plants.enumerated() { water(plant, on: day(2026, 2, 1 + index), by: "Sam", store: store) }
        let pq = combine([plants[0], plants[1]], "PQ", on: day(2026, 3, 1), store: store)
        let rst = combine([plants[2], plants[3], plants[4]], "RST", on: day(2026, 4, 1), store: store)
        let big = combine([pq, rst], "Big", on: day(2026, 5, 1), store: store)
        store.save()

        let folded = CareHistory.timeline(for: big)
        XCTAssertEqual(folded.hiddenCount, 2, "PQ is the older combine; P and Q fold")
        XCTAssertLessThanOrEqual(folded.columnCount, CareHistory.maxColumns)
        XCTAssertFalse(folded.threads.contains { $0.plant == plants[0] || $0.plant == plants[1] })
        let pill = folded.rows.firstIndex { if case .showEarlier(2, pq) = $0.kind { return true } else { return false } }
        XCTAssertNotNil(pill)
        if let pill, case .merge(let merge) = folded.rows[pill - 1].kind {
            XCTAssertEqual(merge.output, pq, "the pill sits right under its combine")
        } else {
            XCTFail("pill under PQ's combine")
        }
        XCTAssertFalse(folded.rows.contains { $0.plant == plants[0] }, "P's care is folded away with it")
        assertLinesNeverCross(folded)

        let open = CareHistory.timeline(for: big, expanded: true)
        XCTAssertEqual(open.hiddenCount, 0)
        XCTAssertEqual(open.columnCount, 5)
        XCTAssertEqual(open.threads.count, 8)
        XCTAssertFalse(open.rows.contains { if case .showEarlier = $0.kind { return true } else { return false } })
        assertLinesNeverCross(open)
    }

    // MARK: - Colors

    func testAPlantKeepsItsColorInsideLaterCombines() {
        let nested = Nested(test: self)
        let outer = CareHistory.timeline(for: nested.abc)
        let inner = CareHistory.timeline(for: nested.ab)
        XCTAssertEqual(thread(outer, nested.ab).color, thread(inner, nested.ab).color, "AB is the same color in ABC's history")
        XCTAssertEqual(thread(outer, nested.a).color, thread(inner, nested.a).color)
        XCTAssertEqual(thread(outer, nested.b).color, thread(inner, nested.b).color)
        // In the order threads began: A, B, C, then AB, then ABC gets the next unused one.
        XCTAssertEqual([nested.a, nested.b, nested.c, nested.ab, nested.abc].map { thread(outer, $0).color }, [0, 1, 2, 3, 4])
        // A retired original's own history uses the same colors too.
        XCTAssertEqual(thread(CareHistory.timeline(for: nested.c), nested.c).color, 2)
    }

    // MARK: - Glyphs, milestones, cuttings, where it went

    func testGlyphsCarryTheKind() {
        let store = TestStore()
        let plant = store.plant(nickname: "Fern", acquired: day(2026, 1, 1))
        water(plant, on: day(2026, 2, 1), by: "Sam", store: store)
        let feed = CareSchedule.makeTask(name: "Fertilize", count: 1, unit: .month, firstDue: day(2026, 2, 1),
                                         plants: [plant], household: store.household, context: store.context,
                                         persistence: store.persistence)
        CareSchedule.markDone(feed, by: "Alex", at: day(2026, 2, 3), household: store.household,
                              context: store.context, persistence: store.persistence)
        Milestones.add(title: "First bloom", date: day(2026, 2, 5), notes: "A tiny flower stalk.", by: "Alex",
                       to: plant, household: store.household, context: store.context, persistence: store.persistence)
        store.save()
        let glyphs = CareHistory.timeline(for: plant).rows.compactMap { $0.lanes.first?.glyph }
        XCTAssertEqual(glyphs, [.milestone, .task, .watering])
    }

    func testMilestonesSitOnTheirPlantsThreadByDate() {
        let store = TestStore()
        let a = store.plant(nickname: "A", acquired: day(2026, 1, 1))
        let b = store.plant(nickname: "B", acquired: day(2026, 1, 2))
        Milestones.add(title: "Repotted", date: day(2026, 2, 1), notes: nil, by: "Sam", to: b,
                       household: store.household, context: store.context, persistence: store.persistence)
        let ab = combine([a, b], "AB", on: day(2026, 3, 1), store: store)
        // Written on the combined plant but dated before the combine: it was for the originals.
        Milestones.add(title: "  ", date: day(2026, 2, 10), notes: nil, by: "", to: ab,
                       household: store.household, context: store.context, persistence: store.persistence)
        store.save()

        let marks = CareHistory.milestones(for: ab)
        XCTAssertEqual(marks.map(\.title), ["Milestone", "Repotted"])
        XCTAssertEqual(marks.map(\.source), [a, b])
        XCTAssertNil(marks[0].addedBy)
        let timeline = CareHistory.timeline(for: ab)
        let row = timeline.rows.first { if case .milestone(let mark) = $0.kind { return mark.title == "Repotted" } else { return false } }!
        XCTAssertEqual(row.lanes[thread(timeline, b).lane].glyph, .milestone)
    }

    func testCuttingsLinkBothWays() {
        let store = TestStore()
        let parent = store.plant(nickname: "Lulu", acquired: day(2026, 1, 1))
        let cutting = Lineage.takeCutting(from: parent, nickname: "Pip Jr.", date: day(2026, 2, 1), household: store.household,
                                          context: store.context, persistence: store.persistence)
        store.save()

        let taken = CareHistory.cuttings(for: parent)
        XCTAssertEqual(taken.count, 1)
        XCTAssertEqual(taken[0].direction, .taken)
        XCTAssertEqual(taken[0].linked, cutting)
        XCTAssertEqual(CareHistory.timeline(for: parent).rows.compactMap { $0.lanes.first?.glyph }, [.cutting])

        let from = CareHistory.cuttings(for: cutting)
        XCTAssertEqual(from.map(\.direction), [.startedFrom])
        XCTAssertEqual(from.first?.linked, parent)
    }

    func testARetiredPlantShowsWhereItWent() {
        let nested = Nested(test: self)
        let timeline = CareHistory.timeline(for: nested.c)
        guard case .joined(let into, let with, let date, _) = timeline.rows[1].kind else { return XCTFail("joined row first") }
        XCTAssertEqual(into, nested.abc)
        XCTAssertEqual(with, [nested.ab])
        XCTAssertEqual(date, day(2026, 4, 1))
        XCTAssertEqual(timeline.rows[1].lanes[0].glyph, .joined)
        XCTAssertFalse(timeline.rows[1].lanes[0].lineAbove)
        XCTAssertTrue(timeline.rows[1].lanes[0].lineBelow)
    }

    // MARK: - One plant

    func testFocusKeepsOnlyThatPlantsRowsAndTheirMonths() {
        let nested = Nested(test: self)
        let timeline = CareHistory.timeline(for: nested.abc)
        let c = timeline.focused(on: nested.c)
        let kinds = c.rows.map(\.kind)
        // April: ABC's combine (C went into it); March: C's watering. Nothing of A, B, AB's care.
        XCTAssertEqual(kinds.count, 4)
        guard case .month = kinds[0], case .merge(let merge) = kinds[1], case .month = kinds[2], case .log(let entry) = kinds[3] else {
            return XCTFail("month, combine, month, log")
        }
        XCTAssertEqual(merge.output, nested.abc)
        XCTAssertEqual(entry.source, nested.c)
        XCTAssertEqual(c.threads, timeline.threads, "the other lanes still show as hairlines")

        let root = timeline.focused(on: nested.abc)
        XCTAssertEqual(root.rows.filter { !$0.isMonth }.count, 2, "its watering and the combine that made it")
    }

    // MARK: - Draw-in

    func testDrawInGoesTopDownAndOriginalsStartAtTheirNode() {
        let nested = Nested(test: self)
        let timeline = CareHistory.timeline(for: nested.abc)
        let schedule = CareHistory.drawSchedule(for: timeline, window: 100)
        XCTAssertEqual(schedule.rows.count, timeline.rows.count)
        let root = thread(timeline, nested.abc).lane

        // The viewed plant's line starts at once, its pieces follow on without
        // gaps, and the whole line takes one segment.
        let rootSpans = schedule.rows.compactMap { $0.lines[root] }
        XCTAssertEqual(rootSpans.first?.delay ?? -1, 0, accuracy: 0.0001)
        for (upper, lower) in zip(rootSpans, rootSpans.dropFirst()) {
            XCTAssertEqual(upper.end, lower.delay, accuracy: 0.0001)
        }
        XCTAssertEqual(rootSpans.last?.end ?? 0, CareHistory.segmentDuration, accuracy: 0.0001)

        // C starts when ABC's line reaches the combine node.
        let mergeRow = timeline.rows.firstIndex { if case .merge(let m) = $0.kind { return m.output == nested.abc } else { return false } }!
        let node = schedule.rows[mergeRow].lines[root]!
        let cLane = thread(timeline, nested.c).lane
        XCTAssertEqual(schedule.rows[mergeRow].lines[cLane]?.delay ?? -1, node.delay + node.duration / 2, accuracy: 0.0001)
        XCTAssertEqual(schedule.rows[mergeRow].dot ?? -1, node.delay + node.duration / 2, accuracy: 0.0001)

        // Words follow their dot, never before the 30 ms stagger.
        for (index, timing) in schedule.rows.enumerated() {
            XCTAssertGreaterThanOrEqual(timing.label, CareHistory.labelStagger * Double(index))
            if let dot = timing.dot { XCTAssertGreaterThan(timing.label, dot) }
        }
    }

    func testOnlyTheFirstScreenfulIsTimed() {
        let nested = Nested(test: self)
        let timeline = CareHistory.timeline(for: nested.abc)
        let schedule = CareHistory.drawSchedule(for: timeline, window: 3)
        XCTAssertNotNil(schedule.timing(forRow: 2))
        XCTAssertNil(schedule.timing(forRow: 3), "past the window: already drawn")
        XCTAssertEqual(CareHistory.drawSchedule(for: .empty, window: 10), .idle)
    }

    func testEaseInverseRoundTrips() {
        for s in stride(from: 0.0, through: 1.0, by: 0.125) {
            XCTAssertEqual(CareHistory.easeInOut(CareHistory.easeInOutInverse(s)), s, accuracy: 0.0001)
        }
    }

    // MARK: - What a change touches

    func testOnlyChangesToThisFamilyCount() {
        let nested = Nested(test: self)
        let store = nested.store
        let footprint = CareHistory.Footprint(plant: nested.abc)
        let stranger = store.plant(nickname: "Stranger", acquired: day(2026, 1, 1))
        store.save()
        water(stranger, on: day(2026, 5, 1), by: "Sam", store: store)
        let strangerLog = stranger.wateringTask!.lastLog!
        XCTAssertFalse(footprint.isAffected(by: [strangerLog, stranger.wateringTask!, stranger]))

        water(nested.abc, on: day(2026, 5, 2), by: "Sam", store: store)
        XCTAssertTrue(footprint.isAffected(by: [nested.abc.wateringTask!.lastLog!]), "a new log on the family's task")
        // An old log of an original, already in the history.
        let oldLog = nested.a.tasks!.flatMap { $0.logs ?? [] }.first!
        XCTAssertTrue(footprint.isAffected(by: [oldLog]))
        let milestone = Milestones.add(title: "Bloom", date: day(2026, 5, 3), notes: nil, by: "Sam", to: nested.b,
                                       household: store.household, context: store.context, persistence: store.persistence)
        XCTAssertTrue(footprint.isAffected(by: [milestone]))
        let otherMilestone = Milestones.add(title: "Bloom", date: day(2026, 5, 3), notes: nil, by: "Sam", to: stranger,
                                            household: store.household, context: store.context, persistence: store.persistence)
        XCTAssertFalse(footprint.isAffected(by: [otherMilestone]))
        let cutting = Lineage.takeCutting(from: nested.abc, nickname: "Jr", date: day(2026, 5, 4), household: store.household,
                                          context: store.context, persistence: store.persistence)
        XCTAssertTrue(footprint.isAffected(by: [cutting]), "a new cutting of a family plant")
    }

    func testTheScreenRecomputesOnlyForItsFamily() {
        let nested = Nested(test: self)
        let store = nested.store
        let model = CareHistoryModel(plant: nested.abc)
        XCTAssertEqual(model.builds, 1)
        let rowsBefore = model.timeline.rows.count
        func changed(_ objects: [NSManagedObject], key: String = NSInsertedObjectsKey) -> Notification {
            Notification(name: .NSManagedObjectContextObjectsDidChange, object: store.context,
                         userInfo: [key: Set(objects)])
        }

        let stranger = store.plant(nickname: "Stranger", acquired: day(2026, 1, 1))
        water(stranger, on: day(2026, 5, 1), by: "Sam", store: store)
        model.contextChanged(changed([stranger.wateringTask!.lastLog!, stranger.wateringTask!, stranger]))
        XCTAssertEqual(model.builds, 1, "another plant's watering doesn't recompute")

        water(nested.abc, on: day(2026, 5, 2), by: "Sam", store: store)
        let log = nested.abc.wateringTask!.lastLog!
        model.contextChanged(changed([log]))
        XCTAssertEqual(model.builds, 2)
        XCTAssertEqual(model.timeline.rows.count, rowsBefore + 2, "May header and the new log")

        // Undone (deleted): its id is remembered, so it still counts.
        CareHistory.undo(log, context: store.context)
        model.contextChanged(changed([log], key: NSDeletedObjectsKey))
        XCTAssertEqual(model.builds, 3)
        XCTAssertEqual(model.timeline.rows.count, rowsBefore)
    }

    // MARK: - Undo one log

    func testUndoTakesBackOnlyThatLog() {
        let store = TestStore()
        let plant = store.plant(acquired: day(2026, 1, 1))
        water(plant, on: day(2026, 2, 1), by: "Sam", store: store)
        water(plant, on: day(2026, 2, 8), by: "Alex", store: store)
        water(plant, on: day(2026, 2, 15), by: "Sam", store: store)
        store.save()
        let middle = CareHistory.entries(for: plant)[1]
        XCTAssertEqual(middle.doneAt, day(2026, 2, 8))
        plant.wateringTask!.dueOverride = day(2026, 3, 1)

        CareHistory.undo(middle.log, context: store.context)
        store.save()
        XCTAssertEqual(CareHistory.entries(for: plant).map(\.doneAt), [day(2026, 2, 15), day(2026, 2, 1)])
        XCTAssertEqual(plant.wateringTask!.dueOverride, day(2026, 3, 1), "not the latest, so the schedule stays")

        CareHistory.undo(CareHistory.entries(for: plant)[0].log, context: store.context)
        XCTAssertNil(plant.wateringTask!.dueOverride, "the latest log's override goes with it, like undoDone")
        XCTAssertEqual(CareHistory.entries(for: plant).map(\.doneAt), [day(2026, 2, 1)])
    }

    func testUndoingAOneTimeTaskBringsItBack() {
        let store = TestStore()
        let plant = store.plant(acquired: day(2026, 1, 1))
        let repot = CareSchedule.makeTask(name: "Repot", count: 1, unit: .once, firstDue: day(2026, 2, 1),
                                          plants: [plant], household: store.household, context: store.context,
                                          persistence: store.persistence)
        CareSchedule.markDone(repot, by: "Sam", at: day(2026, 2, 3), household: store.household,
                              context: store.context, persistence: store.persistence)
        store.save()
        XCTAssertTrue(repot.isArchived)
        CareHistory.undo(repot.lastLog!, context: store.context)
        XCTAssertFalse(repot.isArchived)
        XCTAssertTrue(plant.activeTasks.contains(repot))
    }

    // MARK: - Words

    func testDayLabelsInsideAMonth() {
        // Nov 14 2025 was a Friday.
        XCTAssertEqual(CareHistory.dayLabel(day(2025, 11, 14), locale: enUS), "Fri 14")
        XCTAssertEqual(CareHistory.dayLabel(nil, locale: enUS), "Unknown date")
        XCTAssertEqual(CareHistory.spokenDay(day(2025, 11, 14), now: day(2025, 12, 1), locale: enUS), "Friday November 14")
        XCTAssertEqual(CareHistory.spokenDay(day(2024, 11, 14), now: day(2025, 12, 1), locale: enUS), "Thursday November 14, 2024")
        XCTAssertEqual(CareHistory.monthLabel(day(2025, 11, 14), locale: enUS), "November 2025")
        XCTAssertEqual(CareHistory.monthLabel(day(2025, 11, 14), short: true, now: day(2025, 12, 1), locale: enUS), "Nov")
    }

    func testRowsReadAsASentence() {
        let store = TestStore()
        let rosie = store.plant(nickname: "Rosie", acquired: day(2025, 1, 1))
        let spike = store.plant(nickname: "Spike", acquired: day(2025, 1, 2))
        water(rosie, on: day(2025, 11, 14), by: "Alex", store: store)
        let trio = combine([rosie, spike], "The Trio", on: day(2025, 11, 20), store: store)
        water(trio, on: day(2025, 11, 21), by: " ", store: store)
        store.save()
        let rows = CareHistory.timeline(for: trio).rows
        let spoken = rows.map { CareHistory.spokenLabel(for: $0, viewedPlant: trio, now: day(2025, 12, 1), locale: enUS) }
        XCTAssertEqual(spoken, [
            "November 2025",
            "Watered, Friday November 21.",
            "Combined into The Trio from Rosie and Spike, Thursday November 20.",
            "Watered, Friday November 14, by Alex. Rosie, before the Combine.",
        ])
        XCTAssertEqual(CareHistory.names([rosie, spike, trio]), "Rosie, Spike & The Trio")
    }

    // MARK: - Celebrations

    func testRoundNumbersAndYearsAreCelebrated() {
        func stats(waterings: Int, first: Date) -> CareHistory.Stats {
            CareHistory.Stats(counts: [.init(title: "Watered", count: waterings, isWatering: true)], total: waterings,
                              lead: .init(title: "Watered", count: waterings, isWatering: true), since: first,
                              mostlyBy: nil, mostlyByCount: 0, firstLog: first)
        }
        let now = day(2026, 11, 21)
        XCTAssertEqual(stats(waterings: 100, first: day(2026, 1, 1)).celebration(now: now), "100th watering 🎉")
        XCTAssertEqual(stats(waterings: 25, first: day(2026, 1, 1)).celebration(now: now), "25th watering 🎉")
        XCTAssertNil(stats(waterings: 24, first: day(2026, 1, 1)).celebration(now: now))
        XCTAssertEqual(stats(waterings: 24, first: day(2024, 10, 1)).celebration(now: now), "Cared for 2 years and counting")
        XCTAssertEqual(stats(waterings: 7, first: day(2025, 11, 21)).celebration(now: now), "Cared for 1 year and counting")
        XCTAssertEqual([1, 2, 3, 4, 11, 12, 13, 21, 102, 111].map(CareHistory.Stats.ordinal),
                       ["1st", "2nd", "3rd", "4th", "11th", "12th", "13th", "21st", "102nd", "111th"])
    }

    func testOneHundredWateringsFromTheStore() {
        let store = TestStore()
        let plant = store.plant(acquired: day(2024, 1, 1))
        for index in 0..<100 {
            water(plant, on: day(2024, 1, 2).addingTimeInterval(Double(index) * 86_400 * 3), by: "Sam", store: store)
        }
        store.save()
        XCTAssertEqual(CareHistory.stats(for: plant)?.celebration(now: day(2026, 11, 21)), "100th watering 🎉")
    }
}
