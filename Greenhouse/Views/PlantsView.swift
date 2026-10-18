import CoreData
import SwiftUI

/// Home screen: one tile per active plant, plus select-to-staple.
struct PlantsView: View {
    let household: Household
    @FetchRequest private var plants: FetchedResults<Plant>
    @State private var selecting = false
    @State private var selection: Set<NSManagedObjectID> = []
    @State private var showingAdd = false
    @State private var showingStaple = false

    init(household: Household) {
        self.household = household
        let request = NSFetchRequest<Plant>(entityName: "Plant")
        request.predicate = NSPredicate(format: "household == %@ AND status == %@", household, PlantStatus.active.rawValue)
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
        _plants = FetchRequest(fetchRequest: request)
    }

    private var selectedPlants: [Plant] {
        plants.filter { selection.contains($0.objectID) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
                    ForEach(plants) { plant in
                        if selecting {
                            Button { toggle(plant) } label: {
                                PlantTile(plant: plant, selected: selection.contains(plant.objectID))
                            }
                            .buttonStyle(.plain)
                        } else {
                            NavigationLink(value: plant) { PlantTile(plant: plant, selected: false) }
                                .buttonStyle(.plain)
                        }
                    }
                }
                .padding()
            }
            .overlay {
                if plants.isEmpty {
                    ContentUnavailableView("No plants yet", systemImage: "leaf", description: Text("Tap + to add your first plant."))
                }
            }
            .navigationTitle(household.name ?? "Plants")
            .navigationDestination(for: Plant.self) { PlantDetailView(plant: $0, household: household) }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if plants.count >= 2 {
                        Button(selecting ? "Cancel" : "Staple") {
                            selecting.toggle()
                            selection = []
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingAdd = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Add plant")
                }
            }
            .safeAreaInset(edge: .bottom) {
                if selecting {
                    Button {
                        showingStaple = true
                    } label: {
                        Text(selection.count < 2 ? "Pick 2 or more plants to staple" : "Staple \(selection.count) plants together")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(selection.count < 2)
                    .padding()
                    .background(.bar)
                }
            }
            .sheet(isPresented: $showingAdd) { AddPlantView(household: household) }
            .sheet(isPresented: $showingStaple) {
                StapleSheet(plants: selectedPlants, household: household) {
                    selecting = false
                    selection = []
                }
            }
        }
    }

    private func toggle(_ plant: Plant) {
        if selection.contains(plant.objectID) {
            selection.remove(plant.objectID)
        } else {
            selection.insert(plant.objectID)
        }
    }
}

struct PlantTile: View {
    @ObservedObject var plant: Plant
    let selected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            PlantPhotoView(photo: Lineage.timeline(for: plant).last?.photo, maxPixel: 400)
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
        .overlay {
            if selected {
                RoundedRectangle(cornerRadius: 16).stroke(Color.accentColor, lineWidth: 3)
            }
        }
        .overlay(alignment: .topTrailing) {
            if selected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.white, Color.accentColor)
                    .padding(14)
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
