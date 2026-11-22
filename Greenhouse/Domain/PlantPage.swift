import Foundation

/// The plant page's small pieces of logic (birthday, confetti, care teaser,
/// stat counts), kept pure so they're testable without a screen.
enum PlantPage {
    // MARK: - Birthday

    struct Birthday: Equatable {
        /// How many years the household has had it, counting back through combines.
        let years: Int
        /// The day it came home (the earliest acquired date in its family).
        let since: Date
    }

    /// The plant's birthday if it's today. Uses the same rule as the
    /// anniversary notification (`NotificationPlanner.nextAnniversary`): the
    /// earliest acquired date in its family, the first one a year after, and
    /// Feb 29 falling back to Feb 28 in other years.
    static func birthday(of plant: Plant, now: Date = .now, calendar: Calendar = .current) -> Birthday? {
        guard let since = Lineage.effectiveAcquiredDate(of: plant) else { return nil }
        let startOfToday = calendar.startOfDay(for: now)
        // Noon today is "after" the start of today, so an anniversary that
        // falls today is the one returned.
        guard let next = NotificationPlanner.nextAnniversary(of: plant, after: startOfToday, hour: 12, minute: 0, calendar: calendar),
              calendar.isDate(next.date, inSameDayAs: now) else { return nil }
        let years = calendar.component(.year, from: now) - calendar.component(.year, from: since)
        guard years >= 1 else { return nil }
        return Birthday(years: years, since: since)
    }

    /// "Monty turns 2 today"
    static func birthdayTitle(name: String, years: Int) -> String {
        "\(name) turns \(years) today"
    }

    // MARK: - Confetti, once per day per plant

    /// Remembers on this phone which plants already had their birthday
    /// confetti today, so it drifts down once and is just there after that.
    enum ConfettiLedger {
        static let key = "plantPage.birthdayConfetti"

        /// True the first time it's asked for this plant today; it then records
        /// the day, so the next ask (a second visit) says no.
        static func shouldPlay(
            plantID: UUID?,
            now: Date = .now,
            calendar: Calendar = .current,
            defaults: UserDefaults = .standard
        ) -> Bool {
            guard let plantID else { return false }
            let today = dayStamp(now, calendar: calendar)
            var shown = defaults.dictionary(forKey: key) as? [String: String] ?? [:]
            if shown[plantID.uuidString] == today { return false }
            // Only today's entries are worth keeping.
            shown = shown.filter { $0.value == today }
            shown[plantID.uuidString] = today
            defaults.set(shown, forKey: key)
            return true
        }

        static func dayStamp(_ date: Date, calendar: Calendar) -> String {
            let parts = calendar.dateComponents([.year, .month, .day], from: date)
            return "\(parts.year ?? 0)-\(parts.month ?? 0)-\(parts.day ?? 0)"
        }
    }

    // MARK: - Care history teaser

    /// The line under "Care history": "Watered Tue by Alex", "Watered today by
    /// you", or "No care logged yet".
    static func careTeaser(
        latest entry: CareHistory.Entry?,
        viewerName: String,
        now: Date = .now,
        calendar: Calendar = .current,
        locale: Locale = .current
    ) -> String {
        guard let entry else { return "No care logged yet" }
        return careTeaser(
            title: entry.title,
            isWatering: entry.log.task?.isWatering ?? false,
            doneAt: entry.doneAt,
            doneBy: entry.doneBy,
            viewerName: viewerName,
            now: now,
            calendar: calendar,
            locale: locale
        )
    }

    static func careTeaser(
        title: String,
        isWatering: Bool,
        doneAt: Date?,
        doneBy: String?,
        viewerName: String,
        now: Date = .now,
        calendar: Calendar = .current,
        locale: Locale = .current
    ) -> String {
        var text = isWatering ? "Watered" : "\(title) done"
        if let doneAt { text += " " + when(doneAt, now: now, calendar: calendar, locale: locale) }
        if let name = byName(doneBy, viewerName: viewerName) { text += " by \(name)" }
        return text
    }

    /// "today", "yesterday", "Tue" within the last week, then "Nov 14", or
    /// "Nov 14, 2024" in an earlier year.
    static func when(_ date: Date, now: Date, calendar: Calendar, locale: Locale) -> String {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? 0
        if days <= 0 { return "today" }
        if days == 1 { return "yesterday" }
        var style = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
        if days < 7 { return date.formatted(style.weekday(.abbreviated)) }
        style = style.month(.abbreviated).day()
        if calendar.component(.year, from: date) != calendar.component(.year, from: now) {
            style = style.year()
        }
        return date.formatted(style)
    }

    /// "you" when it was this phone's name; nil when nobody's name was set.
    static func byName(_ doneBy: String?, viewerName: String) -> String? {
        let name = doneBy?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !name.isEmpty else { return nil }
        let viewer = viewerName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !viewer.isEmpty, name.caseInsensitiveCompare(viewer) == .orderedSame { return "you" }
        return name
    }

    // MARK: - Stats and photos

    struct Stats: Equatable {
        let waterings: Int
        let milestones: Int
        let photos: Int
    }

    /// The three stat cards: waterings (including the plants it was combined
    /// from), milestones and photos, the same sets the page lists.
    static func stats(for plant: Plant, entries: [CareHistory.Entry]) -> Stats {
        Stats(
            waterings: entries.filter { $0.log.task?.isWatering == true }.count,
            milestones: Milestones.history(for: plant).count,
            photos: Lineage.timeline(for: plant).count
        )
    }

    /// The photo strip: the newest few, newest first.
    static func strip<T>(_ timeline: [T], count: Int = 3) -> [T] {
        Array(timeline.suffix(count).reversed())
    }
}
