import XCTest
@testable import Greenhouse

/// A photo library in memory: albums by id, what was saved where.
private final class FakeLibrary: PhotoLibraryStore {
    var status: PhotoLibraryAccess = .allowed
    var answer: PhotoLibraryAccess = .allowed
    var requests = 0
    /// id → title
    var albums: [String: String] = [:]
    /// Limited access can hide albums from the app.
    var albumsHidden = false
    var created = 0
    var failSavesIntoAlbums = false
    var saved: [(data: Data, album: String?)] = []

    func access() -> PhotoLibraryAccess { status }

    func requestAccess() async -> PhotoLibraryAccess {
        requests += 1
        status = answer
        return answer
    }

    func albumExists(id: String) -> Bool { !albumsHidden && albums[id] != nil }

    func findAlbum(named name: String) -> String? {
        albumsHidden ? nil : albums.first { $0.value == name }?.key
    }

    func createAlbum(named name: String) async throws -> String {
        await Task.yield()  // lets a second save run in between, if it can
        created += 1
        let id = "album-\(created)"
        albums[id] = name
        return id
    }

    func save(_ data: Data, toAlbum albumID: String?) async throws {
        if let albumID {
            if failSavesIntoAlbums || albums[albumID] == nil { throw SystemPhotoLibrary.Failure.albumMissing }
        }
        saved.append((data, albumID))
    }
}

@MainActor
final class PhotoLibrarySaverTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite = ""

    override func setUp() {
        super.setUp()
        suite = "PhotoLibrarySaverTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    private let photo = Data([0xFF, 0xD8, 0x01])

    func testTheFirstSaveMakesTheAlbumAndLaterOnesReuseIt() async {
        let library = FakeLibrary()
        let saver = PhotoLibrarySaver(library: library, defaults: defaults)
        let first = await saver.save(photo)
        let second = await saver.save(photo)
        XCTAssertEqual(first, .saved)
        XCTAssertEqual(second, .saved)
        XCTAssertEqual(library.created, 1)
        XCTAssertEqual(library.albums["album-1"], "Greenhouse")
        XCTAssertEqual(defaults.string(forKey: PhotoLibrarySaver.albumIDKey), "album-1", "kept per phone")
        XCTAssertEqual(library.saved.map(\.album), ["album-1", "album-1"])
    }

    func testADeletedAlbumIsMadeAgain() async {
        let library = FakeLibrary()
        let saver = PhotoLibrarySaver(library: library, defaults: defaults)
        await saver.save(photo)
        library.albums.removeAll()  // deleted in the Photos app
        await saver.save(photo)
        XCTAssertEqual(library.created, 2)
        XCTAssertEqual(defaults.string(forKey: PhotoLibrarySaver.albumIDKey), "album-2")
        XCTAssertEqual(library.saved.last?.album, "album-2")
    }

    func testAnExistingGreenhouseAlbumIsAdoptedRatherThanDuplicated() async {
        // e.g. after reinstalling, when the stored id is gone but the album isn't.
        let library = FakeLibrary()
        library.albums = ["old": "Greenhouse", "other": "Holiday"]
        let saver = PhotoLibrarySaver(library: library, defaults: defaults)
        await saver.save(photo)
        XCTAssertEqual(library.created, 0)
        XCTAssertEqual(library.saved.first?.album, "old")
        XCTAssertEqual(defaults.string(forKey: PhotoLibrarySaver.albumIDKey), "old")
    }

    func testTwoQuickShotsOnAFirstRunMakeOneAlbum() async {
        let library = FakeLibrary()
        let saver = PhotoLibrarySaver(library: library, defaults: defaults)
        async let a = saver.save(photo)
        async let b = saver.save(photo)
        let results = await [a, b]
        XCTAssertEqual(results, [.saved, .saved])
        XCTAssertEqual(library.created, 1)
    }

    func testAccessIsAskedOnlyAtTheFirstSave() async {
        let library = FakeLibrary()
        library.status = .notDetermined
        let saver = PhotoLibrarySaver(library: library, defaults: defaults)
        XCTAssertEqual(library.requests, 0, "nothing asked up front")
        await saver.save(photo)
        await saver.save(photo)
        XCTAssertEqual(library.requests, 1)
        XCTAssertEqual(library.saved.count, 2)
    }

    func testDeniedSavesNothingAndSaysSoOnce() async {
        let library = FakeLibrary()
        library.status = .notDetermined
        library.answer = .denied
        let saver = PhotoLibrarySaver(library: library, defaults: defaults)
        let first = await saver.save(photo)
        let second = await saver.save(photo)
        XCTAssertEqual(first, .denied(tellUser: true))
        XCTAssertEqual(second, .denied(tellUser: false), "only once")
        XCTAssertTrue(library.saved.isEmpty)
        XCTAssertEqual(library.created, 0)

        // Allowed later, then taken away again: say it again.
        library.status = .allowed
        let outcome1 = await saver.save(photo)
        XCTAssertEqual(outcome1, .saved)
        library.status = .denied
        let outcome2 = await saver.save(photo)
        XCTAssertEqual(outcome2, .denied(tellUser: true))
    }

    func testTurnedOffInSettingsDoesNothingAtAll() async {
        let library = FakeLibrary()
        library.status = .notDetermined
        defaults.set(false, forKey: PhotoLibrarySaver.enabledKey)
        let saver = PhotoLibrarySaver(library: library, defaults: defaults)
        let outcome3 = await saver.save(photo)
        XCTAssertEqual(outcome3, .off)
        XCTAssertEqual(library.requests, 0, "doesn't even ask")
        XCTAssertTrue(library.saved.isEmpty)
    }

    func testOnByDefault() {
        XCTAssertTrue(PhotoLibrarySaver.isEnabled(in: defaults))
        defaults.set(false, forKey: PhotoLibrarySaver.enabledKey)
        XCTAssertFalse(PhotoLibrarySaver.isEnabled(in: defaults))
    }

    func testLimitedAccessTrustsTheStoredAlbumInsteadOfMakingOneEachTime() async {
        let library = FakeLibrary()
        let saver = PhotoLibrarySaver(library: library, defaults: defaults)
        await saver.save(photo)  // made with full access
        library.status = .limited
        library.albumsHidden = true
        await saver.save(photo)
        await saver.save(photo)
        XCTAssertEqual(library.created, 1, "no duplicates")
        XCTAssertEqual(library.saved.map(\.album), ["album-1", "album-1", "album-1"])
    }

    func testWhenTheAlbumCantBeUsedThePhotoStillGoesInTheLibrary() async {
        let library = FakeLibrary()
        library.failSavesIntoAlbums = true
        let saver = PhotoLibrarySaver(library: library, defaults: defaults)
        let outcome4 = await saver.save(photo)
        XCTAssertEqual(outcome4, .saved)
        XCTAssertEqual(library.saved.count, 1)
        XCTAssertNil(library.saved.first?.album)
    }
}
