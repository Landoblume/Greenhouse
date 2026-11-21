import CoreData
import UserNotifications

struct PlannedNotification: Equatable {
    let id: String
    let date: Date
    let title: String
    let body: String
    /// The plant a tap should open, for photo check-ins. Travels in the
    /// notification's userInfo under `NotificationPlanner.plantIDKey`.
    var plantID: UUID? = nil
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

    /// Months without a photo before a plant's check-in starts; 0 is Off.
    /// Per phone, like the reminder time.
    static let photoCheckInKey = "photoCheckInMonths"
    static let photoCheckInOptions = [0, 2, 3, 6]
    static let defaultPhotoCheckInMonths = 6
    /// Notification ids for check-ins start with this; a tap on one opens the camera.
    static let photoCheckInPrefix = "photo-"
    static let plantIDKey = "plantID"
    static let photoCheckInTitle = "Photo check-in 📸"
    /// The household gets at most one check-in on each of these days
    /// (Calendar weekdays, 1 is Sunday: Tue, Thu, Sat), so about 3 a week.
    static let checkInSlotWeekdays = [3, 5, 7]
    /// How far ahead check-ins are planned. Every launch and sync plans
    /// again, so a quarter ahead is plenty.
    static let checkInWeeksAhead = 12

    static func photoCheckInMonths(in defaults: UserDefaults = .standard) -> Int {
        defaults.object(forKey: photoCheckInKey) as? Int ?? defaultPhotoCheckInMonths
    }

    static func plan(
        household: Household,
        now: Date = .now,
        hour: Int = 9,
        minute: Int = 0,
        photoCheckInMonths: Int = defaultPhotoCheckInMonths,
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

        let reminders = Array(planned.sorted { $0.date < $1.date }.prefix(limit))

        // Check-ins only take the slots reminders and anniversaries leave
        // over, even when they'd fire sooner.
        let free = limit - reminders.count
        guard free > 0, photoCheckInMonths > 0 else { return reminders }
        let checkIns = photoCheckIns(for: (household.plants ?? []).filter(\.isActive), months: photoCheckInMonths,
                                     after: now, hour: hour, minute: minute, calendar: calendar)
        let sortedCheckIns = checkIns.sorted { ($0.date, $0.id) < ($1.date, $1.id) }
        return (reminders + sortedCheckIns.prefix(free)).sorted { $0.date < $1.date }
    }

    /// When a plant was last seen: its newest photo (by takenAt, including
    /// photos inherited from the plants it was combined from) or when it was
    /// acquired (or added), whichever is later. A new plant whose only photo
    /// is an old one from the library counts from when it arrived.
    static func lastSeen(of plant: Plant) -> Date? {
        let newestPhoto = Lineage.timeline(for: plant).compactMap(\.photo.takenAt).max()
        let arrived = plant.acquiredDate ?? plant.createdAt
        return [newestPhoto, arrived].compactMap({ $0 }).max()
    }

    /// When a plant's check-ins start: `months` after it was last seen.
    static func photoCheckInStart(for plant: Plant, months: Int, calendar: Calendar) -> Date? {
        guard let lastSeen = lastSeen(of: plant) else { return nil }
        return calendar.date(byAdding: .month, value: months, to: calendar.startOfDay(for: lastSeen))
            .map(calendar.startOfDay)
    }

    /// The household's check-ins: one on each slot day (`checkInSlotWeekdays`,
    /// so about 3 a week), for the plant that's been waiting longest. A plant
    /// is waiting from its threshold day (see `photoCheckInStart`) and goes
    /// to the back of the line 7 days after the day it got, so a backlog (30
    /// plants with no photo for years, say) is spread over the following
    /// weeks and then comes round again, and a lone plant hears weekly.
    ///
    /// The days are worked out from the thresholds forward, never from today,
    /// and ties go to the plant id, so every reschedule (on either phone)
    /// plans the same notifications; `now` only decides which of them are
    /// still ahead, and how far ahead (`checkInWeeksAhead`).
    static func photoCheckIns(
        for plants: [Plant],
        months: Int,
        after now: Date,
        hour: Int,
        minute: Int,
        calendar: Calendar
    ) -> [PlannedNotification] {
        guard months > 0 else { return [] }
        struct Waiting {
            let plant: Plant
            let key: String
            let lastSeen: Date
            var due: Date
        }
        var waiting: [Waiting] = plants.compactMap { plant in
            guard let seen = lastSeen(of: plant),
                  let due = photoCheckInStart(for: plant, months: months, calendar: calendar) else { return nil }
            return Waiting(plant: plant, key: plant.uuid?.uuidString ?? "", lastSeen: calendar.startOfDay(for: seen), due: due)
        }
        guard var day = waiting.map(\.due).min(),
              let horizon = calendar.date(byAdding: .day, value: checkInWeeksAhead * 7, to: now).map(calendar.startOfDay)
        else { return [] }

        var result: [PlannedNotification] = []
        while day <= horizon {
            let waitingToday = waiting.indices.filter { waiting[$0].due <= day }
            guard !waitingToday.isEmpty else {
                // Nothing waiting: skip ahead to the next day something is.
                guard let next = waiting.map(\.due).min(), next > day else { break }
                day = next
                continue
            }
            if checkInSlotWeekdays.contains(calendar.component(.weekday, from: day)),
               let index = waitingToday.min(by: { (waiting[$0].due, waiting[$0].key) < (waiting[$1].due, waiting[$1].key) }) {
                if let fire = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day), fire > now {
                    let entry = waiting[index]
                    let gap = calendar.dateComponents([.month], from: entry.lastSeen, to: day).month ?? months
                    let week = (calendar.ordinality(of: .day, in: .era, for: day) ?? 0) / 7
                    result.append(PlannedNotification(
                        id: "\(photoCheckInPrefix)\(entry.key)-\(Int(fire.timeIntervalSince1970))",
                        date: fire,
                        title: photoCheckInTitle,
                        body: photoCheckInBody(plantName: entry.plant.displayName, gapMonths: gap,
                                               variant: photoCheckInVariant(key: entry.key, week: week)),
                        plantID: entry.plant.uuid
                    ))
                }
                waiting[index].due = calendar.date(byAdding: .day, value: 7, to: day) ?? day
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return result
    }

    // MARK: Check-in wording

    /// How many phrasings the body rotates through.
    static let photoCheckInPhrasingCount = 4

    /// Which phrasing a plant gets in a given week: the same on every
    /// reschedule and on both phones (so no `hashValue`, which changes per launch).
    static func photoCheckInVariant(key: String, week: Int) -> Int {
        var hash: UInt64 = 14_695_981_039_346_656_037  // FNV-1a
        for byte in key.utf8 {
            hash = (hash ^ UInt64(byte)) &* 1_099_511_628_211
        }
        return Int((hash &+ UInt64(truncatingIfNeeded: week)) % UInt64(photoCheckInPhrasingCount))
    }

    /// "It's been 7 months since Aloe's last close-up. Show off the new growth? 📸"
    static func photoCheckInBody(plantName: String, gapMonths: Int, variant: Int) -> String {
        let gap = gapText(months: gapMonths)
        let possessive = plantName.hasSuffix("s") ? "\(plantName)'" : "\(plantName)'s"
        switch ((variant % photoCheckInPhrasingCount) + photoCheckInPhrasingCount) % photoCheckInPhrasingCount {
        case 0: return "It's been \(gap) since \(possessive) last close-up. Show off the new growth? 📸"
        case 1: return "\(plantName) hasn't had a photo in \(gap). How's it looking? 📸"
        case 2: return "\(gap.prefix(1).uppercased() + gap.dropFirst()) since \(possessive) last portrait. Time for a fresh one? 📸"
        default: return "Say cheese, \(plantName)! The last photo was \(gap) ago. 📸"
        }
    }

    /// "7 months", "a year", "over a year", "over 2 years".
    static func gapText(months: Int) -> String {
        if months < 12 { return months <= 1 ? "a month" : "\(months) months" }
        let years = months / 12
        if months % 12 == 0 { return years == 1 ? "a year" : "\(years) years" }
        return "over " + (years == 1 ? "a year" : "\(years) years")
    }

    /// The plant a tapped check-in should open Add photo for: the plant
    /// itself while it's active, otherwise the active plant it was combined
    /// into (following later combines too). Nil when it's gone, or was split
    /// into several so there's no one plant to pick.
    static func photoCheckInTarget(plantID: UUID, in household: Household) -> Plant? {
        var plant = (household.plants ?? []).first { $0.uuid == plantID }
        var seen: Set<NSManagedObjectID> = []
        while let current = plant, !current.isActive {
            guard seen.insert(current.objectID).inserted,
                  let event = current.consumedBy, event.kindValue == .staple,
                  let outputs = event.outputs, outputs.count == 1 else { return nil }
            plant = outputs.first
        }
        return plant
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
        let checkInMonths = photoCheckInMonths(in: defaults)

        context.perform {
            center.removeAllPendingNotificationRequests()
            guard let household = persistence.currentHousehold(in: context) else { return }
            let calendar = Calendar.current
            for item in plan(household: household, hour: hour, minute: minute,
                             photoCheckInMonths: checkInMonths, calendar: calendar) {
                let content = UNMutableNotificationContent()
                content.title = item.title
                content.body = item.body
                content.sound = .default
                if let plantID = item.plantID {
                    content.userInfo = [plantIDKey: plantID.uuidString]
                }
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

/// Rebuilds notifications when a photo is added, deleted or redated on this
/// phone, so a plant's check-ins stop as soon as it has a newer photo. (The
/// other phone's photos arrive through `RemoteChangeObserver`.)
final class PhotoChangeObserver {
    static let shared = PhotoChangeObserver()
    private var token: NSObjectProtocol?

    func start(persistence: Persistence = .shared) {
        guard token == nil else { return }
        token = NotificationCenter.default.addObserver(
            forName: .NSManagedObjectContextDidSave,
            object: persistence.viewContext,
            queue: .main
        ) { note in
            let keys = [NSInsertedObjectsKey, NSDeletedObjectsKey, NSUpdatedObjectsKey]
            let touchedPhoto = keys.contains { key in
                (note.userInfo?[key] as? Set<NSManagedObject>)?.contains { $0 is Photo } ?? false
            }
            if touchedPhoto { NotificationPlanner.reschedule(persistence: persistence) }
        }
    }
}
