import UIKit
import SwiftUI

// Screen-level styling shared by the app's Lists and Forms.

extension View {
    /// Paper behind a List or Form instead of the system grouped gray.
    /// Rows get `GH.Palette.surface` through `.listRowBackground`.
    func ghScreen() -> some View {
        scrollContentBackground(.hidden)
            .background(GH.Palette.paper.ignoresSafeArea())
    }
}

/// Filled leaf button. Unlike `.borderedProminent` it keeps its label legible
/// in dark mode, where leaf is the light green and needs dark text.
struct GHProminentButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.controlSize) private var controlSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        let compact = controlSize == .small || controlSize == .mini
        configuration.label
            .font(compact ? .ghRounded(.subheadline, weight: .bold) : .ghRounded(.body, weight: .bold))
            .foregroundStyle(GH.Palette.onLeaf)
            .lineLimit(compact ? 1 : nil)
            .fixedSize(horizontal: compact, vertical: false)
            .multilineTextAlignment(.center)
            .padding(.horizontal, compact ? GH.Space.m : GH.Space.l)
            .padding(.vertical, compact ? GH.Space.xs : GH.Space.s)
            .frame(minHeight: 44)
            .background(GH.Palette.leaf, in: Capsule(style: .continuous))
            .opacity(isEnabled ? 1 : 0.4)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.94 : 1)
            .animation(reduceMotion ? nil : GH.Motion.press, value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == GHProminentButtonStyle {
    static var ghProminent: GHProminentButtonStyle { GHProminentButtonStyle() }
}

/// App-wide chrome that SwiftUI can't style from the view tree.
enum GHAppearance {
    /// Large and inline navigation titles in rounded heavy, scaling with Dynamic Type.
    private static var applied = false

    static func apply() {
        guard !applied else { return }
        applied = true
        func rounded(_ style: UIFont.TextStyle, size: CGFloat) -> UIFont {
            let base = UIFont.systemFont(ofSize: size, weight: .heavy)
            let descriptor = base.fontDescriptor.withDesign(.rounded) ?? base.fontDescriptor
            return UIFontMetrics(forTextStyle: style).scaledFont(for: UIFont(descriptor: descriptor, size: size))
        }
        let ink = UIColor(GH.Palette.ink)
        func make(transparent: Bool) -> UINavigationBarAppearance {
            let appearance = UINavigationBarAppearance()
            if transparent { appearance.configureWithTransparentBackground() } else { appearance.configureWithDefaultBackground() }
            appearance.largeTitleTextAttributes = [.font: rounded(.largeTitle, size: 34), .foregroundColor: ink]
            appearance.titleTextAttributes = [.font: rounded(.headline, size: 17), .foregroundColor: ink]
            return appearance
        }
        let bar = UINavigationBar.appearance()
        bar.standardAppearance = make(transparent: false)
        bar.scrollEdgeAppearance = make(transparent: true)
        bar.compactAppearance = make(transparent: false)
    }
}
