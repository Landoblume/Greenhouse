import SwiftUI

// Pieces of a Care row: the blob-masked plant photo, the Done circle with its
// ripple and hold-to-undo ring, plant chips, and the empty-state art.

// MARK: - Blob

/// A soft, slightly lopsided rounded shape for avatars (blob masks are only for
/// avatars and empty states; photos elsewhere stay rounded rectangles).
struct CareBlob: Shape {
    /// Horizontal and vertical corner radii as fractions of the width and height,
    /// clockwise from top-left. Each side's pair sums to 1.
    struct Variant {
        let h: [CGFloat]
        let v: [CGFloat]
    }

    static let variants: [Variant] = [
        Variant(h: [0.58, 0.42, 0.55, 0.45], v: [0.52, 0.58, 0.42, 0.48]),
        Variant(h: [0.52, 0.48, 0.45, 0.55], v: [0.55, 0.50, 0.50, 0.45]),
        Variant(h: [0.45, 0.55, 0.58, 0.42], v: [0.58, 0.45, 0.55, 0.42]),
        Variant(h: [0.55, 0.45, 0.50, 0.50], v: [0.45, 0.52, 0.48, 0.55]),
    ]

    var variant = 0

    func path(in rect: CGRect) -> Path {
        let shape = Self.variants[abs(variant) % Self.variants.count]
        let w = rect.width, h = rect.height
        let a = shape.h[0] * w          // where the top edge's two corners meet
        let c = shape.h[3] * w          // bottom
        let d = shape.v[0] * h          // left
        let b = shape.v[1] * h          // right
        let k: CGFloat = 0.5523         // quarter-ellipse as a cubic curve
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + a, y: rect.minY))
        path.addCurve(to: CGPoint(x: rect.maxX, y: rect.minY + b),
                      control1: CGPoint(x: rect.minX + a + k * (w - a), y: rect.minY),
                      control2: CGPoint(x: rect.maxX, y: rect.minY + b - k * b))
        path.addCurve(to: CGPoint(x: rect.minX + c, y: rect.maxY),
                      control1: CGPoint(x: rect.maxX, y: rect.minY + b + k * (h - b)),
                      control2: CGPoint(x: rect.minX + c + k * (w - c), y: rect.maxY))
        path.addCurve(to: CGPoint(x: rect.minX, y: rect.minY + d),
                      control1: CGPoint(x: rect.minX + c - k * c, y: rect.maxY),
                      control2: CGPoint(x: rect.minX, y: rect.minY + d + k * (h - d)))
        path.addCurve(to: CGPoint(x: rect.minX + a, y: rect.minY),
                      control1: CGPoint(x: rect.minX, y: rect.minY + d - k * d),
                      control2: CGPoint(x: rect.minX + a - k * a, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

// MARK: - Avatar

/// The plant's cover photo in a blob, or a leaf when there isn't one (or the
/// reminder is for the whole household).
struct CarePlantAvatar: View {
    let plant: Plant?
    var size: CGFloat = 46

    var body: some View {
        Group {
            if let plant {
                CarePlantPhoto(plant: plant, size: size)
            } else {
                CareLeafGlyph(size: size, variant: 0)
            }
        }
        .frame(width: size, height: size)
    }
}

private struct CarePlantPhoto: View {
    /// Observed so a new cover photo shows here without rebuilding the row.
    @ObservedObject var plant: Plant
    let size: CGFloat
    @Environment(\.displayScale) private var scale

    private var variant: Int { Int(plant.uuid?.uuid.0 ?? 0) % CareBlob.variants.count }

    var body: some View {
        if let photo = PlantPhotos.cover(for: plant),
           let image = ThumbnailCache.shared.image(for: photo, maxPixel: size * scale * 1.5) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(CareBlob(variant: variant))
                .accessibilityHidden(true)
        } else {
            CareLeafGlyph(size: size, variant: variant)
        }
    }
}

private struct CareLeafGlyph: View {
    let size: CGFloat
    let variant: Int

    var body: some View {
        ZStack {
            CareBlob(variant: variant).fill(GH.Palette.leafSoft)
            Image(systemName: "leaf.fill")
                .font(.system(size: size * 0.42))
                .foregroundStyle(GH.Palette.leafInk)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

// MARK: - Done circle

private struct CareCheck: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.08, y: rect.minY + rect.height * 0.55))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.38, y: rect.minY + rect.height * 0.85))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.92, y: rect.minY + rect.height * 0.15))
        return path
    }
}

/// Button squash: 0.9 on press, with the press spring. No scaling under Reduce Motion.
private struct CareSquashStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.9 : 1)
            .animation(reduceMotion ? nil : GH.Motion.press, value: configuration.isPressed)
    }
}

/// A droplet ring that ripples out and fades (0.6 -> 1.5, 0.7 s) each time `trigger` changes.
private struct CareRipple: View {
    let color: Color
    let delay: Double
    let trigger: Int

    private enum Phase: CaseIterable {
        case rest, start, end
        var scale: CGFloat { self == .end ? 1.5 : 0.6 }
        var opacity: Double { self == .start ? 0.55 : 0 }
    }

    var body: some View {
        Circle()
            .strokeBorder(color, lineWidth: 2)
            .phaseAnimator(Phase.allCases, trigger: trigger) { view, phase in
                view.scaleEffect(phase.scale).opacity(phase.opacity)
            } animation: { phase in
                phase == .end ? .easeOut(duration: 0.7).delay(delay) : .linear(duration: 0.01)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// The 44-pt Done circle. Tap to finish; once finished, press and hold for 0.6 s to undo.
struct CareDoneButton: View {
    let isDone: Bool
    /// "Watered" or "Done".
    let word: String
    /// Bump to play the ripple.
    let celebrate: Int
    let onDone: () -> Void
    let onUndo: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var holding = false
    @State private var drawn: Bool

    init(isDone: Bool, word: String, celebrate: Int, onDone: @escaping () -> Void, onUndo: @escaping () -> Void) {
        self.isDone = isDone
        self.word = word
        self.celebrate = celebrate
        self.onDone = onDone
        self.onUndo = onUndo
        _drawn = State(initialValue: isDone)
    }

    var body: some View {
        ZStack {
            if !reduceMotion {
                CareRipple(color: GH.Palette.leaf, delay: 0, trigger: celebrate).padding(-4)
                CareRipple(color: GH.Palette.sky, delay: 0.15, trigger: celebrate).padding(-4)
            }
            if isDone { finished } else { pending }
        }
        .frame(width: 44, height: 44)
        .onChange(of: isDone) { _, done in
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.3).delay(0.08)) { drawn = done }
        }
    }

    private var pending: some View {
        Button(action: onDone) {
            ZStack {
                Circle().strokeBorder(GH.Palette.ink2.opacity(0.6), lineWidth: 2)
                CareCheck()
                    .stroke(GH.Palette.ink2, style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
                    .frame(width: 18, height: 18)
            }
            .contentShape(Circle())
        }
        .buttonStyle(CareSquashStyle())
        .accessibilityLabel("Mark \(word.lowercased())")
    }

    private var finished: some View {
        ZStack {
            Circle().fill(GH.Palette.leaf)
            CareCheck()
                .trim(from: 0, to: drawn ? 1 : 0)
                .stroke(GH.Palette.onLeaf, style: StrokeStyle(lineWidth: 2.6, lineCap: .round, lineJoin: .round))
                .frame(width: 18, height: 18)
            // The hold-to-undo ring fills while the finger is down.
            Circle()
                .trim(from: 0, to: holding ? 1 : 0)
                .stroke(GH.Palette.sky, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(1)
                .animation(holding ? .linear(duration: 0.6) : .easeOut(duration: 0.15), value: holding)
        }
        .contentShape(Circle())
        .onLongPressGesture(minimumDuration: 0.6, maximumDistance: 40) {
            holding = false
            onUndo()
        } onPressingChanged: { pressing in
            holding = pressing
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(word). Press and hold to undo")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: "Undo", onUndo)
    }
}

// MARK: - Plant chips

/// Plant names under a reminder, each a capsule that opens that plant. Wraps
/// onto more lines when a reminder covers many plants.
struct PlantNameLinks: View {
    let plants: [Plant]
    let onOpen: (Plant) -> Void

    var body: some View {
        WrappingLayout(spacing: GH.Space.xs, lineSpacing: 0) {
            ForEach(plants) { plant in
                CarePlantChip(plant: plant) { onOpen(plant) }
            }
        }
    }
}

struct CarePlantChip: View {
    @ObservedObject var plant: Plant
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 4) {
                Text(plant.displayName).multilineTextAlignment(.leading)
                Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold))
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(GH.Palette.leafInk)
            .padding(.horizontal, GH.Space.s)
            .padding(.vertical, 6)
            .background(GH.Palette.leafSoft, in: Capsule(style: .continuous))
            // The visible capsule is smaller than the 44-pt target.
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(plant.displayName)
        .accessibilityHint("Opens the plant")
    }
}

/// Lays children out left to right, starting a new line when one won't fit.
struct WrappingLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(width: proposal.width ?? .infinity, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(width: bounds.width, subviews: subviews)
        for (subview, origin) in zip(subviews, result.origins) {
            subview.place(at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y),
                          proposal: ProposedViewSize(width: bounds.width, height: nil))
        }
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> (size: CGSize, origins: [CGPoint]) {
        var origins: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        var widest: CGFloat = 0
        // A child wider than the row is offered the row's width, so its text wraps.
        let offer = ProposedViewSize(width: width.isFinite ? width : nil, height: nil)
        for subview in subviews {
            let size = subview.sizeThatFits(offer)
            if x > 0, x + size.width > width {
                x = 0
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            origins.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
            widest = max(widest, x - spacing)
        }
        return (CGSize(width: widest, height: y + lineHeight), origins)
    }
}

// MARK: - Card chrome

/// The row card: surface (or leafSoft once done), the resting shadow, and a
/// terracotta outline while overdue.
struct CareCardBackground: View {
    var isDone = false
    var isOverdue = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: GH.Radius.control, style: .continuous)
        shape
            .fill(isDone ? GH.Palette.leafSoft : GH.Palette.surface)
            .shadow(color: .black.opacity(0.06), radius: 1, y: 1)
            .shadow(color: .black.opacity(0.08), radius: 14, y: 10)
            .overlay {
                if isOverdue && !isDone {
                    shape.strokeBorder(GH.Palette.terra, lineWidth: 1.5)
                }
            }
    }
}

// MARK: - Empty-state art

/// Floating art: grows in, then bobs +-5 pt on a 4.5 s loop. Fades in only under Reduce Motion.
struct CareEmptyArt: View {
    let name: String
    var height: CGFloat = 150
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if reduceMotion {
                art
            } else {
                art.phaseAnimator([-5.0, 5.0]) { view, offset in
                    view.offset(y: offset)
                } animation: { _ in
                    .easeInOut(duration: 2.25)
                }
            }
        }
        .growIn()
        .accessibilityHidden(true)
    }

    private var art: some View {
        Image(name).resizable().scaledToFit().frame(height: height)
    }
}

/// The soonest upcoming task, under "All caught up".
struct CareNextUpCard: View {
    @ObservedObject var task: CareTask
    var onOpen: () -> Void = {}

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: GH.Space.s) {
                CarePlantAvatar(plant: task.activePlants.first)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Next up").font(.ghEyebrow).textCase(.uppercase).tracking(0.7).foregroundStyle(GH.Palette.skyInk)
                    Text(task.title).font(.body.weight(.semibold)).foregroundStyle(GH.Palette.ink)
                    if let status = CareSchedule.status(of: task) {
                        Text(status.label).font(.footnote).foregroundStyle(GH.Palette.ink2)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(GH.Space.s)
            .frame(minHeight: 72)
            .background { CareCardBackground() }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens the reminder")
    }
}

// MARK: - Scroll softening

/// Rows soften as they enter and leave the viewport: scale 0.94, opacity 0.5,
/// y +-8 at the very edge. Reduce Motion: opacity only, floor 0.7. Measured
/// against the scroll view's bounds with `visualEffect`, because `scrollTransition`
/// is unreliable on List rows (every row in the list came out faded).
struct CareSoftening: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let reduce = reduceMotion
        return content.visualEffect { view, proxy in
            let frame = proxy.frame(in: .scrollView(axis: .vertical))
            let height = max(frame.height, 1)
            let viewport = proxy.bounds(of: .scrollView(axis: .vertical))?.height ?? .infinity
            // 0 when the row is fully inside the viewport, 1 when it has fully left.
            let above = max(0, -frame.minY) / height
            let below = viewport.isFinite ? max(0, frame.maxY - viewport) / height : 0
            let amount = min(1, max(above, below))
            let direction: CGFloat = above > below ? -1 : 1
            return view
                .opacity(1 - amount * (reduce ? 0.3 : 0.5))
                .scaleEffect(reduce ? 1 : 1 - amount * 0.06)
                .offset(y: reduce ? 0 : direction * amount * 8)
        }
    }
}

extension View {
    func careSoftening() -> some View { modifier(CareSoftening()) }
}
