import Foundation

/// The "On this day" throwback on the Plants tab: a photo taken on today's
/// month and day in an earlier year.
enum OnThisDay {
    /// The throwback to show: the photo's owner and how many years back.
    struct Match<Item> {
        let item: Item
        let yearsAgo: Int
    }

    /// Picks which item to show today, or nil when none was taken on this
    /// month and day in an earlier year. A Feb 29 photo shows on Feb 28 in
    /// years without a leap day (the way plant anniversaries do). With several
    /// matches the oldest wins; ties go to the earlier time of day, then the
    /// smaller `key`, so every launch and both phones pick the same one.
    ///
    /// `isUsable` runs only on items that match the date, so it can do the
    /// expensive check (is the picture really there?) cheaply overall.
    static func pick<Item>(
        from items: [Item],
        today: Date,
        calendar: Calendar = .current,
        takenAt: (Item) -> Date?,
        key: (Item) -> String,
        isUsable: (Item) -> Bool = { _ in true }
    ) -> Match<Item>? {
        let now = calendar.dateComponents([.year, .month, .day], from: today)
        guard let year = now.year, let month = now.month, let day = now.day else { return nil }
        let thisYearHasLeapDay = isLeap(year, calendar: calendar)

        var matches: [(item: Item, yearsAgo: Int, date: Date, key: String)] = []
        for item in items {
            guard let date = takenAt(item) else { continue }
            let parts = calendar.dateComponents([.year, .month, .day], from: date)
            guard let photoYear = parts.year, let photoMonth = parts.month, let photoDay = parts.day,
                  photoYear < year else { continue }
            let sameDay = photoMonth == month && photoDay == day
            let leapFallback = photoMonth == 2 && photoDay == 29 && month == 2 && day == 28 && !thisYearHasLeapDay
            guard sameDay || leapFallback else { continue }
            guard isUsable(item) else { continue }
            matches.append((item, year - photoYear, date, key(item)))
        }
        let best = matches.min { a, b in
            if a.yearsAgo != b.yearsAgo { return a.yearsAgo > b.yearsAgo }
            let aTime = timeOfDay(a.date, calendar: calendar)
            let bTime = timeOfDay(b.date, calendar: calendar)
            if aTime != bTime { return aTime < bTime }
            return a.key < b.key
        }
        return best.map { Match(item: $0.item, yearsAgo: $0.yearsAgo) }
    }

    /// "1 year ago today", "3 years ago today".
    static func headline(yearsAgo: Int) -> String {
        "\(yearsAgo) year\(yearsAgo == 1 ? "" : "s") ago today"
    }

    struct PlantPhoto {
        let plant: Plant
        let photo: Photo
    }

    /// The throwback among these plants' photos (their own and the ones they
    /// inherited through a Combine). Photos still without picture data, like
    /// one that hasn't finished syncing, don't count.
    static func pick(in plants: [Plant], today: Date = .now, calendar: Calendar = .current) -> Match<PlantPhoto>? {
        let candidates = plants.filter(\.isActive).flatMap { plant in
            Lineage.timeline(for: plant).map { PlantPhoto(plant: plant, photo: $0.photo) }
        }
        return pick(
            from: candidates,
            today: today,
            calendar: calendar,
            takenAt: { $0.photo.takenAt },
            key: { ($0.photo.uuid?.uuidString ?? "") + "|" + ($0.plant.uuid?.uuidString ?? "") },
            isUsable: { $0.photo.imageData != nil }
        )
    }

    private static func isLeap(_ year: Int, calendar: Calendar) -> Bool {
        guard let feb1 = calendar.date(from: DateComponents(year: year, month: 2, day: 1)),
              let days = calendar.range(of: .day, in: .month, for: feb1)?.count else { return false }
        return days == 29
    }

    private static func timeOfDay(_ date: Date, calendar: Calendar) -> TimeInterval {
        date.timeIntervalSince(calendar.startOfDay(for: date))
    }
}
