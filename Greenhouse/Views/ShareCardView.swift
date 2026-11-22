import CoreTransferable
import SwiftUI
import UniformTypeIdentifiers

/// Paper (light) or night (dark) card.
enum ShareCardStyle: String, CaseIterable, Identifiable {
    case paper, night
    var id: String { rawValue }
    var label: String { self == .paper ? "Paper" : "Night" }
    var colorScheme: ColorScheme { self == .paper ? .light : .dark }
}

/// The "then vs now" share card for one plant: a preview, the paper/night
/// choice and the share sheet. Present it in a sheet; it brings its own
/// navigation bar and Done button.
struct ShareCardView: View {
    @ObservedObject var plant: Plant
    @State private var style: ShareCardStyle
    @State private var rendered: UIImage?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(plant: Plant, style: ShareCardStyle = .paper) {
        self.plant = plant
        _style = State(initialValue: style)
    }

    var body: some View {
        let content = ShareCard.content(for: plant)
        NavigationStack {
            ScrollView {
                VStack(spacing: GH.Space.l) {
                    Group {
                        if let rendered {
                            Image(uiImage: rendered)
                                .resizable()
                                .scaledToFit()
                                .transition(.opacity)
                        } else {
                            RoundedRectangle(cornerRadius: ShareCardCanvas.corner, style: .continuous)
                                .fill(GH.Palette.surface2)
                                .aspectRatio(ShareCardCanvas.size, contentMode: .fit)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: ShareCardCanvas.corner, style: .continuous))
                    .shadow(color: .black.opacity(0.14), radius: 24, y: 12)
                    .frame(maxWidth: 420)
                    .accessibilityElement()
                    .accessibilityAddTraits(.isImage)
                    .accessibilityLabel(Self.accessibilityText(content))

                    Picker("Card style", selection: $style) {
                        ForEach(ShareCardStyle.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 420)

                    if let rendered {
                        ShareLink(item: ShareCardImage(image: rendered),
                                  preview: SharePreview("\(content.name), then vs now", image: Image(uiImage: rendered))) {
                            Label("Share", systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.ghProminent)
                        .frame(maxWidth: 420)
                    }
                }
                .padding(GH.Space.screen)
                .frame(maxWidth: .infinity)
            }
            .background(GH.Palette.paper.ignoresSafeArea())
            .navigationTitle("Then vs now")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .task(id: style) { render(content) }
        }
    }

    /// The export: 1080 × 1350 (4:5), drawn at 3× from 360 × 450 points.
    @MainActor
    private func render(_ content: ShareCard.Content) {
        let renderer = ImageRenderer(content: ShareCardCanvas(content: content, style: style))
        renderer.scale = 3
        let image = renderer.uiImage
        withAnimation(reduceMotion ? GH.Motion.reduced : .easeInOut(duration: 0.25)) { rendered = image }
    }

    static func accessibilityText(_ content: ShareCard.Content) -> String {
        var parts = ["Share card for \(content.name)"]
        if let latin = content.latin { parts.append(latin) }
        parts.append("\(content.growth.value) \(content.growth.unit)")
        parts.append(content.grownBy)
        return parts.joined(separator: ". ")
    }
}

/// The share card itself, at a fixed size so every export looks the same
/// whatever the phone's text size. Materials don't render off screen, so the
/// "glass" labels are a translucent surface.
struct ShareCardCanvas: View {
    static let size = CGSize(width: 360, height: 450)
    static let corner: CGFloat = 24

    let content: ShareCard.Content
    let style: ShareCardStyle

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                HStack(spacing: 6) {
                    AppIconImage()
                        .frame(width: 20, height: 20)
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    Text("Greenhouse")
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                        .foregroundStyle(GH.Palette.leafInk)
                }
                Spacer()
                Text("Then vs now")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(GH.Palette.ink2)
            }
            .frame(height: 20)

            HStack(spacing: 8) {
                photo(content.then, label: "Then", date: content.thenDate, fallback: "EmptySeedling")
                    .saturation(0.9)
                photo(content.now, label: "Now", date: content.now == nil ? nil : content.nowDate, fallback: "EmptyCamera")
            }
            .frame(height: 200)
            .padding(.top, 14)

            VStack(alignment: .leading, spacing: 0) {
                Text(content.name)
                    .font(.system(size: 37, weight: .black, design: .rounded))
                    .tracking(-0.5)
                    .foregroundStyle(GH.Palette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                if let latin = content.latin {
                    Text(latin)
                        .font(.system(size: 13.5).italic())
                        .foregroundStyle(GH.Palette.ink2)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            .padding(.top, 16)

            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text("\(content.growth.value)")
                    .font(.system(size: 51, weight: .black, design: .rounded))
                    .foregroundStyle(GH.Palette.leafInk)
                Text(content.growth.unit)
                    .font(.system(size: 17.5, weight: .heavy, design: .rounded))
                    .foregroundStyle(GH.Palette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .padding(.top, 4)

            Spacer(minLength: 0)

            HStack(spacing: 8) {
                ThreadSquiggle()
                    .frame(width: 107, height: 16)
                Text(content.grownBy)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(GH.Palette.ink2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .padding(24)
        .frame(width: Self.size.width, height: Self.size.height)
        .background {
            ZStack {
                GH.Palette.paper
                RadialGradient(colors: [Color(red: 1, green: 0.94, blue: 0.78).opacity(0.22), .clear],
                               center: UnitPoint(x: 0.85, y: 0.08), startRadius: 0, endRadius: 170)
            }
        }
        .environment(\.colorScheme, style.colorScheme)
        .dynamicTypeSize(.large)
    }

    private func photo(_ photo: Photo?, label: String, date: Date?, fallback: String) -> some View {
        // The photo hangs off a flexible base, so a fill-scaled image can't
        // widen the row past the card's padding.
        Color.clear
            .overlay {
                if let photo, let image = ThumbnailCache.shared.image(for: photo, maxPixel: 900) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    GH.Palette.leafSoft
                        .overlay(alignment: .bottom) {
                            Image(fallback)
                                .resizable()
                                .scaledToFit()
                                .padding(.horizontal, 18)
                                .padding(.bottom, 6)
                        }
                }
            }
            .clipped()
            .overlay(alignment: .topLeading) {
                Text(date.map { "\(label) · \($0.formatted(.dateTime.month(.abbreviated).year()))" } ?? label)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(GH.Palette.ink)
                    .padding(.horizontal, 8)
                    .frame(height: 20)
                    .background(GH.Palette.surface.opacity(0.78), in: Capsule())
                    .padding(8)
            }
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

/// A short braided thread, like the care history's.
private struct ThreadSquiggle: View {
    var body: some View {
        Canvas { context, size in
            let sx = size.width / 160, sy = size.height / 24
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * sx, y: y * sy) }
            var line = Path()
            line.move(to: p(2, 18))
            line.addCurve(to: p(60, 6), control1: p(30, 18), control2: p(34, 6))
            line.addCurve(to: p(118, 14), control1: p(86, 6), control2: p(92, 18))
            line.addCurve(to: p(158, 6), control1: p(144, 10), control2: p(150, 6))
            context.stroke(line, with: .color(GH.threads[3]), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            for (x, y, color) in [(60.0, 6.0, GH.threads[0]), (118, 14, GH.threads[1]), (158, 6, GH.threads[3])] {
                let r = 2.7
                context.fill(Path(ellipseIn: CGRect(x: x * sx - r, y: y * sy - r, width: r * 2, height: r * 2)), with: .color(color))
            }
        }
    }
}

/// The app's own icon, read from the bundle (the asset catalog's app icon
/// can't be loaded by name); a leaf if it isn't there.
private struct AppIconImage: View {
    private static let icon: UIImage? = {
        guard let icons = Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any],
              let primary = icons["CFBundlePrimaryIcon"] as? [String: Any],
              let files = primary["CFBundleIconFiles"] as? [String],
              let name = files.last else { return nil }
        return UIImage(named: name)
    }()

    var body: some View {
        if let icon = Self.icon {
            Image(uiImage: icon).resizable().scaledToFill()
        } else {
            GH.Palette.leaf.overlay(Image(systemName: "leaf.fill").font(.system(size: 11)).foregroundStyle(GH.Palette.onLeaf))
        }
    }
}

/// The rendered card, shared as a PNG.
struct ShareCardImage: Transferable {
    let image: UIImage

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { $0.image.pngData() ?? Data() }
    }
}
