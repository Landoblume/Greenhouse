import Foundation
import Photos

/// What this app may do in the phone's photo library.
enum PhotoLibraryAccess: Equatable {
    case notDetermined
    case allowed
    /// "Limited access": the person picked which photos the app sees. New
    /// photos can still be added, but albums may be hidden from the app.
    case limited
    case denied
}

/// The PhotoKit calls the saver needs, behind a protocol so tests can fake
/// the library.
protocol PhotoLibraryStore {
    func access() -> PhotoLibraryAccess
    func requestAccess() async -> PhotoLibraryAccess
    func albumExists(id: String) -> Bool
    /// The local identifier of an album with this title, if there is one.
    func findAlbum(named name: String) -> String?
    func createAlbum(named name: String) async throws -> String
    /// Adds the photo to the library, and to the album when `albumID` is set.
    func save(_ data: Data, toAlbum albumID: String?) async throws
}

/// Copies photos taken with the in-app camera into this phone's photo
/// library, in a "Greenhouse" album, the way the system camera keeps what it
/// shoots. Library picks and photos synced from the other phone never come
/// through here.
///
/// Per phone (UserDefaults): whether it's on, the album's local identifier,
/// and whether we've already said that access is off.
@MainActor
final class PhotoLibrarySaver {
    static let shared = PhotoLibrarySaver()

    static let albumName = "Greenhouse"
    /// "Save new photos to Photos" in Settings; on unless turned off.
    static let enabledKey = "savePhotosToLibrary"
    static let albumIDKey = "photoLibraryAlbumID"
    static let deniedNoticeKey = "photoLibraryDeniedNoticeShown"

    static let deniedNotice = "Greenhouse can't add photos to your library, so this one is only in Greenhouse. You can allow it in Settings → Greenhouse → Photos."

    enum Outcome: Equatable {
        case saved
        /// Turned off in Settings.
        case off
        /// No access. `tellUser` is true the first time only.
        case denied(tellUser: Bool)
        case failed
    }

    static func isEnabled(in defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: enabledKey) as? Bool ?? true
    }

    private let library: PhotoLibraryStore
    private let defaults: UserDefaults
    /// The save in progress. Each save waits for the one before, so two quick
    /// shots on a first run don't make two albums.
    private var last: Task<Outcome, Never>?

    init(library: PhotoLibraryStore = SystemPhotoLibrary(), defaults: UserDefaults = .standard) {
        self.library = library
        self.defaults = defaults
    }

    /// Saves one captured photo (as encoded image data, ideally the camera's
    /// own file with its metadata). Asks for access the first time.
    @discardableResult
    func save(_ data: Data) async -> Outcome {
        let previous = last
        let task = Task { @MainActor in
            _ = await previous?.value
            return await perform(data)
        }
        last = task
        return await task.value
    }

    private func perform(_ data: Data) async -> Outcome {
        guard Self.isEnabled(in: defaults) else { return .off }
        var access = library.access()
        if access == .notDetermined { access = await library.requestAccess() }
        guard access == .allowed || access == .limited else {
            let tell = !defaults.bool(forKey: Self.deniedNoticeKey)
            defaults.set(true, forKey: Self.deniedNoticeKey)
            return .denied(tellUser: tell)
        }
        // Allowed again: if it's ever taken away, say so again.
        defaults.removeObject(forKey: Self.deniedNoticeKey)
        do {
            try await library.save(data, toAlbum: try await albumID(access: access))
            return .saved
        } catch {
            // The album couldn't be used (limited access can hide it, or it
            // was deleted mid-save): the photo still goes in the library.
            do {
                try await library.save(data, toAlbum: nil)
                return .saved
            } catch {
                return .failed
            }
        }
    }

    /// The album to save into: the stored one if it's still there, otherwise
    /// an existing "Greenhouse" album, otherwise a new one (created on the
    /// first save, and again if the person deleted it). Under limited access
    /// the app may not see its own album, so a stored id is trusted rather
    /// than making a duplicate on every save.
    private func albumID(access: PhotoLibraryAccess) async throws -> String {
        if let stored = defaults.string(forKey: Self.albumIDKey),
           access == .limited || library.albumExists(id: stored) {
            return stored
        }
        let id: String
        if let found = library.findAlbum(named: Self.albumName) {
            id = found
        } else {
            id = try await library.createAlbum(named: Self.albumName)
        }
        defaults.set(id, forKey: Self.albumIDKey)
        return id
    }
}

/// The real photo library.
struct SystemPhotoLibrary: PhotoLibraryStore {
    enum Failure: Error { case albumMissing, noIdentifier }

    func access() -> PhotoLibraryAccess {
        Self.map(PHPhotoLibrary.authorizationStatus(for: .readWrite))
    }

    func requestAccess() async -> PhotoLibraryAccess {
        Self.map(await PHPhotoLibrary.requestAuthorization(for: .readWrite))
    }

    func albumExists(id: String) -> Bool {
        PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [id], options: nil).firstObject != nil
    }

    func findAlbum(named name: String) -> String? {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "title == %@", name)
        return PHAssetCollection.fetchAssetCollections(with: .album, subtype: .albumRegular, options: options)
            .firstObject?.localIdentifier
    }

    func createAlbum(named name: String) async throws -> String {
        let box = IdentifierBox()
        try await PHPhotoLibrary.shared().performChanges {
            box.value = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: name)
                .placeholderForCreatedAssetCollection.localIdentifier
        }
        guard let id = box.value else { throw Failure.noIdentifier }
        return id
    }

    func save(_ data: Data, toAlbum albumID: String?) async throws {
        let album = albumID.flatMap {
            PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [$0], options: nil).firstObject
        }
        if albumID != nil, album == nil { throw Failure.albumMissing }
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            request.addResource(with: .photo, data: data, options: nil)
            if let album, let placeholder = request.placeholderForCreatedAsset {
                PHAssetCollectionChangeRequest(for: album)?.addAssets([placeholder] as NSArray)
            }
        }
    }

    private static func map(_ status: PHAuthorizationStatus) -> PhotoLibraryAccess {
        switch status {
        case .authorized: return .allowed
        case .limited: return .limited
        case .notDetermined: return .notDetermined
        default: return .denied
        }
    }

    /// Carries the new album's id out of the change block.
    private final class IdentifierBox: @unchecked Sendable {
        var value: String?
    }
}
