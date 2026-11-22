import CoreData
import SwiftUI

/// Every care task in the household: Overdue, Today, This week, then Later.
struct CareView: View {
    @ObservedObject var household: Household
    @AppStorage(Collections.selectedKey) private var selectedCollection = ""
    @FetchRequest private var tasks: FetchedResults<CareTask>
    @Environment(\.managedObjectContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showingNew = false
    @State private var editing: CareTask?
    /// Lets a plant name under a reminder push that plant onto the stack.
    @State private var path = NavigationPath()
    /// Tasks just marked done stay in their old section for a moment, so the
    /// check, the ripples and the tint play in place before the row moves on.
    @State private var pinned: [NSManagedObjectID: (section: CareSection, due: Date)] = [:]
    /// The latest pin for each task, so an older pin's timer (Done, undo, Done
    /// again within the four seconds) can't end the newer celebration early.
    @State private var pinTokens: [NSManagedObjectID: UUID] = [:]
    /// Where the visible list ends on screen (the top of the floating tab bar),
    /// so rows start to soften above the bar rather than behind it.
    @State private var visibleBottom: CGFloat = .infinity
    /// Bumped at midnight so tasks move into their new sections.
    @State private var clock = Date.now
    /// True for the first second after the tab loads: only then do rows grow in.
    @State private var loading = true

    init(household: Household) {
        self.household = household
        let request = NSFetchRequest<CareTask>(entityName: "CareTask")
        request.predicate = NSPredicate(format: "household == %@ AND isArchived == NO", household)
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
        _tasks = FetchRequest(fetchRequest: request)
    }

    private var relevant: [CareTask] {
        let collection = Collections.find(selectedCollection, in: household)
        return tasks.filter { $0.isRelevant && Collections.contains(collection, $0) }
    }

    var body: some View {
        NavigationStack(path: $path) {
            let all = relevant
            let items = listItems(for: all)
            List {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    row(item, index: index)
                        .listRowInsets(EdgeInsets(top: 5, leading: GH.Space.m, bottom: 5, trailing: GH.Space.m))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            }
            // Inside the tab bar clearance: the List's frame stops at the top of
            // the bar (its rows still scroll on underneath).
            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).maxY } action: {
                visibleBottom = $0
            }
            .listStyle(.plain)
            .ghScreen()
            .ghTabBarClearance()
            .navigationTitle("Care")
            .navigationDestination(for: Plant.self) { PlantDetailView(plant: $0, household: household) }
            .navigationDestination(for: Project.self) { ProjectDetailView(project: $0, household: household) }
            .navigationDestination(for: CareHistoryRoute.self) { CareHistoryView(plant: $0.plant) }
            .toolbar {
                Button { showingNew = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Add care reminder")
            }
            .sheet(isPresented: $showingNew) { TaskEditorView(household: household, task: nil, preselected: []) }
            .sheet(item: $editing) { TaskEditorView(household: household, task: $0, preselected: []) }
            .redrawsOnCollectionChanges(household)
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
                clock = .now
            }
            .task {
                #if DEBUG
                CareDemo.applyIfRequested(household: household, context: context)
                CareDemo.applyAppearanceIfRequested()
                #endif
                try? await Task.sleep(for: .seconds(1))
                loading = false
            }
        }
    }

    // MARK: Rows

    private enum Item: Identifiable {
        case summary(String)
        case filters
        case header(CareSection)
        case task(CareTask)
        case caughtUp(hasTasks: Bool)
        case nextUp(CareTask)

        var id: String {
            switch self {
            case .summary: "summary"
            case .filters: "filters"
            case .header(let section): "header-\(section.rawValue)"
            case .task(let task): "task-\(task.objectID.uriRepresentation().absoluteString)"
            case .caughtUp: "caught-up"
            case .nextUp: "next-up"
            }
        }
    }

    private func listItems(for all: [CareTask]) -> [Item] {
        let groups = CareAgenda.group(all, now: max(clock, .now), overrides: pinned)
        func count(_ section: CareSection) -> Int { groups.first { $0.section == section }?.tasks.count ?? 0 }
        var items: [Item] = [.filters]
        if let summary = CareAgenda.summary(overdue: count(.overdue), today: count(.today)) {
            items.append(.summary(summary))
        }
        if count(.overdue) + count(.today) == 0 {
            items.append(.caughtUp(hasTasks: !all.isEmpty))
            if let next = CareAgenda.nextUp(in: all) { items.append(.nextUp(next)) }
        }
        for group in groups {
            items.append(.header(group.section))
            items += group.tasks.map { .task($0) }
        }
        return items
    }

    @ViewBuilder private func row(_ item: Item, index: Int) -> some View {
        switch item {
        case .filters:
            CollectionBar(household: household)
                .listRowInsets(EdgeInsets())
        case .summary(let text):
            Text(text)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(GH.Palette.ink2)
                .padding(.horizontal, GH.Space.xxs)
                .careEnter(index: index, active: loading)
        case .header(let section):
            Text(section.title)
                .font(.ghEyebrow)
                .textCase(.uppercase)
                .tracking(0.7)
                .foregroundStyle(section == .overdue ? GH.Palette.terraInk : GH.Palette.ink2)
                .padding(.horizontal, GH.Space.xxs)
                .padding(.top, GH.Space.xs)
                .accessibilityAddTraits(.isHeader)
                .careEnter(index: index, active: loading)
        case .task(let task):
            TaskRow(task: task, household: household, onEdit: edit(task), onOpenPlant: openPlant, layout: .card, onDone: pin)
                .careEnter(index: index, active: loading)
                .careSoftening(visibleBottom: visibleBottom)
        case .caughtUp(let hasTasks):
            caughtUp(hasTasks: hasTasks)
        case .nextUp(let task):
            CareNextUpCard(task: task, onOpen: edit(task))
                .careEnter(index: index, active: loading)
        }
    }

    private func caughtUp(hasTasks: Bool) -> some View {
        VStack(spacing: GH.Space.s) {
            CareEmptyArt(name: "EmptyWateringCan")
            Text(hasTasks ? "All caught up" : "Nothing scheduled")
                .font(.ghRounded(.title2))
                .foregroundStyle(GH.Palette.ink)
            Text(hasTasks
                 ? "Nothing needs water or care today."
                 : "Plants get a watering schedule when you add them. Tap + for other reminders, like a quarterly treatment.")
                .font(.subheadline)
                .foregroundStyle(GH.Palette.ink2)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, GH.Space.m)
        .accessibilityElement(children: .combine)
    }

    // MARK: Actions

    private func openPlant(_ plant: Plant) { path.append(plant) }

    private func edit(_ task: CareTask) -> () -> Void {
        { editing = task }
    }

    /// Keeps a just-finished row where it is while it celebrates.
    private func pin(_ task: CareTask) {
        guard let due = CareSchedule.nextDue(for: task) else { return }
        let status = CareSchedule.status(nextDue: due)
        let id = task.objectID
        let token = UUID()
        // A row pinned again (done, undone, done) keeps its first place.
        if pinned[id] == nil { pinned[id] = (CareAgenda.section(for: status), due) }
        pinTokens[id] = token
        Task { @MainActor in
            try? await Task.sleep(for: TaskRow.celebration)
            guard pinTokens[id] == token else { return }
            pinTokens[id] = nil
            withAnimation(reduceMotion ? GH.Motion.reduced : GH.Motion.enter) { pinned[id] = nil }
        }
    }
}

/// Rows grow in (GH.Motion.enter, staggered over the first six) only while the
/// tab is first loading; rows made later by scrolling just appear.
private struct CareEnter: ViewModifier {
    let delay: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown: Bool

    init(index: Int, active: Bool) {
        delay = Double(min(index, 5)) * GH.Motion.staggerStep
        _shown = State(initialValue: !active)
    }

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .scaleEffect(shown || reduceMotion ? 1 : 0.96)
            .offset(y: shown || reduceMotion ? 0 : 12)
            .onAppear {
                guard !shown else { return }
                withAnimation((reduceMotion ? GH.Motion.reduced : GH.Motion.enter).delay(delay)) { shown = true }
            }
    }
}

private extension View {
    func careEnter(index: Int, active: Bool) -> some View {
        modifier(CareEnter(index: index, active: active))
    }
}

/// Create or edit a reminder: a name, an interval (or just once), and the
/// plants it covers (none means the whole household).
struct TaskEditorView: View {
    let household: Household
    let task: CareTask?
    let preselected: [Plant]
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    @FetchRequest private var plants: FetchedResults<Plant>

    @State private var name = ""
    @State private var count = 1
    @State private var unit: IntervalUnit = .month
    @State private var firstDue = Date()
    @State private var instructions = ""
    @State private var selected: Set<NSManagedObjectID> = []
    @State private var confirmingDelete = false
    @FocusState private var nameFocused: Bool

    /// Common ones, so the usual cases are two taps.
    private static let presets: [(String, Int, IntervalUnit)] = [
        ("Hydrogen peroxide treatment", 3, .month),
        ("Fertilize", 1, .month),
        ("Rotate pot", 1, .week),
        ("Check for pests", 2, .week),
        ("Clean grow lights", 1, .month),
    ]

    init(household: Household, task: CareTask?, preselected: [Plant]) {
        self.household = household
        self.task = task
        self.preselected = preselected
        let request = NSFetchRequest<Plant>(entityName: "Plant")
        request.predicate = NSPredicate(format: "household == %@ AND status == %@", household, PlantStatus.active.rawValue)
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
        _plants = FetchRequest(fetchRequest: request)
    }

    private var isWatering: Bool { task?.isWatering == true }

    var body: some View {
        NavigationStack {
            Form {
                if !isWatering {
                    Section {
                        TextField("What (e.g. Hydrogen peroxide treatment)", text: $name)
                            .focused($nameFocused)
                        if task == nil {
                            Menu("Suggestions") {
                                ForEach(Self.presets, id: \.0) { preset in
                                    Button("\(preset.0) · \(CareSchedule.cadence(count: preset.1, unit: preset.2))") {
                                        name = preset.0
                                        count = preset.1
                                        unit = preset.2
                                    }
                                }
                            }
                        }
                    }
                    .listRowBackground(GH.Palette.surface)
                }
                Section {
                    if unit != .once {
                        Stepper("Every \(count)", value: $count, in: 1...365)
                    }
                    Picker("Unit", selection: $unit) {
                        // Watering always repeats.
                        ForEach(IntervalUnit.allCases.filter { !isWatering || $0 != .once }) {
                            Text($0.label(count: count).capitalizedFirst).tag($0)
                        }
                    }
                    .pickerStyle(.segmented)
                    if task == nil || unit == .once {
                        DatePicker(unit == .once ? "Due" : "First due", selection: $firstDue, displayedComponents: .date)
                        .tint(GH.Palette.leafDeep)
                    }
                } header: {
                    Text("Repeats")
                } footer: {
                    Text(CareSchedule.cadence(count: count, unit: unit).capitalizedFirst)
                }
                .listRowBackground(GH.Palette.surface)
                Section("Instructions") {
                    TextField("How to do it (e.g. bottom-water, let it drain)", text: $instructions, axis: .vertical)
                        .lineLimit(2...)
                }
                .listRowBackground(GH.Palette.surface)
                if !isWatering {
                    Section {
                        ForEach(plants) { plant in
                            Button {
                                if selected.contains(plant.objectID) { selected.remove(plant.objectID) } else { selected.insert(plant.objectID) }
                            } label: {
                                HStack {
                                    Text(plant.displayName).foregroundStyle(GH.Palette.ink)
                                    Spacer()
                                    if selected.contains(plant.objectID) {
                                        Image(systemName: "checkmark").foregroundStyle(GH.Palette.leaf)
                                    }
                                }
                            }
                        }
                    } header: {
                        Text("For")
                    } footer: {
                        Text(selected.isEmpty ? "No plants picked: it's a household-wide reminder." : "\(selected.count) plant\(selected.count == 1 ? "" : "s")")
                    }
                    .listRowBackground(GH.Palette.surface)
                }
                if let task, !isWatering {
                    Section {
                        Button("Delete reminder", role: .destructive) { confirmingDelete = true }
                    }
                    .listRowBackground(GH.Palette.surface)
                    .confirmationDialog("Delete \(task.name ?? "this reminder")?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                        Button("Delete", role: .destructive) {
                            context.delete(task)
                            Persistence.shared.save(context)
                            NotificationPlanner.reschedule()
                            dismiss()
                        }
                    }
                }
            }
            .ghScreen()
            .navigationTitle(task == nil ? "New reminder" : (isWatering ? "Watering" : "Edit reminder"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(!isWatering && name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        if let task {
            name = task.name ?? ""
            count = Int(task.intervalCount)
            unit = task.unit
            firstDue = task.firstDue ?? Date()
            instructions = task.instructions ?? ""
            selected = Set((task.plants ?? []).map(\.objectID))
        } else {
            selected = Set(preselected.map(\.objectID))
            // A new reminder starts with its name, so open the keyboard there.
            nameFocused = true
        }
    }

    private func save() {
        let chosen = plants.filter { selected.contains($0.objectID) }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if let task {
            if !isWatering {
                task.name = trimmed
                let targets = task.mutableSetValue(forKey: "plants")
                targets.removeAllObjects()
                targets.addObjects(from: chosen)
            }
            // A new schedule replaces a date left over from a one-off snooze.
            if Int(task.intervalCount) != count || task.unit != unit { task.dueOverride = nil }
            task.intervalCount = Int64(count)
            task.unit = unit
            task.instructions = PlantFactory.cleanNotes(instructions)
            if unit == .once {
                task.firstDue = firstDue
                // The date just picked is the date, even if it was snoozed.
                task.snoozedUntil = nil
            }
        } else {
            let task = CareSchedule.makeTask(name: trimmed, count: count, unit: unit, firstDue: firstDue,
                                             plants: chosen, household: household, context: context)
            task.instructions = PlantFactory.cleanNotes(instructions)
        }
        Persistence.shared.save(context)
        NotificationPlanner.reschedule()
        dismiss()
    }
}
