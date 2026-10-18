import CloudKit
import CoreData
import UIKit

// Sharing one household between two Apple IDs.
//
// The owner shares the Household object; Core Data moves it and everything
// related to it (plants, photos, tasks...) into a CloudKit zone and hands back a
// CKShare. Apple's sharing sheet sends the invite link (Messages, Mail...).
// When the other person taps it, iOS opens this app with the share's metadata,
// and accepting it pulls the household into their shared store.

extension Persistence {
    func existingShare(for household: Household) -> CKShare? {
        guard let cloudKit else { return nil }
        return (try? cloudKit.fetchShares(matching: [household.objectID]))?[household.objectID]
    }

    /// People other than the owner who accepted an invite to this household.
    /// An invite that was created but never accepted counts as zero.
    func joinedCount(for household: Household) -> Int {
        guard let share = existingShare(for: household) else { return 0 }
        return share.participants.filter { $0.role != .owner && $0.acceptanceStatus == .accepted }.count
    }

    func shareForInvite(_ household: Household) async throws -> CKShare {
        guard let cloudKit, let privateStore else { throw SharingError.unavailable }
        if let share = existingShare(for: household) { return share }
        let (_, share, _) = try await cloudKit.share([household], to: nil)
        share[CKShare.SystemFieldKey.title] = "Greenhouse: \(household.name ?? "our plants")" as CKRecordValue
        _ = try await cloudKit.persistUpdatedShare(share, in: privateStore)
        return share
    }

    func acceptShare(_ metadata: CKShare.Metadata) {
        guard let cloudKit, let sharedStore else { return }
        cloudKit.acceptShareInvitations(from: [metadata], into: sharedStore) { _, error in
            if let error { print("Greenhouse: accepting share failed: \(error)") }
        }
    }
}

enum SharingError: LocalizedError {
    case unavailable

    var errorDescription: String? { "iCloud isn't available. Check that you're signed in to iCloud in Settings." }
}

/// Presents Apple's sharing sheet. It's a UIKit controller that doesn't behave
/// as a SwiftUI sheet, so it's presented from the top view controller instead.
@MainActor
enum SharingPresenter {
    private static let delegate = SharingDelegate()

    static func present(share: CKShare) {
        let controller = UICloudSharingController(share: share, container: Persistence.shared.ckContainer)
        // Invite-only, and invited people can add plants and log care.
        controller.availablePermissions = [.allowPrivate, .allowReadWrite]
        controller.delegate = delegate
        topViewController()?.present(controller, animated: true)
    }

    private static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        var top = scene?.keyWindow?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}

private final class SharingDelegate: NSObject, UICloudSharingControllerDelegate {
    func itemTitle(for csc: UICloudSharingController) -> String? { "Greenhouse" }

    func cloudSharingController(_ csc: UICloudSharingController, failedToSaveShareWithError error: Error) {
        print("Greenhouse: sharing failed: \(error)")
    }
}
