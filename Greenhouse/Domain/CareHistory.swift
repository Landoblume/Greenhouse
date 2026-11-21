import CoreData

/// Everything that's been done for a plant, newest first: each care log on its
/// tasks, including tasks that were archived (a one-time task that's finished,
/// or the watering a combine retired). A combined plant also shows what was
/// done for the plants it was combined from.
///
/// The history reads as threads: each plant in the family is a lane, and at a
/// combine the lanes of the originals join the combined plant's lane.
/// Everything here is pure, so the layout is testable without a screen.
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
        /// The plant the task belonged to; differs from the viewed plant for
        /// care done before a combine.
        let source: Plant
        var id: NSManagedObjectID { log.objectID }
    }

    /// Newest first. Logs with the same date are ordered by id, so the order
    /// is the same on every launch and on both phones.
    static func entries(for plant: Plant) -> [Entry] {
        var seen: Set<NSManagedObjectID> = []
        var result: [Entry] = []
        for source in [plant] + Lineage.ancestors(of: plant) {
            for task in source.tasks ?? [] {
                for log in task.logs ?? [] where seen.insert(log.objectID).inserted {
                    result.append(Entry(
                        log: log,
                        title: title(of: task),
                        doneAt: log.doneAt,
                        doneBy: cleaned(log.doneBy),
                        source: source
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

    // MARK: - Threads

    /// One plant's line through the history.
    struct CareThread: Identifiable, Equatable {
        let plant: Plant
        /// 0 is the viewed plant; originals follow, nearest first. Also picks the color.
        let lane: Int
        /// When the thread begins: the day it was combined into existence, or
        /// acquired (or its first log, if that's earlier).
        let start: Date?
        /// When it joined another plant; nil while it carries on.
        let end: Date?
        let mergesInto: Plant?
        var id: NSManagedObjectID { plant.objectID }
    }

    /// The viewed plant first, then every plant it came from.
    static func threads(for plant: Plant) -> [CareThread] {
        let family = [plant] + Lineage.ancestors(of: plant)
        return family.enumerated().map { lane, member in
            let logDates = (member.tasks ?? []).flatMap { $0.logs ?? [] }.compactMap(\.doneAt)
            let began = member.producedBy?.date ?? member.acquiredDate
            return CareThread(
                plant: member,
                lane: lane,
                start: [began, logDates.min()].compactMap { $0 }.min(),
                end: member.consumedBy?.date,
                mergesInto: member.consumedBy.flatMap { event in
                    family.first { ($0.producedBy == event) }
                }
            )
        }
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
            let inputs = (event.inputs ?? []).sorted { ($0.acquiredDate ?? .distantPast) < ($1.acquiredDate ?? .distantPast) }
            return Merge(output: member, inputs: inputs, date: event.date, kind: event.kindValue)
        }
    }

    // MARK: - Rows

    /// What a lane looks like in one row of the list.
    struct LaneMark: Equatable {
        /// A line comes in from the row above.
        var lineAbove = false
        /// A line carries on to the row below.
        var lineBelow = false
        /// A log's dot, or the merge node on the combined plant's lane.
        var dot = false
        /// On the combined plant's lane: the node itself.
        var isMergeNode = false
        /// On an original's lane in its merge row: the lane it curves into.
        var joinsLane: Int?

        var isEmpty: Bool { self == LaneMark() }
    }

    enum RowKind: Equatable {
        /// nil is the "Unknown date" group.
        case month(Date?)
        case log(Entry)
        case merge(Merge)
    }

    struct Row: Identifiable, Equatable {
        let id: String
        let kind: RowKind
        /// One per thread, same order as `Timeline.threads`.
        var lanes: [LaneMark]
    }

    struct Timeline: Equatable {
        let threads: [CareThread]
        let rows: [Row]
    }

    /// The whole list, newest first, under month headers, with each lane's
    /// marks worked out so the view only has to draw them.
    static func timeline(for plant: Plant, calendar: Calendar = .current) -> Timeline {
        let threads = threads(for: plant)
        let lane = Dictionary(uniqueKeysWithValues: threads.map { ($0.plant.objectID, $0.lane) })
        let merges = merges(for: plant)

        enum Item { case log(Entry), merge(Merge)
            var date: Date? {
                switch self {
                case .log(let entry): entry.doneAt
                case .merge(let merge): merge.date
                }
            }
        }
        var items: [Item] = entries(for: plant).map(Item.log) + merges.map(Item.merge)
        // Stable: newest first; on a tie, care done comes before the combine.
        items = items.enumerated().sorted { a, b in
            let aDate = a.element.date ?? .distantPast
            let bDate = b.element.date ?? .distantPast
            if aDate != bDate { return aDate > bDate }
            switch (a.element, b.element) {
            case (.log, .merge): return true
            case (.merge, .log): return false
            default: return a.offset < b.offset
            }
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
            case .month: break
            case .log(let entry): if let l = lane[entry.source.objectID] { note(l, at: index) }
            case .merge(let merge):
                if let out = lane[merge.output.objectID] { note(out, at: index) }
                for input in merge.inputs { if let l = lane[input.objectID] { note(l, at: index) } }
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
            case .month: break
            case .log(let entry):
                if let l = lane[entry.source.objectID] { marks[l].dot = true }
            case .merge(let merge):
                guard let out = lane[merge.output.objectID] else { break }
                marks[out].dot = true
                marks[out].isMergeNode = true
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
        return Timeline(threads: threads, rows: rows)
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
        /// The day of the oldest log.
        let since: Date?
        /// Whoever did the most; ties go to the first name alphabetically.
        let mostlyBy: String?

        /// "Watered 23 times since May 2023 · mostly by Sam 💚"
        var headline: String {
            let lead = counts.first { $0.isWatering } ?? counts[0]
            let times = lead.count == 1 ? "1 time" : "\(lead.count) times"
            var text = lead.isWatering ? "Watered \(times)" : "\(lead.title) \(times)"
            if let since { text += " since " + since.formatted(.dateTime.month(.abbreviated).year()) }
            if let mostlyBy { text += " · mostly by \(mostlyBy) 💚" }
            return text
        }

        /// The other kinds, "Mist 4 · Repot 1", or nil when there's only one kind.
        var others: String? {
            let lead = counts.first { $0.isWatering } ?? counts[0]
            let rest = counts.filter { $0.title != lead.title }
            return rest.isEmpty ? nil : rest.map { "\($0.title) \($0.count)" }.joined(separator: " · ")
        }
    }

    /// Nil when there are no logs.
    static func stats(for plant: Plant) -> Stats? {
        let all = entries(for: plant)
        guard !all.isEmpty else { return nil }
        var byKind: [String: (count: Int, watering: Bool)] = [:]
        for entry in all {
            let isWatering = entry.log.task?.isWatering ?? false
            byKind[entry.title] = ((byKind[entry.title]?.count ?? 0) + 1, isWatering)
        }
        let counts = byKind
            .map { KindCount(title: $0.key, count: $0.value.count, isWatering: $0.value.watering) }
            .sorted {
                if $0.count != $1.count { return $0.count > $1.count }
                if $0.isWatering != $1.isWatering { return $0.isWatering }
                return $0.title < $1.title
            }
        var people: [String: Int] = [:]
        for name in all.compactMap(\.doneBy) { people[name, default: 0] += 1 }
        let mostlyBy = people.max { a, b in
            a.value != b.value ? a.value < b.value : a.key > b.key
        }?.key
        return Stats(counts: counts, total: all.count, since: all.compactMap(\.doneAt).min(), mostlyBy: mostlyBy)
    }

    // MARK: - Helpers

    private static func title(of task: CareTask) -> String {
        if task.isWatering { return "Watered" }
        return cleaned(task.name) ?? "Care task"
    }

    private static func cleaned(_ text: String?) -> String? {
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}
