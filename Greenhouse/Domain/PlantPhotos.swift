import CoreData
import ImageIO
import UIKit

/// Changing photos after they're added: the main photo, captions, dates, and
/// deleting them.
enum PlantPhotos {
    /// The photo on the plant's tile and at the top of its page: the main
    /// photo (the first one added, or one picked later) if it still exists,
    /// otherwise the oldest.
    static func cover(for plant: Plant) -> Photo? {
        let timeline = Lineage.timeline(for: plant)
        if let id = plant.coverPhotoID, let picked = timeline.first(where: { $0.photo.uuid == id }) {
            return picked.photo
        }
        return timeline.first?.photo
    }

    static func isCover(_ photo: Photo, of plant: Plant) -> Bool {
        cover(for: plant) == photo
    }

    static func setCover(_ photo: Photo, of plant: Plant) {
        plant.coverPhotoID = photo.uuid
    }

    static func update(_ photo: Photo, caption: String, takenAt: Date) {
        let trimmed = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        photo.caption = trimmed.isEmpty ? nil : trimmed
        photo.takenAt = takenAt
    }

    /// Swaps in a cropped version of the photo, for both phones. The date and
    /// caption stay.
    static func replaceImage(of photo: Photo, with image: UIImage) {
        guard let data = ImageTools.preparedJPEG(from: image) else { return }
        ThumbnailCache.shared.forget(photo)
        photo.imageData = data
    }

    /// Deletes the photo for everyone in the household. Any plant that used it
    /// as its main photo goes back to showing the oldest one.
    static func delete(_ photo: Photo, context: NSManagedObjectContext) {
        if let id = photo.uuid {
            let request = NSFetchRequest<Plant>(entityName: "Plant")
            request.predicate = NSPredicate(format: "coverPhotoID == %@", id as CVarArg)
            for plant in (try? context.fetch(request)) ?? [] {
                plant.coverPhotoID = nil
            }
        }
        context.delete(photo)
    }

    /// When the photo was taken, read from the camera's EXIF data. Photos
    /// picked from the library keep this, so a photo from last spring is dated
    /// last spring instead of today.
    static func captureDate(from data: Data) -> Date? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { return nil }
        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any]
        let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        let raw = exif?[kCGImagePropertyExifDateTimeOriginal] as? String
            ?? exif?[kCGImagePropertyExifDateTimeDigitized] as? String
            ?? tiff?[kCGImagePropertyTIFFDateTime] as? String
        guard let raw else { return nil }
        // EXIF dates are local time with no zone, e.g. "2026:04:12 15:30:02".
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return formatter.date(from: raw)
    }
}
