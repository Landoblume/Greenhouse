import CoreData
import SwiftUI

/// One plant in the Plants-tab masonry: a 28-pt rounded photo with a watering
/// chip, then the nickname and Latin name.
struct PlantTile: View {
    @ObservedObject var plant: Plant
    /// Set on the Plants tab, where tapping the tile morphs it into the page.
    var morph: TileMorphSource? = nil
    /// Off when the Plants tab's "Show care badges" is turned off.
    var showsCareBadge = true
    /// The tile photo's decode size; the iOS 17 morph's flying copy uses it
    /// too, to hit the same cached picture.
    static let photoMaxPixel: CGFloat = 600
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var photoHeight: CGFloat { PlantTileStyle.photoHeight(forID: plant.uuid) }
    private var isCombined: Bool { plant.producedBy?.kindValue == .staple }
    private var inProject: Bool { Plans.isInActiveProject(plant) }

    var body: some View {
        VStack(alignment: .leading, spacing: GH.Space.xs) {
            photo
            VStack(alignment: .leading, spacing: 0) {
                Text(plant.displayName)
                    .font(.ghRounded(.headline))
                    .foregroundStyle(GH.Palette.ink)
                    .lineLimit(2)
                if let latin = plant.scientificName, !latin.isEmpty {
                    Text(latin)
                        .font(.footnote)
                        .italic()
                        .foregroundStyle(GH.Palette.ink2)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 6)
        }
        // Only the tile itself opens the plant, not the gutter beside it.
        .contentShape(RoundedRectangle(cornerRadius: GH.Radius.tile, style: .continuous))
        .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: GH.Radius.tile, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Opens the plant")
        .redrawsOnRelatedChanges(plant)
        .redrawsOnWateringChanges(plant)
    }

    /// "Monty, Monstera deliciosa, watering due today, Combined, in a project".
    private var accessibilityLabel: String {
        var parts = [plant.displayName]
        if let latin = plant.scientificName, !latin.isEmpty, latin != plant.displayName { parts.append(latin) }
        if let watering = plant.wateringTask, let status = CareSchedule.status(of: watering) {
            parts.append((plant.mediumValue == .soil ? "watering " : plant.mediumValue.careTaskName.lowercased() + " ") + status.label.prefix(1).lowercased() + status.label.dropFirst())
        }
        if isCombined { parts.append("Combined") }
        if inProject { parts.append("in a project") }
        return parts.joined(separator: ", ")
    }

    private var photo: some View {
        Color.clear
            .frame(height: photoHeight)
            .frame(maxWidth: .infinity)
            .background(GH.Palette.leafSoft)
            .overlay {
                // The picture is 24 pt taller than its frame so it can drift
                // -12...+12 pt as the tile crosses the screen without ever
                // showing an edge. Reduce Motion keeps it still.
                let drift = !reduceMotion
                TilePhotoView(photo: PlantPhotos.cover(for: plant), maxPixel: Self.photoMaxPixel)
                    .frame(height: photoHeight + 24)
                    .visualEffect { content, proxy in
                        content.offset(y: drift ? Self.parallax(proxy) : 0)
                    }
                    .accessibilityHidden(true)
            }
            .clipShape(RoundedRectangle(cornerRadius: GH.Radius.tile, style: .continuous))
            .overlay(alignment: .topLeading) {
                if showsCareBadge, let watering = plant.wateringTask {
                    WateringChipView(task: watering, medium: plant.mediumValue).padding(10)
                        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                }
            }
            .overlay(alignment: .bottom) {
                if inProject || isCombined {
                    HStack(spacing: GH.Space.xs) {
                        if inProject {
                            Image(systemName: "hammer.fill")
                                .font(.caption)
                                .foregroundStyle(GH.Palette.onLeaf)
                                .frame(width: 28, height: 28)
                                .background(GH.Palette.leaf, in: Circle())
                        }
                        Spacer(minLength: 0)
                        if isCombined { combinedBadge.layoutPriority(1) }
                    }
                    .padding(10)
                    // Badges on the photo stop growing at the largest regular
                    // size; the tile's name and VoiceOver label carry the rest.
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                }
            }
            .overlay {
                if inProject {
                    RoundedRectangle(cornerRadius: GH.Radius.tile, style: .continuous)
                        .strokeBorder(GH.Palette.leaf, lineWidth: 3)
                }
            }
            .tileMorphSource(id: plant.objectID, in: morph?.namespace)
            .modifier(TileFrameReporter(id: plant.objectID, store: morph?.frames))
    }

    /// "Combined" with its icon, or the icon alone when the tile is too narrow.
    private var combinedBadge: some View {
        ViewThatFits(in: .horizontal) {
            Label("Combined", systemImage: "arrow.triangle.merge")
                .font(.caption.weight(.bold))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 9)
                .frame(minHeight: 28)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: GH.Radius.chip, style: .continuous))
            Image(systemName: "arrow.triangle.merge")
                .font(.caption.weight(.bold))
                .frame(width: 28, height: 28)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: GH.Radius.chip, style: .continuous))
        }
        .foregroundStyle(GH.Palette.ink)
    }

    /// -12 at the top of the screen to +12 at the bottom, from the tile's
    /// middle relative to the scroll view.
    nonisolated private static func parallax(_ proxy: GeometryProxy) -> CGFloat {
        let viewport = proxy.bounds(of: .scrollView)?.height ?? 0
        guard viewport > 0 else { return 0 }
        let middle = proxy.frame(in: .scrollView).midY
        let progress = min(1, max(0, middle / viewport))
        return (progress - 0.5) * 24
    }
}

/// Keeps the photo's on-screen frame in the store, for the iOS 17 morph.
/// Without a store it measures nothing.
private struct TileFrameReporter: ViewModifier {
    let id: NSManagedObjectID
    let store: TileFrameStore?

    func body(content: Content) -> some View {
        if let store {
            content.onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { store.frames[id] = $0 }
        } else {
            content
        }
    }
}

/// "Water today" (sky), "In 4 days" (leaf) or "Overdue · 1 day" (terracotta),
/// falling back to "207d" / "Due" / "in 3d" on a narrow tile so it never
/// truncates. Watches the watering task, so it updates the moment someone waters.
struct WateringChipView: View {
    @ObservedObject var task: CareTask
    var medium: GrowMedium = .soil

    var body: some View {
        if let chip = WateringChip.make(for: CareSchedule.status(of: task), medium: medium) {
            let colors = Self.colors(chip.tone)
            ViewThatFits(in: .horizontal) {
                label(chip.label, icon: chip.icon)
                label(chip.shortLabel, icon: chip.icon)
            }
            .foregroundStyle(colors.ink)
            .background(colors.fill, in: RoundedRectangle(cornerRadius: GH.Radius.chip, style: .continuous))
            .accessibilityHidden(true)
        }
    }

    private func label(_ text: String, icon: String) -> some View {
        Label(text, systemImage: icon)
            .font(.caption.weight(.bold))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 9)
            .frame(minHeight: 26)
    }

    private static func colors(_ tone: WateringChip.Tone) -> (fill: Color, ink: Color) {
        switch tone {
        case .due: (GH.Palette.skySoft, GH.Palette.skyInk)
        case .later: (GH.Palette.leafSoft, GH.Palette.leafInk)
        case .overdue: (GH.Palette.terraSoft, GH.Palette.terraInk)
        }
    }
}

extension View {
    /// The tile's spoken watering status comes from the watering task and its
    /// logs, which the plant doesn't observe. This redraws it when one changes
    /// (marked done here, or a log arriving from the other phone).
    func redrawsOnWateringChanges(_ plant: Plant) -> some View {
        onReceive(ContextChanges.publisher(for: plant.managedObjectContext)) { note in
            if ContextChanges.touches(note, in: plant.managedObjectContext, where: { $0 is CareLog || $0 is CareTask }) {
                plant.objectWillChange.send()
            }
        }
    }
}
