import CoreData

enum DueStatus: Equatable {
    case overdue(days: Int)
    case today
    case upcoming(days: Int)

    var label: String {
        switch self {
        case .overdue(let days): days == 1 ? "Overdue by 1 day" : "Overdue by \(days) days"
        case .today: "Due today"
        case .upcoming(1): "Due tomorrow"
        case .upcoming(let days): "In \(days) days"
        }
    }

    var needsAttention: Bool {
        switch self {
        case .overdue, .today: true
        case .upcoming: false
        }
    }
}

/// Recurring care: when tasks are due, marking them done, and what happens to
/// them when plants are stapled or split.
///
/// Watering is not special-cased in the model. It's a CareTask with
/// `isWatering` set, one per plant, so the same code handles "water every 7
/// days" and "hydrogen peroxide treatment every 3 months".
enum CareSchedule {
    static func addInterval(_ count: Int, _ unit: IntervalUnit, to date: Date, calendar: Calendar = .current) -> Date {
        guard unit != .once else { return date }
        let component: Calendar.Component = switch unit {
        case .day, .once: .day
        case .week: .weekOfYear
        case .month: .month
        }
        return calendar.date(byAdding: component, value: count, to: date) ?? date
    }

    /// A snooze if there is one, otherwise the schedule.
    static func nextDue(for task: CareTask, calendar: Calendar = .current) -> Date? {
        if let snoozed = task.snoozedUntil { return calendar.startOfDay(for: snoozed) }
        return scheduledDue(for: task, calendar: calendar)
    }

    /// Last time done plus the interval; before the first time, `firstDue`.
    /// A one-time task is always due on `firstDue`.
    private static func scheduledDue(for task: CareTask, calendar: Calendar) -> Date? {
        if task.unit != .once {
            if let override = task.dueOverride { return calendar.startOfDay(for: override) }
            if let doneAt = task.lastLog?.doneAt {
                return addInterval(Int(task.intervalCount), task.unit, to: calendar.startOfDay(for: doneAt), calendar: calendar)
            }
        }
        return task.firstDue.map { calendar.startOfDay(for: $0) }
    }

    // MARK: - Snooze

    /// Pushes the reminder out `days` days from its due date, or from today
    /// if it's already overdue.
    static func snooze(_ task: CareTask, days: Int, now: Date = .now, calendar: Calendar = .current) {
        let today = calendar.startOfDay(for: now)
        let base = max(today, nextDue(for: task, calendar: calendar) ?? today)
        task.snoozedUntil = calendar.date(byAdding: .day, value: days, to: base)
    }

    /// The question to ask when a snoozed reminder gets done: stay on the new
    /// timing, or go back to the original one?
    struct SnoozeChoice: Equatable {
        let title: String
        /// Next due if the new timing sticks.
        let keepDue: Date
        /// Next due if it was a one-off.
        let originalDue: Date
    }

    /// Nil when there's nothing to ask: not snoozed, a one-time task, or both
    /// answers land on the same day.
    static func snoozeChoice(for task: CareTask, doneAt: Date = .now, calendar: Calendar = .current) -> SnoozeChoice? {
        guard task.snoozedUntil != nil, task.unit != .once, task.intervalCount > 0,
              var original = scheduledDue(for: task, calendar: calendar) else { return nil }
        let count = Int(task.intervalCount)
        let today = calendar.startOfDay(for: doneAt)
        let keep = addInterval(count, task.unit, to: today, calendar: calendar)
        while original <= today {
            original = addInterval(count, task.unit, to: original, calendar: calendar)
        }
        guard keep != original else { return nil }
        let isWeekly = task.unit == .week || (task.unit == .day && count % 7 == 0)
        let weekday = calendar.weekdaySymbols[calendar.component(.weekday, from: today) - 1]
        return SnoozeChoice(
            title: isWeekly ? "Keep \(weekday)s going forward?" : "Keep this new timing?",
            keepDue: keep,
            originalDue: original
        )
    }

    // MARK: - Undo

    /// Same-day only: an older log is history, not a slip of the thumb. A
    /// finished one-time task has already left the list.
    static func canUndoDone(_ task: CareTask, now: Date = .now, calendar: Calendar = .current) -> Bool {
        guard task.unit != .once, let doneAt = task.lastLog?.doneAt else { return false }
        return calendar.isDate(doneAt, inSameDayAs: now)
    }

    static func undoDone(_ task: CareTask, context: NSManagedObjectContext) {
        guard let log = task.lastLog else { return }
        context.delete(log)
        // Updates `task.logs` now, so the due date is right on the next draw.
        context.processPendingChanges()
        task.dueOverride = nil
    }

    static func status(nextDue: Date, now: Date = .now, calendar: Calendar = .current) -> DueStatus {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: nextDue)).day ?? 0
        if days < 0 { return .overdue(days: -days) }
        if days == 0 { return .today }
        return .upcoming(days: days)
    }

    static func status(of task: CareTask, now: Date = .now, calendar: Calendar = .current) -> DueStatus? {
        nextDue(for: task, calendar: calendar).map { status(nextDue: $0, now: now, calendar: calendar) }
    }

    /// One-word cadence when there is one ("weekly", "quarterly"), else nil.
    static func cadenceWord(count: Int, unit: IntervalUnit) -> String? {
        switch (count, unit) {
        case (_, .once): "one time"
        case (1, .day): "daily"
        case (1, .week): "weekly"
        case (1, .month): "monthly"
        case (3, .month): "quarterly"
        case (12, .month): "yearly"
        default: nil
        }
    }

    /// "quarterly" or "every 5 weeks".
    static func cadence(count: Int, unit: IntervalUnit) -> String {
        cadenceWord(count: count, unit: unit) ?? "every \(count) \(unit.label(count: count))"
    }

    static func markDone(
        _ task: CareTask,
        by name: String,
        at date: Date = .now,
        keepNewTiming: Bool = true,
        household: Household,
        context: NSManagedObjectContext,
        persistence: Persistence = .shared
    ) {
        // Read before the log goes in; the log changes the schedule.
        let original = snoozeChoice(for: task, doneAt: date)?.originalDue
        let log = persistence.insert(CareLog.self, alongside: household, in: context)
        log.uuid = UUID()
        log.doneAt = date
        log.doneBy = name
        log.task = task
        task.snoozedUntil = nil
        task.dueOverride = keepNewTiming ? nil : original
        // A one-time task is finished, so it leaves Care and the plant page.
        if task.unit == .once { task.isArchived = true }
    }

    @discardableResult
    static func makeTask(
        name: String,
        count: Int,
        unit: IntervalUnit,
        firstDue: Date,
        isWatering: Bool = false,
        plants: [Plant],
        household: Household,
        context: NSManagedObjectContext,
        persistence: Persistence = .shared
    ) -> CareTask {
        let task = persistence.insert(CareTask.self, alongside: household, in: context)
        task.uuid = UUID()
        task.name = name
        task.intervalCount = Int64(count)
        task.unit = unit
        task.firstDue = firstDue
        task.isWatering = isWatering
        task.createdAt = .now
        task.household = household
        task.mutableSetValue(forKey: "plants").addObjects(from: plants)
        return task
    }

    /// Hands care over when plants are stapled or split.
    ///
    /// - Watering: each new plant gets one watering task on the shortest of the
    ///   old schedules, picking up from the most recent watering. The old
    ///   watering tasks are archived (not deleted) so their logs stay in history.
    /// - Other tasks: the old plants are swapped for the new ones.
    static func transferTasks(
        from oldPlants: [Plant],
        to newPlants: [Plant],
        date: Date,
        household: Household,
        context: NSManagedObjectContext,
        persistence: Persistence = .shared
    ) {
        let oldWatering = oldPlants.compactMap(\.wateringTask)
        let shortest = oldWatering.min { approximateDays($0) < approximateDays($1) }
        let lastWatered = oldWatering.compactMap { $0.lastLog?.doneAt }.max()
        for task in oldWatering { task.isArchived = true }

        let count = shortest.map { Int($0.intervalCount) } ?? 7
        let unit = shortest?.unit ?? .day
        let firstDue = addInterval(count, unit, to: Calendar.current.startOfDay(for: lastWatered ?? date))
        let instructions = shortest?.instructions ?? oldWatering.compactMap(\.instructions).first
        for plant in newPlants {
            let task = makeTask(name: "Water", count: count, unit: unit, firstDue: firstDue, isWatering: true,
                                plants: [plant], household: household, context: context, persistence: persistence)
            task.instructions = instructions
        }

        let others = Set(oldPlants.flatMap(\.activeTasks)).filter { !$0.isWatering }
        for task in others {
            let targets = task.mutableSetValue(forKey: "plants")
            for plant in oldPlants { targets.remove(plant) }
            targets.addObjects(from: newPlants)
        }
    }

    private static func approximateDays(_ task: CareTask) -> Int {
        let perUnit = switch task.unit {
        case .day: 1
        case .week: 7
        case .month: 30
        case .once: 0
        }
        return Int(task.intervalCount) * perUnit
    }
}
