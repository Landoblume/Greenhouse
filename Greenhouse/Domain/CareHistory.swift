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
        /// The plant whose thread this sits on; differs from the viewed plant
        /// for care done before a combine.
        let source: Plant
        /// Every plant the care was for, oldest first, `source` among them. More
        /// than one when a task that covered several originals moved to the
        /// combined plant: the log shows once, on the oldest.
        let sources: [Plant]
        var id: NSManagedObjectID { log.objectID }

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
        let all = entries(for: plant)
        return family.enumerated().map { lane, member in
            let logDates = all.filter { $0.source == member }.compactMap(\.doneAt)
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
            return Merge(output: member, inputs: sortedByAcquired(event.inputs ?? []), date: event.date, kind: event.kindValue)
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
        /// What the headline leads with: watering if there is any, else the most done.
        let lead: KindCount
        /// The day of the oldest log of the lead kind.
        let since: Date?
        /// Whoever did the most; ties go to the first name alphabetically.
        /// Not necessarily a majority: see `byline(viewerName:)`.
        let mostlyBy: String?
        /// How many of all the logs `mostlyBy` did.
        let mostlyByCount: Int

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
            mostlyByCount: top?.value ?? 0
        )
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
