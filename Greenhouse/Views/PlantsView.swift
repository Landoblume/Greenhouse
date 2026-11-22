import CoreData
import SwiftUI

/// Home screen: a masonry of plant tiles under a friendly header, search,
/// collection chips and, some days, an "On this day" throwback.
struct PlantsView: View {
    @ObservedObject var household: Household
    @AppStorage(Collections.selectedKey) private var selectedCollection = ""
    @AppStorage(SettingsKey.myName) private var myName = ""
    @FetchRequest private var allPlants: FetchedResults<Plant>
    @FetchRequest(fetchRequest: Household.all()) private var households: FetchedResults<Household>
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    /// The other people sharing the household, and today's throwback. Worked
    /// out when the data or the day changes, not on every redraw.
    @State private var others: [String] = []
    @State private var throwback: OnThisDay.Match<OnThisDay.PlantPhoto>?
    @State private var showingAdd = false
    @State private var combining: Plant?
    #if DEBUG
    @State private var filter = PlantFilter(genus: DemoData.startingGenus)
    #else
    @State private var filter = PlantFilter()
    #endif
    @FocusState private var searchFocused: Bool
    @State private var deleting: Plant?
    @State private var choosingPlants: PlantCollection?
    /// The stack's pages, so a tile can push its plant itself (to choose how
    /// it animates). Value links further in still push onto it.
    @State private var path = NavigationPath()
    @Namespace private var morphSpace
    @State private var tileFrames = TileFrameStore()
    @State private var flight: TileFlight?

    init(household: Household) {
        self.household = household
        let request = NSFetchRequest<Plant>(entityName: "Plant")
        request.predicate = NSPredicate(format: "household == %@ AND status == %@", household, PlantStatus.active.rawValue)
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
        _allPlants = FetchRequest(fetchRequest: request)
    }

    private var collection: PlantCollection? { Collections.find(selectedCollection, in: household) }
    private var inCollection: [Plant] { allPlants.filter { Collections.contains(collection, $0) } }
    private var plants: [Plant] { filter.apply(to: inCollection) }
    /// One column at accessibility text sizes, where two would squeeze the names.
    private var columns: Int { typeSize.isAccessibilitySize ? 1 : 2 }
    private var morphStyle: TileMorph { TileMorph.current(reduceMotion: reduceMotion) }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header
                        .padding(.horizontal, GH.Space.screen)
                        .growIn(index: 0)
                    ForEach(HouseholdMerge.candidates(for: household, in: Array(households))) { other in
                        MergeCard(source: other, target: household)
                            .padding(.horizontal, GH.Space.screen)
                    }
                    if allPlants.isEmpty {
                        PlantsEmptyState { showingAdd = true }
                    } else {
                        populated
                    }
                }
                .padding(.top, GH.Space.xs)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(GH.Palette.paper.ignoresSafeArea())
            .ghTabBarClearance()
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Plant.self) { PlantDetailView(plant: $0, household: household) }
            .navigationDestination(for: PlantTileRoute.self) { route in
                PlantDetailView(plant: route.plant, household: household, heroEntrance: route.entrance)
                    .tileMorphDestination(id: route.plant.objectID, in: morphSpace, enabled: morphStyle == .zoom)
            }
            .navigationDestination(for: Project.self) { ProjectDetailView(project: $0, household: household) }
            .navigationDestination(for: CareHistoryRoute.self) { CareHistoryView(plant: $0.plant) }
            .onChange(of: PlantFilter.genera(in: inCollection)) {
                filter = filter.clearingUnavailableGenus(in: inCollection)
            }
            .onAppear { refreshOthers(); refreshThrowback() }
            .onChange(of: myName) { refreshOthers() }
            .onChange(of: inCollection.map(\.objectID)) { refreshThrowback() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { refreshOthers(); refreshThrowback() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in refreshThrowback() }
            .onReceive(ContextChanges.publisher(for: household.managedObjectContext)) { note in
                // New care logs (here or syncing in) can add a person; photo,
                // plant and Combine changes can change the throwback. Only
                // this (main-thread) context counts: see `ContextChanges`.
                let store = household.managedObjectContext
                if ContextChanges.touches(note, in: store, where: { $0 is CareLog }) { refreshOthers() }
                if ContextChanges.touches(note, in: store, where: {
                    $0 is Photo || $0 is Plant || $0 is LineageEvent || $0 is PlantCollection
                }) { refreshThrowback() }
            }
            .sheet(isPresented: $showingAdd) { AddPlantView(household: household) }
            .sheet(item: $choosingPlants) { CollectionPlantsSheet(collection: $0, household: household) }
            .confirmationDialog("Delete \(deleting?.displayName ?? "plant")?",
                                isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                                titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if let deleting {
                        Lineage.delete(deleting, context: context)
                        Persistence.shared.save(context)
                        NotificationPlanner.reschedule()
                    }
                    deleting = nil
                }
            } message: {
                Text("Removes it from both phones, with its photos, history and its own reminders. To merge it with another plant instead, use Combine.")
            }
            .sheet(item: $combining) { CombineSheet(plant: $0, household: household) }
        }
        .overlay {
            if let flight { TileFlightOverlay(flight: flight) }
        }
    }

    // MARK: - Opening a plant

    /// A tile's tap. iOS 18 pushes with the zoom; iOS 17 pushes without the
    /// slide and flies the photo up into the hero; Reduce Motion pushes
    /// without the slide and lets the page fade in.
    private func open(_ plant: Plant) {
        guard flight == nil else { return }
        let style = morphStyle
        guard style != .zoom else {
            path.append(PlantTileRoute(plant: plant, entrance: style.heroEntrance))
            return
        }
        var instant = Transaction()
        instant.disablesAnimations = true
        // No frame for the tile (not measured yet): no flight, so the hero
        // fades in on its own rather than waiting for a photo that never lands.
        guard style == .overlay, let from = tileFrames.frames[plant.objectID] else {
            withTransaction(instant) { path.append(PlantTileRoute(plant: plant, entrance: .fadeIn)) }
            return
        }
        withTransaction(instant) {
            flight = TileFlight(plantID: plant.objectID, photo: PlantPhotos.cover(for: plant), from: from)
            path.append(PlantTileRoute(plant: plant, entrance: style.heroEntrance))
        }
        // Next frame, once the copy is drawn over the tile: fly, then fade.
        DispatchQueue.main.async {
            withAnimation(GH.Motion.hero) {
                flight?.landed = true
            } completion: {
                withAnimation(.easeOut(duration: 0.2)) {
                    flight?.fading = true
                } completion: {
                    flight = nil
                }
            }
        }
    }

    // MARK: - Header

    /// Today's date, the big title, the household's avatars and the + button.
    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .bottom) {
                titleBlock
                Spacer(minLength: GH.Space.s)
                HStack(spacing: GH.Space.s) {
                    PeopleAvatars(names: others)
                    addButton
                }
            }
            VStack(alignment: .leading, spacing: GH.Space.s) {
                titleBlock
                HStack(spacing: GH.Space.s) {
                    PeopleAvatars(names: others)
                    Spacer(minLength: 0)
                    addButton
                }
            }
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let name = household.name?.trimmingCharacters(in: .whitespaces), !name.isEmpty {
                Text(name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(GH.Palette.ink2)
            }
            Text("Plants")
                .font(.ghRounded(.largeTitle))
                .foregroundStyle(GH.Palette.ink)
                .accessibilityAddTraits(.isHeader)
        }
    }

    private var addButton: some View {
        Button { showingAdd = true } label: {
            Image(systemName: "plus")
                .font(.body.weight(.bold))
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .foregroundStyle(GH.Palette.onLeaf)
                .frame(width: 44, height: 44)
                .background(GH.Palette.leaf, in: Circle())
                .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add plant")
    }

    private func refreshOthers() {
        let loggers = (household.tasks ?? []).flatMap { ($0.logs ?? []).compactMap(\.doneBy) }
        let updated = PeopleAvatars.others(me: myName, loggers: loggers)
        if updated != others { others = updated }
    }

    private func refreshThrowback() {
        let pick = OnThisDay.pick(in: inCollection, today: .now)
        let changed = pick?.item.photo != throwback?.item.photo || pick?.yearsAgo != throwback?.yearsAgo
        if changed { throwback = pick }
    }

    // MARK: - With plants

    @ViewBuilder
    private var populated: some View {
        searchRow
            .padding(.horizontal, GH.Space.screen)
            .growIn(index: 1)
        VStack(alignment: .leading, spacing: 0) {
            CollectionBar(household: household)
            if let collection {
                Button { choosingPlants = collection } label: {
                    Label("Choose plants for \(collection.name ?? "this collection")", systemImage: "checklist")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(GH.Palette.leafInk)
                        .frame(minHeight: 44)
                }
                .padding(.leading, GH.Space.screen)
            }
        }
        // Chips scroll sideways and fade out at the right edge.
        .padding(.leading, 4)
        .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.94),
                                     .init(color: .clear, location: 1)], startPoint: .leading, endPoint: .trailing))
        .growIn(index: 2)
        if let throwback {
            OnThisDayCard(plant: throwback.item.plant, photo: throwback.item.photo, yearsAgo: throwback.yearsAgo)
                .padding(.horizontal, GH.Space.screen)
                .growIn(index: 3)
        }
        if let genus = filter.genus {
            GenusChip(genus: genus) {
                withAnimation(reduceMotion ? GH.Motion.reduced : GH.Motion.enter) { filter.genus = nil }
            }
                .padding(.horizontal, GH.Space.screen)
        }
        grid
    }

    @ViewBuilder
    private var grid: some View {
        if plants.isEmpty, !inCollection.isEmpty {
            ContentUnavailableView {
                Label("No matching plants", systemImage: "magnifyingglass")
            } actions: {
                Button("Clear search and filters") {
                    filter = PlantFilter()
                }
                .buttonStyle(.ghProminent)
            }
        } else if plants.isEmpty, let collection {
            ContentUnavailableView("Nothing in \(collection.name ?? "this collection") yet", systemImage: "square.stack",
                                   description: Text("Tap \u{201C}Choose plants\u{201D} above, or + to add a new plant here."))
        } else {
            LazyMasonry(items: plants,
                        heights: plants.map { PlantTileStyle.estimatedHeight(forID: $0.uuid) },
                        columns: columns) { plant, index in
                Button { open(plant) } label: {
                    PlantTile(plant: plant, morph: TileMorphSource(namespace: morphSpace,
                                                                   frames: morphStyle == .overlay ? tileFrames : nil))
                }
                    .buttonStyle(.plain)
                    .contextMenu {
                        if allPlants.count >= 2 {
                            Button { combining = plant } label: {
                                Label("Combine with other plants…", systemImage: "arrow.triangle.merge")
                            }
                        }
                        Button(role: .destructive) { deleting = plant } label: {
                            Label("Delete plant", systemImage: "trash")
                        }
                    }
                    .transition(.opacity)
                    .modifier(FirstTilesGrowIn(index: index))
                    .scrollSoftening()
            }
            .padding(.horizontal, GH.Space.screen)
            // Filtering or sorting reflows the tiles (the ids are stable);
            // Reduce Motion makes it a quick ease instead of a spring.
            .animation(reduceMotion ? GH.Motion.reduced : GH.Motion.enter, value: plants.map(\.objectID))
        }
    }

    // MARK: - Search and filter

    private var searchRow: some View {
        HStack(spacing: 10) {
            HStack(spacing: GH.Space.xs) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(GH.Palette.ink2)
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    .accessibilityHidden(true)
                TextField("Search plants, rooms, Latin names", text: $filter.query)
                    .focused($searchFocused)
                    .submitLabel(.search)
                    .autocorrectionDisabled()
                    .foregroundStyle(GH.Palette.ink)
                if !filter.query.isEmpty {
                    Button { filter.query = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(GH.Palette.ink2)
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.leading, 14)
            .padding(.trailing, filter.query.isEmpty ? 14 : 0)
            .frame(minHeight: 44)
            .background(GH.Palette.surface2, in: RoundedRectangle(cornerRadius: GH.Radius.control, style: .continuous))
            filterMenu
        }
    }

    private var filterMenu: some View {
        Menu {
            Section("Show") {
                ForEach(PlantSetting.allCases) { setting in
                    Toggle(setting.label, isOn: Binding(
                        get: { filter.settings.contains(setting) },
                        set: { on in
                            if on { filter.settings.insert(setting) } else { filter.settings.remove(setting) }
                        }
                    ))
                }
                Toggle("Needs water now", isOn: $filter.needsWater)
            }
            if PlantFilter.offersGenusPicker(in: inCollection) {
                Picker("Genus", selection: $filter.genus) {
                    Text("Any genus").tag(String?.none)
                    ForEach(PlantFilter.genusCounts(in: inCollection), id: \.genus) {
                        Text($0.label).tag(String?.some($0.genus))
                    }
                }
                .pickerStyle(.menu)
            }
            Picker("Sort by", selection: $filter.sort) {
                ForEach(PlantFilter.Sort.allCases) { Text($0.label).tag($0) }
            }
            if filter.isFiltering {
                Button("Clear filters", role: .destructive) {
                    filter.settings = []
                    filter.needsWater = false
                    filter.genus = nil
                    filter.sort = .added
                }
            }
        } label: {
            Image(systemName: filter.isFiltering
                  ? "line.3.horizontal.decrease.circle.fill"
                  : "line.3.horizontal.decrease.circle")
                .font(.title3)
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .foregroundStyle(filter.isFiltering ? GH.Palette.leafInk : GH.Palette.ink)
                .frame(width: 44, height: 44)
                .background(filter.isFiltering ? GH.Palette.leafSoft : GH.Palette.surface2, in: Circle())
        }
        .accessibilityLabel("Filter and sort")
    }
}

/// The "Monstera ✕" chip above the grid while a genus filter is on.
struct GenusChip: View {
    let genus: String
    let onClear: () -> Void

    var body: some View {
        Button(action: onClear) {
            HStack(spacing: 6) {
                Text(genus)
                Image(systemName: "xmark").font(.caption.weight(.heavy))
            }
            .font(.ghRounded(.subheadline, weight: .bold))
            .foregroundStyle(GH.Palette.leafInk)
            .padding(.horizontal, 14)
            .frame(minHeight: 34)
            .background(GH.Palette.leafSoft, in: Capsule(style: .continuous))
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Genus \(genus)")
        .accessibilityHint("Removes this filter")
    }
}

/// Small blob-shaped initials for the other people sharing the household:
/// two of them, then a "+N" bubble when there are more.
struct PeopleAvatars: View {
    /// Everyone else, in a stable order. Empty hides the avatars.
    let names: [String]

    /// The other people who've logged care: not this phone's own name, and
    /// nobody at all when this phone's name isn't set yet (there's no telling
    /// which logger is "me"). Case and spacing don't make a different person,
    /// and the order is by name so both phones show the same people.
    static func others(me: String, loggers: [String]) -> [String] {
        func clean(_ name: String) -> String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
        let mine = clean(me)
        guard !mine.isEmpty else { return [] }
        var seen: Set<String> = [mine.lowercased()]
        var result: [String] = []
        func inOrder(_ a: String, _ b: String) -> Bool {
            let order = a.localizedCaseInsensitiveCompare(b)
            return order == .orderedSame ? a < b : order == .orderedAscending
        }
        for name in loggers.map(clean).sorted(by: inOrder) where !name.isEmpty {
            if seen.insert(name.lowercased()).inserted { result.append(name) }
        }
        return result
    }

    /// "Shared with Alex", "Shared with Alex and Sam", "Shared with Alex, Sam and Riley".
    static func spokenLabel(for names: [String]) -> String {
        "Shared with \(names.formatted(.list(type: .and)))"
    }

    private static let fills: [(Color, Color)] = [(GH.Palette.terraSoft, GH.Palette.terraInk), (GH.Palette.skySoft, GH.Palette.skyInk),
                                                  (GH.Palette.leafSoft, GH.Palette.leafInk)]

    var body: some View {
        if !names.isEmpty {
            let shown = Array(names.prefix(2))
            let extra = names.count - shown.count
            HStack(spacing: -8) {
                ForEach(Array(shown.enumerated()), id: \.offset) { index, name in
                    bubble(String(name.prefix(1)).uppercased(), index: index)
                }
                if extra > 0 { bubble("+\(extra)", index: 2) }
            }
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Self.spokenLabel(for: names))
        }
    }

    private func bubble(_ text: String, index: Int) -> some View {
        let colors = Self.fills[index % Self.fills.count]
        return Text(text)
            .font(.ghRounded(.footnote))
            .foregroundStyle(colors.1)
            .minimumScaleFactor(0.7)
            .lineLimit(1)
            .frame(width: 32, height: 32)
            .background(colors.0, in: BlobShape(variant: index))
            .overlay { if index > 0 { BlobShape(variant: index).stroke(GH.Palette.paper, lineWidth: 2) } }
    }
}

/// Only the first screenful of tiles grows in; tiles scrolled to later are
/// built on demand and just appear (scroll softening handles their entrance).
struct FirstTilesGrowIn: ViewModifier {
    let index: Int

    func body(content: Content) -> some View {
        if index < 8 {
            content.growIn(index: index, baseDelay: 0.2)
        } else {
            content
        }
    }
}

/// An irregular rounded rectangle, for avatars only.
struct BlobShape: Shape {
    var variant = 0

    func path(in rect: CGRect) -> Path {
        // Horizontal and vertical corner radii as fractions of the size:
        // top-left, top-right, bottom-right, bottom-left.
        let (rx, ry): ([CGFloat], [CGFloat]) = variant % 2 == 0
            ? ([0.58, 0.42, 0.55, 0.45], [0.52, 0.58, 0.42, 0.48])
            : ([0.45, 0.55, 0.42, 0.58], [0.58, 0.45, 0.55, 0.42])
        let w = rect.width, h = rect.height
        let k: CGFloat = 0.5523
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rx[0] * w, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - rx[1] * w, y: rect.minY))
        path.addCurve(to: CGPoint(x: rect.maxX, y: rect.minY + ry[1] * h),
                      control1: CGPoint(x: rect.maxX - rx[1] * w * (1 - k), y: rect.minY),
                      control2: CGPoint(x: rect.maxX, y: rect.minY + ry[1] * h * (1 - k)))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - ry[2] * h))
        path.addCurve(to: CGPoint(x: rect.maxX - rx[2] * w, y: rect.maxY),
                      control1: CGPoint(x: rect.maxX, y: rect.maxY - ry[2] * h * (1 - k)),
                      control2: CGPoint(x: rect.maxX - rx[2] * w * (1 - k), y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + rx[3] * w, y: rect.maxY))
        path.addCurve(to: CGPoint(x: rect.minX, y: rect.maxY - ry[3] * h),
                      control1: CGPoint(x: rect.minX + rx[3] * w * (1 - k), y: rect.maxY),
                      control2: CGPoint(x: rect.minX, y: rect.maxY - ry[3] * h * (1 - k)))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + ry[0] * h))
        path.addCurve(to: CGPoint(x: rect.minX + rx[0] * w, y: rect.minY),
                      control1: CGPoint(x: rect.minX, y: rect.minY + ry[0] * h * (1 - k)),
                      control2: CGPoint(x: rect.minX + rx[0] * w * (1 - k), y: rect.minY))
        path.closeSubpath()
        return path
    }
}

/// Offers to bring plants from your own household into the one you joined.
struct MergeCard: View {
    @ObservedObject var source: Household
    let target: Household
    @Environment(\.managedObjectContext) private var context
    @State private var confirming = false
    @State private var dismissed = false

    private var count: Int { (source.plants ?? []).filter(\.isActive).count }

    var body: some View {
        if !dismissed {
            VStack(alignment: .leading, spacing: 10) {
                Label("You have \(count) plant\(count == 1 ? "" : "s") of your own", systemImage: "arrow.triangle.merge")
                    .font(.headline)
                Text("They're from before you joined \(target.name ?? "this household"). Bring them in to share them here, with their photos, reminders and history.")
                    .font(.subheadline)
                    .foregroundStyle(GH.Palette.ink2)
                HStack {
                    Button("Bring them in") { confirming = true }
                        .buttonStyle(.ghProminent)
                    Button("Not now") { dismissed = true }
                        .buttonStyle(.bordered)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(GH.Palette.leafSoft, in: RoundedRectangle(cornerRadius: GH.Radius.card, style: .continuous))
            .confirmationDialog("Move \(count) plant\(count == 1 ? "" : "s") into \(target.name ?? "this household")?",
                                isPresented: $confirming, titleVisibility: .visible) {
                Button("Move them") {
                    HouseholdMerge.move(source, into: target, context: context)
                    Persistence.shared.save(context)
                    NotificationPlanner.reschedule()
                }
            } message: {
                Text("Everyone in the household will see them. Your separate household is removed once they've moved.")
            }
        }
    }
}

/// "Due today" / "In 3 days" / "Overdue", plus who did it last.
struct DueBadge: View {
    @ObservedObject var task: CareTask

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let status = CareSchedule.status(of: task) {
                Label(status.label + (task.snoozedUntil == nil ? "" : " (snoozed)"),
                      systemImage: task.isWatering ? "drop.fill" : "calendar")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(status.needsAttention ? GH.Palette.terraInk : GH.Palette.ink2)
            }
            if let last = task.lastLog, let at = last.doneAt {
                Text("\(task.isWatering ? "Watered" : "Done") by \(last.doneBy ?? "someone") \(at.formatted(.relative(presentation: .named)))")
                    .font(.caption2)
                    .foregroundStyle(GH.Palette.ink2)
                    .lineLimit(1)
            }
        }
    }
}

struct PlantPhotoView: View {
    let photo: Photo?
    let maxPixel: CGFloat

    var body: some View {
        if let photo, let image = ThumbnailCache.shared.image(for: photo, maxPixel: maxPixel) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            ZStack {
                GH.Palette.leafSoft
                Image(systemName: "leaf.fill")
                    .font(.largeTitle)
                    .foregroundStyle(GH.Palette.leafInk.opacity(0.6))
            }
        }
    }
}
