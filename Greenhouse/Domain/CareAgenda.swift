import CoreData
import Foundation

/// Where a task sits on the Care tab.
enum CareSection: Int, CaseIterable, Comparable {
    case overdue, today, thisWeek, later

    var title: String {
        switch self {
        case .overdue: "Overdue"
        case .today: "Today"
        case .thisWeek: "This week"
        case .later: "Later"
        }
    }

    static func < (lhs: CareSection, rhs: CareSection) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// Pure logic behind the Care tab: which section a task belongs in, who
/// usually does it, and the "just done" line.
enum CareAgenda {
    /// Upcoming tasks up to a week out are "This week"; anything further is "Later".
    static func section(for status: DueStatus) -> CareSection {
        switch status {
        case .overdue: .overdue
        case .today: .today
        case .upcoming(let days): days <= 7 ? .thisWeek : .later
        }
    }

    /// Sections in display order, empty ones left out. A task with no due
    /// date at all goes last, under "Later". `overrides` keeps a task where it
    /// was for a moment after it's marked done, so its celebration plays in place.
    static func group(
        _ tasks: [CareTask],
        now: Date = .now,
        calendar: Calendar = .current,
        overrides: [NSManagedObjectID: (section: CareSection, due: Date)] = [:]
    ) -> [(section: CareSection, tasks: [CareTask])] {
        func placement(_ task: CareTask) -> (section: CareSection, due: Date) {
            if let pinned = overrides[task.objectID] { return pinned }
            guard let due = CareSchedule.nextDue(for: task, calendar: calendar) else { return (.later, .distantFuture) }
            return (section(for: CareSchedule.status(nextDue: due, now: now, calendar: calendar)), due)
        }
        let placed = tasks.map { (task: $0, place: placement($0)) }
        return CareSection.allCases.compactMap { section in
            let inSection = placed.filter { $0.place.section == section }.sorted {
                if $0.place.due != $1.place.due { return $0.place.due < $1.place.due }
                return $0.task.title < $1.task.title
            }
            return inSection.isEmpty ? nil : (section, inSection.map(\.task))
        }
    }

    /// The soonest task that isn't due yet.
    static func nextUp(in tasks: [CareTask], now: Date = .now, calendar: Calendar = .current) -> CareTask? {
        tasks.compactMap { task -> (CareTask, Date)? in
            guard let due = CareSchedule.nextDue(for: task, calendar: calendar),
                  !CareSchedule.status(nextDue: due, now: now, calendar: calendar).needsAttention else { return nil }
            return (task, due)
        }
        .min { $0.1 != $1.1 ? $0.1 < $1.1 : $0.0.title < $1.0.title }?.0
    }

    /// The name that most often marked this task done. Ties go to whoever did it
    /// most recently, then alphabetically, so it never flickers between phones.
    static func usualDoer(of task: CareTask) -> String? {
        var counts: [String: (count: Int, latest: Date)] = [:]
        for log in task.logs ?? [] {
            guard let name = log.doneBy?.trimmingCharacters(in: .whitespaces), !name.isEmpty else { continue }
            let when = log.doneAt ?? .distantPast
            let old = counts[name]
            counts[name] = ((old?.count ?? 0) + 1, max(old?.latest ?? .distantPast, when))
        }
        return counts.min {
            if $0.value.count != $1.value.count { return $0.value.count > $1.value.count }
            if $0.value.latest != $1.value.latest { return $0.value.latest > $1.value.latest }
            return $0.key < $1.key
        }?.key
    }

    /// "Just now · Sam · hold to undo", or the time of day once it's been a while.
    static func doneLine(doneAt: Date, by name: String?, now: Date = .now) -> String {
        let when = now.timeIntervalSince(doneAt) < 90 ? "Just now" : doneAt.formatted(date: .omitted, time: .shortened)
        let who = name?.trimmingCharacters(in: .whitespaces) ?? ""
        return [when, who.isEmpty ? nil : who, "hold to undo"].compactMap { $0 }.joined(separator: " · ")
    }

    /// "1 overdue · 3 today", or nil when neither applies.
    static func summary(overdue: Int, today: Int) -> String? {
        let parts = [overdue > 0 ? "\(overdue) overdue" : nil, today > 0 ? "\(today) today" : nil].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
