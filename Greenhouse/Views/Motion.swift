import SwiftUI

/// Shared motion for scrolling pages. Everything here backs off when the
/// phone's Reduce Motion setting is on: no movement or scaling, only fades.
extension View {
    /// Rows ease in as they scroll into view and settle as they leave: a fade
    /// with a slight scale and rise. Use it on the rows of a `ScrollView`
    /// (`scrollTransition` doesn't act inside a `List`).
    func fluidScrollRow() -> some View {
        modifier(FluidScrollRow())
    }

    /// Flips `revealed` to true the first time the view appears, animated
    /// unless Reduce Motion is on. Drives "draw in" effects like a line
    /// growing from nothing.
    func revealsOnAppear(_ revealed: Binding<Bool>, delay: Double = 0) -> some View {
        modifier(RevealOnAppear(revealed: revealed, delay: delay))
    }
}

private struct FluidScrollRow: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if reduceMotion {
            content.scrollTransition(.animated) { view, phase in
                view.opacity(phase.isIdentity ? 1 : 0.4)
            }
        } else {
            content.scrollTransition(.interactive) { view, phase in
                view
                    .opacity(phase.isIdentity ? 1 : 0.25)
                    .scaleEffect(phase.isIdentity ? 1 : 0.94)
                    .offset(y: phase.isIdentity ? 0 : phase.value * 14)
            }
        }
    }
}

private struct RevealOnAppear: ViewModifier {
    @Binding var revealed: Bool
    let delay: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.onAppear {
            guard !revealed else { return }
            if reduceMotion {
                revealed = true
            } else {
                withAnimation(.easeOut(duration: 0.7).delay(delay)) { revealed = true }
            }
        }
    }
}
