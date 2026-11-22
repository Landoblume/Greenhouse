import CoreData
import SwiftUI

/// A plant's page: a 380-pt hero photo that scrolls away under a compact
/// bar, then a sheet with its name, chips, stats and foldable sections.
struct PlantDetailView: View {
    @ObservedObject var plant: Plant
    let household: Household
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKey.myName) private var myName = ""
    @State private var showingAddPhoto = false
    @State private var showingCombine = false
    @State private var showingCutting = false
    @State private var showingEdit = false
    @State private var showingNewTask = false
    @State private var editingTask: CareTask?
    @State private var addingMilestone = false
    @State private var editingMilestone: Milestone?
    @State private var scroll = PlantHeroScroll()
    @State private var photoFrames = PhotoFrameStore()
    @State private var viewerPhotoID: NSManagedObjectID?
    @State private var showingViewer = false

    /// The hero is "collapsed" once it's scrolled under the bar, which is
    /// about this far from the top.
    private static let collapseDistance = GH.PlantPage.heroHeight - 110

    var body: some View {
        let timeline = Lineage.timeline(for: plant)
        let entries = CareHistory.entries(for: plant)
        ScrollView {
            VStack(spacing: 0) {
                PlantHero(photo: PlantPhotos.cover(for: plant), scroll: scroll, collapseDistance: Self.collapseDistance)
                sheet(timeline: timeline, entries: entries)
            }
        }
        .ghTabBarClearance()
        .background(GH.Palette.paper.ignoresSafeArea())
        .ignoresSafeArea(.container, edges: .top)
        .overlay(alignment: .top) {
            PlantPageBar(title: plant.displayName, scroll: scroll, onBack: { dismiss() }, onShare: {
                // Wave 3 opens the then-vs-now share card from here.
            }, showsMenu: plant.isActive) {
                moreMenu
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .background(InteractivePopEnabler().frame(width: 0, height: 0).accessibilityHidden(true))
        .sheet(isPresented: $showingAddPhoto) { AddPhotoSheet(plant: plant, household: household) }
        .sheet(isPresented: $showingCombine) { CombineSheet(plant: plant, household: household) }
        .sheet(isPresented: $showingCutting) { CuttingSheet(plant: plant, household: household) }
        .sheet(isPresented: $addingMilestone) { MilestoneEditorView(plant: plant, household: household, milestone: nil) }
        .sheet(item: $editingMilestone) { MilestoneEditorView(plant: plant, household: household, milestone: $0) }
        .sheet(isPresented: $showingEdit) { EditPlantView(plant: plant) }
        .sheet(isPresented: $showingNewTask) { TaskEditorView(household: household, task: nil, preselected: [plant]) }
        .sheet(item: $editingTask) { TaskEditorView(household: household, task: $0, preselected: []) }
        .fullScreenCover(isPresented: $showingViewer) {
            PhotoViewer(plant: plant, frames: photoFrames, current: $viewerPhotoID, onClose: closeViewer)
                .presentationBackground(.clear)
        }
        .redrawsOnRelatedChanges(plant, includingCare: true)
    }

    // MARK: Sheet

    /// The content that rides up over the hero with 34-pt top corners. Its
    /// parts grow in one after another.
    private func sheet(timeline: [Lineage.TimelinePhoto], entries: [CareHistory.Entry]) -> some View {
        let birthday = PlantPage.birthday(of: plant)
        let first = birthday == nil ? 0 : 1
        return VStack(alignment: .leading, spacing: GH.Space.m) {
            if let birthday {
                BirthdayBanner(name: plant.displayName, plantID: plant.uuid, birthday: birthday)
                    .growIn(index: 0, baseDelay: 0.25)
            }
            titleBlock
                .growIn(index: first, baseDelay: 0.25)
            PlantStatCards(stats: PlantPage.stats(for: plant, entries: entries))
                .growIn(index: first + 1, baseDelay: 0.25)
            if !plant.isActive {
                retiredNote
                    .growIn(index: first + 2, baseDelay: 0.25)
            }
            Group {
                if plant.isActive { careSection }
                CareHistoryLinkRow(plant: plant, teaser: PlantPage.careTeaser(latest: entries.first, viewerName: myName))
            }
            .growIn(index: first + 2, baseDelay: 0.25)
            photosSection(timeline)
                .growIn(index: first + 3, baseDelay: 0.25)
            Group {
                milestonesSection
                projectsSection
                PlantNotesSection(plant: plant)
                ZoneSection(plant: plant, household: household)
                if plant.isActive { actionsCard }
            }
            .growIn(index: first + 4, baseDelay: 0.25)
        }
        .padding(.horizontal, GH.Space.screen)
        .padding(.top, 22)
        .padding(.bottom, GH.Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GH.Palette.paper, in: UnevenRoundedRectangle(
            topLeadingRadius: GH.Radius.sheet, topTrailingRadius: GH.Radius.sheet, style: .continuous))
        .padding(.top, -GH.PlantPage.sheetOverlap)
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(plant.displayName)
                .font(.ghRounded(.largeTitle))
                .foregroundStyle(GH.Palette.ink)
                .accessibilityAddTraits(.isHeader)
            if let latin = plant.scientificName, latin != plant.displayName {
                Text(latin)
                    .italic()
                    .foregroundStyle(GH.Palette.ink2)
            }
            if let since = Lineage.effectiveAcquiredDate(of: plant) {
                Text("Had since \(Lineage.format(since)) · \(Self.age(since: since))")
                    .font(.subheadline)
                    .foregroundStyle(GH.Palette.ink2)
            }
            ChipFlow {
                if let location = plant.location {
                    PlantChip(text: location, systemImage: "mappin.and.ellipse")
                        .accessibilityLabel("Where: \(location)")
                }
                lightChip
                PlantChip(text: plant.settingValue.label, systemImage: Self.settingIcon(plant.settingValue))
                    .accessibilityLabel("Lives: \(plant.settingValue.label)")
                ForEach((plant.collections ?? []).map(\.path).sorted(), id: \.self) { path in
                    PlantChip(text: path, systemImage: "square.stack")
                        .accessibilityLabel("Collection: \(path)")
                }
            }
            .padding(.top, GH.Space.xxs)
            if let species = plant.species {
                Text("Likes: \(species.light.lowercased())")
                    .font(.footnote)
                    .foregroundStyle(GH.Palette.ink2)
            }
        }
    }

    /// Opens the light meter for an active plant.
    @ViewBuilder
    private var lightChip: some View {
        let label = plant.lightSourceValue?.label ?? "Light not set"
        if plant.isActive {
            NavigationLink {
                LightMeterView(plant: plant)
            } label: {
                PlantChip(text: label, systemImage: "sun.max", showsChevron: true)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Light: \(label)")
            .accessibilityHint("Measure the light here")
        } else {
            PlantChip(text: label, systemImage: "sun.max")
                .accessibilityLabel("Light: \(label)")
        }
    }

    private var retiredNote: some View {
        Label("This plant is retired: it was \(plant.statusValue == .stapled ? "combined into another" : "split into new plants"). See Milestones & family below.",
              systemImage: "archivebox")
            .font(.callout)
            .foregroundStyle(GH.Palette.ink)
            .padding(GH.Space.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .ghCard()
    }

    // MARK: Sections

    private var careSection: some View {
        let tasks = plant.activeTasks
        return CollapsibleSection("Care", summary: "\(tasks.count)") {
            ForEach(Array(tasks.enumerated()), id: \.element.objectID) { index, task in
                if index > 0 { CardDivider() }
                TaskRow(task: task, household: household) { editingTask = task }
            }
            CardActionButton(title: "Add a care reminder", systemImage: "plus") { showingNewTask = true }
        }
    }

    @ViewBuilder
    private func photosSection(_ timeline: [Lineage.TimelinePhoto]) -> some View {
        CollapsibleSection("Photos", summary: "\(timeline.count)") {
            if timeline.isEmpty {
                PlantPhotosEmptyState(name: plant.displayName,
                                      onTakePhoto: plant.isActive ? { showingAddPhoto = true } : nil)
            } else {
                PlantPhotoStrip(items: PlantPage.strip(timeline), total: timeline.count,
                                hiddenID: showingViewer ? viewerPhotoID : nil, frames: photoFrames,
                                onOpen: openViewer)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: GH.Space.l) { photoActions(timeline) }
                    VStack(alignment: .leading, spacing: 0) { photoActions(timeline) }
                }
            }
        }
    }

    @ViewBuilder
    private func photoActions(_ timeline: [Lineage.TimelinePhoto]) -> some View {
        if plant.isActive {
            CardActionButton(title: "Add photo", systemImage: "camera") { showingAddPhoto = true }
        }
        if timeline.count >= 2 {
            NavigationLink {
                ThenNowView(plant: plant)
            } label: {
                CardActionLabel(title: "Then vs now", systemImage: "rectangle.split.2x1")
            }
            .buttonStyle(.plain)
        }
    }

    private var milestonesSection: some View {
        let milestones = Milestones.history(for: plant)
        let lineage = Lineage.history(of: plant)
        // Stored under its old name so it stays folded or open as before.
        return CollapsibleSection("Milestones & family", summary: milestones.isEmpty ? nil : "\(milestones.count)", storageKey: "History") {
            ForEach(milestones) { item in
                Button { editingMilestone = item.milestone } label: {
                    MilestoneRow(item: item, viewedPlant: plant)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button { editingMilestone = item.milestone } label: { Label("Edit", systemImage: "pencil") }
                    Button(role: .destructive) { delete(item.milestone) } label: { Label("Delete", systemImage: "trash") }
                }
                .accessibilityAction(named: "Delete") { delete(item.milestone) }
            }
            if plant.isActive {
                CardActionButton(title: "Add milestone", systemImage: "flag") { addingMilestone = true }
            }
            if !lineage.isEmpty {
                if !milestones.isEmpty || plant.isActive { CardDivider() }
                ForEach(lineage) { line in
                    lineageRow(line)
                        .padding(.leading, CGFloat(line.depth) * 16)
                }
            }
        }
    }

    @ViewBuilder
    private func lineageRow(_ line: Lineage.HistoryLine) -> some View {
        let row = Group {
            if let other = line.plant {
                NavigationLink(value: other) {
                    HStack {
                        Text(line.text).foregroundStyle(GH.Palette.leafInk)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(GH.Palette.ink2)
                            .accessibilityHidden(true)
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                Text(line.text).foregroundStyle(GH.Palette.ink)
            }
        }
        if let cutting = line.unlinks {
            // Was a swipe in the old list; a press-and-hold menu here.
            row
                .contextMenu {
                    Button(role: .destructive) { unlink(cutting) } label: { Label("Unlink", systemImage: "link.badge.plus") }
                }
                .accessibilityAction(named: "Unlink") { unlink(cutting) }
        } else {
            row
        }
    }

    @ViewBuilder
    private var projectsSection: some View {
        let projects = Plans.sorted(Array(plant.projects ?? []))
        if !projects.isEmpty {
            CollapsibleSection("Projects", summary: "\(projects.count)") {
                ForEach(Array(projects.enumerated()), id: \.element.objectID) { index, project in
                    if index > 0 { CardDivider() }
                    ProjectRow(project: project, household: household)
                        // Inside a card the row's text would take the leaf tint.
                        .buttonStyle(.plain)
                }
            }
        }
    }

    private var actionsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            CardActionButton(title: "Combine with other plants…", systemImage: "arrow.triangle.merge") { showingCombine = true }
            CardDivider()
            CardActionButton(title: "Take a cutting…", systemImage: "scissors") { showingCutting = true }
        }
        .padding(.horizontal, GH.Space.m)
        .padding(.vertical, GH.Space.xxs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ghCard()
    }

    @ViewBuilder
    private var moreMenu: some View {
        Button { showingEdit = true } label: { Label("Edit plant", systemImage: "pencil") }
        Button { showingAddPhoto = true } label: { Label("Add photo", systemImage: "camera") }
        Button { addingMilestone = true } label: { Label("Add milestone", systemImage: "flag") }
        Button { showingNewTask = true } label: { Label("Add a care reminder", systemImage: "plus") }
        Divider()
        Button { showingCombine = true } label: { Label("Combine with other plants…", systemImage: "arrow.triangle.merge") }
        Button { showingCutting = true } label: { Label("Take a cutting…", systemImage: "scissors") }
    }

    // MARK: Actions

    private func openViewer(_ photo: Photo) {
        var instant = Transaction()
        instant.disablesAnimations = true
        withTransaction(instant) {
            viewerPhotoID = photo.objectID
            showingViewer = true
        }
    }

    private func closeViewer() {
        var instant = Transaction()
        instant.disablesAnimations = true
        withTransaction(instant) {
            showingViewer = false
            viewerPhotoID = nil
        }
    }

    private func delete(_ milestone: Milestone) {
        context.delete(milestone)
        Persistence.shared.save(context)
    }

    private func unlink(_ cutting: Plant) {
        Lineage.setCuttingParent(of: cutting, to: nil)
        Persistence.shared.save(context)
    }

    static func settingIcon(_ setting: PlantSetting) -> String {
        switch setting {
        case .indoor: "house"
        case .outdoor: "tree"
        case .seasonal: "arrow.triangle.2.circlepath"
        }
    }

    static func age(since date: Date, now: Date = .now) -> String {
        let months = Calendar.current.dateComponents([.month], from: date, to: now).month ?? 0
        if months < 1 { return "under a month" }
        if months < 24 { return months == 1 ? "1 month" : "\(months) months" }
        let years = months / 12
        let rest = months % 12
        return rest == 0 ? "\(years) years" : "\(years) yr \(rest) mo"
    }
}

/// A leaf-colored action inside a plant-page card ("Add photo").
struct CardActionButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) { CardActionLabel(title: title, systemImage: systemImage) }
            .buttonStyle(.plain)
    }
}

struct CardActionLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.body.weight(.semibold))
            .foregroundStyle(GH.Palette.leaf)
            .frame(minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
    }
}

/// A hairline between rows in a card.
struct CardDivider: View {
    var body: some View {
        GH.Palette.line.frame(height: 1).accessibilityHidden(true)
    }
}

struct ZoneSection: View {
    @ObservedObject var plant: Plant
    @ObservedObject var household: Household

    var body: some View {
        let advice = Hardiness.advice(setting: plant.settingValue, zone: household.hardinessZone, species: plant.species)
        if advice != .none {
            CollapsibleSection("Grow zone") {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(advice.message)
                        if let detail = advice.detail {
                            Text(detail).font(.caption).foregroundStyle(GH.Palette.ink2)
                        }
                    }
                } icon: {
                    Image(systemName: advice.isWarning ? "snowflake" : "thermometer.sun")
                        .foregroundStyle(advice.isWarning ? GH.Palette.terraInk : GH.Palette.leafInk)
                }
                if let species = plant.species {
                    LabeledContent("Light", value: species.light)
                    LabeledContent("Frost", value: species.frost)
                    Group {
                        if species.verified == true, let source = species.source, let url = URL(string: source) {
                            Link("Zones from \(species.sourceHost ?? "source")", destination: url)
                        } else {
                            Text("Zone range not yet checked against a reference.")
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(GH.Palette.ink2)
                }
            }
        }
    }
}

/// Notes typed right on the plant's page; saved when you leave the field.
struct PlantNotesSection: View {
    @ObservedObject var plant: Plant
    @Environment(\.managedObjectContext) private var context
    @State private var notes: String
    @FocusState private var focused: Bool

    init(plant: Plant) {
        _plant = ObservedObject(wrappedValue: plant)
        _notes = State(initialValue: plant.notes ?? "")
    }

    // The modifiers go on the field, not the section: a List section applies
    // its modifiers to the header and the row separately, which added the
    // keyboard's Done button twice.
    var body: some View {
        CollapsibleSection("Notes") {
            TextField("Anything worth remembering: quirks, where it came from, what it likes…", text: $notes, axis: .vertical)
                .lineLimit(2...)
                .focused($focused)
                .onChange(of: focused) { _, isFocused in if !isFocused { save() } }
                .onDisappear(perform: save)
                .onChange(of: plant.notes) { _, saved in
                    // Changed on the other phone.
                    if !focused { notes = saved ?? "" }
                }
                .toolbar {
                    if focused {
                        ToolbarItem(placement: .keyboard) { Button("Done") { focused = false } }
                    }
                }
        }
    }

    private func save() {
        let value = PlantFactory.cleanNotes(notes)
        guard plant.managedObjectContext != nil, value != plant.notes else { return }
        plant.notes = value
        Persistence.shared.save(context)
    }
}

extension View {
    /// A plant view only watches the plant itself, so editing one of its photos,
    /// milestones or projects (a new date, a fixed note, a project started,
    /// here or on the other phone) wouldn't redraw it. This redraws it whenever
    /// any of those change, which also re-sorts the timeline and History.
    /// `includingCare` also watches reminders and care logs, for views that
    /// show counts or "last watered" from them (the plant page).
    func redrawsOnRelatedChanges(_ plant: Plant, includingCare: Bool = false) -> some View {
        onReceive(NotificationCenter.default.publisher(for: .NSManagedObjectContextObjectsDidChange)) { note in
            let keys = [NSInsertedObjectsKey, NSUpdatedObjectsKey, NSDeletedObjectsKey, NSRefreshedObjectsKey]
            let changed = keys.contains { key in
                (note.userInfo?[key] as? Set<NSManagedObject>)?.contains { object in
                    object is Photo || object is Milestone || object is Project
                        || (includingCare && (object is CareLog || object is CareTask))
                } ?? false
            }
            if changed { plant.objectWillChange.send() }
        }
    }
}

extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
