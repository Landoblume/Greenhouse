#if DEBUG
import CoreData
import Foundation
import UIKit

/// Reshapes the demo household's reminders so every Care tab state can be seen
/// in the simulator. Debug builds only, run once per store:
///
///     xcrun simctl launch booted com.landenblume.greenhouse -demoData YES -openTab 1 -careDemo mixed
///
/// `mixed`: one overdue, one due today (already done by "Alex" a moment ago on
/// request with `-careDemoDone YES`), some this week, one later, plus a
/// household-wide task. `clear`: nothing due, so "All caught up" shows.
enum CareDemo {
    /// `-careDemoDark YES` forces dark mode on every window (the simulator's own
    /// appearance switch doesn't reach the app from the command line).
    static func applyAppearanceIfRequested() {
        guard UserDefaults.standard.bool(forKey: "careDemoDark") else { return }
        for scene in UIApplication.shared.connectedScenes {
            for window in (scene as? UIWindowScene)?.windows ?? [] { window.overrideUserInterfaceStyle = .dark }
        }
    }

    static func applyIfRequested(household: Household, context: NSManagedObjectContext) {
        let defaults = UserDefaults.standard
        guard let mode = defaults.string(forKey: "careDemo"), !defaults.bool(forKey: "careDemoApplied-\(mode)") else { return }
        defaults.set(true, forKey: "careDemoApplied-\(mode)")
        let calendar = Calendar.current
        func ago(_ days: Int) -> Date { calendar.date(byAdding: .day, value: -days, to: .now) ?? .now }
        func log(_ task: CareTask, _ name: String, daysAgo: Int) {
            CareSchedule.markDone(task, by: name, at: ago(daysAgo), household: household, context: context)
        }
        let watering = (household.plants ?? []).filter(\.isActive).compactMap(\.wateringTask).sorted { $0.title < $1.title }
        // Every watering task is weekly, so "done N days ago" is due 7 - N days from now.
        let offsets = mode == "clear" ? [2, 3, 5] : [-2, 0, 3]
        for (index, task) in watering.enumerated() {
            let due = offsets[index % offsets.count]
            for entry in task.logs ?? [] { context.delete(entry) }
            task.snoozedUntil = nil
            task.dueOverride = nil
            log(task, "Sam", daysAgo: 7 - due + 7)
            log(task, index % 2 == 0 ? "Sam" : "Alex", daysAgo: 7 - due)
        }
        if mode != "clear" {
            let plants = (household.plants ?? []).filter(\.isActive).sorted { $0.displayName < $1.displayName }
            CareSchedule.makeTask(name: "Clean grow lights", count: 1, unit: .month, firstDue: calendar.date(byAdding: .day, value: 2, to: .now) ?? .now,
                                  plants: [], household: household, context: context)
            CareSchedule.makeTask(name: "Fertilize", count: 1, unit: .month, firstDue: .now,
                                  plants: Array(plants.prefix(2)), household: household, context: context)
            CareSchedule.makeTask(name: "Rotate pot", count: 1, unit: .week, firstDue: calendar.date(byAdding: .day, value: 12, to: .now) ?? .now,
                                  plants: Array(plants.suffix(1)), household: household, context: context)
            if defaults.bool(forKey: "careDemoDone"), let today = watering.dropFirst().first {
                CareSchedule.markDone(today, by: "Alex", at: .now, household: household, context: context)
            }
        } else {
            let first = calendar.date(byAdding: .day, value: 4, to: .now) ?? .now
            CareSchedule.makeTask(name: "Clean grow lights", count: 1, unit: .month, firstDue: first, plants: [],
                                  household: household, context: context)
        }
        Persistence.shared.save(context)
    }
}
#endif
