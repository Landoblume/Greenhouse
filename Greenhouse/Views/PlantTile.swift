import SwiftUI

/// One plant in the Plants-tab masonry: a 28-pt rounded photo with a watering
/// chip, then the nickname and Latin name.
struct PlantTile: View {
    @ObservedObject var plant: Plant
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
        .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: GH.Radius.tile, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the plant")
        .redrawsOnRelatedChanges(plant)
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
                PlantPhotoView(photo: PlantPhotos.cover(for: plant), maxPixel: 600)
                    .frame(height: photoHeight + 24)
                    .visualEffect { content, proxy in
                        content.offset(y: drift ? Self.parallax(proxy) : 0)
                    }
                    .accessibilityHidden(true)
            }
            .clipShape(RoundedRectangle(cornerRadius: GH.Radius.tile, style: .continuous))
            .overlay(alignment: .topLeading) {
                if let watering = plant.wateringTask {
                    WateringChipView(task: watering).padding(10)
                }
            }
            .overlay(alignment: .topTrailing) {
                if inProject {
                    Image(systemName: "hammer.fill")
                        .font(.caption)
                        .foregroundStyle(GH.Palette.onLeaf)
                        .frame(width: 28, height: 28)
                        .background(GH.Palette.leaf, in: Circle())
                        .padding(10)
                        .accessibilityLabel("Part of a project in progress")
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if isCombined {
                    Label("Combined", systemImage: "arrow.triangle.merge")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(GH.Palette.ink)
                        .padding(.horizontal, 9)
                        .frame(minHeight: 26)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: GH.Radius.chip, style: .continuous))
                        .padding(10)
                }
            }
            .overlay {
                if inProject {
                    RoundedRectangle(cornerRadius: GH.Radius.tile, style: .continuous)
                        .strokeBorder(GH.Palette.leaf, lineWidth: 3)
                }
            }
    }

    /// -12 at the top of the screen to +12 at the bottom, from the tile's
    /// middle relative to the scroll view.
    private static func parallax(_ proxy: GeometryProxy) -> CGFloat {
        let viewport = proxy.bounds(of: .scrollView)?.height ?? 0
        guard viewport > 0 else { return 0 }
        let middle = proxy.frame(in: .scrollView).midY
        let progress = min(1, max(0, middle / viewport))
        return (progress - 0.5) * 24
    }
}

/// "Water today" (sky), "In 4 days" (leaf) or "Overdue · 1 day" (terracotta).
/// Watches the watering task, so it updates the moment someone waters.
struct WateringChipView: View {
    @ObservedObject var task: CareTask

    var body: some View {
        if let chip = WateringChip.make(for: CareSchedule.status(of: task)) {
            let colors = Self.colors(chip.tone)
            Label(chip.label, systemImage: "drop.fill")
                .font(.caption.weight(.bold))
                .foregroundStyle(colors.ink)
                .padding(.horizontal, 9)
                .frame(minHeight: 26)
                .background(colors.fill, in: RoundedRectangle(cornerRadius: GH.Radius.chip, style: .continuous))
        }
    }

    private static func colors(_ tone: WateringChip.Tone) -> (fill: Color, ink: Color) {
        switch tone {
        case .due: (GH.Palette.skySoft, GH.Palette.skyInk)
        case .later: (GH.Palette.leafSoft, GH.Palette.leafInk)
        case .overdue: (GH.Palette.terraSoft, GH.Palette.terraInk)
        }
    }
}
