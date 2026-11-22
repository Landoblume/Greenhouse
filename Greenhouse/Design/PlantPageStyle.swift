import SwiftUI

// Tokens and small shapes for the plant page and its photo viewer. Kept here
// rather than in Theme.swift so the plant page owns them.

extension GH {
    enum PlantPage {
        /// The hero photo's height before it scrolls away.
        static let heroHeight: CGFloat = 380
        /// How far the content sheet rides up over the hero.
        static let sheetOverlap: CGFloat = 36
        /// The photo viewer's backdrop and text: "greenhouse at night" in both
        /// modes, since photos read best on dark.
        static let viewerBackground = Color(red: 0x0D / 255, green: 0x17 / 255, blue: 0x12 / 255)
        static let viewerInk = Color(red: 0xE6 / 255, green: 0xEE / 255, blue: 0xE2 / 255)
        static let viewerInk2 = Color(red: 0xA3 / 255, green: 0xB5 / 255, blue: 0xA6 / 255)
        /// Confetti colors: sky, leaf, honey and terracotta.
        static let confetti: [Color] = [GH.Palette.sky, GH.Palette.leaf, GH.threads[4], GH.Palette.terra]
    }
}

/// A soft organic blob for small icon backdrops (the birthday banner's badge).
struct PlantPageBlobShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * w, y: rect.minY + y * h) }
        var path = Path()
        path.move(to: p(0.52, 0.0))
        path.addCurve(to: p(1.0, 0.47), control1: p(0.80, 0.0), control2: p(1.0, 0.20))
        path.addCurve(to: p(0.50, 1.0), control1: p(1.0, 0.78), control2: p(0.78, 1.0))
        path.addCurve(to: p(0.0, 0.53), control1: p(0.22, 1.0), control2: p(0.0, 0.80))
        path.addCurve(to: p(0.52, 0.0), control1: p(0.0, 0.22), control2: p(0.25, 0.0))
        path.closeSubpath()
        return path
    }
}

/// The plant page's round glass buttons (back, share, more) over the hero.
struct GlassCircleLabel: View {
    let systemImage: String
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(GH.Palette.ink)
            .frame(width: 44, height: 44)
            .background {
                // Reduce Transparency gets a solid surface instead of glass.
                if reduceTransparency {
                    Circle().fill(GH.Palette.surface)
                } else {
                    Circle().fill(.regularMaterial)
                }
            }
            .overlay(Circle().strokeBorder(GH.Palette.line, lineWidth: 0.5))
            .contentShape(Circle())
    }
}
