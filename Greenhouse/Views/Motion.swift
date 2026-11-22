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

    /// A loading placeholder's soft sweep of light. Under Reduce Motion it
    /// stays still.
    func shimmer() -> some View {
        modifier(Shimmer())
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

private struct Shimmer: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = -1

    func body(content: Content) -> some View {
        content
            .overlay {
                if !reduceMotion {
                    GeometryReader { proxy in
                        LinearGradient(
                            colors: [.clear, GH.Palette.surface.opacity(0.7), .clear],
                            startPoint: .leading, endPoint: .trailing
                        )
                        .frame(width: proxy.size.width * 0.6)
                        .offset(x: phase * proxy.size.width)
                    }
                    .allowsHitTesting(false)
                }
            }
            .clipped()
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) { phase = 1.2 }
            }
            .accessibilityHidden(true)
    }
}
