import CoreGraphics

/// The geometry behind cropping a photo: the image sits behind a fixed crop
/// window, filling it at zoom 1, and can be zoomed in and dragged. Whatever is
/// inside the window is the crop.
enum ImageCrop {
    enum Aspect: String, CaseIterable, Identifiable {
        case original, square, landscape, portrait

        var id: Self { self }

        var label: String {
            switch self {
            case .original: "Original"
            case .square: "Square"
            case .landscape: "4:3"
            case .portrait: "3:4"
            }
        }

        /// Width ÷ height.
        func ratio(for imageSize: CGSize) -> CGFloat {
            switch self {
            case .original: imageSize.width / imageSize.height
            case .square: 1
            case .landscape: 4 / 3
            case .portrait: 3 / 4
            }
        }
    }

    static let maxZoom: CGFloat = 5

    /// The biggest window of `ratio` that fits in `space`.
    static func window(ratio: CGFloat, in space: CGSize) -> CGSize {
        if space.width / space.height > ratio {
            CGSize(width: space.height * ratio, height: space.height)
        } else {
            CGSize(width: space.width, height: space.width / ratio)
        }
    }

    /// Points per image pixel on screen.
    static func scale(imageSize: CGSize, window: CGSize, zoom: CGFloat) -> CGFloat {
        max(window.width / imageSize.width, window.height / imageSize.height) * zoom
    }

    /// Keeps the image covering the whole window: the image's centre can move
    /// only as far as its overhang past the window.
    static func clamped(offset: CGSize, imageSize: CGSize, window: CGSize, zoom: CGFloat) -> CGSize {
        let k = scale(imageSize: imageSize, window: window, zoom: zoom)
        let maxX = max(0, (imageSize.width * k - window.width) / 2)
        let maxY = max(0, (imageSize.height * k - window.height) / 2)
        return CGSize(width: min(max(offset.width, -maxX), maxX), height: min(max(offset.height, -maxY), maxY))
    }

    /// The part of the image (in pixels) inside the window. `offset` is how
    /// far the image's centre is from the window's centre, in points.
    static func rect(imageSize: CGSize, window: CGSize, zoom: CGFloat, offset: CGSize) -> CGRect {
        let k = scale(imageSize: imageSize, window: window, zoom: zoom)
        let offset = clamped(offset: offset, imageSize: imageSize, window: window, zoom: zoom)
        let width = window.width / k
        let height = window.height / k
        let x = imageSize.width / 2 - offset.width / k - width / 2
        let y = imageSize.height / 2 - offset.height / k - height / 2
        return CGRect(x: x, y: y, width: width, height: height)
            .integral
            .intersection(CGRect(origin: .zero, size: imageSize))
    }
}
