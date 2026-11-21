// Greenhouse design tokens + motion helpers (iOS 17+).
// Drop into the app target. Colors adapt to light / dark automatically.

import SwiftUI
import UIKit

// MARK: - Color helpers

private extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

private extension Color {
    /// A color that switches between a light and a dark value with the system appearance.
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

// MARK: - Tokens

enum GH {
    /// Core palette. Text tokens (ink, ink2, *Ink) pass 4.5:1 on paper, surface and their soft tint.
    enum Palette {
        static let paper     = Color(light: 0xF5F1E8, dark: 0x0D1712) // screen background
        static let surface   = Color(light: 0xFFFCF5, dark: 0x15231B) // cards, rows
        static let surface2  = Color(light: 0xECE6D8, dark: 0x1D2F25) // fields, quiet chips
        static let ink       = Color(light: 0x1B3125, dark: 0xE6EEE2) // primary text
        static let ink2      = Color(light: 0x53655A, dark: 0xA3B5A6) // secondary text
        static let leaf      = Color(light: 0x2E6A46, dark: 0x7EC492) // accent, primary action
        static let onLeaf    = Color(light: 0xFFFFFF, dark: 0x0D1712) // text/icons on leaf
        static let leafSoft  = Color(light: 0xDCEAD6, dark: 0x1E3A2A) // selected, done
        static let leafInk   = Color(light: 0x245A3A, dark: 0x9DD8AE) // text on leafSoft
        static let terra     = Color(light: 0xB65A35, dark: 0xE08E68) // pots, overdue, milestones
        static let terraSoft = Color(light: 0xF4DDD0, dark: 0x3A251B)
        static let terraInk  = Color(light: 0x97472A, dark: 0xEFAA88)
        static let sky       = Color(light: 0x3A82B8, dark: 0x86BEE8) // water, care
        static let skySoft   = Color(light: 0xDAE9F4, dark: 0x16293A)
        static let skyInk    = Color(light: 0x235C87, dark: 0xA9D2F2)
        static let line      = Color(light: 0x1B3125, dark: 0xE6EEE2).opacity(0.12)
    }

    /// Care-history thread colors, assigned in this order (1–4 stay distinct under common color blindness).
    static let threads: [Color] = [
        Color(light: 0x2F7FC1, dark: 0x7DB8EA), // 1 Sky
        Color(light: 0xD0702A, dark: 0xF0A060), // 2 Clay
        Color(light: 0x8E54A8, dark: 0xC69BDB), // 3 Plum
        Color(light: 0x3B8A55, dark: 0x7FCB91), // 4 Leaf
        Color(light: 0xB8901A, dark: 0xE2C15A), // 5 Honey
        Color(light: 0x23897D, dark: 0x6FCFC2), // 6 Teal
        Color(light: 0xC9557A, dark: 0xEE93B1), // 7 Rose
        Color(light: 0x5F6E86, dark: 0xA6B3C8), // 8 Slate
    ]

    /// Always use with `.continuous` corner style.
    enum Radius {
        static let chip: CGFloat = 13
        static let control: CGFloat = 22
        static let card: CGFloat = 24
        static let tile: CGFloat = 28
        static let sheet: CGFloat = 34
    }

    /// 4-pt grid.
    enum Space {
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 8
        static let s: CGFloat = 12
        static let m: CGFloat = 16
        static let screen: CGFloat = 20
        static let l: CGFloat = 24
        static let xl: CGFloat = 32
        static let xxl: CGFloat = 48
    }

    /// Springs from the Motion specs board.
    enum Motion {
        static let enter = Animation.spring(duration: 0.5, bounce: 0.15)   // content grows in
        static let hero  = Animation.spring(duration: 0.45, bounce: 0.12)  // tile -> plant page, photo viewer
        static let fold  = Animation.spring(duration: 0.4, bounce: 0.1)    // section fold / unfold
        static let press = Animation.spring(duration: 0.3, bounce: 0.5)    // Watered / Done squash
        static let dot   = Animation.spring(duration: 0.35, bounce: 0.4)   // thread dots popping in
        static let zoom  = Animation.spring(duration: 0.5, bounce: 0.15)   // care-history level change
        static let reduced = Animation.easeOut(duration: 0.2)              // Reduce Motion: crossfade only
        static let staggerStep: Double = 0.04                              // 40 ms, first 6 items only
    }
}

// MARK: - Type

extension Font {
    /// SF Pro Rounded for headings and numbers.
    static func ghRounded(_ style: Font.TextStyle, weight: Font.Weight = .heavy) -> Font {
        .system(style, design: .rounded, weight: weight)
    }
    /// Eyebrow labels ("ON THIS DAY"); pair with `.textCase(.uppercase)` and `.tracking(0.7)`.
    static let ghEyebrow = Font.caption.weight(.heavy)
}

/// Large friendly numbers ("23 waterings") that still follow Dynamic Type.
struct GHDisplayNumber: View {
    let value: String
    var color: Color = GH.Palette.skyInk
    @ScaledMetric(relativeTo: .largeTitle) private var size: CGFloat = 48

    var body: some View {
        Text(value)
            .font(.system(size: size, weight: .black, design: .rounded))
            .foregroundStyle(color)
    }
}

// MARK: - Motion helpers

/// "Things grow in, they don't pop in": drift up 12 pt, scale from 0.96, fade.
/// Reduce Motion turns it into a plain fade.
struct GrowIn: ViewModifier {
    var delay: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .scaleEffect(shown || reduceMotion ? 1 : 0.96)
            .offset(y: shown || reduceMotion ? 0 : 12)
            .onAppear {
                let animation = reduceMotion ? GH.Motion.reduced : GH.Motion.enter
                withAnimation(animation.delay(delay)) { shown = true }
            }
    }
}

/// "Scroll is alive": rows and tiles soften as they enter and leave the viewport.
struct ScrollSoftening: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let reduce = reduceMotion // capture a plain value; the transition closure runs off the main actor
        return content.scrollTransition(.interactive, axis: .vertical) { view, phase in
            view
                .opacity(phase.isIdentity ? 1 : (reduce ? 0.7 : 0.5))
                .scaleEffect(phase.isIdentity || reduce ? 1 : 0.94)
                .offset(y: reduce ? 0 : phase.value * 8)
        }
    }
}

extension View {
    /// Use `index` to stagger items in a list; only the first 6 are delayed.
    func growIn(index: Int = 0, baseDelay: Double = 0) -> some View {
        modifier(GrowIn(delay: baseDelay + Double(min(index, 5)) * GH.Motion.staggerStep))
    }

    func scrollSoftening() -> some View {
        modifier(ScrollSoftening())
    }

    /// Card surface with continuous corners and the resting shadow.
    func ghCard(radius: CGFloat = GH.Radius.card) -> some View {
        background(GH.Palette.surface, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .shadow(color: .black.opacity(0.06), radius: 1, y: 1)
            .shadow(color: .black.opacity(0.08), radius: 14, y: 10)
    }
}
