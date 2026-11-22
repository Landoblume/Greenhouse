import CoreData

/// Everything that's been done for a plant, newest first: each care log on its
/// tasks, including tasks that were archived (a one-time task that's finished,
/// or the watering a combine retired). A combined plant also shows what was
/// done for the plants it was combined from.
///
/// The history reads as threads: each plant in the family is a lane, and at a
/// combine the lanes of the originals join the combined plant's lane.
/// Everything here is pure, so the layout is testable without a screen. The
/// draw-in timing, the "is this change ours" test, the one-plant filter and
/// the spoken labels live in CareHistoryLayout.swift.
enum CareHistory {
    // MARK: - Entries

    struct Entry: Identifiable, Equatable {
        let log: CareLog
        /// "Watered" for watering tasks, otherwise the task's name.
        let title: String
        /// Nil when the log has no date (shouldn't happen, but a synced row can be half-written).
        let doneAt: Date?
        /// Nil when nobody's name was set.
        let doneBy: String?
        /// The plant whose thread this sits on; differs from the viewed plant
        /// for care done before a combine.
        let source: Plant
        /// Every plant the care was for, oldest first, `source` among them. More
        /// than one when a task that covered several originals moved to the
        /// combined plant: the log shows once, on the oldest.
        let sources: [Plant]
        var id: NSManagedObjectID { log.objectID }

        var isWatering: Bool { log.task?.isWatering ?? false }

        /// "Aloe + Fern"
        var sourceLabel: String { sources.map(\.displayName).joined(separator: " + ") }
    }

    /// Newest first. Logs with the same date are ordered by id, so the order
    /// is the same on every launch and on both phones.
    static func entries(for plant: Plant) -> [Entry] {
        let family = [plant] + Lineage.ancestors(of: plant)
        var seen: Set<NSManagedObjectID> = []
        var result: [Entry] = []
        for member in family {
            for task in member.tasks ?? [] {
                for log in task.logs ?? [] where seen.insert(log.objectID).inserted {
                    let resolved = owner(of: log.doneAt, startingAt: member, family: family)
                    result.append(Entry(
                        log: log,
                        title: title(of: task),
                        doneAt: log.doneAt,
                        doneBy: cleaned(log.doneBy),
                        source: resolved.plant,
                        sources: resolved.labels
                    ))
                }
            }
        }
        return result.sorted { a, b in
            let aDate = a.doneAt ?? .distantPast
            let bDate = b.doneAt ?? .distantPast
            if aDate != bDate { return aDate > bDate }
            return (a.log.uuid?.uuidString ?? "") < (b.log.uuid?.uuidString ?? "")
        }
    }

    /// Whose thread a log belongs on, by its date. A task moves to the combined
    /// plant at a combine, so care dated before it was for the originals; and
    /// a log dated on or after the combine (a combine entered with an earlier
    /// date than the care) is for the combined plant. Either can chain through
    /// nested combines.
    private static func owner(of date: Date?, startingAt start: Plant, family: [Plant]) -> (plant: Plant, labels: [Plant]) {
        guard let date else { return (start, [start]) }
        var current = start
        var labels = [start]
        for _ in 0..<family.count * 2 {
            if let event = current.producedBy, let combined = event.date, date < combined {
                let inputs = sortedByAge(inputsAlive(in: event, at: date))
                guard let oldest = inputs.first else { break }
                current = oldest
                labels = inputs
            } else if let event = current.consumedBy, let combined = event.date, date >= combined,
                      let output = sortedByAcquired(event.outputs ?? []).first(where: { family.contains($0) }) {
                current = output
                labels = [output]
            } else {
                break
            }
        }
        return (current, labels)
    }

    /// The plants a combine's care could have been for on `date`: its inputs,
    /// except one that was itself made by a later combine, which stands for
    /// the plants it was made from.
    private static func inputsAlive(in event: LineageEvent, at date: Date) -> [Plant] {
        var result: [Plant] = []
        for input in event.inputs ?? [] {
            if let madeBy = input.producedBy, let made = madeBy.date, date < made {
                result += inputsAlive(in: madeBy, at: date)
            } else {
                result.append(input)
            }
        }
        return Array(Set(result))
    }

    /// By how long you've had them (counting back through combines), oldest
    /// first; ties by id.
    private static func sortedByAge(_ plants: [Plant]) -> [Plant] {
        plants.sorted { a, b in
            let aDate = Lineage.effectiveAcquiredDate(of: a) ?? .distantPast
            let bDate = Lineage.effectiveAcquiredDate(of: b) ?? .distantPast
            if aDate != bDate { return aDate < bDate }
            return (a.uuid?.uuidString ?? "") < (b.uuid?.uuidString ?? "")
        }
    }

    /// Oldest first; ties by id so it never depends on set order.
    private static func sortedByAcquired(_ plants: Set<Plant>) -> [Plant] {
        plants.sorted { a, b in
            let aDate = a.acquiredDate ?? .distantPast
            let bDate = b.acquiredDate ?? .distantPast
            if aDate != bDate { return aDate < bDate }
            return (a.uuid?.uuidString ?? "") < (b.uuid?.uuidString ?? "")
        }
    }

    // MARK: - Milestones and cuttings on the threads

    /// A milestone ("First bloom") written down for a plant in the family.
    struct MilestoneMark: Identifiable, Equatable {
        let milestone: Milestone
        let title: String
        let date: Date?
        let addedBy: String?
        let notes: String?
        /// The thread it sits on, by date (like a log).
        let source: Plant
        var id: NSManagedObjectID { milestone.objectID }
    }

    /// A cutting taken from a plant in the family, or the cutting a plant in
    /// the family was started from. Either way the row links to the other plant.
    struct CuttingMark: Identifiable, Equatable {
        enum Direction: Equatable {
            /// `cutting` was taken from `parent`, which is in this family.
            case taken
            /// A plant in this family started as `cutting`, from `parent` outside it.
            case startedFrom
        }
        let cutting: Plant
        let parent: Plant
        let direction: Direction
        let date: Date?
        /// The thread it sits on.
        let source: Plant
        /// The plant the row opens.
        var linked: Plant { direction == .taken ? cutting : parent }
        var id: String { "\(direction == .taken ? "taken" : "from")-\(cutting.objectID.uriRepresentation())" }
    }

    /// Newest first.
    static func milestones(for plant: Plant) -> [MilestoneMark] {
        let family = [plant] + Lineage.ancestors(of: plant)
        return family.flatMap { member in
            (member.milestones ?? []).map { milestone in
                MilestoneMark(
                    milestone: milestone,
                    title: cleaned(milestone.title) ?? "Milestone",
                    date: milestone.date,
                    addedBy: cleaned(milestone.addedBy),
                    notes: cleaned(milestone.notes),
                    source: owner(of: milestone.date, startingAt: member, family: family).plant
                )
            }
        }
        .sorted { a, b in
            let aDate = a.date ?? .distantPast
            let bDate = b.date ?? .distantPast
            if aDate != bDate { return aDate > bDate }
            return (a.milestone.uuid?.uuidString ?? "") < (b.milestone.uuid?.uuidString ?? "")
        }
    }

    /// Newest first: cuttings taken from the family, and the plant a member
    /// was itself started from.
    static func cuttings(for plant: Plant) -> [CuttingMark] {
        let family = [plant] + Lineage.ancestors(of: plant)
        var result: [CuttingMark] = []
        for member in family {
            for cutting in member.cuttings ?? [] where !family.contains(cutting) {
                result.append(CuttingMark(
                    cutting: cutting, parent: member, direction: .taken, date: cutting.acquiredDate,
                    source: owner(of: cutting.acquiredDate, startingAt: member, family: family).plant
                ))
            }
            if let parent = member.cuttingOf, !family.contains(parent) {
                result.append(CuttingMark(
                    cutting: member, parent: parent, direction: .startedFrom, date: member.acquiredDate, source: member
                ))
            }
        }
        return result.sorted { a, b in
            let aDate = a.date ?? .distantPast
            let bDate = b.date ?? .distantPast
            if aDate != bDate { return aDate > bDate }
            return a.id < b.id
        }
    }

    // MARK: - Threads

    /// One plant's line through the history.
    struct CareThread: Identifiable, Equatable {
        let plant: Plant
        /// Its index in the timeline's threads (0 is the viewed plant;
        /// originals follow, nearest first). Lane marks are in this order.
        let lane: Int
        /// When the thread begins: the day it was combined into existence, or
        /// acquired (or its first log, if that's earlier).
        let start: Date?
        /// When it joined another plant; nil while it carries on.
        let end: Date?
        let mergesInto: Plant?
        /// Where it's drawn, left to right. A combined plant shares a column
        /// with its middle original (one carries straight on), so this isn't
        /// unique, but threads sharing a column never overlap in time.
        var column = 0
        /// Into `GH.threads` (wrapping). The same for this plant in every
        /// history it shows in.
        var color = 0
        var id: NSManagedObjectID { plant.objectID }
    }

    /// The viewed plant first, then every plant it came from (nearest first),
    /// laid out with nothing folded.
    static func threads(for plant: Plant) -> [CareThread] {
        let family = [plant] + Lineage.ancestors(of: plant)
        let all = entries(for: plant)
        let colors = colorOrder(for: plant)
        var result = family.enumerated().map { lane, member in
            let logDates = all.filter { $0.source == member }.compactMap(\.doneAt)
            let began = member.producedBy?.date ?? member.acquiredDate
            return CareThread(
                plant: member,
                lane: lane,
                start: [began, logDates.min()].compactMap { $0 }.min(),
                end: member.consumedBy?.date,
                mergesInto: member.consumedBy.flatMap { event in
                    family.first { ($0.producedBy == event) }
                },
                color: colors[member.objectID] ?? lane
            )
        }
        let layout = columns(of: familyTree(result), hidden: [])
        for index in result.indices { result[index].column = layout.columns[index] ?? 0 }
        return result
    }

    /// Thread colors for everyone connected to this plant by combines (and
    /// splits), in the order their threads began. A plant keeps its color in
    /// every history it shows in, and a combined plant gets the next unused one.
    static func colorOrder(for plant: Plant) -> [NSManagedObjectID: Int] {
        var seen: Set<NSManagedObjectID> = [plant.objectID]
        var component = [plant]
        var queue = [plant]
        while let next = queue.popLast() {
            var neighbors: Set<Plant> = []
            for event in [next.producedBy, next.consumedBy].compactMap({ $0 }) {
                neighbors.formUnion(event.inputs ?? [])
                neighbors.formUnion(event.outputs ?? [])
            }
            for neighbor in neighbors where seen.insert(neighbor.objectID).inserted {
                component.append(neighbor)
                queue.append(neighbor)
            }
        }
        let ordered = component.sorted { a, b in
            let aDate = a.producedBy?.date ?? a.acquiredDate ?? a.createdAt ?? .distantPast
            let bDate = b.producedBy?.date ?? b.acquiredDate ?? b.createdAt ?? .distantPast
            if aDate != bDate { return aDate < bDate }
            return (a.uuid?.uuidString ?? "") < (b.uuid?.uuidString ?? "")
        }
        return Dictionary(uniqueKeysWithValues: ordered.enumerated().map { ($0.element.objectID, $0.offset) })
    }

    // MARK: - Lane layout (pure, over thread indices)

    /// The family as a tree of thread indices: 0 is the viewed plant, and a
    /// node's children are the originals of the combine that made it, left to
    /// right by when their threads began.
    struct FamilyTree: Equatable {
        var children: [[Int]]
        /// When each node was combined into existence (nil for a plant that wasn't).
        var combinedAt: [Date?]
        var root: Int { 0 }
        var count: Int { children.count }

        func parent(of node: Int) -> Int? {
            children.firstIndex { $0.contains(node) }
        }

        func descendants(of node: Int) -> [Int] {
            children[node].flatMap { [$0] + descendants(of: $0) }
        }
    }

    static func familyTree(_ threads: [CareThread]) -> FamilyTree {
        let index = Dictionary(uniqueKeysWithValues: threads.map { ($0.plant.objectID, $0.lane) })
        var children = Array(repeating: [Int](), count: threads.count)
        // Nearest first, so a plant reached twice (both halves of a split
        // combined again) hangs under the first one only.
        var claimed: Set<Int> = [0]
        var queue = threads.isEmpty ? [] : [0]
        while !queue.isEmpty {
            let node = queue.removeFirst()
            let inputs = (threads[node].plant.producedBy?.inputs ?? []).compactMap { index[$0.objectID] }
            for input in inputs.sorted() where claimed.insert(input).inserted {
                children[node].append(input)
                queue.append(input)
            }
        }
        func earliest(_ node: Int) -> Date {
            ([threads[node].start ?? .distantFuture] + children[node].map(earliest)).min() ?? .distantFuture
        }
        // Worked out before sorting: the sort mustn't read `children` while it rearranges it.
        let began = children.indices.map(earliest)
        for node in children.indices {
            children[node].sort { a, b in
                let aDate = began[a], bDate = began[b]
                if aDate != bDate { return aDate < bDate }
                return (threads[a].plant.uuid?.uuidString ?? "") < (threads[b].plant.uuid?.uuidString ?? "")
            }
        }
        return FamilyTree(children: children, combinedAt: threads.map { $0.plant.producedBy?.date })
    }

    /// Every visible node gets a column. Each subtree owns a contiguous run of
    /// columns, and a combined plant takes its middle original's column (left
    /// of middle for an even count), so branches stay short and lines never cross.
    static func columns(of tree: FamilyTree, hidden: Set<Int>) -> (columns: [Int: Int], count: Int) {
        var result: [Int: Int] = [:]
        func place(_ node: Int, at offset: Int) -> Int {
            let kids = tree.children[node].filter { !hidden.contains($0) }
            guard !kids.isEmpty else {
                result[node] = offset
                return 1
            }
            var next = offset
            for kid in kids { next += place(kid, at: next) }
            result[node] = result[kids[(kids.count - 1) / 2]]
            return next - offset
        }
        guard tree.count > 0 else { return ([:], 0) }
        let width = place(tree.root, at: 0)
        return (result, width)
    }

    /// Past this many columns, older branches fold away.
    static let maxColumns = 4

    /// Which threads to hide so at most `maxColumns` show: the oldest combine
    /// first (its originals fold into a "Show N earlier plants" pill under it),
    /// and if the viewed plant itself was combined from too many, its oldest
    /// originals. `folds` says how many plants each visible node hides.
    static func fold(_ tree: FamilyTree, maxColumns: Int = maxColumns) -> (hidden: Set<Int>, folds: [Int: Int]) {
        var hidden: Set<Int> = []
        func visibleKids(_ node: Int) -> [Int] { tree.children[node].filter { !hidden.contains($0) } }
        func width(_ node: Int) -> Int {
            let kids = visibleKids(node)
            return kids.isEmpty ? 1 : kids.map(width).reduce(0, +)
        }
        var steps = 0
        while tree.count > 0, width(tree.root) > maxColumns, steps < tree.count {
            steps += 1
            let oldestCombine = (0..<tree.count)
                .filter { $0 != tree.root && !hidden.contains($0) && width($0) > 1 }
                .min { a, b in
                    let aDate = tree.combinedAt[a] ?? .distantPast
                    let bDate = tree.combinedAt[b] ?? .distantPast
                    return aDate != bDate ? aDate < bDate : a < b
                }
            if let oldestCombine {
                hidden.formUnion(tree.descendants(of: oldestCombine))
            } else {
                let kids = visibleKids(tree.root)
                guard kids.count > 1, let oldest = kids.first else { break }
                hidden.insert(oldest)
                hidden.formUnion(tree.descendants(of: oldest))
            }
        }
        // Credit each hidden plant to its nearest visible ancestor.
        var folds: [Int: Int] = [:]
        for node in hidden {
            var up = tree.parent(of: node)
            while let current = up, hidden.contains(current) { up = tree.parent(of: current) }
            if let owner = up { folds[owner, default: 0] += 1 }
        }
        return (hidden, folds)
    }

    /// Where originals joined: "Combined" (or, for plants split earlier, "Split").
    struct Merge: Identifiable, Equatable {
        let output: Plant
        let inputs: [Plant]
        let date: Date?
        let kind: LineageKind
        var id: NSManagedObjectID { output.objectID }

        var title: String { kind == .staple ? "Combined" : "Split" }
    }

    static func merges(for plant: Plant) -> [Merge] {
        ([plant] + Lineage.ancestors(of: plant)).compactMap { member in
            guard let event = member.producedBy else { return nil }
            return Merge(output: member, inputs: sortedByAcquired(event.inputs ?? []), date: event.date, kind: event.kindValue)
        }
    }

    // MARK: - Rows

    /// How a dot looks: the shape carries the kind, so color isn't the only cue.
    enum Glyph: Equatable {
        /// A filled dot.
        case watering
        /// A ring: any other reminder (fertilize, a treatment).
        case task
        /// A diamond.
        case milestone
        /// A dot with a dotted twig leaving the thread.
        case cutting
        /// The big node on a combined plant's lane.
        case merge
        /// At the top of a plant that was combined away: where its thread ends.
        case joined
    }

    /// What a lane looks like in one row of the list.
    struct LaneMark: Equatable {
        /// A line comes in from the row above.
        var lineAbove = false
        /// A line carries on to the row below.
        var lineBelow = false
        /// Set when this lane has a dot in the row.
        var glyph: Glyph?
        /// On an original's lane in its merge row: the lane it curves into.
        var joinsLane: Int?

        var dot: Bool { glyph != nil }
        /// On the combined plant's lane: the node itself.
        var isMergeNode: Bool { glyph == .merge }
        var isEmpty: Bool { self == LaneMark() }
    }

    enum RowKind: Equatable {
        /// nil is the "Unknown date" group.
        case month(Date?)
        case log(Entry)
        case merge(Merge)
        case milestone(MilestoneMark)
        case cutting(CuttingMark)
        /// At the top of a plant that was combined (or split) into `into`.
        case joined(into: Plant, with: [Plant], date: Date?, kind: LineageKind)
        /// Under a folded combine: how many earlier plants it hides.
        case showEarlier(count: Int, under: Plant)
    }

    struct Row: Identifiable, Equatable {
        let id: String
        let kind: RowKind
        /// One per thread, same order as `Timeline.threads`.
        var lanes: [LaneMark]

        /// The plant whose thread carries this row's dot (nil for months, the
        /// fold pill and the "became part of" row, which sits on lane 0).
        var plant: Plant? {
            switch kind {
            case .month, .showEarlier, .joined: nil
            case .log(let entry): entry.source
            case .merge(let merge): merge.output
            case .milestone(let mark): mark.source
            case .cutting(let mark): mark.source
            }
        }

        var date: Date? {
            switch kind {
            case .month(let date): date
            case .log(let entry): entry.doneAt
            case .merge(let merge): merge.date
            case .milestone(let mark): mark.date
            case .cutting(let mark): mark.date
            case .joined(_, _, let date, _): date
            case .showEarlier: nil
            }
        }

        var isMonth: Bool {
            if case .month = kind { return true }
            return false
        }
    }

    struct Timeline: Equatable {
        /// Only the threads that show (folded ones are left out), indexed by `lane`.
        let threads: [CareThread]
        let rows: [Row]
        /// How many columns the lanes need.
        var columnCount = 1
        /// Plants folded away; 0 when everything shows.
        var hiddenCount = 0

        static let empty = Timeline(threads: [], rows: [])
    }

    /// The whole list, newest first, under month headers, with each lane's
    /// marks worked out so the view only has to draw them. Past
    /// `maxColumns` the oldest branches fold unless `expanded`.
    static func timeline(for plant: Plant, expanded: Bool = false, calendar: Calendar = .current) -> Timeline {
        timeline(for: plant, entries: entries(for: plant), expanded: expanded, calendar: calendar)
    }

    /// The same, from entries already worked out (the screen computes them once for the stats too).
    static func timeline(for plant: Plant, entries allEntries: [Entry], expanded: Bool, calendar: Calendar = .current) -> Timeline {
        let family = threads(for: plant)
        let tree = familyTree(family)
        let folding = expanded ? (hidden: Set<Int>(), folds: [Int: Int]()) : fold(tree)
        let layout = columns(of: tree, hidden: folding.hidden)
        let visible = family.indices.filter { !folding.hidden.contains($0) }
        let threads: [CareThread] = visible.enumerated().map { newLane, old in
            let thread = family[old]
            return CareThread(plant: thread.plant, lane: newLane, start: thread.start, end: thread.end,
                              mergesInto: thread.mergesInto, column: layout.columns[old] ?? 0, color: thread.color)
        }
        let lane = Dictionary(uniqueKeysWithValues: threads.map { ($0.plant.objectID, $0.lane) })
        func shows(_ plant: Plant) -> Bool { lane[plant.objectID] != nil }

        enum Item {
            case log(Entry), merge(Merge), milestone(MilestoneMark), cutting(CuttingMark)
            case joined(Plant, [Plant], Date?, LineageKind), showEarlier(Int, Plant, Date?)
            var date: Date? {
                switch self {
                case .log(let entry): entry.doneAt
                case .merge(let merge): merge.date
                case .milestone(let mark): mark.date
                case .cutting(let mark): mark.date
                case .joined(_, _, let date, _): date
                case .showEarlier(_, _, let date): date
                }
            }
            /// On the same date: where the plant went first, then what was
            /// done, then the combine, then what it folds.
            var rank: Int {
                switch self {
                case .joined: 0
                case .log, .milestone, .cutting: 1
                case .merge: 2
                case .showEarlier: 3
                }
            }
        }
        var items: [Item] = allEntries.filter { shows($0.source) }.map(Item.log)
        items += milestones(for: plant).filter { shows($0.source) }.map(Item.milestone)
        items += cuttings(for: plant).filter { shows($0.source) }.map(Item.cutting)
        for merge in merges(for: plant) where shows(merge.output) {
            items.append(.merge(merge))
            if let old = family.firstIndex(where: { $0.plant == merge.output }), let count = folding.folds[old], count > 0 {
                items.append(.showEarlier(count, merge.output, merge.date))
            }
        }
        if let event = plant.consumedBy, let output = sortedByAcquired(event.outputs ?? []).first {
            let others = sortedByAcquired(event.inputs ?? []).filter { $0 != plant }
            items.append(.joined(output, others, event.date, event.kindValue))
        }
        // Stable: newest first; ties by rank, then the order they were gathered.
        items = items.enumerated().sorted { a, b in
            let aDate = a.element.date ?? .distantPast
            let bDate = b.element.date ?? .distantPast
            if aDate != bDate { return aDate > bDate }
            if a.element.rank != b.element.rank { return a.element.rank < b.element.rank }
            return a.offset < b.offset
        }.map(\.element)

        // Flatten with month headers.
        var rows: [Row] = []
        var currentMonth: DateComponents?
        var started = false
        for item in items {
            let comps = item.date.map { calendar.dateComponents([.year, .month], from: $0) }
            if !started || currentMonth != comps {
                started = true
                currentMonth = comps
                let start = comps.flatMap { calendar.date(from: $0) }
                rows.append(Row(id: "month-\(start.map { String($0.timeIntervalSince1970) } ?? "unknown")", kind: .month(start), lanes: []))
            }
            switch item {
            case .log(let entry): rows.append(Row(id: "log-\(entry.id.uriRepresentation())", kind: .log(entry), lanes: []))
            case .merge(let merge): rows.append(Row(id: "merge-\(merge.id.uriRepresentation())", kind: .merge(merge), lanes: []))
            case .milestone(let mark): rows.append(Row(id: "milestone-\(mark.id.uriRepresentation())", kind: .milestone(mark), lanes: []))
            case .cutting(let mark): rows.append(Row(id: "cutting-\(mark.id)", kind: .cutting(mark), lanes: []))
            case .joined(let into, let with, let date, let kind):
                rows.append(Row(id: "joined-\(plant.objectID.uriRepresentation())",
                                kind: .joined(into: into, with: with, date: date, kind: kind), lanes: []))
            case .showEarlier(let count, let under, _):
                rows.append(Row(id: "earlier-\(under.objectID.uriRepresentation())", kind: .showEarlier(count: count, under: under), lanes: []))
            }
        }

        // Where each thread first and last appears in the list.
        var first: [Int: Int] = [:]
        var last: [Int: Int] = [:]
        func note(_ laneIndex: Int, at index: Int) {
            first[laneIndex] = min(first[laneIndex] ?? index, index)
            last[laneIndex] = max(last[laneIndex] ?? index, index)
        }
        for (index, row) in rows.enumerated() {
            switch row.kind {
            case .month, .showEarlier: break
            case .joined: note(0, at: index)
            case .merge(let merge):
                if let out = lane[merge.output.objectID] { note(out, at: index) }
                for input in merge.inputs { if let l = lane[input.objectID] { note(l, at: index) } }
            default:
                if let source = row.plant, let l = lane[source.objectID] { note(l, at: index) }
            }
        }
        // A thread that carries on past the combine runs from the top of the list.
        for thread in threads where thread.end == nil {
            if first[thread.lane] != nil { first[thread.lane] = 0 }
        }

        for index in rows.indices {
            var marks = Array(repeating: LaneMark(), count: threads.count)
            for l in marks.indices {
                guard let top = first[l], let bottom = last[l] else { continue }
                marks[l].lineAbove = index > top && index <= bottom
                marks[l].lineBelow = index >= top && index < bottom
            }
            switch rows[index].kind {
            case .month, .showEarlier: break
            case .log(let entry):
                if let l = lane[entry.source.objectID] { marks[l].glyph = entry.isWatering ? .watering : .task }
            case .milestone(let mark):
                if let l = lane[mark.source.objectID] { marks[l].glyph = .milestone }
            case .cutting(let mark):
                if let l = lane[mark.source.objectID] { marks[l].glyph = .cutting }
            case .joined:
                marks[0].glyph = .joined
                marks[0].lineAbove = false
            case .merge(let merge):
                guard let out = lane[merge.output.objectID] else { break }
                marks[out].glyph = .merge
                // The output thread starts here, so nothing runs below it.
                marks[out].lineBelow = false
                for input in merge.inputs {
                    guard let l = lane[input.objectID] else { continue }
                    marks[l].joinsLane = out
                    marks[l].lineAbove = false
                }
            }
            rows[index].lanes = marks
        }
        return Timeline(threads: threads, rows: rows, columnCount: max(layout.count, 1), hiddenCount: folding.hidden.count)
    }

    // MARK: - Stats

    struct KindCount: Equatable {
        let title: String
        let count: Int
        let isWatering: Bool
    }

    struct Stats: Equatable {
        /// Most done first, watering winning ties.
        let counts: [KindCount]
        let total: Int
        /// What the headline leads with: watering if there is any, else the most done.
        let lead: KindCount
        /// The day of the oldest log of the lead kind.
        let since: Date?
        /// Whoever did the most; ties go to the first name alphabetically.
        /// Not necessarily a majority: see `byline(viewerName:)`.
        let mostlyBy: String?
        /// How many of all the logs `mostlyBy` did.
        let mostlyByCount: Int
        /// The oldest log of any kind.
        var firstLog: Date? = nil

        /// A person has to have done more than this share of all the logs
        /// (unnamed ones count) before the line credits them.
        static let clearMajority = 0.6

        /// Nobody is credited before this many logs; two waterings aren't a pattern.
        static let minimumLogs = 3

        /// "all by Sam 💚" when every log is theirs, "mostly by Sam 💚" when
        /// they did a clear majority of all the logs, and "you" for the
        /// viewer in either. "shared care 💚" when the named logs are spread
        /// around. Nil when nobody's name was set on any log, or there are
        /// fewer than `minimumLogs`, since then there's nothing to say.
        func byline(viewerName: String? = nil) -> String? {
            guard let mostlyBy, total >= Self.minimumLogs else { return nil }
            let viewer = viewerName?.trimmingCharacters(in: .whitespacesAndNewlines)
            let isViewer = viewer.map { !$0.isEmpty && $0.caseInsensitiveCompare(mostlyBy) == .orderedSame } ?? false
            let who = isViewer ? "you" : mostlyBy
            if mostlyByCount == total { return "all by \(who) 💚" }
            guard Double(mostlyByCount) > Double(total) * Self.clearMajority else { return "shared care 💚" }
            return "mostly by \(who) 💚"
        }

        /// "Watered 23 times since May 2023 · mostly by Sam 💚"
        func headline(viewerName: String?) -> String {
            let times = lead.count == 1 ? "1 time" : "\(lead.count) times"
            var text = lead.isWatering ? "Watered \(times)" : "\(lead.title) \(times)"
            if let since { text += " since " + since.formatted(.dateTime.month(.abbreviated).year()) }
            if let byline = byline(viewerName: viewerName) { text += " · " + byline }
            return text
        }

        /// The headline without knowing who's looking, so a name is never "you".
        var headline: String { headline(viewerName: nil) }

        /// The other kinds, "Mist 4 · Repot 1", or nil when there's only one kind.
        var others: String? {
            let rest = counts.filter { $0.title != lead.title }
            return rest.isEmpty ? nil : rest.map { "\($0.title) \($0.count)" }.joined(separator: " · ")
        }

        /// How many times it's been watered.
        var waterings: Int { counts.first { $0.isWatering }?.count ?? 0 }

        /// A line worth a little party: "100th watering 🎉" when the watering
        /// count is a round number, otherwise "Cared for 2 years and counting"
        /// once the first log is a year or more old. Nil otherwise.
        func celebration(now: Date = .now, calendar: Calendar = .current) -> String? {
            if Self.isRound(waterings) { return "\(Self.ordinal(waterings)) watering 🎉" }
            if let firstLog, let years = calendar.dateComponents([.year], from: firstLog, to: now).year, years >= 1 {
                return years == 1 ? "Cared for 1 year and counting" : "Cared for \(years) years and counting"
            }
            return nil
        }

        /// 10, 25, 50, then every hundred.
        static func isRound(_ count: Int) -> Bool {
            [10, 25, 50].contains(count) || (count >= 100 && count % 100 == 0)
        }

        static func ordinal(_ number: Int) -> String {
            let suffix: String
            switch (number % 10, number % 100) {
            case (_, 11...13): suffix = "th"
            case (1, _): suffix = "st"
            case (2, _): suffix = "nd"
            case (3, _): suffix = "rd"
            default: suffix = "th"
            }
            return "\(number)\(suffix)"
        }
    }

    /// Nil when there are no logs.
    static func stats(for plant: Plant) -> Stats? {
        stats(of: entries(for: plant))
    }

    static func stats(of all: [Entry]) -> Stats? {
        guard !all.isEmpty else { return nil }
        var byKind: [String: (count: Int, watering: Bool)] = [:]
        for entry in all {
            byKind[entry.title] = ((byKind[entry.title]?.count ?? 0) + 1, entry.isWatering)
        }
        let counts = byKind
            .map { KindCount(title: $0.key, count: $0.value.count, isWatering: $0.value.watering) }
            .sorted {
                if $0.count != $1.count { return $0.count > $1.count }
                if $0.isWatering != $1.isWatering { return $0.isWatering }
                return $0.title < $1.title
            }
        let lead = counts.first { $0.isWatering } ?? counts[0]
        var people: [String: Int] = [:]
        for name in all.compactMap(\.doneBy) { people[name, default: 0] += 1 }
        let top = people.max { a, b in
            a.value != b.value ? a.value < b.value : a.key > b.key
        }
        return Stats(
            counts: counts,
            total: all.count,
            lead: lead,
            since: all.filter { $0.title == lead.title }.compactMap(\.doneAt).min(),
            mostlyBy: top?.key,
            mostlyByCount: top?.value ?? 0,
            firstLog: all.compactMap(\.doneAt).min()
        )
    }

    // MARK: - Undo one log

    /// Takes back one log, and only that one: the swipe on a history row. Like
    /// `CareSchedule.undoDone`, a schedule override set by the latest log goes
    /// with it; and a one-time task whose only log this was comes back.
    static func undo(_ log: CareLog, context: NSManagedObjectContext) {
        let task = log.task
        let wasLatest = task?.lastLog == log
        context.delete(log)
        // Updates `task.logs` now, so the due date is right on the next draw.
        context.processPendingChanges()
        guard let task else { return }
        if wasLatest { task.dueOverride = nil }
        if task.unit == .once, (task.logs ?? []).isEmpty, task.isRelevant { task.isArchived = false }
    }

    // MARK: - Helpers

    private static func title(of task: CareTask) -> String {
        if task.isWatering { return "Watered" }
        return cleaned(task.name) ?? "Care task"
    }

    static func cleaned(_ text: String?) -> String? {
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}
