import CoreData

/// Staple (combine) and split plants, and read their family tree.
///
/// A plant record is an identity over time. Stapling retires the inputs and
/// creates one new plant; splitting retires the parent and creates several.
/// Photos and logs stay on the plant they were recorded on, and a plant's
/// timeline is its own photos plus its ancestors'.
enum Lineage {
    // MARK: - Changes

    @discardableResult
    static func staple(
        _ plants: [Plant],
        nickname: String?,
        date: Date = .now,
        household: Household,
        context: NSManagedObjectContext,
        persistence: Persistence = .shared
    ) -> Plant {
        precondition(plants.count >= 2, "Stapling needs at least two plants")
        let event = makeEvent(.staple, date: date, household: household, context: context, persistence: persistence)
        let merged = makeChild(of: plants[0], nickname: nickname, date: date, household: household, context: context, persistence: persistence)
        merged.producedBy = event
        for plant in plants {
            plant.statusValue = .stapled
            plant.consumedBy = event
        }
        CareSchedule.transferTasks(from: plants, to: [merged], date: date, household: household, context: context, persistence: persistence)
        Collections.inherit(from: plants, to: [merged])
        return merged
    }

    /// Deletes a plant for everyone in the household, with its photos and the
    /// reminders that were only for it. The hidden originals it was stapled or
    /// split from go too, unless another plant still comes from them (the
    /// other half of a split), so no history is left pointing at nothing.
    static func delete(_ plant: Plant, context: NSManagedObjectContext) {
        var doomed: Set<Plant> = [plant]
        var queue = [plant]
        while let next = queue.popLast() {
            for parent in next.producedBy?.inputs ?? [] where !doomed.contains(parent) {
                let descendants = parent.consumedBy?.outputs ?? []
                if descendants.isSubset(of: doomed) {
                    doomed.insert(parent)
                    queue.append(parent)
                }
            }
        }
        let events = doomed.compactMap(\.producedBy) + doomed.compactMap(\.consumedBy)
        for event in Set(events) where (event.outputs ?? []).isSubset(of: doomed) {
            context.delete(event)
        }
        let tasks = doomed.flatMap { $0.tasks ?? [] }
        for task in Set(tasks) where (task.plants ?? []).isSubset(of: doomed) {
            context.delete(task)
        }
        for doomedPlant in doomed { context.delete(doomedPlant) }
    }

    @discardableResult
    static func split(
        _ parent: Plant,
        names: [String],
        date: Date = .now,
        household: Household,
        context: NSManagedObjectContext,
        persistence: Persistence = .shared
    ) -> [Plant] {
        precondition(names.count >= 2, "Splitting needs at least two new plants")
        let event = makeEvent(.split, date: date, household: household, context: context, persistence: persistence)
        let children = names.map { name in
            let child = makeChild(of: parent, nickname: name, date: date, household: household, context: context, persistence: persistence)
            child.producedBy = event
            return child
        }
        parent.statusValue = .split
        parent.consumedBy = event
        CareSchedule.transferTasks(from: [parent], to: children, date: date, household: household, context: context, persistence: persistence)
        Collections.inherit(from: [parent], to: children)
        return children
    }

    private static func makeEvent(
        _ kind: LineageKind, date: Date, household: Household,
        context: NSManagedObjectContext, persistence: Persistence
    ) -> LineageEvent {
        let event = persistence.insert(LineageEvent.self, alongside: household, in: context)
        event.uuid = UUID()
        event.kind = kind.rawValue
        event.date = date
        event.household = household
        return event
    }

    /// A new plant that inherits species, setting, location and light from `template`.
    private static func makeChild(
        of template: Plant, nickname: String?, date: Date, household: Household,
        context: NSManagedObjectContext, persistence: Persistence
    ) -> Plant {
        let plant = persistence.insert(Plant.self, alongside: household, in: context)
        plant.uuid = UUID()
        plant.createdAt = date
        plant.acquiredDate = date
        plant.scientificName = template.scientificName
        plant.commonName = template.commonName
        plant.catalogID = template.catalogID
        plant.setting = template.setting
        plant.location = template.location
        plant.lightSource = template.lightSource
        let trimmed = nickname?.trimmingCharacters(in: .whitespaces) ?? ""
        plant.nickname = trimmed.isEmpty ? nil : trimmed
        plant.statusValue = .active
        plant.household = household
        return plant
    }

    // MARK: - Reading the tree

    /// The plants that went into this one, oldest first.
    static func parents(of plant: Plant) -> [Plant] {
        sortedByAcquired(plant.producedBy?.inputs ?? [])
    }

    /// Every plant upstream of this one, nearest first, without repeats.
    static func ancestors(of plant: Plant) -> [Plant] {
        var result: [Plant] = []
        var seen: Set<NSManagedObjectID> = [plant.objectID]
        var queue = parents(of: plant)
        while !queue.isEmpty {
            let next = queue.removeFirst()
            guard seen.insert(next.objectID).inserted else { continue }
            result.append(next)
            queue.append(contentsOf: parents(of: next))
        }
        return result
    }

    /// The earliest acquired date in the plant's line: how long you've had it.
    static func effectiveAcquiredDate(of plant: Plant) -> Date? {
        ([plant] + ancestors(of: plant)).compactMap(\.acquiredDate).min()
    }

    struct TimelinePhoto: Identifiable {
        let photo: Photo
        /// The plant the photo was taken of; differs from the viewed plant for
        /// photos inherited from an ancestor.
        let source: Plant
        var id: NSManagedObjectID { photo.objectID }
    }

    /// This plant's photos plus its ancestors', oldest first.
    static func timeline(for plant: Plant) -> [TimelinePhoto] {
        ([plant] + ancestors(of: plant))
            .flatMap { source in (source.photos ?? []).map { TimelinePhoto(photo: $0, source: source) } }
            .sorted { ($0.photo.takenAt ?? .distantPast) < ($1.photo.takenAt ?? .distantPast) }
    }

    /// e.g. "Combined from Aloe vera (acq. Mar 26, 2026) + Aloe vera (acq. Jul 24, 2026) on Oct 17, 2026"
    static func summary(of event: LineageEvent) -> String {
        let date = event.date.map(format) ?? "an unknown date"
        let inputs = sortedByAcquired(event.inputs ?? [])
        switch event.kindValue {
        case .staple:
            let names = inputs.map { "\($0.displayName) (acq. \($0.acquiredDate.map(format) ?? "?"))" }
            return "Combined from \(names.joined(separator: " + ")) on \(date)"
        case .split:
            return "Split from \(inputs.first?.displayName ?? "a plant") on \(date)"
        }
    }

    struct HistoryLine: Identifiable {
        let id = UUID()
        let depth: Int
        let text: String
        /// Set when the line names a plant you can open.
        let plant: Plant?
    }

    /// The plant's story as an indented list: what it became (if retired),
    /// then where it came from, recursively.
    static func history(of plant: Plant) -> [HistoryLine] {
        var lines: [HistoryLine] = []
        if let retired = plant.consumedBy {
            let date = retired.date.map(format) ?? "?"
            let verb = retired.kindValue == .staple ? "Combined" : "Split"
            lines.append(HistoryLine(depth: 0, text: "\(verb) on \(date) into:", plant: nil))
            for output in sortedByAcquired(retired.outputs ?? []) {
                lines.append(HistoryLine(depth: 1, text: output.displayName, plant: output))
            }
        }
        if plant.producedBy == nil {
            let acquired = plant.acquiredDate.map(format) ?? "an unknown date"
            lines.append(HistoryLine(depth: 0, text: "Acquired \(acquired)", plant: nil))
        } else {
            var visited: Set<NSManagedObjectID> = []
            appendOrigin(of: plant, depth: 0, into: &lines, visited: &visited)
        }
        return lines
    }

    private static func appendOrigin(of plant: Plant, depth: Int, into lines: inout [HistoryLine], visited: inout Set<NSManagedObjectID>) {
        guard let event = plant.producedBy, visited.insert(event.objectID).inserted else { return }
        lines.append(HistoryLine(depth: depth, text: summary(of: event), plant: nil))
        for parent in sortedByAcquired(event.inputs ?? []) {
            let acquired = parent.acquiredDate.map(format) ?? "?"
            lines.append(HistoryLine(depth: depth + 1, text: "\(parent.displayName) · acq. \(acquired)", plant: parent))
            appendOrigin(of: parent, depth: depth + 2, into: &lines, visited: &visited)
        }
    }

    private static func sortedByAcquired(_ plants: Set<Plant>) -> [Plant] {
        plants.sorted { ($0.acquiredDate ?? .distantPast) < ($1.acquiredDate ?? .distantPast) }
    }

    static func format(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day().year())
    }
}
