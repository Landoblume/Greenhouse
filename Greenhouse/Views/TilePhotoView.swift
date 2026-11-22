import CoreData
import SwiftUI
import UIKit

/// Decoded tile thumbnails, kept so scrolling back doesn't decode again. A
/// photo that changes (a crop, here or on the other phone) gets a new version,
/// so its old thumbnails are never looked up.
final class TileThumbnailCache {
    static let shared = TileThumbnailCache()
    private let cache = NSCache<NSString, UIImage>()
    private var versions: [NSManagedObjectID: Int] = [:]
    private var observer: NSObjectProtocol?

    private init() {
        cache.countLimit = 160
        observer = NotificationCenter.default.addObserver(
            forName: .NSManagedObjectContextObjectsDidChange, object: nil, queue: .main
        ) { [weak self] note in
            for key in [NSUpdatedObjectsKey, NSRefreshedObjectsKey] {
                for photo in (note.userInfo?[key] as? Set<NSManagedObject> ?? []) where photo is Photo {
                    self?.versions[photo.objectID, default: 0] += 1
                }
            }
        }
    }

    func key(for photo: Photo, maxPixel: CGFloat) -> String {
        "\(photo.objectID.uriRepresentation().absoluteString)-\(versions[photo.objectID] ?? 0)-\(Int(maxPixel))"
    }

    func image(forKey key: String) -> UIImage? { cache.object(forKey: key as NSString) }
    func store(_ image: UIImage, forKey key: String) { cache.setObject(image, forKey: key as NSString) }
}

/// A plant photo for a grid tile. The picture is decoded off the main thread
/// while a soft leaf-green placeholder shows, then fades in, so a screenful of
/// tiles never holds up scrolling or the first draw.
struct TilePhotoView: View {
    let photo: Photo?
    let maxPixel: CGFloat
    @State private var loaded: UIImage?

    private var key: String? { photo.map { TileThumbnailCache.shared.key(for: $0, maxPixel: maxPixel) } }

    var body: some View {
        // Scrolling back to a tile reuses the cached picture on the first frame.
        let image = loaded ?? key.flatMap { TileThumbnailCache.shared.image(forKey: $0) }
        ZStack {
            GH.Palette.leafSoft
            if photo == nil {
                Image(systemName: "leaf.fill")
                    .font(.largeTitle)
                    .foregroundStyle(GH.Palette.leafInk.opacity(0.6))
            }
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .transition(.opacity)
            }
        }
        .task(id: key) { await load() }
    }

    private func load() async {
        guard let photo, let key else { return }
        if TileThumbnailCache.shared.image(forKey: key) != nil { return }
        guard let data = photo.imageData else { return }
        let pixel = maxPixel
        let decoded = await Task.detached(priority: .userInitiated) {
            ImageTools.thumbnail(from: data, maxPixel: pixel)
        }.value
        guard !Task.isCancelled, let decoded else { return }
        TileThumbnailCache.shared.store(decoded, forKey: key)
        withAnimation(.easeOut(duration: 0.2)) { loaded = decoded }
    }
}
