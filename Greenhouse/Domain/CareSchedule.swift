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
        let component: Calendar.Component = switch unit {
        case .day: .day
        case .week: .weekOfYear
        case .month: .month
        }
        return calendar.date(byAdding: component, value: count, to: date) ?? date
    }

    /// Last time done plus the interval; before the first time, `firstDue`.
    static func nextDue(for task: CareTask, calendar: Calendar = .current) -> Date? {
        if let doneAt = task.lastLog?.doneAt {
            return addInterval(Int(task.intervalCount), task.unit, to: calendar.startOfDay(for: doneAt), calendar: calendar)
        }
        return task.firstDue.map { calendar.startOfDay(for: $0) }
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
        household: Household,
        context: NSManagedObjectContext,
        persistence: Persistence = .shared
    ) {
        let log = persistence.insert(CareLog.self, alongside: household, in: context)
        log.uuid = UUID()
        log.doneAt = date
        log.doneBy = name
        log.task = task
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
        for plant in newPlants {
            makeTask(name: "Water", count: count, unit: unit, firstDue: firstDue, isWatering: true,
                     plants: [plant], household: household, context: context, persistence: persistence)
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
        }
        return Int(task.intervalCount) * perUnit
    }
}
