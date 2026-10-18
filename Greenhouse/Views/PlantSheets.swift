import SwiftUI

struct AddPhotoSheet: View {
    let plant: Plant
    let household: Household
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?
    @State private var takenAt = Date()

    var body: some View {
        NavigationStack {
            Form {
                Section { PhotoInput(image: $image) }
                Section {
                    DatePicker("Taken on", selection: $takenAt, in: ...Date(), displayedComponents: .date)
                }
            }
            .navigationTitle("Add photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let data = image.flatMap({ ImageTools.preparedJPEG(from: $0) }) {
                            PlantFactory.addPhoto(data, takenAt: takenAt, to: plant, household: household, context: context)
                            Persistence.shared.save(context)
                        }
                        dismiss()
                    }
                    .disabled(image == nil)
                }
            }
        }
    }
}

/// First photo next to the latest one: "look how it's grown".
struct ThenNowView: View {
    let plant: Plant

    var body: some View {
        let timeline = Lineage.timeline(for: plant)
        ScrollView {
            VStack(spacing: 16) {
                if let since = Lineage.effectiveAcquiredDate(of: plant) {
                    Text("\(PlantDetailView.age(since: since).capitalizedFirst) since you got it")
                        .font(.title2.bold())
                }
                HStack(alignment: .top, spacing: 12) {
                    column("Then", timeline.first)
                    column("Now", timeline.last)
                }
            }
            .padding()
        }
        .navigationTitle("Then vs now")
    }

    private func column(_ title: String, _ item: Lineage.TimelinePhoto?) -> some View {
        VStack(spacing: 6) {
            Text(title).font(.headline)
            PlantPhotoView(photo: item?.photo, maxPixel: 1200)
                .frame(height: 260)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            Text(item?.photo.takenAt.map(Lineage.format) ?? "")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct StapleSheet: View {
    let plants: [Plant]
    let household: Household
    let onDone: () -> Void
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var nickname = ""
    @State private var date = Date()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(plants) { plant in
                        VStack(alignment: .leading) {
                            Text(plant.displayName)
                            Text("acq. \(plant.acquiredDate.map(Lineage.format) ?? "?")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Combining")
                } footer: {
                    Text("These become one plant with one tile. Their photos, history and care carry over, and the originals stay reachable from History.")
                }
                Section("New plant") {
                    TextField("Nickname (optional)", text: $nickname)
                    DatePicker("Stapled on", selection: $date, in: ...Date(), displayedComponents: .date)
                }
            }
            .navigationTitle("Staple plants")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Staple") {
                        Lineage.staple(plants, nickname: nickname, date: date, household: household, context: context)
                        Persistence.shared.save(context)
                        NotificationPlanner.reschedule()
                        onDone()
                        dismiss()
                    }
                }
            }
            .onAppear {
                if nickname.isEmpty { nickname = plants.first?.displayName ?? "" }
            }
        }
    }
}

struct SplitSheet: View {
    let plant: Plant
    let household: Household
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var names: [String] = []
    @State private var date = Date()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper("\(names.count) new plants", value: Binding(
                        get: { names.count },
                        set: { resize(to: $0) }
                    ), in: 2...12)
                    ForEach(names.indices, id: \.self) { index in
                        TextField("Plant \(index + 1)", text: $names[index])
                    }
                } footer: {
                    Text("\(plant.displayName) is retired and each new plant links back to it. Cuttings, divisions and pups all work this way.")
                }
                Section {
                    DatePicker("Split on", selection: $date, in: ...Date(), displayedComponents: .date)
                }
            }
            .navigationTitle("Split \(plant.displayName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Split") {
                        let finalNames = names.enumerated().map { index, name in
                            name.trimmingCharacters(in: .whitespaces).isEmpty ? defaultName(index) : name
                        }
                        Lineage.split(plant, names: finalNames, date: date, household: household, context: context)
                        Persistence.shared.save(context)
                        NotificationPlanner.reschedule()
                        dismiss()
                    }
                }
            }
            .onAppear { if names.isEmpty { resize(to: 2) } }
        }
    }

    private func defaultName(_ index: Int) -> String { "\(plant.displayName) #\(index + 1)" }

    private func resize(to count: Int) {
        if count > names.count {
            names += (names.count..<count).map(defaultName)
        } else {
            names = Array(names.prefix(count))
        }
    }
}

struct EditPlantView: View {
    @ObservedObject var plant: Plant
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var nickname = ""
    @State private var location = ""
    @State private var acquired = Date()
    @State private var setting: PlantSetting = .indoor
    @State private var light: LightSource?

    var body: some View {
        NavigationStack {
            Form {
                TextField("Nickname", text: $nickname)
                TextField("Where it lives", text: $location)
                DatePicker("Got it on", selection: $acquired, in: ...Date(), displayedComponents: .date)
                Picker("Lives", selection: $setting) {
                    ForEach(PlantSetting.allCases) { Text($0.label).tag($0) }
                }
                LightSourcePicker(selection: $light)
            }
            .navigationTitle("Edit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let trimmedNick = nickname.trimmingCharacters(in: .whitespaces)
                        let trimmedLocation = location.trimmingCharacters(in: .whitespaces)
                        plant.nickname = trimmedNick.isEmpty ? nil : trimmedNick
                        plant.location = trimmedLocation.isEmpty ? nil : trimmedLocation
                        plant.acquiredDate = acquired
                        plant.settingValue = setting
                        plant.lightSourceValue = light
                        Persistence.shared.save(context)
                        NotificationPlanner.reschedule()
                        dismiss()
                    }
                }
            }
            .onAppear {
                nickname = plant.nickname ?? ""
                location = plant.location ?? ""
                acquired = plant.acquiredDate ?? Date()
                setting = plant.settingValue
                light = plant.lightSourceValue
            }
        }
    }
}
