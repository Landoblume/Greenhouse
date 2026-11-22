import SwiftUI

/// A plant-page card whose header folds it away. Which sections are folded
/// is remembered on this phone and applies to every plant, so hiding Photos
/// once keeps it hidden until you open it again.
///
/// Folding springs the card's height (`GH.Motion.fold`), turns the chevron a
/// quarter turn and grows the contents in; with Reduce Motion it crossfades.
struct CollapsibleSection<Content: View>: View {
    let title: String
    /// Shown next to the title while folded, e.g. "12" photos.
    var summary: String?
    /// What the folded state is stored under. Defaults to the title; a renamed
    /// section keeps its old key so it stays folded or open as it was.
    var storageKey: String
    @ViewBuilder var content: Content
    @AppStorage(SettingsKey.collapsedPlantSections) private var collapsedList = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(_ title: String, summary: String? = nil, storageKey: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.summary = summary
        self.storageKey = storageKey ?? title
        self.content = content()
    }

    private var isCollapsed: Bool { CollapsedSections.isCollapsed(storageKey, in: collapsedList) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(reduceMotion ? GH.Motion.reduced : GH.Motion.fold) {
                    collapsedList = CollapsedSections.toggled(storageKey, in: collapsedList)
                }
            } label: {
                HStack(spacing: GH.Space.xs) {
                    Text(title)
                        .font(.ghRounded(.title3))
                        .foregroundStyle(GH.Palette.ink)
                        .multilineTextAlignment(.leading)
                    if isCollapsed, let summary {
                        Text(summary)
                            .font(.subheadline)
                            .foregroundStyle(GH.Palette.ink2)
                            .transition(.opacity)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(GH.Palette.ink2)
                        .rotationEffect(.degrees(isCollapsed ? 0 : 90))
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .padding(.vertical, GH.Space.xxs)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(.isHeader)
            .accessibilityValue(isCollapsed ? "Folded" : "Open")
            .accessibilityHint(isCollapsed ? "Shows this section" : "Hides this section")

            if !isCollapsed {
                VStack(alignment: .leading, spacing: GH.Space.s) {
                    content
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, GH.Space.m)
                .transition(reduceMotion ? .opacity : .sectionGrowIn)
            }
        }
        .padding(.horizontal, GH.Space.m)
        .padding(.top, GH.Space.xxs)
        // Clipped so the contents never spill past the card while it springs.
        .clipShape(RoundedRectangle(cornerRadius: GH.Radius.card, style: .continuous))
        .ghCard()
    }
}

/// The folded sections, stored as one title per line.
enum CollapsedSections {
    static func isCollapsed(_ title: String, in list: String) -> Bool {
        list.split(separator: "\n").contains { $0 == title }
    }

    /// The stored list with `title` folded if it was open, or opened if it was folded.
    static func toggled(_ title: String, in list: String) -> String {
        var titles = list.split(separator: "\n").map(String.init)
        if let index = titles.firstIndex(of: title) {
            titles.remove(at: index)
        } else {
            titles.append(title)
        }
        return titles.joined(separator: "\n")
    }
}

/// A section's contents growing in as it unfolds: up from 12 pt below, from
/// 0.96 scale, fading in. Folding just fades them out while the card closes.
private struct SectionGrowIn: ViewModifier {
    let shown: Bool

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .scaleEffect(shown ? 1 : 0.96, anchor: .top)
            .offset(y: shown ? 0 : 12)
    }
}

extension AnyTransition {
    static var sectionGrowIn: AnyTransition {
        .asymmetric(
            insertion: .modifier(active: SectionGrowIn(shown: false), identity: SectionGrowIn(shown: true)),
            removal: .opacity
        )
    }
}
