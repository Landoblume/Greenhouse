import SwiftUI

/// Take a cutting, camera first: snap the cutting, then a card with the photo,
/// a name and what it's grown in. Add makes the plant with that photo as its
/// main photo. Three taps: Take a cutting, shutter, Add.
///
/// With no camera to use (denied, or the simulator), or when someone taps
/// Skip photo, it falls back to today's form (CuttingSheet), which has the
/// same medium picker.
struct CuttingCameraView: View {
    let plant: Plant
    let household: Household

    private enum Stage { case camera, card, form }

    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var camera = CheckInCameraSession()
    @State private var stage = Stage.camera
    @State private var shot: CapturedPhoto?
    /// The photo as stored in the app (resized JPEG); `shot.data` is the camera's own file.
    @State private var prepared: Data?
    @State private var shooting = false
    @State private var nickname: String
    @State private var medium = CuttingDefaults.medium
    @State private var saving = false
    @State private var addCount = 0
    @State private var libraryNotice: String?

    init(plant: Plant, household: Household) {
        self.plant = plant
        self.household = household
        _nickname = State(initialValue: CuttingDefaults.name(for: plant))
    }

    var body: some View {
        ZStack {
            switch stage {
            case .camera:
                cameraStage
                    .transition(.opacity)
            case .card:
                cardStage
                    .transition(.opacity)
            case .form:
                CuttingSheet(plant: plant, household: household)
                    .transition(.opacity)
            }
        }
        .background(GH.Palette.paper.ignoresSafeArea())
        .sensoryFeedback(.success, trigger: addCount)
        .task(id: stage == .camera) {
            if stage == .camera { await camera.start() } else { camera.stop() }
        }
        .onDisappear { camera.stop() }
        // No camera here, or access is off: today's form instead.
        .onChange(of: camera.problem) { _, problem in
            if problem != nil, stage == .camera { go(to: .form) }
        }
    }

    private func go(to next: Stage) {
        withAnimation(reduceMotion ? GH.Motion.reduced : GH.Motion.enter) { stage = next }
    }

    // MARK: Camera

    private var cameraStage: some View {
        VStack(alignment: .leading, spacing: GH.Space.m) {
            HStack(alignment: .top, spacing: GH.Space.s) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Take a cutting")
                        .font(.ghRounded(.title2))
                        .foregroundStyle(GH.Palette.ink)
                    Text("Snap the cutting from \(plant.displayName)")
                        .font(.subheadline)
                        .foregroundStyle(GH.Palette.ink2)
                }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                closeButton
            }
            viewfinder
            HStack {
                Button { go(to: .form) } label: {
                    Text("Skip photo")
                        .font(.system(.subheadline, weight: .semibold))
                        .foregroundStyle(GH.Palette.leafInk)
                        .minimumScaleFactor(0.8)
                        .lineLimit(1)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                .frame(width: 96, alignment: .leading)
                Spacer()
                ShutterButton(enabled: camera.isRunning && !shooting) {
                    Task { await shoot() }
                }
                Spacer()
                Button { camera.flip() } label: {
                    Image(systemName: "arrow.triangle.2.circlepath.camera")
                        .font(.system(.title3, weight: .semibold))
                        .foregroundStyle(GH.Palette.ink)
                        .frame(width: 52, height: 52)
                        .background(GH.Palette.surface2, in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(!camera.canFlip || shooting)
                .opacity(camera.canFlip ? 1 : 0.4)
                .frame(width: 96, alignment: .trailing)
                .accessibilityLabel("Flip camera")
            }
            .padding(.horizontal, GH.Space.xs)
        }
        .padding(.horizontal, GH.Space.screen)
        .padding(.top, GH.Space.screen)
        .padding(.bottom, GH.Space.xs)
        // A camera screen keeps its controls in place.
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
    }

    private var viewfinder: some View {
        ZStack {
            Color(red: 0.043, green: 0.067, blue: 0.051) // camera black, the same in both modes
            if camera.isRunning {
                CameraPreview(session: camera.session)
                    .accessibilityLabel("Live camera view")
                    .accessibilityAddTraits(.isImage)
                ThirdsGrid()
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            } else {
                ProgressView().tint(.white)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 220, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
    }

    private var closeButton: some View {
        Button { dismiss() } label: {
            Image(systemName: "xmark")
                .font(.system(.body, weight: .bold))
                .foregroundStyle(GH.Palette.ink)
                .frame(width: 36, height: 36)
                .background(GH.Palette.surface2, in: Circle())
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Close")
    }

    private func shoot() async {
        shooting = true
        defer { shooting = false }
        guard let captured = await camera.capture(),
              let data = ImageTools.preparedJPEG(from: captured.image) else { return }
        // The camera's own file goes to the photo library; the app keeps the prepared copy.
        shot = CapturedPhoto(image: captured.image, data: captured.data)
        prepared = data
        go(to: .card)
    }

    // MARK: Card

    private var cardStage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: GH.Space.m) {
                HStack(alignment: .top) {
                    Text("New cutting")
                        .font(.ghRounded(.title2))
                        .foregroundStyle(GH.Palette.ink)
                        .accessibilityAddTraits(.isHeader)
                    Spacer(minLength: 0)
                    closeButton
                }
                if let image = shot?.image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .frame(height: 260)
                        .clipShape(RoundedRectangle(cornerRadius: GH.Radius.card, style: .continuous))
                        .accessibilityLabel("Photo of the cutting")
                        .accessibilityAddTraits(.isImage)
                }
                TextField("Name", text: $nickname)
                    .font(.ghRounded(.title3, weight: .bold))
                    .padding(GH.Space.s)
                    .frame(minHeight: 48)
                    .background(GH.Palette.surface, in: RoundedRectangle(cornerRadius: GH.Radius.control, style: .continuous))
                    .submitLabel(.done)
                VStack(alignment: .leading, spacing: GH.Space.xs) {
                    Text("Grown in")
                        .font(.ghEyebrow)
                        .textCase(.uppercase)
                        .tracking(0.7)
                        .foregroundStyle(GH.Palette.ink2)
                    GrowMediumPicker(selection: $medium)
                }
                Button(action: add) {
                    Text("Add").frame(maxWidth: .infinity)
                }
                .buttonStyle(.ghProminent)
                .disabled(saving)
                if let libraryNotice {
                    Text(libraryNotice)
                        .font(.footnote)
                        .foregroundStyle(GH.Palette.ink2)
                }
                HStack {
                    Button("Retake") {
                        shot = nil
                        prepared = nil
                        go(to: .camera)
                    }
                    Spacer()
                }
                .font(.system(.subheadline, weight: .semibold))
                .foregroundStyle(GH.Palette.leafInk)
                Text(CuttingDefaults.footer(parent: plant.displayName))
                    .font(.footnote)
                    .foregroundStyle(GH.Palette.ink2)
            }
            .padding(.horizontal, GH.Space.screen)
            .padding(.top, GH.Space.screen)
            .padding(.bottom, GH.Space.l)
            .growIn()
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func add() {
        guard !saving else { return }
        saving = true
        Lineage.takeCutting(from: plant, nickname: nickname, date: .now, medium: medium, photo: prepared,
                            household: household, context: context)
        Persistence.shared.save(context)
        NotificationPlanner.reschedule()
        addCount += 1
        let libraryCopy = shot?.data
        Task {
            // Respects "Save new photos to Photos"; says so once when access is off.
            if let libraryCopy, case .denied(tellUser: true) = await PhotoLibrarySaver.shared.save(libraryCopy) {
                withAnimation(reduceMotion ? GH.Motion.reduced : GH.Motion.enter) { libraryNotice = PhotoLibrarySaver.deniedNotice }
                try? await Task.sleep(for: .seconds(4))
            }
            dismiss()
        }
    }
}

/// What a new cutting starts as, shared by the photo card and the form.
enum CuttingDefaults {
    /// Most cuttings start in water, so that's what's picked.
    static let medium = GrowMedium.water

    static func name(for parent: Plant) -> String { "\(parent.displayName) cutting" }

    static func footer(parent: String) -> String {
        "\(parent) stays as it is. The cutting gets its own tile and reminder, counts from today, and each links to the other in History."
    }
}
