import SwiftUI

/// "On this day / 1 year ago today": an old photo of one of your plants with a
/// sepia wash. Tapping opens that plant.
struct OnThisDayCard: View {
    let plant: Plant
    let photo: Photo
    let yearsAgo: Int

    var body: some View {
        NavigationLink(value: plant) {
            HStack(spacing: 14) {
                TilePhotoView(photo: photo, maxPixel: 300)
                    .frame(width: 88, height: 88)
                    .saturation(0.55)
                    .colorMultiply(Color(red: 1, green: 0.92, blue: 0.78))
                    .brightness(0.03)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text("On this day")
                        .font(.ghEyebrow)
                        .textCase(.uppercase)
                        .tracking(0.7)
                        .foregroundStyle(GH.Palette.terraInk)
                    Text(OnThisDay.headline(yearsAgo: yearsAgo))
                        .font(.ghRounded(.title3))
                        .foregroundStyle(GH.Palette.ink)
                    Text("\(plant.displayName) · see how far it's come")
                        .font(.subheadline)
                        .foregroundStyle(GH.Palette.ink2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(GH.Palette.ink2)
                    .accessibilityHidden(true)
            }
            .padding(12)
            .ghCard(radius: 26)
            .contentShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens \(plant.displayName)")
        .redrawsOnRelatedChanges(plant)
    }
}
