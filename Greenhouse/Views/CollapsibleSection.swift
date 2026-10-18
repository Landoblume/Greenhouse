import SwiftUI

/// A plant-page section whose header folds it away. Which sections are folded
/// is remembered on this phone and applies to every plant, so hiding Photos
/// once keeps it hidden until you open it again.
struct CollapsibleSection<Content: View>: View {
    let title: String
    /// Shown next to the title while folded, e.g. "12" photos.
    var summary: String?
    @ViewBuilder var content: Content
    @AppStorage(SettingsKey.collapsedPlantSections) private var collapsedList = ""

    init(_ title: String, summary: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.summary = summary
        self.content = content()
    }

    private var isCollapsed: Bool { CollapsedSections.isCollapsed(title, in: collapsedList) }

    var body: some View {
        Section {
            if !isCollapsed { content }
        } header: {
            Button {
                withAnimation { collapsedList = CollapsedSections.toggled(title, in: collapsedList) }
            } label: {
                HStack {
                    Text(title)
                    if isCollapsed, let summary { Text("· \(summary)") }
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .rotationEffect(.degrees(isCollapsed ? -90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(isCollapsed ? "Shows this section" : "Hides this section")
        }
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
