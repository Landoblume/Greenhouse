import CoreData

/// Dated events written into a plant's History by hand.
enum Milestones {
    /// Quick picks on the add screen; any title works.
    static let suggestions = ["New pot", "Repotted", "Fertilized", "Pruned", "First bloom", "New leaf", "Propagated", "Moved spots"]

    struct Item: Identifiable {
        let milestone: Milestone
        /// The plant it was written on; differs from the viewed plant for
        /// milestones from a plant it was combined or split from.
        let source: Plant
        var id: NSManagedObjectID { milestone.objectID }
    }

    /// Which milestone a photo goes with, as picked on the photo screens.
    enum Choice: Hashable {
        case none
        case existing(Milestone)
        /// A new milestone with this title, dated the day the photo was taken.
        case new(title: String)
    }

    /// Links a photo to the picked milestone, creating it first if it's new.
    /// A blank new title links nothing.
    @discardableResult
    static func attach(
        _ photo: Photo,
        to choice: Choice,
        by name: String,
        plant: Plant,
        household: Household,
        context: NSManagedObjectContext,
        persistence: Persistence = .shared
    ) -> Milestone? {
        switch choice {
        case .none:
            photo.milestone = nil
        case .existing(let milestone):
            photo.milestone = milestone
        case .new(let title):
            guard !title.trimmingCharacters(in: .whitespaces).isEmpty else {
                photo.milestone = nil
                return nil
            }
            photo.milestone = add(title: title, date: photo.takenAt ?? .now, notes: nil, by: name, to: plant,
                                  household: household, context: context, persistence: persistence)
        }
        return photo.milestone
    }

    /// A milestone's photos, oldest first.
    static func photos(of milestone: Milestone) -> [Photo] {
        (milestone.photos ?? []).sorted { ($0.takenAt ?? .distantPast) < ($1.takenAt ?? .distantPast) }
    }

    @discardableResult
    static func add(
        title: String,
        date: Date,
        notes: String?,
        by name: String,
        to plant: Plant,
        household: Household,
        context: NSManagedObjectContext,
        persistence: Persistence = .shared
    ) -> Milestone {
        let milestone = persistence.insert(Milestone.self, alongside: household, in: context)
        milestone.uuid = UUID()
        milestone.createdAt = .now
        milestone.addedBy = nonEmpty(name)
        milestone.plant = plant
        update(milestone, title: title, date: date, notes: notes)
        return milestone
    }

    static func update(_ milestone: Milestone, title: String, date: Date, notes: String?) {
        milestone.title = title.trimmingCharacters(in: .whitespaces)
        milestone.date = date
        milestone.notes = nonEmpty(notes)
    }

    /// This plant's milestones plus the ones from plants it came from, oldest
    /// first, like the photo timeline.
    static func history(for plant: Plant) -> [Item] {
        ([plant] + Lineage.ancestors(of: plant))
            .flatMap { source in (source.milestones ?? []).map { Item(milestone: $0, source: source) } }
            .sorted { ($0.milestone.date ?? .distantPast) < ($1.milestone.date ?? .distantPast) }
    }

    private static func nonEmpty(_ text: String?) -> String? {
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}
