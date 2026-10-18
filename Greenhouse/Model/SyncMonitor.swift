import CloudKit
import CoreData

/// Watches iCloud sync and keeps the last failure in plain words.
///
/// Core Data reports sync problems only as events, and the useful part (which
/// record CloudKit rejected and why) is buried a few errors deep. Without this,
/// a failed upload is invisible until something else, like sharing, breaks.
final class SyncMonitor: ObservableObject {
    static let shared = SyncMonitor()

    @Published private(set) var lastError: String?
    @Published private(set) var lastSuccess: Date?
    private var token: NSObjectProtocol?

    func start(container: NSPersistentCloudKitContainer) {
        guard token == nil else { return }
        token = NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: container,
            queue: .main
        ) { [weak self] note in
            guard let event = note.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                    as? NSPersistentCloudKitContainer.Event,
                  let end = event.endDate else { return }
            if let error = event.error {
                let text = "\(Self.label(event.type)) failed at \(end.formatted(date: .omitted, time: .shortened)):\n\(Self.describe(error))"
                print("Greenhouse: sync \(text)")
                self?.lastError = text
            } else if event.succeeded, event.type != .setup {
                self?.lastSuccess = end
                self?.lastError = nil
            }
        }
    }

    private static func label(_ type: NSPersistentCloudKitContainer.EventType) -> String {
        switch type {
        case .setup: "Setup"
        case .import: "Download"
        case .export: "Upload"
        @unknown default: "Sync"
        }
    }

    /// Unwraps an error chain into readable lines, including CloudKit's
    /// per-record reasons (e.g. "Cannot create new type … in production schema").
    static func describe(_ error: Error) -> String {
        var lines: [String] = []
        func walk(_ error: NSError, depth: Int) {
            guard depth < 5 else { return }
            let indent = String(repeating: "  ", count: depth)
            var line = "\(indent)\(error.domain) \(error.code): \(error.localizedDescription)"
            if let debug = error.userInfo[NSDebugDescriptionErrorKey] as? String, debug != error.localizedDescription {
                line += " (\(debug))"
            }
            lines.append(line)
            if let partial = error.userInfo[CKPartialErrorsByItemIDKey] as? [AnyHashable: Error] {
                for (item, itemError) in partial.prefix(6) {
                    let itemName = (item as? CKRecord.ID)?.recordName ?? "\(item)"
                    lines.append("\(indent)  • \(itemName):")
                    walk(itemError as NSError, depth: depth + 2)
                }
            }
            if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError {
                walk(underlying, depth: depth + 1)
            }
        }
        walk(error as NSError, depth: 0)
        return lines.joined(separator: "\n")
    }
}
