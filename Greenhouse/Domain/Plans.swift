import CoreData

/// Where a project is: just an idea, underway, or finished.
enum ProjectState: CaseIterable, Identifiable {
    case planned, inProgress, done

    var id: Self { self }

    var label: String {
        switch self {
        case .planned: "Planned"
        case .inProgress: "In progress"
        case .done: "Done"
        }
    }
}

/// The Plans tab: plants you want, and projects for the plants you have.
enum Plans {
    @discardableResult
    static func addWish(
        species: Species?,
        scientificName: String,
        notes: String?,
        by name: String,
        collection: PlantCollection?,
        household: Household,
        context: NSManagedObjectContext,
        persistence: Persistence = .shared
    ) -> WishlistItem {
        let item = persistence.insert(WishlistItem.self, alongside: household, in: context)
        item.uuid = UUID()
        item.createdAt = .now
        item.scientificName = species?.latin ?? scientificName.trimmingCharacters(in: .whitespaces)
        item.commonName = species?.primaryCommonName
        item.catalogID = species?.id
        item.notes = nonEmpty(notes)
        item.addedBy = nonEmpty(name)
        item.household = household
        item.collection = collection
        return item
    }

    /// A wish came true: the new plant joins the wish's collection and the
    /// wish comes off the list.
    static func fulfill(_ item: WishlistItem, with plant: Plant, context: NSManagedObjectContext) {
        if let collection = item.collection {
            plant.mutableSetValue(forKey: "collections").add(collection)
        }
        context.delete(item)
    }

    @discardableResult
    static func addProject(
        title: String,
        notes: String?,
        targetDate: Date?,
        plants: [Plant],
        collection: PlantCollection?,
        household: Household,
        context: NSManagedObjectContext,
        persistence: Persistence = .shared
    ) -> Project {
        let project = persistence.insert(Project.self, alongside: household, in: context)
        project.uuid = UUID()
        project.createdAt = .now
        project.household = household
        project.collection = collection
        update(project, title: title, notes: notes, targetDate: targetDate, plants: plants)
        return project
    }

    static func update(_ project: Project, title: String, notes: String?, targetDate: Date?, plants: [Plant]) {
        project.title = title.trimmingCharacters(in: .whitespaces)
        project.notes = nonEmpty(notes)
        project.targetDate = targetDate
        let set = project.mutableSetValue(forKey: "plants")
        set.removeAllObjects()
        set.addObjects(from: plants)
    }

    static func updateDetails(_ project: Project, budget: Double, place: String?, link: String?) {
        project.budget = max(0, budget)
        project.place = nonEmpty(place)
        project.link = nonEmpty(link)
    }

    // MARK: Steps and supplies

    /// The phone's currency, for costs and budgets.
    static var currencyCode: String { Locale.current.currency?.identifier ?? "USD" }

    @discardableResult
    static func addItem(
        _ kind: ProjectItemKind,
        title: String,
        cost: Double = 0,
        to project: Project,
        household: Household,
        context: NSManagedObjectContext,
        persistence: Persistence = .shared
    ) -> ProjectItem? {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let item = persistence.insert(ProjectItem.self, alongside: household, in: context)
        item.uuid = UUID()
        item.kind = kind.rawValue
        item.title = trimmed
        item.cost = max(0, cost)
        item.createdAt = .now
        item.project = project
        return item
    }

    /// Steps or supplies in the order they were added.
    static func items(_ kind: ProjectItemKind, of project: Project) -> [ProjectItem] {
        (project.items ?? [])
            .filter { $0.kindValue == kind }
            .sorted { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }
    }

    /// e.g. (2, 5) for two of five steps done.
    static func stepProgress(of project: Project) -> (done: Int, total: Int) {
        let steps = items(.step, of: project)
        return (steps.filter(\.isDone).count, steps.count)
    }

    /// What all the supplies add up to.
    static func estimatedCost(of project: Project) -> Double {
        items(.supply, of: project).reduce(0) { $0 + $1.cost }
    }

    /// What the supplies already bought add up to.
    static func spent(on project: Project) -> Double {
        items(.supply, of: project).filter(\.isDone).reduce(0) { $0 + $1.cost }
    }

    static func setDone(_ project: Project, _ done: Bool, at date: Date = .now) {
        project.isDone = done
        project.doneAt = done ? date : nil
    }

    static func state(of project: Project) -> ProjectState {
        if project.isDone { return .done }
        return project.startedAt == nil ? .planned : .inProgress
    }

    /// Moving to a state keeps the dates that still apply: a finished project
    /// remembers when it started, and re-picking In progress keeps the start.
    static func setState(_ project: Project, _ state: ProjectState, at date: Date = .now) {
        switch state {
        case .planned:
            project.startedAt = nil
            setDone(project, false)
        case .inProgress:
            if project.startedAt == nil { project.startedAt = date }
            setDone(project, false)
        case .done:
            if !project.isDone { setDone(project, true, at: date) }
        }
    }

    /// Projects a plant's Edit screen offers: every unfinished one, plus
    /// finished ones it's already in (so unticking still works).
    static func projectChoices(for plant: Plant, in household: Household) -> [Project] {
        sorted((household.projects ?? []).filter { !$0.isDone || ($0.plants ?? []).contains(plant) })
    }

    /// Puts the plant in exactly these projects (the other side of picking a
    /// project's plants).
    static func setProjects(of plant: Plant, to projects: Set<Project>) {
        let set = plant.mutableSetValue(forKey: "projects")
        set.removeAllObjects()
        set.addObjects(from: Array(projects))
    }

    /// Whether the plant is part of a project that's underway, which the
    /// Plants tab marks on its tile.
    static func isInActiveProject(_ plant: Plant) -> Bool {
        (plant.projects ?? []).contains { state(of: $0) == .inProgress }
    }

    /// In-progress projects first, then planned ones (soonest target date,
    /// then oldest), then finished ones, most recently finished first.
    static func sorted(_ projects: [Project]) -> [Project] {
        projects.sorted { a, b in
            if a.isDone != b.isDone { return !a.isDone }
            if a.isDone { return (a.doneAt ?? .distantPast) > (b.doneAt ?? .distantPast) }
            let aStarted = a.startedAt != nil
            let bStarted = b.startedAt != nil
            if aStarted != bStarted { return aStarted }
            let aTarget = a.targetDate ?? .distantFuture
            let bTarget = b.targetDate ?? .distantFuture
            if aTarget != bTarget { return aTarget < bTarget }
            return (a.createdAt ?? .distantPast) < (b.createdAt ?? .distantPast)
        }
    }

    private static func nonEmpty(_ text: String?) -> String? {
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}
