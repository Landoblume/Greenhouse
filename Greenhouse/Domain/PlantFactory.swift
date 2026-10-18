import CoreData
import ImageIO
import UIKit

/// Creating plants and photos.
enum PlantFactory {
    @discardableResult
    static func create(
        scientificName: String,
        species: Species?,
        nickname: String?,
        acquired: Date,
        location: String?,
        setting: PlantSetting,
        lightSource: LightSource? = nil,
        waterEvery days: Int,
        photo: Data?,
        photoTakenAt: Date? = nil,
        collections: [PlantCollection] = [],
        now: Date = .now,
        household: Household,
        context: NSManagedObjectContext,
        persistence: Persistence = .shared
    ) -> Plant {
        let plant = persistence.insert(Plant.self, alongside: household, in: context)
        plant.uuid = UUID()
        plant.createdAt = now
        plant.scientificName = species?.latin ?? scientificName.trimmingCharacters(in: .whitespaces)
        plant.commonName = species?.primaryCommonName
        plant.catalogID = species?.id
        plant.nickname = nonEmpty(nickname)
        plant.acquiredDate = acquired
        plant.location = nonEmpty(location)
        plant.settingValue = setting
        plant.lightSourceValue = lightSource
        plant.statusValue = .active
        plant.household = household
        plant.mutableSetValue(forKey: "collections").addObjects(from: collections)

        let firstDue = CareSchedule.addInterval(days, .day, to: Calendar.current.startOfDay(for: now))
        CareSchedule.makeTask(name: "Water", count: days, unit: .day, firstDue: firstDue, isWatering: true,
                              plants: [plant], household: household, context: context, persistence: persistence)

        if let photo {
            addPhoto(photo, takenAt: photoTakenAt ?? now, to: plant, household: household, context: context, persistence: persistence)
        }
        return plant
    }

    @discardableResult
    static func addPhoto(
        _ data: Data,
        takenAt: Date,
        caption: String? = nil,
        to plant: Plant,
        household: Household,
        context: NSManagedObjectContext,
        persistence: Persistence = .shared
    ) -> Photo {
        let photo = persistence.insert(Photo.self, alongside: household, in: context)
        photo.uuid = UUID()
        photo.takenAt = takenAt
        photo.caption = nonEmpty(caption)
        photo.imageData = data
        photo.plant = plant
        return photo
    }

    private static func nonEmpty(_ text: String?) -> String? {
        let trimmed = text?.trimmingCharacters(in: .whitespaces) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Notes as stored: trimmed, and nil when there's nothing left.
    static func cleanNotes(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

enum ImageTools {
    /// Shrinks a photo to fit `maxDimension` and JPEG-encodes it, which keeps
    /// it around 0.5–1.5 MB. Photos count against the household owner's
    /// iCloud storage, so full-size camera files would add up fast.
    static func preparedJPEG(from image: UIImage, maxDimension: CGFloat = 2048, quality: CGFloat = 0.75) -> Data? {
        let longest = max(image.size.width, image.size.height)
        let scale = min(1, maxDimension / longest)
        let size = CGSize(width: (image.size.width * scale).rounded(), height: (image.size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        // Drawing also bakes the camera's rotation into the pixels.
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return resized.jpegData(compressionQuality: quality)
    }

    /// Redraws the image upright at its pixel size, so pixel coordinates
    /// match what's on screen (camera photos are often stored sideways with a
    /// rotation flag).
    static func upright(_ image: UIImage) -> UIImage {
        guard image.imageOrientation != .up || image.scale != 1 else { return image }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let size = CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    /// Cuts `rect` (in pixels) out of an upright image.
    static func cropped(_ image: UIImage, to rect: CGRect) -> UIImage? {
        upright(image).cgImage?.cropping(to: rect).map { UIImage(cgImage: $0) }
    }

    /// Decodes a small version without loading the full image into memory.
    static func thumbnail(from data: Data, maxPixel: CGFloat) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

/// Keeps decoded thumbnails around so scrolling the grid doesn't re-decode.
final class ThumbnailCache {
    static let shared = ThumbnailCache()
    private let cache = NSCache<NSString, UIImage>()
    /// Bumped when a photo changes (a crop, here or on the other phone), so
    /// the old thumbnails are no longer looked up.
    private var versions: [NSManagedObjectID: Int] = [:]
    private var observer: NSObjectProtocol?

    private init() {
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

    func forget(_ photo: Photo) {
        versions[photo.objectID, default: 0] += 1
    }

    func image(for photo: Photo, maxPixel: CGFloat) -> UIImage? {
        let version = versions[photo.objectID] ?? 0
        let key = "\(photo.objectID.uriRepresentation().absoluteString)-\(version)-\(Int(maxPixel))" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let data = photo.imageData, let image = ImageTools.thumbnail(from: data, maxPixel: maxPixel) else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }
}
