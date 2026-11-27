import SwiftUI

/// What a plant is grown in. Soil is the default (and what a plant with no
/// stored medium reads as); the others are cuttings or houseplants living in
/// water, LECA clay balls or sphagnum moss. Non-soil plants don't get
/// "watered", they get their water changed, on a longer starting schedule.
/// Care is partly vibes, so 21 days is only a starting point: snooze, or keep
/// a new day, to feel it out.
enum GrowMedium: String, CaseIterable, Identifiable {
    case soil, water, leca, sphagnum

    var id: Self { self }

    var label: String {
        switch self {
        case .soil: "Soil"
        case .water: "Water"
        case .leca: "LECA"
        case .sphagnum: "Sphagnum"
        }
    }

    /// The picker's icon.
    var icon: String {
        switch self {
        case .soil: "mountain.2.fill"
        case .water: "drop.fill"
        case .leca: "circle.hexagongrid.fill"
        case .sphagnum: "humidity.fill"
        }
    }

    /// The icon on the watering chip and Care row: a droplet for soil, and a
    /// different one for "change the water" so the two read apart.
    var careIcon: String {
        self == .soil ? "drop.fill" : "arrow.triangle.2.circlepath"
    }

    /// The main reminder's default name.
    var careTaskName: String { self == .soil ? "Water" : "Change water" }

    /// What the Done circle says once it's finished.
    var doneWord: String { self == .soil ? "Watered" : "Water changed" }

    /// Soil follows the species ("Water every 7 days"); the rest start at 21.
    var defaultIntervalDays: Int? { self == .soil ? nil : 21 }

    /// Every name a watering reminder gets by default, to tell a custom one apart.
    static let defaultTaskNames: Set<String> = Set(allCases.map(\.careTaskName))

    /// Sets the plant's medium and renames its watering reminder, but only if
    /// that still has the old medium's default name (a name someone typed is
    /// kept). The interval is never touched: how often is up to them.
    static func apply(_ medium: GrowMedium, to plant: Plant) {
        let old = plant.mediumValue
        plant.mediumValue = medium
        guard old != medium else { return }
        for task in plant.tasks ?? [] where task.isWatering && !task.isArchived {
            if task.name == nil || task.name == old.careTaskName { task.name = medium.careTaskName }
            // Its row's title follows the plant's medium, so rows watching the
            // task redraw even when a custom name meant nothing was renamed.
            task.objectWillChange.send()
        }
    }
}

/// Big tappable icons, one per medium. Reused wherever a medium is chosen.
struct GrowMediumPicker: View {
    @Binding var selection: GrowMedium

    var body: some View {
        HStack(spacing: GH.Space.xs) {
            ForEach(GrowMedium.allCases) { medium in
                let selected = medium == selection
                Button { selection = medium } label: {
                    VStack(spacing: 6) {
                        Image(systemName: medium.icon)
                            .font(.system(size: 28))
                            .frame(height: 32)
                        Text(medium.label)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .foregroundStyle(selected ? GH.Palette.onLeaf : GH.Palette.ink)
                    .frame(maxWidth: .infinity, minHeight: 72)
                    .background(selected ? GH.Palette.leaf : GH.Palette.surface2,
                                in: RoundedRectangle(cornerRadius: GH.Radius.chip, style: .continuous))
                    .contentShape(Rectangle())
                }
                // A plain style so each icon is its own target inside a Form row.
                .buttonStyle(.plain)
                .accessibilityLabel(medium.label)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .animation(.easeOut(duration: 0.12), value: selection)
    }
}
