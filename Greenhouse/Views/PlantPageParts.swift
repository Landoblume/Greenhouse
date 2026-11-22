import CoreData
import SwiftUI

// The pieces of the plant page's content sheet: birthday banner and
// confetti, stat cards, chips, the care-history link, the photo strip and its
// empty state.

// MARK: - Birthday

/// "Monty turns 2 today · Home since Nov 21, 2024", on the plant's
/// anniversary. Confetti drifts down at the right edge, clear of the text,
/// the first time the page opens that day; after that (and with Reduce
/// Motion) it's just lying there.
struct BirthdayBanner: View {
    let name: String
    let plantID: UUID?
    let birthday: PlantPage.Birthday

    var body: some View {
        HStack(spacing: GH.Space.s) {
            Image(systemName: "party.popper.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(GH.Palette.terraSoft)
                .frame(width: 44, height: 44)
                .background(GH.Palette.terra, in: BlobShape())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(PlantPage.birthdayTitle(name: name, years: birthday.years))
                    .font(.ghRounded(.headline))
                    .foregroundStyle(GH.Palette.terraInk)
                Text("Home since \(Lineage.format(birthday.since))")
                    .font(.subheadline)
                    .foregroundStyle(GH.Palette.ink)
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, GH.Space.m)
        .padding(.vertical, 14)
        // The confetti's strip on the right; text never runs under it.
        .padding(.trailing, BirthdayConfetti.width)
        .background(alignment: .trailing) {
            BirthdayConfetti(plantID: plantID)
                .frame(width: BirthdayConfetti.width)
        }
        .background(GH.Palette.terraSoft, in: RoundedRectangle(cornerRadius: GH.Radius.control, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: GH.Radius.control, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// Paper bits that fall about 26 pt into place over 1.4–1.6 s, then stay.
/// Whether they fall or are already lying there is decided once, when the
/// banner appears (`PlantPage.ConfettiLedger`).
struct BirthdayConfetti: View {
    static let width: CGFloat = 70
    let plantID: UUID?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var mode: Mode = .undecided

    private enum Mode: Equatable {
        case undecided
        case falling(since: Date)
        case settled
    }

    private struct Piece {
        let x: CGFloat       // from the strip's leading edge
        let y: CGFloat       // resting point from the top
        let size: CGSize
        let angle: Double    // resting rotation, degrees
        let color: Int
        let delay: Double
    }

    private static let pieces: [Piece] = [
        Piece(x: 12, y: 8, size: CGSize(width: 7, height: 12), angle: 24, color: 0, delay: 0.00),
        Piece(x: 40, y: 20, size: CGSize(width: 7, height: 12), angle: -30, color: 1, delay: 0.07),
        Piece(x: 24, y: 38, size: CGSize(width: 7, height: 12), angle: 60, color: 2, delay: 0.15),
        Piece(x: 52, y: 46, size: CGSize(width: 7, height: 12), angle: -12, color: 3, delay: 0.03),
        Piece(x: 16, y: 58, size: CGSize(width: 6, height: 6), angle: 80, color: 0, delay: 0.21),
        Piece(x: 42, y: 62, size: CGSize(width: 6, height: 6), angle: -50, color: 2, delay: 0.11),
        Piece(x: 58, y: 10, size: CGSize(width: 6, height: 6), angle: 10, color: 1, delay: 0.25),
    ]
    /// Each bit's fall; with the delays above the whole drift is 1.35–1.6 s.
    private static let fall: Double = 1.35
    /// Waits for the banner to grow in first.
    private static let startDelay: Double = 0.45

    private var fallingSince: Date? {
        if case .falling(let since) = mode { return since }
        return nil
    }

    var body: some View {
        let falling = fallingSince
        TimelineView(.animation(paused: falling == nil)) { timeline in
            let elapsed = falling.map { timeline.date.timeIntervalSince($0) - Self.startDelay } ?? .infinity
            Canvas { context, size in
                guard mode != .undecided else { return }
                for piece in Self.pieces {
                    let t = min(max((elapsed - piece.delay) / Self.fall, 0), 1)
                    let eased = 1 - pow(1 - t, 3)
                    // Banners grow taller at big text sizes; keep the bits inside.
                    let restY = min(piece.y, size.height - piece.size.height)
                    let y = restY - 26 * (1 - eased)
                    let x = piece.x + CGFloat(sin(t * .pi * 2)) * 3 * CGFloat(1 - eased)
                    var bit = context
                    bit.opacity = min(t * 3, 1)
                    bit.translateBy(x: x, y: y)
                    bit.rotate(by: .degrees(piece.angle - 90 * (1 - eased)))
                    let rect = CGRect(x: -piece.size.width / 2, y: -piece.size.height / 2,
                                      width: piece.size.width, height: piece.size.height)
                    let shape = piece.size.width == piece.size.height
                        ? Path(ellipseIn: rect)
                        : Path(roundedRect: rect, cornerRadius: 2)
                    bit.fill(shape, with: .color(GH.PlantPage.confetti[piece.color]))
                }
            }
        }
        .accessibilityHidden(true)
        .task {
            guard mode == .undecided else { return }
            let plays = PlantPage.ConfettiLedger.shouldPlay(plantID: plantID)
            guard plays, !reduceMotion else {
                mode = .settled
                return
            }
            mode = .falling(since: .now)
            try? await Task.sleep(for: .seconds(Self.startDelay + 1.7))
            mode = .settled
        }
    }
}

// MARK: - Title chips

/// Lays chips out left to right, wrapping onto new lines.
struct ChipFlow: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(width: proposal.width ?? .infinity, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(width: bounds.width, subviews: subviews)
        for (subview, origin) in zip(subviews, result.origins) {
            subview.place(at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y),
                          proposal: ProposedViewSize(width: min(subview.sizeThatFits(.unspecified).width, bounds.width), height: nil))
        }
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> (size: CGSize, origins: [CGPoint]) {
        var origins: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0, widest: CGFloat = 0
        for subview in subviews {
            var size = subview.sizeThatFits(.unspecified)
            size.width = min(size.width, width)
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

/// A quiet capsule ("Living room", "East-facing window"). Tappable ones get a
/// 44-pt hit area around the smaller capsule.
struct PlantChip: View {
    let text: String
    let systemImage: String
    var showsChevron = false

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.footnote.weight(.semibold))
                .accessibilityHidden(true)
            Text(text)
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(GH.Palette.ink2)
                    .accessibilityHidden(true)
            }
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(GH.Palette.ink)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .frame(minHeight: 30)
        .background(GH.Palette.surface2, in: Capsule(style: .continuous))
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
}

// MARK: - Stats

/// Waterings, milestones and photos as three cards with big rounded numbers.
/// At accessibility text sizes they stack.
struct PlantStatCards: View {
    let stats: PlantPage.Stats
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 10))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 10))
        layout {
            card(stats.waterings, one: "watering", many: "waterings", color: GH.Palette.skyInk)
            card(stats.milestones, one: "milestone", many: "milestones", color: GH.Palette.terraInk)
            card(stats.photos, one: "photo", many: "photos", color: GH.Palette.leafInk)
        }
    }

    private func card(_ value: Int, one: String, many: String, color: Color) -> some View {
        let label = value == 1 ? one : many
        // Stacked cards at accessibility sizes put the label beside the number.
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: GH.Space.s))
            : AnyLayout(VStackLayout(alignment: .leading, spacing: 0))
        return layout {
            GHDisplayNumber(value: "\(value)", color: color)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(label)
                .font(.subheadline)
                .foregroundStyle(GH.Palette.ink2)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, GH.Space.s)
        .ghCard()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(value) \(label)")
    }
}

// MARK: - Care history link

/// Opens the plant's care history. Its own card, so it stays put when Care is
/// folded, with a teaser of the latest entry ("Watered Tue by Alex").
struct CareHistoryLinkRow: View {
    let plant: Plant
    let teaser: String

    var body: some View {
        NavigationLink(value: CareHistoryRoute(plant: plant)) {
            HStack(spacing: GH.Space.s) {
                MiniThreadIcon()
                    .frame(width: 40, height: 24)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Care history")
                        .font(.ghRounded(.title3))
                        .foregroundStyle(GH.Palette.ink)
                    Text(teaser)
                        .font(.subheadline)
                        .foregroundStyle(GH.Palette.ink2)
                }
                .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(GH.Palette.ink2)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, GH.Space.m)
            .padding(.vertical, GH.Space.s)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: GH.Radius.card, style: .continuous))
            .ghCard()
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens everything done for this plant")
    }
}

/// Three little threads joining into one, the care history's mark.
struct MiniThreadIcon: View {
    var body: some View {
        Canvas { context, size in
            let sx = size.width / 40, sy = size.height / 24
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * sx, y: y * sy) }
            var left = Path()
            left.move(to: p(6, 20))
            left.addCurve(to: p(20, 4), control1: p(6, 12), control2: p(20, 12))
            var right = Path()
            right.move(to: p(34, 20))
            right.addCurve(to: p(20, 4), control1: p(34, 12), control2: p(20, 12))
            var middle = Path()
            middle.move(to: p(20, 20))
            middle.addLine(to: p(20, 4))
            let stroke = StrokeStyle(lineWidth: 2.4, lineCap: .round)
            context.stroke(left, with: .color(GH.threads[0]), style: stroke)
            context.stroke(right, with: .color(GH.threads[1]), style: stroke)
            context.stroke(middle, with: .color(GH.threads[3]), style: stroke)
        }
    }
}

// MARK: - Photos

/// Remembers where each strip thumbnail sits on screen, so the photo viewer
/// can grow out of (and shrink back into) the one tapped. A plain object on
/// purpose: frames change on every scroll frame and mustn't redraw the page.
final class PhotoFrameStore {
    var frames: [NSManagedObjectID: CGRect] = [:]
}

/// The newest three photos, newest first. The last says "+N" when there are
/// more; the viewer pages through them all.
struct PlantPhotoStrip: View {
    let items: [Lineage.TimelinePhoto]
    let total: Int
    /// The photo the viewer is showing, hidden here so it seems to have left.
    let hiddenID: NSManagedObjectID?
    let frames: PhotoFrameStore
    let onOpen: (Photo) -> Void

    var body: some View {
        HStack(spacing: GH.Space.xs) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                Button { onOpen(item.photo) } label: {
                    Color.clear
                        .aspectRatio(1, contentMode: .fit)
                        .overlay { PlantPhotoView(photo: item.photo, maxPixel: 400) }
                        .clipShape(RoundedRectangle(cornerRadius: GH.Radius.chip, style: .continuous))
                        .overlay(alignment: .bottomTrailing) {
                            if index == items.count - 1, total > items.count {
                                Text("+\(total - items.count)")
                                    .font(.ghRounded(.subheadline, weight: .bold))
                                    .foregroundStyle(GH.Palette.ink)
                                    .padding(.horizontal, GH.Space.xs)
                                    .padding(.vertical, GH.Space.xxs)
                                    .background(.regularMaterial, in: Capsule(style: .continuous))
                                    .padding(6)
                            }
                        }
                        .contentShape(RoundedRectangle(cornerRadius: GH.Radius.chip, style: .continuous))
                }
                .buttonStyle(.plain)
                .opacity(hiddenID == item.id ? 0 : 1)
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frames.frames[item.id] = $0 }
                .accessibilityLabel(label(for: item, index: index))
                .accessibilityHint("Opens the photo full screen")
            }
            // Keep thumbnails the same size when there are fewer than three.
            ForEach(min(items.count, 3)..<3, id: \.self) { _ in
                Color.clear.aspectRatio(1, contentMode: .fit)
            }
        }
    }

    private func label(for item: Lineage.TimelinePhoto, index: Int) -> String {
        var text = "Photo from \(item.photo.takenAt.map(Lineage.format) ?? "an unknown date")"
        if index == items.count - 1, total > items.count { text += ", \(total - items.count) more" }
        return text
    }
}

/// Empty-state art: grows in, then bobs ±5 pt on a 4.5 s loop. Reduce
/// Motion: it just fades in.
struct FloatingArt: View {
    let name: String
    var size: CGFloat = 150
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let art = Image(name)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
        Group {
            if reduceMotion {
                art
            } else {
                art.phaseAnimator([-5.0, 5.0]) { content, offset in
                    content.offset(y: offset)
                } animation: { _ in
                    .easeInOut(duration: 2.25)
                }
            }
        }
        .growIn()
    }
}

/// "No photos of Pip yet": the Photos section before the first picture.
struct PlantPhotosEmptyState: View {
    let name: String
    /// Nil for a retired plant, which can't take new photos.
    let onTakePhoto: (() -> Void)?

    var body: some View {
        VStack(spacing: GH.Space.xs) {
            FloatingArt(name: "EmptyCamera")
            Text("No photos of \(name) yet")
                .font(.ghRounded(.title3))
                .foregroundStyle(GH.Palette.ink)
                .multilineTextAlignment(.center)
                .growIn(index: 1)
            Text("Start a timeline you'll love scrolling back through.")
                .font(.subheadline)
                .foregroundStyle(GH.Palette.ink2)
                .multilineTextAlignment(.center)
                .growIn(index: 2)
            if let onTakePhoto {
                Button(action: onTakePhoto) {
                    Label("Take the first photo", systemImage: "camera")
                }
                .buttonStyle(.ghProminent)
                .padding(.top, GH.Space.xs)
                .growIn(index: 3)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, GH.Space.xs)
    }
}
