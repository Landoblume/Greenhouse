import SwiftUI

/// One draw-in: when the screen appeared or the level last changed. Rows
/// compare their own timing against it, so a row created after its moment
/// (by lazy loading, or scrolled to later) shows already drawn.
struct HistoryDrawClock: Equatable {
    var epoch = Date()
    /// Bumped by every draw-in: the lines draw again.
    var token = 0
    /// Bumped only on coming back to the screen: the dots spring in again
    /// too. A level change leaves them be, so they glide to their new spots.
    var visit = 0

    var elapsed: Double { Date().timeIntervalSince(epoch) }

    /// True while a row with this timing should still animate in.
    func animates(_ timing: CareHistory.DrawSchedule.RowTiming?) -> Bool {
        guard let timing else { return false }
        return elapsed < timing.settled + 0.25
    }

    mutating func restart() {
        epoch = Date()
        token += 1
    }

    /// Back on the screen: lines and dots both draw in again.
    mutating func replay() {
        restart()
        visit += 1
    }
}

/// Combine nodes that have already bloomed during this visit, so each pulses once.
final class HistoryBloomLedger {
    private var done: Set<String> = []
    func claim(_ id: String) -> Bool { done.insert(id).inserted }
    func reset() { done.removeAll() }
}

/// The threads' lines and the row's dot, drawn beside one row. Each row
/// draws its own piece from its top edge to its bottom edge, so pieces meet
/// exactly; the row's scroll motion is applied to its words only, never to
/// this gutter, so the threads stay continuous while scrolling.
struct HistoryThreadGutter: View {
    let rowID: String
    let lanes: [CareHistory.LaneMark]
    let threads: [CareHistory.CareThread]
    let geometry: LaneGeometry
    let nodeY: CGFloat
    /// One plant: this lane goes thick and the rest turn to hairlines.
    var focusLane: Int?
    /// The color of the plant a "became part of" node points to.
    var joinedColor: Int?
    let timing: CareHistory.DrawSchedule.RowTiming?
    let clock: HistoryDrawClock
    let reduceMotion: Bool
    let namespace: Namespace.ID
    let bloom: HistoryBloomLedger

    var body: some View {
        GeometryReader { proxy in
            let height = proxy.size.height
            let fresh = clock.animates(timing)
            let animate = fresh && !reduceMotion
            ZStack(alignment: .topLeading) {
                ZStack(alignment: .topLeading) {
                    ForEach(lanes.indices, id: \.self) { lane in
                        if let path = path(lane: lane, height: height) {
                            HistoryLanePiece(path: path, color: color(lane), width: width(lane), opacity: opacity(lane),
                                      span: timing?.lines[lane], animate: animate, clock: clock)
                        }
                    }
                }
                // A new level draws its lines again; the dots stay put and move.
                .id(clock.token)

                if let lane = lanes.firstIndex(where: \.dot), let glyph = lanes[lane].glyph, lane < threads.count {
                    HistoryDotView(
                        id: rowID,
                        glyph: glyph,
                        color: glyph == .joined ? CareHistoryStyle.color(joinedColor ?? threads[lane].color) : color(lane),
                        delay: timing?.dot,
                        fresh: fresh,
                        reduceMotion: reduceMotion,
                        clock: clock,
                        bloom: bloom
                    )
                    .id(clock.visit)
                    // Under Reduce Motion levels crossfade, so dots don't travel.
                    .modifier(HistoryDotIdentity(id: rowID, namespace: reduceMotion ? nil : namespace))
                    .position(x: geometry.x(threads[lane].column), y: nodeY)
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func isFocus(_ lane: Int) -> Bool { focusLane == nil || focusLane == lane }
    private func color(_ lane: Int) -> Color { CareHistoryStyle.color(lane < threads.count ? threads[lane].color : lane) }
    private func width(_ lane: Int) -> CGFloat {
        guard let focusLane else { return CareHistoryStyle.thread }
        return focusLane == lane ? CareHistoryStyle.focusThread : CareHistoryStyle.hairline
    }
    private func opacity(_ lane: Int) -> Double { isFocus(lane) ? 1 : CareHistoryStyle.hairlineOpacity }

    /// The lane's whole piece in this row, top to bottom, so trimming it draws it newest first.
    private func path(lane: Int, height: CGFloat) -> Path? {
        guard lane < threads.count else { return nil }
        let mark = lanes[lane]
        let x = geometry.x(threads[lane].column)
        var path = Path()
        var drew = false
        if let into = mark.joinsLane, into < threads.count {
            // An original leaving the combined plant's node: a cubic with
            // vertical ends, then on down its own lane.
            let from = CGPoint(x: geometry.x(threads[into].column), y: nodeY)
            let span = max(min(CareHistoryStyle.branch, height - nodeY), 1)
            let to = CGPoint(x: x, y: nodeY + span)
            path.move(to: from)
            path.addCurve(to: to, control1: CGPoint(x: from.x, y: nodeY + span / 2), control2: CGPoint(x: x, y: nodeY + span / 2))
            if mark.lineBelow, to.y < height { path.addLine(to: CGPoint(x: x, y: height)) }
            return path
        }
        if mark.lineAbove {
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: mark.dot && !mark.lineBelow ? nodeY : (mark.lineBelow ? height : nodeY)))
            drew = true
        }
        if mark.lineBelow, !mark.lineAbove {
            path.move(to: CGPoint(x: x, y: mark.dot ? nodeY : 0))
            path.addLine(to: CGPoint(x: x, y: height))
            drew = true
        }
        return drew ? path : nil
    }
}

/// A dot keeps its identity across levels, so it moves to its new spot.
private struct HistoryDotIdentity: ViewModifier {
    let id: String
    let namespace: Namespace.ID?

    func body(content: Content) -> some View {
        if let namespace {
            content.matchedGeometryEffect(id: id, in: namespace)
        } else {
            content
        }
    }
}

/// One lane's line in one row. Trims in on its own timing. Square ends, so
/// pieces in neighboring rows meet without overlapping (which would show as
/// darker ticks on the translucent hairlines).
private struct HistoryLanePiece: View {
    let path: Path
    let color: Color
    let width: CGFloat
    let opacity: Double
    let span: CareHistory.DrawSchedule.Span?
    let clock: HistoryDrawClock
    @State private var progress: CGFloat

    init(path: Path, color: Color, width: CGFloat, opacity: Double, span: CareHistory.DrawSchedule.Span?,
         animate: Bool, clock: HistoryDrawClock) {
        self.path = path
        self.color = color
        self.width = width
        self.opacity = opacity
        self.span = span
        self.clock = clock
        _progress = State(initialValue: animate && span != nil ? 0 : 1)
    }

    var body: some View {
        path.trim(from: 0, to: progress)
            .stroke(color.opacity(opacity), style: StrokeStyle(lineWidth: width, lineCap: .butt))
            .onAppear {
                guard progress < 1, let span else { return }
                let wait = max(0, span.delay - clock.elapsed)
                withAnimation(.linear(duration: max(span.duration, 0.01)).delay(wait)) { progress = 1 }
            }
    }
}

/// A row's dot. Springs in as the line passes it (a fade under Reduce
/// Motion). A combine node blooms once, the first time it comes into view.
private struct HistoryDotView: View {
    let id: String
    let glyph: CareHistory.Glyph
    let color: Color
    let delay: Double?
    let reduceMotion: Bool
    let clock: HistoryDrawClock
    let bloom: HistoryBloomLedger
    @State private var shown: Bool
    @State private var blooms = 0

    init(id: String, glyph: CareHistory.Glyph, color: Color, delay: Double?, fresh: Bool,
         reduceMotion: Bool, clock: HistoryDrawClock, bloom: HistoryBloomLedger) {
        self.id = id
        self.glyph = glyph
        self.color = color
        self.delay = delay
        self.reduceMotion = reduceMotion
        self.clock = clock
        self.bloom = bloom
        // Reduce Motion draws the lines at once, but the dots still fade in.
        _shown = State(initialValue: !(fresh && delay != nil))
    }

    var body: some View {
        HistoryGlyphView(glyph: glyph, color: color)
            .scaleEffect(shown || reduceMotion ? 1 : 0.2)
            .opacity(shown ? 1 : 0)
            .phaseAnimator([1.0, 1.12, 1.0], trigger: blooms) { view, scale in
                view.scaleEffect(scale)
            } animation: { _ in .spring(duration: 0.25, bounce: 0.3) }
            .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.6), trigger: blooms)
            .onAppear {
                let wait = max(0, (delay ?? 0) - clock.elapsed)
                if !shown {
                    withAnimation((reduceMotion ? GH.Motion.reduced : GH.Motion.dot).delay(wait)) { shown = true }
                }
                guard glyph == .merge, !reduceMotion, bloom.claim(id) else { return }
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(wait + 0.35))
                    blooms += 1
                }
            }
    }
}

/// The shape of a dot: the kind reads from the shape, not just the color.
struct HistoryGlyphView: View {
    let glyph: CareHistory.Glyph
    let color: Color

    private let paper = GH.Palette.paper

    var body: some View {
        switch glyph {
        case .watering:
            Circle().fill(color)
                .frame(width: CareHistoryStyle.dot, height: CareHistoryStyle.dot)
                .background(Circle().fill(paper).padding(-CareHistoryStyle.halo))
        case .task:
            Circle().fill(paper)
                .overlay(Circle().stroke(color, lineWidth: 3))
                .frame(width: CareHistoryStyle.dot - 2, height: CareHistoryStyle.dot - 2)
        case .milestone:
            Rectangle().fill(color)
                .frame(width: CareHistoryStyle.dot, height: CareHistoryStyle.dot)
                .rotationEffect(.degrees(45))
                .background(Rectangle().fill(paper).padding(-CareHistoryStyle.halo).rotationEffect(.degrees(45)))
        case .cutting:
            ZStack {
                Path { p in
                    p.move(to: CGPoint(x: 9, y: 9))
                    p.addQuadCurve(to: CGPoint(x: 20, y: -2), control: CGPoint(x: 9, y: 0))
                }
                .stroke(color, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: [1, 5]))
                Circle().fill(color)
                    .frame(width: CareHistoryStyle.dot, height: CareHistoryStyle.dot)
                    .background(Circle().fill(paper).padding(-CareHistoryStyle.halo))
                    .position(x: 9, y: 9)
            }
            .frame(width: 18, height: 18)
        case .merge, .joined:
            Circle().fill(paper)
                .overlay(Circle().stroke(color, lineWidth: 3))
                .overlay {
                    Image(systemName: glyph == .merge ? "arrow.triangle.merge" : "arrow.up.forward")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(color)
                }
                .frame(width: CareHistoryStyle.node, height: CareHistoryStyle.node)
        }
    }
}
