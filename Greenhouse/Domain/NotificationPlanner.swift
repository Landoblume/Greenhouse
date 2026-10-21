import CoreData
import UserNotifications

struct PlannedNotification: Equatable {
    let id: String
    let date: Date
    let title: String
    let body: String
}

/// Turns care tasks and plant anniversaries into local notifications.
///
/// Notifications are scheduled on each phone from the shared data, so the
/// whole set is rebuilt whenever something changes: on launch, when the app
/// comes forward, after a local edit, and when the other phone's changes sync
/// in. That rebuild is what cancels your reminder after your partner already
/// watered.
enum NotificationPlanner {
    /// iOS keeps at most 64 pending notifications per app.
    static let limit = 60

    static let hourKey = "notifyHour"
    static let minuteKey = "notifyMinute"

    static func plan(
        household: Household,
        now: Date = .now,
        hour: Int = 9,
        minute: Int = 0,
        calendar: Calendar = .current
    ) -> [PlannedNotification] {
        func at(_ day: Date) -> Date? {
            calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)
        }
        var planned: [PlannedNotification] = []

        let tasks = (household.tasks ?? []).filter { !$0.isArchived && $0.isRelevant }

        // Watering: one notification per day listing every plant due.
        var wateringByDay: [Date: [String]] = [:]
        for task in tasks where task.isWatering {
            guard let due = CareSchedule.nextDue(for: task, calendar: calendar),
                  let fire = at(due), fire > now else { continue }
            wateringByDay[fire, default: []].append(contentsOf: task.activePlants.map(\.displayName))
        }
        for (fire, names) in wateringByDay {
            planned.append(PlannedNotification(
                id: "water-\(Int(fire.timeIntervalSince1970))",
                date: fire,
                title: "Watering day 💧",
                body: "Time to water \(names.sorted().joined(separator: ", "))"
            ))
        }

        for task in tasks where !task.isWatering {
            guard let due = CareSchedule.nextDue(for: task, calendar: calendar),
                  let fire = at(due), fire > now else { continue }
            planned.append(PlannedNotification(
                id: "task-\(task.uuid?.uuidString ?? "")-\(Int(fire.timeIntervalSince1970))",
                date: fire,
                title: "Plant care 🪴",
                body: taskBody(task)
            ))
        }

        for plant in (household.plants ?? []) where plant.isActive {
            if let anniversary = nextAnniversary(of: plant, after: now, hour: hour, minute: minute, calendar: calendar) {
                planned.append(anniversary)
            }
        }

        return Array(planned.sorted { $0.date < $1.date }.prefix(limit))
    }

    /// "Time for your quarterly hydrogen peroxide treatment: Aloe, Pothos"
    /// A one-time task just says what: "Water the cutting: Cutting"
    static func taskBody(_ task: CareTask) -> String {
        if task.unit == .once {
            let names = task.activePlants.map(\.displayName)
            let what = task.name ?? "Care task"
            return names.isEmpty ? what : "\(what): \(names.joined(separator: ", "))"
        }
        let name = lowercasedFirst(task.name ?? "care task")
        let count = Int(task.intervalCount)
        let what: String
        if let word = CareSchedule.cadenceWord(count: count, unit: task.unit) {
            what = "\(word) \(name)"
        } else {
            what = "\(name) (every \(count) \(task.unit.label(count: count)))"
        }
        let plants = task.activePlants.map(\.displayName)
        return plants.isEmpty ? "Time for your \(what)" : "Time for your \(what): \(plants.joined(separator: ", "))"
    }

    /// Lowercases a leading capital ("Hydrogen" → "hydrogen") but leaves
    /// acronyms alone ("UV lamp" stays).
    private static func lowercasedFirst(_ text: String) -> String {
        guard let first = text.first else { return text }
        let second = text.dropFirst().first
        if second?.isUppercase == true { return text }
        return first.lowercased() + text.dropFirst()
    }

    static func nextAnniversary(
        of plant: Plant,
        after now: Date,
        hour: Int,
        minute: Int,
        calendar: Calendar
    ) -> PlannedNotification? {
        guard let acquired = Lineage.effectiveAcquiredDate(of: plant) else { return nil }
        let start = calendar.dateComponents([.year, .month, .day], from: acquired)
        guard let startYear = start.year, let month = start.month, let day = start.day else { return nil }
        let thisYear = calendar.component(.year, from: now)
        // First anniversary is a year after acquiring; nothing to plan if that's
        // further out than next year (e.g. an acquired date in the future).
        let firstYear = max(thisYear, startYear + 1)
        guard firstYear <= thisYear + 1 else { return nil }

        for year in firstYear...(thisYear + 1) {
            // Feb 29 falls back to Feb 28 in other years.
            var components = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)
            if calendar.date(from: components).map({ calendar.component(.month, from: $0) != month }) ?? true {
                components.day = day - 1
            }
            guard let fire = calendar.date(from: components), fire > now else { continue }
            let years = year - startYear
            var body = "You've had \(plant.displayName) for \(years) year\(years == 1 ? "" : "s") 🎉"
            if let event = plant.producedBy, event.kindValue == .staple, let date = event.date {
                body += " (combined \(Lineage.format(date)))"
            }
            return PlannedNotification(
                id: "anniversary-\(plant.uuid?.uuidString ?? "")-\(year)",
                date: fire,
                title: "Plant anniversary",
                body: body
            )
        }
        return nil
    }

    // MARK: - Scheduling

    static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            if granted { DispatchQueue.main.async { reschedule() } }
        }
    }

    /// Replaces every pending notification with a fresh plan.
    static func reschedule(persistence: Persistence = .shared) {
        let center = UNUserNotificationCenter.current()
        let context = persistence.viewContext
        let defaults = UserDefaults.standard
        let hour = defaults.object(forKey: hourKey) as? Int ?? 9
        let minute = defaults.object(forKey: minuteKey) as? Int ?? 0

        context.perform {
            center.removeAllPendingNotificationRequests()
            guard let household = persistence.currentHousehold(in: context) else { return }
            let calendar = Calendar.current
            for item in plan(household: household, hour: hour, minute: minute, calendar: calendar) {
                let content = UNMutableNotificationContent()
                content.title = item.title
                content.body = item.body
                content.sound = .default
                let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: item.date)
                let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
                center.add(UNNotificationRequest(identifier: item.id, content: content, trigger: trigger))
            }
        }
    }
}

/// Rebuilds notifications when the other phone's changes sync in. Imports can
/// arrive in bursts, so it waits for a quiet second first.
final class RemoteChangeObserver {
    static let shared = RemoteChangeObserver()
    private var pending: DispatchWorkItem?
    private var token: NSObjectProtocol?

    func start(persistence: Persistence = .shared) {
        guard token == nil else { return }
        token = NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange,
            object: persistence.container.persistentStoreCoordinator,
            queue: .main
        ) { [weak self] _ in
            self?.pending?.cancel()
            let work = DispatchWorkItem { NotificationPlanner.reschedule(persistence: persistence) }
            self?.pending = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work)
        }
    }
}
