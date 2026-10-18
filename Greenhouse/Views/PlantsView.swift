import CoreData
import SwiftUI

/// Home screen: one tile per active plant.
struct PlantsView: View {
    @ObservedObject var household: Household
    @AppStorage(Collections.selectedKey) private var selectedCollection = ""
    @FetchRequest private var allPlants: FetchedResults<Plant>
    @FetchRequest(fetchRequest: Household.all()) private var households: FetchedResults<Household>
    @Environment(\.managedObjectContext) private var context
    @State private var showingAdd = false
    @State private var combining: Plant?
    @State private var deleting: Plant?

    init(household: Household) {
        self.household = household
        let request = NSFetchRequest<Plant>(entityName: "Plant")
        request.predicate = NSPredicate(format: "household == %@ AND status == %@", household, PlantStatus.active.rawValue)
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
        _allPlants = FetchRequest(fetchRequest: request)
    }

    private var collection: PlantCollection? { Collections.find(selectedCollection, in: household) }
    private var plants: [Plant] { allPlants.filter { Collections.contains(collection, $0) } }
    @State private var choosingPlants: PlantCollection?

    var body: some View {
        NavigationStack {
            ScrollView {
                CollectionBar(household: household)
                    .padding(.top, 4)
                if let collection {
                    Button { choosingPlants = collection } label: {
                        Label("Choose plants for \(collection.name ?? "this collection")", systemImage: "checklist")
                            .font(.subheadline)
                    }
                    .padding(.top, 8)
                }
                ForEach(HouseholdMerge.candidates(for: household, in: Array(households))) { other in
                    MergeCard(source: other, target: household)
                        .padding([.horizontal, .top])
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
                    ForEach(plants) { plant in
                        NavigationLink(value: plant) { PlantTile(plant: plant) }
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
                    }
                }
                .padding()
            }
            .overlay {
                if allPlants.isEmpty {
                    ContentUnavailableView("No plants yet", systemImage: "leaf", description: Text("Tap + to add your first plant."))
                } else if plants.isEmpty, let collection {
                    ContentUnavailableView("Nothing in \(collection.name ?? "this collection") yet", systemImage: "square.stack",
                                           description: Text("Tap “Choose plants” above, or + to add a new plant here."))
                        .allowsHitTesting(false)
                }
            }
            .navigationTitle(household.name ?? "Plants")
            .navigationDestination(for: Plant.self) { PlantDetailView(plant: $0, household: household) }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingAdd = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Add plant")
                }
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
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Bring them in") { confirming = true }
                        .buttonStyle(.borderedProminent)
                    Button("Not now") { dismissed = true }
                        .buttonStyle(.bordered)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
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

struct PlantTile: View {
    @ObservedObject var plant: Plant

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            PlantPhotoView(photo: PlantPhotos.cover(for: plant), maxPixel: 400)
                .frame(height: 150)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            Text(plant.displayName)
                .font(.headline)
                .lineLimit(1)
            if let latin = plant.scientificName {
                Text(latin)
                    .font(.caption)
                    .italic()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if let since = Lineage.effectiveAcquiredDate(of: plant) {
                Text("Since \(Lineage.format(since))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if let watering = plant.wateringTask {
                DueBadge(task: watering)
            }
        }
        .padding(8)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
        .redrawsOnPhotoChanges(plant)
    }
}

/// "Due today" / "In 3 days" / "Overdue", plus who did it last.
struct DueBadge: View {
    @ObservedObject var task: CareTask

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let status = CareSchedule.status(of: task) {
                Label(status.label, systemImage: task.isWatering ? "drop.fill" : "calendar")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(status.needsAttention ? Color.orange : Color.secondary)
            }
            if let last = task.lastLog, let at = last.doneAt {
                Text("\(task.isWatering ? "Watered" : "Done") by \(last.doneBy ?? "someone") \(at.formatted(.relative(presentation: .named)))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
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
                Color.green.opacity(0.15)
                Image(systemName: "leaf.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.green.opacity(0.6))
            }
        }
    }
}
