@preconcurrency import AVFoundation
import PhotosUI
import SwiftUI

/// The camera a photo check-in opens: framed for matching the last shot
/// (rule-of-thirds grid, the last photo as a ghost), saving straight to the
/// plant's timeline. Add photo (AddPhotoSheet) stays the general way in.
struct CheckInCameraView: View {
    @ObservedObject var plant: Plant
    let household: Household
    /// When the check-in arrived, if it came from a notification. A photo of
    /// the plant since that day means someone already answered it.
    var firedAt: Date? = nil

    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(SettingsKey.myName) private var myName = ""
    @StateObject private var camera = CheckInCameraSession()
    @State private var ghostOn = true
    @State private var takeAnother = false
    @State private var saving = false
    @State private var savedCount = 0
    @State private var toast: String?
    @State private var libraryNotice: String?
    @State private var libraryItem: PhotosPickerItem?

    private var latest: Lineage.TimelinePhoto? { Lineage.timeline(for: plant).last }

    private var answer: Photo? {
        guard let firedAt, !takeAnother, savedCount == 0 else { return nil }
        return NotificationPlanner.photoAnswering(checkInOn: firedAt, plant: plant)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: GH.Space.m) {
            header
            if let answer {
                AlreadySnappedCard(photo: answer, plantName: plant.displayName) {
                    withAnimation(reduceMotion ? GH.Motion.reduced : GH.Motion.enter) { takeAnother = true }
                } onDone: { dismiss() }
                .growIn()
                Spacer(minLength: 0)
            } else {
                viewfinder
                controls
                Text(CheckInText.footer(plantName: plant.displayName, by: myName))
                    .font(.footnote)
                    .foregroundStyle(GH.Palette.ink2)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, GH.Space.screen)
        .padding(.top, GH.Space.screen)
        .padding(.bottom, GH.Space.xs)
        // A camera screen keeps its controls in place; past this size the
        // viewfinder would have no room left.
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .background(GH.Palette.paper.ignoresSafeArea())
        .overlay(alignment: .top) { toastView }
        .sensoryFeedback(.success, trigger: savedCount)
        .task(id: answer == nil) {
            if answer == nil { await camera.start() } else { camera.stop() }
        }
        .onDisappear { camera.stop() }
        .onChange(of: libraryItem) { _, item in
            Task { await saveLibraryPick(item) }
        }
    }

    // MARK: Parts

    private var header: some View {
        HStack(alignment: .top, spacing: GH.Space.s) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Check in on \(plant.displayName)")
                    .font(.ghRounded(.title2))
                    .foregroundStyle(GH.Palette.ink)
                Text(CheckInText.lastPhotoLine(takenAt: latest?.photo.takenAt, now: .now))
                    .font(.subheadline)
                    .foregroundStyle(GH.Palette.ink2)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
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
    }

    private var viewfinder: some View {
        ZStack {
            Color(red: 0.043, green: 0.067, blue: 0.051) // camera black, the same in both modes
            if camera.isRunning {
                CameraPreview(session: camera.session)
                    .accessibilityLabel("Live camera view of \(plant.displayName)")
                    .accessibilityAddTraits(.isImage)
                if ghostOn, let ghost = ghostImage {
                    Image(uiImage: ghost)
                        .resizable()
                        .scaledToFill()
                        .opacity(0.35)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                        .transition(.opacity)
                }
                ThirdsGrid()
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            } else if let problem = camera.problem {
                NoCameraFallback(problem: problem, libraryItem: $libraryItem)
            } else {
                ProgressView().tint(.white)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 220, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay(alignment: .topLeading) {
            if camera.isRunning, ghostImage != nil, let date = latest?.photo.takenAt {
                GhostToggle(isOn: $ghostOn, date: date)
                    .padding(GH.Space.s)
            }
        }
    }

    private var controls: some View {
        HStack {
            LastThumbnail(photo: latest?.photo)
            Spacer()
            ShutterButton(enabled: camera.isRunning && !saving) {
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
            .disabled(!camera.canFlip || saving)
            .opacity(camera.canFlip ? 1 : 0.4)
            .accessibilityLabel("Flip camera")
        }
        .padding(.horizontal, GH.Space.xs)
    }

    @ViewBuilder
    private var toastView: some View {
        if let toast {
            VStack(alignment: .leading, spacing: 4) {
                Text(toast)
                    .font(.ghRounded(.headline, weight: .bold))
                    .foregroundStyle(GH.Palette.leafInk)
                if let libraryNotice {
                    Text(libraryNotice)
                        .font(.footnote)
                        .foregroundStyle(GH.Palette.ink2)
                }
            }
            .padding(.horizontal, GH.Space.m)
            .padding(.vertical, GH.Space.s)
            .background(GH.Palette.leafSoft, in: RoundedRectangle(cornerRadius: GH.Radius.control, style: .continuous))
            .shadow(color: .black.opacity(0.12), radius: 14, y: 8)
            .padding(.horizontal, GH.Space.screen)
            .padding(.top, GH.Space.xl)
            .transition(reduceMotion ? .opacity : .scale(scale: 0.9).combined(with: .opacity))
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.updatesFrequently)
        }
    }

    private var ghostImage: UIImage? {
        latest.flatMap { ThumbnailCache.shared.image(for: $0.photo, maxPixel: 1200) }
    }

    // MARK: Saving

    private func shoot() async {
        saving = true
        guard let shot = await camera.capture() else {
            saving = false
            return
        }
        await save(shot.image, takenAt: .now, libraryCopy: shot.data)
    }

    /// The simulator, or camera access off: a library photo answers the
    /// check-in too (dated from the photo, and not copied back to Photos).
    private func saveLibraryPick(_ item: PhotosPickerItem?) async {
        guard let item, let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else { return }
        saving = true
        await save(image, takenAt: PlantPhotos.captureDate(from: data) ?? .now, libraryCopy: nil)
    }

    private func save(_ image: UIImage, takenAt: Date, libraryCopy: Data?) async {
        guard let data = ImageTools.preparedJPEG(from: image) else {
            saving = false
            return
        }
        PlantFactory.addPhoto(data, takenAt: takenAt, to: plant, household: household, context: context)
        Persistence.shared.save(context)
        savedCount += 1
        withAnimation(reduceMotion ? GH.Motion.reduced : GH.Motion.press) {
            toast = "Got it! \(plant.displayName) is looking good 🌿"
        }
        UIAccessibility.post(notification: .announcement, argument: toast)
        if let libraryCopy, case .denied(tellUser: true) = await PhotoLibrarySaver.shared.save(libraryCopy) {
            withAnimation(reduceMotion ? GH.Motion.reduced : GH.Motion.enter) { libraryNotice = PhotoLibrarySaver.deniedNotice }
        }
        try? await Task.sleep(for: .seconds(libraryNotice == nil ? 1.6 : 4))
        dismiss()
    }
}

// MARK: - Wording

enum CheckInText {
    /// "Last photo Aug 30 · 83 days ago", "Last photo today", or "No photos yet".
    static func lastPhotoLine(takenAt: Date?, now: Date, calendar: Calendar = .current) -> String {
        guard let takenAt else { return "No photos yet" }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: takenAt), to: calendar.startOfDay(for: now)).day ?? 0
        switch days {
        case ...0: return "Last photo today"
        case 1: return "Last photo yesterday"
        default: return "Last photo \(shortDate(takenAt, now: now, calendar: calendar)) · \(days) days ago"
        }
    }

    /// "Aug 30", or "Aug 30, 2025" when it's not this year.
    static func shortDate(_ date: Date, now: Date, calendar: Calendar = .current) -> String {
        var style = Date.FormatStyle.dateTime.month(.abbreviated).day()
        style.calendar = calendar
        style.timeZone = calendar.timeZone
        if calendar.component(.year, from: date) != calendar.component(.year, from: now) { style = style.year() }
        return date.formatted(style)
    }

    /// "Saves to Pip's timeline · by Sam"
    static func footer(plantName: String, by name: String) -> String {
        let possessive = plantName.hasSuffix("s") ? "\(plantName)’" : "\(plantName)’s"
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "Saves to \(possessive) timeline" : "Saves to \(possessive) timeline · by \(trimmed)"
    }
}

// MARK: - Pieces

/// Two lines each way, a third of the way in.
struct ThirdsGrid: View {
    var body: some View {
        Canvas { context, size in
            var path = Path()
            for fraction in [1.0 / 3, 2.0 / 3] {
                path.move(to: CGPoint(x: size.width * fraction, y: 0))
                path.addLine(to: CGPoint(x: size.width * fraction, y: size.height))
                path.move(to: CGPoint(x: 0, y: size.height * fraction))
                path.addLine(to: CGPoint(x: size.width, y: size.height * fraction))
            }
            context.stroke(path, with: .color(.white.opacity(0.18)), lineWidth: 1)
        }
    }
}

private struct GhostToggle: View {
    @Binding var isOn: Bool
    let date: Date
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            withAnimation(reduceMotion ? GH.Motion.reduced : GH.Motion.enter) { isOn.toggle() }
        } label: {
            Label("Ghost of \(CheckInText.shortDate(date, now: .now))",
                  systemImage: isOn ? "square.on.square.dashed" : "square.dashed")
                .font(.system(.footnote, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, GH.Space.s)
                .frame(minHeight: 44)
                .background(.ultraThinMaterial.opacity(isOn ? 1 : 0.6), in: Capsule())
                .environment(\.colorScheme, .dark)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Shows the last photo faintly over the camera, to match the framing")
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

private struct LastThumbnail: View {
    let photo: Photo?

    var body: some View {
        Group {
            if let photo, let image = ThumbnailCache.shared.image(for: photo, maxPixel: 160) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "leaf")
                    .font(.title3)
                    .foregroundStyle(GH.Palette.leafInk)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(GH.Palette.leafSoft)
            }
        }
        .frame(width: 52, height: 52)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement()
        .accessibilityLabel(photo == nil ? "No previous photo" : "Previous photo")
    }
}

/// A leaf ring around a leaf disc; squashes a little when pressed.
struct ShutterButton: View {
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(GH.Palette.leaf)
                .padding(9)
                .overlay(Circle().strokeBorder(GH.Palette.leaf, lineWidth: 4))
                .frame(width: 80, height: 80)
        }
        .buttonStyle(ShutterPress())
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
        .accessibilityLabel("Take photo")
    }

    private struct ShutterPress: ButtonStyle {
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .scaleEffect(configuration.isPressed && !reduceMotion ? 0.9 : 1)
                .animation(GH.Motion.press, value: configuration.isPressed)
        }
    }
}

/// What shows in the viewfinder when there's no camera to use.
private struct NoCameraFallback: View {
    let problem: String
    @Binding var libraryItem: PhotosPickerItem?

    var body: some View {
        VStack(spacing: GH.Space.m) {
            Image(systemName: "camera.badge.ellipsis")
                .font(.system(.largeTitle))
                .foregroundStyle(.white.opacity(0.8))
                .accessibilityHidden(true)
            Text(problem)
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
            PhotosPicker(selection: $libraryItem, matching: .images) {
                Label("Choose from library", systemImage: "photo.on.rectangle")
                    .font(.system(.subheadline, weight: .semibold))
                    .padding(.horizontal, GH.Space.m)
                    .frame(minHeight: 44)
                    .background(.white.opacity(0.18), in: Capsule())
                    .foregroundStyle(.white)
            }
        }
        .padding(GH.Space.l)
    }
}

/// UX#7: the other phone already took one since the check-in arrived.
private struct AlreadySnappedCard: View {
    @ObservedObject var photo: Photo
    let plantName: String
    let onTakeAnother: () -> Void
    let onDone: () -> Void

    private var isToday: Bool { photo.takenAt.map(Calendar.current.isDateInToday) ?? false }

    var body: some View {
        VStack(spacing: GH.Space.m) {
            if let image = ThumbnailCache.shared.image(for: photo, maxPixel: 600) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 160, height: 160)
                    .clipShape(RoundedRectangle(cornerRadius: GH.Radius.card, style: .continuous))
                    .accessibilityLabel("The new photo of \(plantName)")
            }
            Text(isToday ? "Already snapped today 💚" : "Already snapped \(CheckInText.shortDate(photo.takenAt ?? .now, now: .now)) 💚")
                .font(.ghRounded(.title3))
                .foregroundStyle(GH.Palette.leafInk)
                .multilineTextAlignment(.center)
            Text("\(plantName) has a fresh photo on its timeline, so this check-in is done.")
                .font(.subheadline)
                .foregroundStyle(GH.Palette.ink2)
                .multilineTextAlignment(.center)
            Button("Done", action: onDone)
                .buttonStyle(.ghProminent)
            Button("Take another anyway", action: onTakeAnother)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(GH.Palette.leafInk)
                .frame(minHeight: 44)
        }
        .padding(GH.Space.l)
        .frame(maxWidth: .infinity)
        .background(GH.Palette.leafSoft, in: RoundedRectangle(cornerRadius: GH.Radius.card, style: .continuous))
    }
}
