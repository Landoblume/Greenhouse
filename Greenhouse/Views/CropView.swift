import SwiftUI

/// Pinch to zoom and drag the photo behind a crop window, pick a shape, and
/// Done hands back the cropped image.
struct CropView: View {
    let onDone: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss
    private let image: UIImage
    @State private var aspect: ImageCrop.Aspect = .original
    @State private var zoom: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var zoomAtStart: CGFloat?
    @State private var offsetAtStart: CGSize?
    @State private var window: CGSize = .zero

    init(image: UIImage, onDone: @escaping (UIImage) -> Void) {
        self.image = ImageTools.upright(image)
        self.onDone = onDone
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                GeometryReader { geo in
                    let window = ImageCrop.window(ratio: aspect.ratio(for: image.size),
                                                  in: CGSize(width: geo.size.width - 32, height: geo.size.height - 32))
                    let k = ImageCrop.scale(imageSize: image.size, window: window, zoom: zoom)
                    ZStack {
                        Image(uiImage: image)
                            .resizable()
                            .frame(width: image.size.width * k, height: image.size.height * k)
                            .offset(offset)
                        // Dim everything outside the window.
                        Rectangle()
                            .fill(.black.opacity(0.6))
                            .overlay {
                                Rectangle()
                                    .frame(width: window.width, height: window.height)
                                    .blendMode(.destinationOut)
                            }
                            .compositingGroup()
                            .allowsHitTesting(false)
                        Rectangle()
                            .stroke(.white, lineWidth: 1.5)
                            .frame(width: window.width, height: window.height)
                            .allowsHitTesting(false)
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
                    .contentShape(Rectangle())
                    .gesture(gestures(window: window))
                    .onAppear { self.window = window }
                    .onChange(of: window) { _, new in
                        self.window = new
                        offset = ImageCrop.clamped(offset: offset, imageSize: image.size, window: new, zoom: zoom)
                    }
                }
                .background(.black)

                Picker("Shape", selection: $aspect) {
                    ForEach(ImageCrop.Aspect.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                Text("Pinch to zoom, drag to move.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom)
            .navigationTitle("Crop")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .principal) {
                    Button("Reset") {
                        zoom = 1
                        offset = .zero
                        aspect = .original
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        let rect = ImageCrop.rect(imageSize: image.size, window: window, zoom: zoom, offset: offset)
                        if let cropped = ImageTools.cropped(image, to: rect) { onDone(cropped) }
                        dismiss()
                    }
                    .disabled(window == .zero)
                }
            }
        }
    }

    private func gestures(window: CGSize) -> some Gesture {
        let pinch = MagnifyGesture()
            .onChanged { value in
                let start = zoomAtStart ?? zoom
                zoomAtStart = start
                zoom = min(max(start * value.magnification, 1), ImageCrop.maxZoom)
                offset = ImageCrop.clamped(offset: offset, imageSize: image.size, window: window, zoom: zoom)
            }
            .onEnded { _ in zoomAtStart = nil }
        let drag = DragGesture()
            .onChanged { value in
                let start = offsetAtStart ?? offset
                offsetAtStart = start
                let moved = CGSize(width: start.width + value.translation.width, height: start.height + value.translation.height)
                offset = ImageCrop.clamped(offset: moved, imageSize: image.size, window: window, zoom: zoom)
            }
            .onEnded { _ in offsetAtStart = nil }
        return SimultaneousGesture(pinch, drag)
    }
}
