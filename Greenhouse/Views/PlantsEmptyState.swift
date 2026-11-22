import SwiftUI

/// First launch, no plants yet: the seedling grows in and then bobs gently.
struct PlantsEmptyState: View {
    let onAdd: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: GH.Space.m) {
            art
                .growIn(index: 0, baseDelay: 0.1)
            Text("Your greenhouse is waiting")
                .font(.ghRounded(.title2))
                .foregroundStyle(GH.Palette.ink)
                .multilineTextAlignment(.center)
                .growIn(index: 2, baseDelay: 0.1)
                .accessibilityAddTraits(.isHeader)
            Text("Add your first plant to start its journal: photos, care and milestones, all in one place.")
                .font(.body)
                .foregroundStyle(GH.Palette.ink2)
                .multilineTextAlignment(.center)
                .growIn(index: 3, baseDelay: 0.1)
            Button(action: onAdd) {
                Label("Add a plant", systemImage: "plus")
            }
            .buttonStyle(.ghProminent)
            .growIn(index: 4, baseDelay: 0.1)
        }
        .padding(.horizontal, GH.Space.xl)
        .padding(.top, GH.Space.xl)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var art: some View {
        let image = Image("EmptySeedling")
            .resizable()
            .scaledToFit()
            .frame(maxWidth: 220, maxHeight: 220)
            .accessibilityHidden(true)
        if reduceMotion {
            image
        } else {
            // Two phases of 2.25 s each: a ±5 pt bob on a 4.5 s loop.
            PhaseAnimator([5.0, -5.0]) { offset in
                image.offset(y: offset)
            } animation: { _ in
                .easeInOut(duration: 2.25)
            }
        }
    }
}
