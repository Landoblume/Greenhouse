import SwiftUI

/// Shared motion for scrolling pages. Everything here backs off when the
/// phone's Reduce Motion setting is on: no movement or scaling, only fades.
extension View {
    /// Rows soften as they scroll in and out. Kept for existing callers; it is
    /// the theme's `scrollSoftening()` (Reduce Motion: opacity only).
    func fluidScrollRow() -> some View {
        scrollSoftening()
    }

    /// Flips `revealed` to true the first time the view appears, animated
    /// unless Reduce Motion is on. Drives "draw in" effects like a line
    /// growing from nothing.
    func revealsOnAppear(_ revealed: Binding<Bool>, delay: Double = 0) -> some View {
        modifier(RevealOnAppear(revealed: revealed, delay: delay))
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
