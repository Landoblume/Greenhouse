import Observation
import SwiftUI
import UIKit

/// How far the plant page's hero has scrolled under the top bar: 0 while it's
/// all showing, 1 once it's gone. Kept in its own object so only the bar
/// redraws while scrolling, not the whole page.
@Observable
final class PlantHeroScroll {
    var progress: CGFloat = 0

    /// `minY` is the hero's top edge in the scroll view (0 at rest, negative
    /// as it scrolls away). Rounded so tiny moves don't redraw the bar.
    func update(heroMinY minY: CGFloat, collapsesOver distance: CGFloat) {
        let raw = distance > 0 ? -minY / distance : 0
        let next = (min(max(raw, 0), 1) * 50).rounded() / 50
        if next != progress { progress = next }
    }

    var isCollapsed: Bool { progress >= 0.96 }
}

/// The 380-pt photo at the top of a plant page, with the dappled-light
/// overlay. It fades in from 1.06 scale, drifts slower than the page as it
/// scrolls away (softening a little), and stretches when pulled down. Reduce
/// Motion keeps only the fade: no scale, drift, stretch or blur.
struct PlantHero: View {
    let photo: Photo?
    let scroll: PlantHeroScroll
    /// The distance over which the hero is considered collapsing.
    let collapseDistance: CGFloat
    var height: CGFloat = GH.PlantPage.heroHeight
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    var body: some View {
        let reduce = reduceMotion
        let height = height
        // The size comes from the clear base; the photo and light only draw
        // over it. A fill image sized on its own is as wide as its aspect
        // needs at 380 pt tall, and a landscape photo stretched the page.
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .overlay {
                ZStack {
                    PlantPhotoView(photo: photo, maxPixel: 1600)
                    // "Greenhouse at night": the photo dims a little in dark mode.
                    if colorScheme == .dark {
                        Color.black.opacity(0.2)
                    }
                    Image("DappledLight")
                        .resizable()
                        .scaledToFill()
                        .blendMode(.softLight)
                        .opacity(shown ? (colorScheme == .dark ? 0.32 : 0.4) : 0)
                        .animation(reduce ? GH.Motion.reduced : .easeOut(duration: 1).delay(0.2), value: shown)
                        .accessibilityHidden(true)
                }
            }
            .clipped()
        .scaleEffect(shown || reduce ? 1 : 1.06)
        .opacity(shown ? 1 : 0)
        .visualEffect { content, proxy in
            let minY = proxy.frame(in: .scrollView).minY
            let pull = reduce ? 0 : max(minY, 0)
            let away = reduce ? 0 : max(-minY, 0)
            return content
                // Pulled down: grow upward from the bottom edge to fill the gap.
                .scaleEffect(1 + pull / height, anchor: .bottom)
                // Scrolled up: drift at a little over half speed, softening.
                .offset(y: away * 0.45)
                .blur(radius: min(away / height, 1) * 6)
        }
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.frame(in: .scrollView).minY
        } action: { minY in
            scroll.update(heroMinY: minY, collapsesOver: collapseDistance)
        }
        .onAppear {
            guard !shown else { return }
            withAnimation(reduce ? GH.Motion.reduced : .easeOut(duration: 0.8)) { shown = true }
        }
        .accessibilityElement()
        .accessibilityLabel(photo == nil ? "No photo yet" : "Main photo")
        .accessibilityAddTraits(.isImage)
    }
}

/// The plant page's top bar: glass back, share and more buttons over the
/// hero. As the hero scrolls away a compact bar fades in behind them with the
/// plant's name (the name itself takes 0.3 s). Reduce Motion: a solid bar,
/// no blur.
struct PlantPageBar<MenuContent: View>: View {
    let title: String
    let scroll: PlantHeroScroll
    let onBack: () -> Void
    let onShare: () -> Void
    var showsMenu = true
    @ViewBuilder var menu: () -> MenuContent
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let progress = scroll.progress
        let collapsed = scroll.isCollapsed
        // The bar's background comes in over the last stretch of the hero.
        let backdrop = min(max((progress - 0.7) / 0.3, 0), 1)
        HStack(spacing: 10) {
            Button(action: onBack) { GlassCircleLabel(systemImage: "chevron.left") }
                .accessibilityLabel("Back")
            Spacer(minLength: 0)
            Button(action: onShare) { GlassCircleLabel(systemImage: "square.and.arrow.up") }
                .accessibilityLabel("Share then vs now")
            if showsMenu {
                Menu(content: menu) { GlassCircleLabel(systemImage: "ellipsis") }
                    .accessibilityLabel("More")
            }
        }
        .buttonStyle(.plain)
        .overlay {
            // Only in the tree while collapsed, so VoiceOver doesn't read the
            // name twice while the hero is showing. The fade still runs.
            Group {
                if collapsed {
                    Text(title)
                        .font(.ghRounded(.headline))
                        .foregroundStyle(GH.Palette.ink)
                        .lineLimit(1)
                        .padding(.horizontal, 120)
                        .accessibilityAddTraits(.isHeader)
                        .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.3), value: collapsed)
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .padding(.horizontal, GH.Space.m)
        .padding(.top, GH.Space.xxs)
        .padding(.bottom, GH.Space.xs)
        .background {
            ZStack(alignment: .bottom) {
                if reduceMotion {
                    GH.Palette.paper
                } else {
                    Rectangle().fill(.regularMaterial)
                }
                GH.Palette.line.frame(height: 0.5)
            }
            .opacity(backdrop)
            .ignoresSafeArea(edges: .top)
        }
    }
}

// MARK: - Swipe back without a navigation bar

/// The plant page hides the system navigation bar for its own glass buttons,
/// which also turns off the edge swipe back. This puts the swipe back while
/// the page is showing, then hands the gesture its old delegate again.
struct InteractivePopEnabler: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Controller { Controller() }
    func updateUIViewController(_ controller: Controller, context: Context) {}

    final class Controller: UIViewController {
        private let gate = PopGestureGate()
        private weak var previousDelegate: UIGestureRecognizerDelegate?
        private weak var installedOn: UIGestureRecognizer?

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            guard let navigation = navigationController, let pop = navigation.interactivePopGestureRecognizer else { return }
            guard pop.delegate !== gate else { return }
            previousDelegate = pop.delegate
            gate.navigation = navigation
            pop.delegate = gate
            pop.isEnabled = true
            installedOn = pop
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            restore()
        }

        private func restore() {
            guard let pop = installedOn, pop.delegate === gate else { return }
            pop.delegate = previousDelegate
            installedOn = nil
        }
    }
}

/// Lets the swipe start whenever there's a page to go back to and no other
/// transition is running.
private final class PopGestureGate: NSObject, UIGestureRecognizerDelegate {
    weak var navigation: UINavigationController?

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let navigation else { return false }
        return navigation.viewControllers.count > 1 && navigation.transitionCoordinator == nil
    }
}
