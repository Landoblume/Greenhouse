import CoreData
import SwiftUI

/// A plant's photos full screen. It grows out of the strip thumbnail that was
/// tapped (and back into it when closed), pages left and right through every
/// photo, and closes with a drag down. The ••• menu edits whichever photo is
/// showing. Reduce Motion: it crossfades in and out instead.
///
/// Presented as a clear full-screen cover without the system slide, so it
/// sits above the floating tab bar while the page stays visible behind it.
struct PhotoViewer: View {
    @ObservedObject var plant: Plant
    /// Where the strip's thumbnails are on screen.
    let frames: PhotoFrameStore
    /// The photo showing. The page hides its thumbnail while the viewer is up.
    @Binding var current: NSManagedObjectID?
    /// Takes the cover down (without animation; the viewer has animated itself out).
    let onClose: () -> Void

    @Environment(\.managedObjectContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var space
    @State private var phase: Phase = .thumb
    @State private var appeared = false
    @State private var dragX: CGFloat = 0
    @State private var drag: CGSize = .zero
    @State private var dragAxis: Axis?
    @State private var closing = false
    @State private var editing = false
    @State private var cropping = false
    @State private var confirmingDelete = false

    private enum Phase {
        /// Sitting where the tapped thumbnail is.
        case thumb
        /// Full size, on its own: the end points of the grow/shrink.
        case full
        /// Full size inside the pager.
        case paging
    }

    /// Same order as the plant page's timeline: oldest first.
    private var timeline: [Lineage.TimelinePhoto] { Lineage.timeline(for: plant) }

    var body: some View {
        let items = timeline
        let index = items.firstIndex { $0.photo.objectID == current } ?? 0
        ZStack {
            GH.PlantPage.viewerBackground
                .opacity(phase == .thumb ? 0 : max(0, 1 - drag.height / 400))
                .ignoresSafeArea()
            GeometryReader { geo in
                imageLayer(items: items, index: index, geo: geo)
            }
            .ignoresSafeArea()
            if !items.isEmpty {
                chrome(items: items, index: index)
                    .opacity(phase == .paging && drag == .zero && !closing ? 1 : 0)
                    .animation(.easeOut(duration: 0.2), value: phase == .paging && drag == .zero && !closing)
            }
        }
        .opacity(appeared ? 1 : 0)
        .onAppear(perform: open)
        .onChange(of: items.isEmpty) { _, empty in
            if empty { fadeOut() }
        }
        .sheet(isPresented: $editing) {
            if let photo = items.viewerItem(at: index)?.photo { EditPhotoSheet(photo: photo, plant: plant) }
        }
        .fullScreenCover(isPresented: $cropping) {
            if let photo = items.viewerItem(at: index)?.photo, let data = photo.imageData, let image = UIImage(data: data) {
                CropView(image: image) { cropped in
                    PlantPhotos.replaceImage(of: photo, with: cropped)
                    Persistence.shared.save(context)
                }
            }
        }
        .confirmationDialog("Delete this photo?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { delete(items: items, index: index) }
        } message: {
            Text("It's removed from both phones.")
        }
        .redrawsOnRelatedChanges(plant)
    }

    // MARK: Image layer

    @ViewBuilder
    private func imageLayer(items: [Lineage.TimelinePhoto], index: Int, geo: GeometryProxy) -> some View {
        let screen = CGRect(origin: .zero, size: geo.size)
        let origin = geo.frame(in: .global).origin
        if let item = items.viewerItem(at: index) {
            if phase == .paging {
                pager(items: items, index: index, screen: screen)
            } else {
                let full = fittedRect(for: item.photo, in: screen)
                let thumb = frames.frames[item.photo.objectID].map { $0.offsetBy(dx: -origin.x, dy: -origin.y) } ?? full
                ZStack {
                    // Two slots; the photo follows whichever is the source, so
                    // switching it animates the photo between them.
                    Color.clear
                        .frame(width: thumb.width, height: thumb.height)
                        .position(x: thumb.midX, y: thumb.midY)
                        .matchedGeometryEffect(id: "slot", in: space, isSource: phase == .thumb)
                    Color.clear
                        .frame(width: full.width, height: full.height)
                        .position(x: full.midX, y: full.midY)
                        .matchedGeometryEffect(id: "slot", in: space, isSource: phase != .thumb)
                    ViewerPhoto(photo: item.photo, radius: phase == .thumb ? GH.Radius.chip : 0)
                        .matchedGeometryEffect(id: "slot", in: space, isSource: false)
                        .offset(drag)
                        .scaleEffect(dragScale)
                }
                .allowsHitTesting(false)
            }
        }
    }

    private func pager(items: [Lineage.TimelinePhoto], index: Int, screen: CGRect) -> some View {
        let gap: CGFloat = 16
        let window = max(0, index - 1)...min(items.count - 1, index + 1)
        return ZStack {
            ForEach(items[window], id: \.photo.objectID) { item in
                let position = items.firstIndex { $0.photo.objectID == item.photo.objectID } ?? index
                let rect = fittedRect(for: item.photo, in: screen)
                ViewerPhoto(photo: item.photo, radius: 0)
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
                    .offset(x: CGFloat(position - index) * (screen.width + gap) + dragX)
                    .transition(.identity)
            }
        }
        .frame(width: screen.width, height: screen.height)
        .offset(drag)
        .scaleEffect(dragScale)
        .contentShape(Rectangle())
        .gesture(dragGesture(items: items, index: index, width: screen.width))
        .accessibilityElement()
        .accessibilityLabel(pagerLabel(items: items, index: index))
        .accessibilityAddTraits(.isImage)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: page(to: index + 1, items: items)
            case .decrement: page(to: index - 1, items: items)
            @unknown default: break
            }
        }
        .accessibilityAction(.escape) { close() }
    }

    /// "Photo from Nov 14, 2026, 3 of 12. New leaf."
    private func pagerLabel(items: [Lineage.TimelinePhoto], index: Int) -> String {
        guard let photo = items.viewerItem(at: index)?.photo else { return "Photo" }
        var text = "Photo from \(photo.takenAt.map(Lineage.format) ?? "an unknown date"), \(index + 1) of \(items.count)"
        if let caption = photo.caption { text += ". \(caption)" }
        return text
    }

    /// Shrinks a little as it's dragged down, like the system photo viewer.
    private var dragScale: CGFloat { 1 - min(max(drag.height, 0) / 1600, 0.25) }

    private func dragGesture(items: [Lineage.TimelinePhoto], index: Int, width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                guard !closing else { return }
                if dragAxis == nil {
                    dragAxis = abs(value.translation.width) > abs(value.translation.height) ? .horizontal : .vertical
                }
                if dragAxis == .horizontal {
                    var x = value.translation.width
                    // Resist past the first and last photo.
                    if (index == 0 && x > 0) || (index == items.count - 1 && x < 0) { x /= 3 }
                    dragX = x
                } else {
                    drag = value.translation
                }
            }
            .onEnded { value in
                defer { dragAxis = nil }
                guard !closing else { return }
                if dragAxis == .horizontal {
                    let predicted = value.predictedEndTranslation.width
                    var target = index
                    if predicted < -width / 2 { target += 1 } else if predicted > width / 2 { target -= 1 }
                    page(to: target, items: items)
                } else if value.translation.height > 120 || value.predictedEndTranslation.height > 320 {
                    close()
                } else {
                    withAnimation(reduceMotion ? GH.Motion.reduced : GH.Motion.hero) { drag = .zero }
                }
            }
    }

    private func page(to target: Int, items: [Lineage.TimelinePhoto]) {
        let clamped = min(max(target, 0), items.count - 1)
        withAnimation(reduceMotion ? GH.Motion.reduced : GH.Motion.hero) {
            if items.indices.contains(clamped) { current = items[clamped].photo.objectID }
            dragX = 0
        }
    }

    /// The photo's own shape, as large as fits on screen.
    private func fittedRect(for photo: Photo, in screen: CGRect) -> CGRect {
        let size = ThumbnailCache.shared.image(for: photo, maxPixel: 2048)?.size ?? CGSize(width: 1, height: 1)
        let aspect = size.height > 0 ? size.width / size.height : 1
        var width = screen.width
        var height = width / aspect
        if height > screen.height {
            height = screen.height
            width = height * aspect
        }
        return CGRect(x: screen.midX - width / 2, y: screen.midY - height / 2, width: width, height: height)
    }

    // MARK: Opening and closing

    private func open() {
        if !reduceMotion, let id = current, frames.frames[id] != nil {
            phase = .thumb
            appeared = true
            DispatchQueue.main.async {
                withAnimation(GH.Motion.hero) {
                    phase = .full
                } completion: {
                    phase = .paging
                }
            }
        } else {
            phase = .paging
            withAnimation(reduceMotion ? GH.Motion.reduced : .easeOut(duration: 0.25)) { appeared = true }
        }
    }

    /// Back into its thumbnail if that's on the page, otherwise a fade.
    private func close() {
        guard !closing else { return }
        closing = true
        if !reduceMotion, let id = current, frames.frames[id] != nil {
            phase = .full
            DispatchQueue.main.async {
                withAnimation(GH.Motion.hero) {
                    phase = .thumb
                    drag = .zero
                } completion: {
                    onClose()
                }
            }
        } else {
            fadeOut()
        }
    }

    private func fadeOut() {
        closing = true
        withAnimation(GH.Motion.reduced) { appeared = false } completion: { onClose() }
    }

    private func delete(items: [Lineage.TimelinePhoto], index: Int) {
        guard let photo = items.viewerItem(at: index)?.photo else { return }
        // Move to a neighbour first, so the viewer never shows a deleted photo.
        let neighbour = items.viewerItem(at: index + 1) ?? items.viewerItem(at: index - 1)
        if let neighbour {
            current = neighbour.photo.objectID
        } else {
            fadeOut()
        }
        PlantPhotos.delete(photo, context: context)
        Persistence.shared.save(context)
    }

    // MARK: Chrome

    private func chrome(items: [Lineage.TimelinePhoto], index: Int) -> some View {
        let item = items.viewerItem(at: index)
        return VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button(action: close) { GlassCircleLabel(systemImage: "xmark") }
                    .accessibilityLabel("Close")
                Spacer(minLength: 0)
                if let photo = item?.photo {
                    Menu {
                        Button { editing = true } label: { Label("Edit date, caption or milestone", systemImage: "pencil") }
                        Button { cropping = true } label: { Label("Crop photo", systemImage: "crop") }
                        if !PlantPhotos.isCover(photo, of: plant) {
                            Button {
                                PlantPhotos.setCover(photo, of: plant)
                                Persistence.shared.save(context)
                            } label: { Label("Use as main photo", systemImage: "star") }
                        }
                        Button(role: .destructive) { confirmingDelete = true } label: { Label("Delete photo", systemImage: "trash") }
                    } label: {
                        GlassCircleLabel(systemImage: "ellipsis")
                    }
                    .accessibilityLabel("Photo options")
                }
            }
            .buttonStyle(.plain)
            .overlay {
                VStack(spacing: 0) {
                    Text(item?.photo.takenAt.map(Lineage.format) ?? "Photo")
                        .font(.ghRounded(.headline))
                    Text("\(index + 1) of \(items.count)")
                        .font(.caption)
                        .foregroundStyle(GH.PlantPage.viewerInk2)
                }
                .foregroundStyle(GH.PlantPage.viewerInk)
                .padding(.horizontal, 60)
                .lineLimit(1)
                .allowsHitTesting(false)
            }
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
            .padding(.horizontal, GH.Space.m)
            .padding(.top, GH.Space.xs)
            Spacer(minLength: 0)
            if let item {
                ViewerCaption(photo: item.photo, plant: plant, source: item.source)
            }
        }
    }
}

/// The caption, milestone and origin under a full-screen photo.
private struct ViewerCaption: View {
    @ObservedObject var photo: Photo
    let plant: Plant
    let source: Plant

    var body: some View {
        let lines = photo.caption != nil || photo.milestone != nil || PlantPhotos.isCover(photo, of: plant) || source != plant
        if lines {
            VStack(alignment: .leading, spacing: GH.Space.xxs) {
                if let caption = photo.caption {
                    Text(caption)
                        .font(.body)
                        .foregroundStyle(GH.PlantPage.viewerInk)
                        .lineLimit(4)
                }
                if let milestone = photo.milestone {
                    Label(milestone.title ?? "Milestone", systemImage: "flag.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(GH.PlantPage.viewerInk)
                }
                if PlantPhotos.isCover(photo, of: plant) {
                    Label("Main photo", systemImage: "star.fill")
                        .font(.caption)
                        .foregroundStyle(GH.PlantPage.viewerInk2)
                }
                if source != plant {
                    Text("From \(source.displayName) (acq. \(source.acquiredDate.map(Lineage.format) ?? "?"))")
                        .font(.caption)
                        .foregroundStyle(GH.PlantPage.viewerInk2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, GH.Space.screen)
            .padding(.top, GH.Space.xl)
            .padding(.bottom, GH.Space.m)
            .background {
                LinearGradient(colors: [GH.PlantPage.viewerBackground.opacity(0), GH.PlantPage.viewerBackground.opacity(0.85)],
                               startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea(edges: .bottom)
            }
        }
    }
}

/// A photo filling whatever frame it's given, cropped to it.
private struct ViewerPhoto: View {
    let photo: Photo
    let radius: CGFloat

    var body: some View {
        Color.clear
            .overlay { PlantPhotoView(photo: photo, maxPixel: 2048) }
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

private extension Array where Element == Lineage.TimelinePhoto {
    func viewerItem(at index: Int) -> Lineage.TimelinePhoto? {
        indices.contains(index) ? self[index] : nil
    }
}
