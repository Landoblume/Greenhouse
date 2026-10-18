import PhotosUI
import SwiftUI

struct AddPlantView: View {
    let household: Household
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var species: Species?
    @State private var customLatin = ""
    @State private var nickname = ""
    @State private var acquired = Date()
    @State private var location = ""
    @State private var setting: PlantSetting = .indoor
    @State private var light: LightSource?
    @State private var waterEvery = 7
    @State private var image: UIImage?
    @State private var showingSpeciesPicker = false

    private var latinName: String { species?.latin ?? customLatin }

    var body: some View {
        NavigationStack {
            Form {
                Section("Species") {
                    Button { showingSpeciesPicker = true } label: {
                        if let species {
                            VStack(alignment: .leading) {
                                Text(species.latin).italic()
                                Text(species.common.joined(separator: ", "))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } else if !customLatin.isEmpty {
                            VStack(alignment: .leading) {
                                Text(customLatin).italic()
                                Text("Not in the list, so no care data")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            Label("Choose species…", systemImage: "magnifyingglass")
                        }
                    }
                }

                Section("Photo") {
                    PhotoInput(image: $image)
                }

                Section("About") {
                    TextField("Nickname (optional)", text: $nickname)
                    DatePicker("Got it on", selection: $acquired, in: ...Date(), displayedComponents: .date)
                    TextField("Where it lives (e.g. kitchen window)", text: $location)
                    Picker("Lives", selection: $setting) {
                        ForEach(PlantSetting.allCases) { Text($0.label).tag($0) }
                    }
                    LightSourcePicker(selection: $light)
                }

                Section {
                    Stepper("Water every \(waterEvery) day\(waterEvery == 1 ? "" : "s")", value: $waterEvery, in: 1...90)
                } header: {
                    Text("Watering")
                } footer: {
                    if let species {
                        Text("Starting point for \(species.primaryCommonName). Light: \(species.light).")
                    }
                }
            }
            .navigationTitle("New plant")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(latinName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .sheet(isPresented: $showingSpeciesPicker) {
                SpeciesPickerView { picked in
                    species = picked
                    customLatin = ""
                    waterEvery = picked.waterDays
                } onCustom: { typed in
                    species = nil
                    customLatin = typed
                }
            }
        }
    }

    private func save() {
        PlantFactory.create(
            scientificName: latinName,
            species: species,
            nickname: nickname,
            acquired: acquired,
            location: location,
            setting: setting,
            lightSource: light,
            waterEvery: waterEvery,
            photo: image.flatMap { ImageTools.preparedJPEG(from: $0) },
            household: household,
            context: context
        )
        Persistence.shared.save(context)
        NotificationPlanner.reschedule()
        dismiss()
    }
}

struct SpeciesPickerView: View {
    let onPick: (Species) -> Void
    let onCustom: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var results: [Species] { SpeciesCatalog.shared.search(query) }

    var body: some View {
        NavigationStack {
            List {
                let trimmed = query.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty, !results.contains(where: { SpeciesCatalog.normalize($0.latin) == SpeciesCatalog.normalize(trimmed) }) {
                    Button {
                        onCustom(trimmed)
                        dismiss()
                    } label: {
                        Label("Use “\(trimmed)” as the Latin name", systemImage: "character.cursor.ibeam")
                    }
                }
                ForEach(results) { species in
                    Button {
                        onPick(species)
                        dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(species.latin).italic().foregroundStyle(.primary)
                            Text(species.common.joined(separator: ", "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Common or Latin name")
            .navigationTitle("Species")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }
}

struct LightSourcePicker: View {
    @Binding var selection: LightSource?

    var body: some View {
        Picker("Light", selection: $selection) {
            Text("Not set").tag(LightSource?.none)
            ForEach(LightSource.allCases) { Text($0.label).tag(Optional($0)) }
        }
    }
}

/// Camera first (where there is one), photo library as the fallback.
struct PhotoInput: View {
    @Binding var image: UIImage?
    @State private var showingCamera = false
    @State private var libraryItem: PhotosPickerItem?

    var body: some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(height: 200)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            Button { showingCamera = true } label: {
                Label(image == nil ? "Take photo" : "Retake photo", systemImage: "camera")
            }
            .fullScreenCover(isPresented: $showingCamera) {
                CameraPicker(image: $image).ignoresSafeArea()
            }
        }
        PhotosPicker(selection: $libraryItem, matching: .images) {
            Label("Choose from library", systemImage: "photo.on.rectangle")
        }
        .onChange(of: libraryItem) { _, item in
            Task {
                if let data = try? await item?.loadTransferable(type: Data.self), let picked = UIImage(data: data) {
                    image = picked
                }
            }
        }
    }
}

struct CameraPicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker

        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            parent.image = info[.originalImage] as? UIImage
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
