import SwiftUI

/// One tab in the floating bar.
struct GHTabItem: Identifiable {
    let tag: Int
    let title: String
    let icon: String
    let selectedIcon: String
    var id: Int { tag }
}

/// Floating glass capsule that replaces the system tab bar. The tabs still
/// live in a `TabView` (so each keeps its scroll position and navigation
/// stack); this only draws the bar and sets the selection.
struct GHTabBar: View {
    let items: [GHTabItem]
    @Binding var selection: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var pill

    var body: some View {
        HStack(spacing: 2) {
            ForEach(items) { item in
                let selected = item.tag == selection
                Button {
                    withAnimation(reduceMotion ? GH.Motion.reduced : GH.Motion.press) { selection = item.tag }
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: selected ? item.selectedIcon : item.icon)
                            .font(.system(.title3, weight: .semibold))
                            .imageScale(.medium)
                            .frame(height: 26)
                        Text(item.title)
                            .font(.ghRounded(.caption2, weight: .bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .foregroundStyle(selected ? GH.Palette.leafInk : GH.Palette.ink2)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .padding(.vertical, GH.Space.xs)
                    .background {
                        if selected {
                            Capsule(style: .continuous)
                                .fill(GH.Palette.leafSoft)
                                .matchedGeometryEffect(id: "pill", in: pill)
                        }
                    }
                    .contentShape(Capsule(style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.title)
                .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
                .accessibilityShowsLargeContentViewer {
                    Label(item.title, systemImage: selected ? item.selectedIcon : item.icon)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isTabBar)
        .padding(6)
        // Like the system bar, stop growing at the largest regular text size:
        // four labels don't fit side by side beyond that.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .background(.ultraThinMaterial, in: Capsule(style: .continuous))
        .overlay(Capsule(style: .continuous).strokeBorder(GH.Palette.line, lineWidth: 1))
        .shadow(color: .black.opacity(0.10), radius: 18, y: 8)
        .padding(.horizontal, GH.Space.screen)
        .padding(.bottom, GH.Space.xs)
        .sensoryFeedback(.selection, trigger: selection)
    }
}

private struct TabBarInsetKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
    /// Height a tab's scroll content leaves at the bottom for the floating bar.
    var ghTabBarInset: CGFloat {
        get { self[TabBarInsetKey.self] }
        set { self[TabBarInsetKey.self] = newValue }
    }
}

extension View {
    /// Tells a tab's screen how much room the floating bar needs. Pass 0 while
    /// the keyboard is up.
    func ghTabBarInset(_ height: CGFloat) -> some View {
        environment(\.ghTabBarInset, height)
    }

    /// Put on a tab's List, Form or ScrollView: its last row can scroll clear
    /// of the floating bar. The change is never animated, so content doesn't
    /// glide by the bar's height when the keyboard comes and goes.
    func ghTabBarClearance() -> some View {
        modifier(TabBarClearance())
    }
}

private struct TabBarClearance: ViewModifier {
    @Environment(\.ghTabBarInset) private var inset

    func body(content: Content) -> some View {
        content
            .safeAreaPadding(.bottom, inset)
            .transaction(value: inset) { $0.animation = nil }
    }
}

/// True while the software keyboard is up, so the floating bar can step aside
/// instead of riding on top of it.
@MainActor
final class KeyboardWatcher: ObservableObject {
    @Published var isVisible = false
    private var tokens: [NSObjectProtocol] = []

    init() {
        let center = NotificationCenter.default
        tokens.append(center.addObserver(forName: UIResponder.keyboardWillShowNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.isVisible = true }
        })
        tokens.append(center.addObserver(forName: UIResponder.keyboardWillHideNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.isVisible = false }
        })
    }

    deinit { tokens.forEach(NotificationCenter.default.removeObserver) }
}
