import CoreData
import Foundation

// The parts of the care history the screen needs besides the rows: zooming
// into one plant, when each piece draws in, which saved changes are worth a
// recompute, and the words. All pure, so all tested.

// MARK: - One plant

extension CareHistory.Timeline {
    /// Just `plant`'s own rows (its care, milestones and cuttings, and the
    /// combines it came from or went into), under their month headers. The
    /// other threads keep their lines, so the view can draw them as hairlines.
    func focused(on plant: Plant) -> CareHistory.Timeline {
        guard threads.contains(where: { $0.plant == plant }) else { return self }
        let isRoot = threads.first?.plant == plant
        func keeps(_ row: CareHistory.Row) -> Bool {
            switch row.kind {
            case .month: false
            case .merge(let merge): merge.output == plant || merge.inputs.contains(plant)
            case .joined: isRoot
            case .showEarlier(_, let under): under == plant
            default: row.plant == plant
            }
        }
        var kept: [CareHistory.Row] = []
        var month: CareHistory.Row?
        for row in rows {
            if row.isMonth {
                month = row
            } else if keeps(row) {
                if let header = month {
                    kept.append(header)
                    month = nil
                }
                kept.append(row)
            }
        }
        return CareHistory.Timeline(threads: threads, rows: kept, columnCount: columnCount, hiddenCount: hiddenCount)
    }
}

// MARK: - Draw-in

extension CareHistory {
    /// When each piece of the threads draws in after the screen appears or
    /// the level changes: each thread's line trims top-down (newest first) over
    /// `segment` seconds, eased in and out; a combine's originals start when
    /// the line reaches its node; dots spring in as the line passes; the
    /// words follow on a 30 ms stagger. Only the first `window` rows (about a
    /// screenful) are timed. Rows past it, and rows created later by lazy
    /// loading, show already drawn.
    struct DrawSchedule: Equatable {
        struct Span: Equatable {
            var delay: Double
            var duration: Double
            var end: Double { delay + duration }
        }

        struct RowTiming: Equatable {
            /// By lane: when its piece of line in this row draws.
            var lines: [Int: Span] = [:]
            /// When the dot springs in.
            var dot: Double?
            /// When the row's words (or card) grow in.
            var label: Double = 0
            /// When everything in the row has started; a row first created
            /// after this is drawn without animating.
            var settled: Double { max(lines.values.map(\.end).max() ?? 0, label) }
        }

        let rows: [RowTiming]

        /// Nil means "already drawn".
        func timing(forRow index: Int) -> RowTiming? {
            index >= 0 && index < rows.count ? rows[index] : nil
        }

        static let idle = DrawSchedule(rows: [])
    }

    static let segmentDuration = 0.9
    static let labelStagger = 0.03

    /// Ease-in-out (half a cosine) and its inverse: where the line's front is
    /// at a share of the segment's time, and when it gets to a share of the way.
    static func easeInOut(_ t: Double) -> Double { (1 - cos(.pi * min(max(t, 0), 1))) / 2 }
    static func easeInOutInverse(_ s: Double) -> Double { acos(1 - 2 * min(max(s, 0), 1)) / .pi }

    static func drawSchedule(for timeline: Timeline, window: Int) -> DrawSchedule {
        let count = min(max(window, 0), timeline.rows.count)
        guard count > 0 else { return .idle }
        let rows = timeline.rows
        let laneCount = timeline.threads.count
        var timings = Array(repeating: DrawSchedule.RowTiming(), count: count)

        // Each lane's rows inside the window, top-down.
        var laneRows: [Int: [Int]] = [:]
        for lane in 0..<laneCount {
            let present = (0..<count).filter { lane < rows[$0].lanes.count && !rows[$0].lanes[lane].isEmpty }
            if !present.isEmpty { laneRows[lane] = present }
        }
        // Lanes that begin higher go first, so a combine's node time is known
        // before its originals start from it.
        let order = laneRows.keys.sorted { a, b in
            let aTop = laneRows[a]!.first!, bTop = laneRows[b]!.first!
            return aTop != bTop ? aTop < bTop : a < b
        }
        func nodeTime(lane: Int, row: Int) -> Double? {
            timings[row].lines[lane].map { $0.delay + $0.duration / 2 }
        }
        for lane in order {
            let present = laneRows[lane]!
            let top = present[0]
            var start = 0.0
            if let into = rows[top].lanes[lane].joinsLane, let node = nodeTime(lane: into, row: top) {
                start = node
            }
            let pieces = Double(present.count)
            for (i, row) in present.enumerated() {
                let from = easeInOutInverse(Double(i) / pieces)
                let to = easeInOutInverse(Double(i + 1) / pieces)
                timings[row].lines[lane] = DrawSchedule.Span(
                    delay: start + segmentDuration * from,
                    duration: segmentDuration * (to - from)
                )
            }
        }
        for row in 0..<count {
            if let lane = rows[row].lanes.firstIndex(where: \.dot) {
                timings[row].dot = nodeTime(lane: lane, row: row)
            }
            let reached = timings[row].dot ?? timings[row].lines.values.map(\.delay).min() ?? 0
            timings[row].label = max(reached, labelStagger * Double(row)) + 0.05
        }
        return DrawSchedule(rows: timings)
    }
}

// MARK: - What a change touches

extension CareHistory {
    /// The objects a history was built from. A saved change that touches none
    /// of them (another plant's watering, a project) doesn't recompute or redraw it.
    struct Footprint: Equatable {
        var plants: Set<NSManagedObjectID> = []
        var tasks: Set<NSManagedObjectID> = []
        var logs: Set<NSManagedObjectID> = []
        var milestones: Set<NSManagedObjectID> = []
        var events: Set<NSManagedObjectID> = []

        init(plant: Plant) {
            let family = [plant] + Lineage.ancestors(of: plant)
            for member in family {
                plants.insert(member.objectID)
                for cutting in member.cuttings ?? [] { plants.insert(cutting.objectID) }
                if let parent = member.cuttingOf { plants.insert(parent.objectID) }
                for event in [member.producedBy, member.consumedBy].compactMap({ $0 }) {
                    events.insert(event.objectID)
                    for other in (event.inputs ?? []).union(event.outputs ?? []) { plants.insert(other.objectID) }
                }
                for task in member.tasks ?? [] {
                    tasks.insert(task.objectID)
                    for log in task.logs ?? [] { logs.insert(log.objectID) }
                }
                for milestone in member.milestones ?? [] { milestones.insert(milestone.objectID) }
            }
        }

        func isAffected(by objects: some Sequence<NSManagedObject>) -> Bool {
            objects.contains(where: touches)
        }

        private func touches(_ object: NSManagedObject) -> Bool {
            let id = object.objectID
            if plants.contains(id) || tasks.contains(id) || logs.contains(id)
                || milestones.contains(id) || events.contains(id) { return true }
            func anyPlant(_ set: Set<Plant>?) -> Bool { (set ?? []).contains { plants.contains($0.objectID) } }
            switch object {
            case let log as CareLog:
                guard let task = log.task else { return false }
                return tasks.contains(task.objectID) || anyPlant(task.plants)
            case let task as CareTask:
                return anyPlant(task.plants)
            case let milestone as Milestone:
                return milestone.plant.map { plants.contains($0.objectID) } ?? false
            case let photo as Photo:
                return photo.milestone.map { milestones.contains($0.objectID) } ?? false
            case let plant as Plant:
                return plant.cuttingOf.map { plants.contains($0.objectID) } ?? false
            case let event as LineageEvent:
                return anyPlant(event.inputs) || anyPlant(event.outputs)
            default:
                return false
            }
        }
    }
}

// MARK: - Words

extension CareHistory {
    /// "Fri 14": inside a month group the month is already said.
    static func dayLabel(_ date: Date?, calendar: Calendar = .current, locale: Locale = .current) -> String {
        guard let date else { return "Unknown date" }
        let weekday = date.formatted(Date.FormatStyle(locale: locale, calendar: calendar).weekday(.abbreviated))
        let day = date.formatted(Date.FormatStyle(locale: locale, calendar: calendar).day())
        return "\(weekday) \(day)"
    }

    /// "Friday November 14", with the year when it isn't this year.
    static func spokenDay(_ date: Date?, now: Date = .now, calendar: Calendar = .current, locale: Locale = .current) -> String {
        guard let date else { return "unknown date" }
        let style = Date.FormatStyle(locale: locale, calendar: calendar)
        var text = date.formatted(style.weekday(.wide)) + " " + date.formatted(style.month(.wide).day())
        if calendar.component(.year, from: date) != calendar.component(.year, from: now) {
            text += ", " + date.formatted(style.year())
        }
        return text
    }

    /// "November 2026" for the log; "Nov" (plus the year when it isn't this
    /// year) for the zoomed-out view's left-hand labels.
    static func monthLabel(_ date: Date?, short: Bool = false, now: Date = .now,
                           calendar: Calendar = .current, locale: Locale = .current) -> String {
        guard let date else { return "Unknown date" }
        let style = Date.FormatStyle(locale: locale, calendar: calendar)
        guard short else { return date.formatted(style.month(.wide).year()) }
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
        return sameYear ? date.formatted(style.month(.abbreviated)) : date.formatted(style.month(.abbreviated).year(.twoDigits))
    }

    /// "Rosie", "Rosie & Spike", "Rosie, Spike & Lulu".
    static func names(_ plants: [Plant]) -> String {
        let all = plants.map(\.displayName)
        guard all.count > 1 else { return all.first ?? "" }
        return all.dropLast().joined(separator: ", ") + " & " + all.last!
    }

    /// "Rosie and Spike": VoiceOver says "and" better than "&".
    private static func spoken(_ names: String) -> String {
        names.replacingOccurrences(of: " & ", with: " and ")
    }

    /// What VoiceOver reads for a row, since the threads themselves are hidden
    /// from it: "Watered, Friday November 14, by Alex. Rosie, before the Combine."
    static func spokenLabel(for row: Row, viewedPlant: Plant, now: Date = .now,
                            calendar: Calendar = .current, locale: Locale = .current) -> String {
        func day(_ date: Date?) -> String { spokenDay(date, now: now, calendar: calendar, locale: locale) }
        func before(_ source: Plant, label: String) -> String {
            guard source != viewedPlant else { return "" }
            let word = source.consumedBy?.kindValue == .split ? "split" : "Combine"
            return " \(label), before the \(word)."
        }
        switch row.kind {
        case .month(let date):
            return monthLabel(date, calendar: calendar, locale: locale)
        case .log(let entry):
            let by = entry.doneBy.map { ", by \($0)" } ?? ""
            return "\(entry.title), \(day(entry.doneAt))\(by)." + before(entry.source, label: entry.sourceLabel)
        case .milestone(let mark):
            let by = mark.addedBy.map { ", by \($0)" } ?? ""
            let notes = mark.notes.map { " \($0)" } ?? ""
            return "Milestone, \(mark.title), \(day(mark.date))\(by)." + before(mark.source, label: mark.source.displayName) + notes
        case .merge(let merge):
            if merge.kind == .split {
                return "\(spoken(names(merge.outputs.isEmpty ? [merge.output] : merge.outputs))) split from \(names(merge.inputs)), \(day(merge.date))."
            }
            return "Combined into \(merge.output.displayName) from \(spoken(names(merge.inputs))), \(day(merge.date))."
        case .cutting(let mark):
            switch mark.direction {
            case .taken:
                return "Cutting taken, \(mark.cutting.displayName), \(day(mark.date))." + before(mark.source, label: mark.source.displayName)
            case .startedFrom:
                return "Started as a cutting from \(mark.parent.displayName), \(day(mark.date))."
            }
        case .joined(let into, let with, let date, let kind):
            let verb = kind == .split ? "Split into" : "Became part of"
            let others = with.isEmpty ? "" : ", with \(spoken(names(with)))"
            return "\(verb) \(spoken(names(into)))\(others), \(day(date))."
        case .showEarlier(let count, _):
            return count == 1 ? "Show 1 earlier plant" : "Show \(count) earlier plants"
        }
    }
}
