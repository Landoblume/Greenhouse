import CloudKit
import SwiftUI
import UserNotifications

@main
struct GreenhouseApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    private let persistence = Persistence.shared

    init() {
        guard !Persistence.isRunningTests else { return }
        RemoteChangeObserver.shared.start()
        persistence.initializeCloudKitSchemaIfNeeded()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.managedObjectContext, persistence.viewContext)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, !Persistence.isRunningTests { NotificationPlanner.reschedule() }
        }
    }
}

enum SettingsKey {
    /// Your first name, shown on things you log ("Watered by Sam"). Per phone,
    /// so it isn't synced.
    static let myName = "myName"
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        // Silent CloudKit pushes are how this phone hears about the other
        // phone's changes while the app is in the background.
        application.registerForRemoteNotifications()
        return true
    }

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }

    // Show reminders even when the app is open.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}

/// Receives the household invite when someone taps the iCloud link. iOS hands
/// it to the scene delegate, which SwiftUI doesn't expose, hence this class.
final class SceneDelegate: NSObject, UIWindowSceneDelegate {
    // The app was not running: the invite arrives with the launch.
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        if let metadata = connectionOptions.cloudKitShareMetadata {
            Persistence.shared.acceptShare(metadata)
        }
    }

    // The app was already running.
    func windowScene(_ windowScene: UIWindowScene, userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata) {
        Persistence.shared.acceptShare(cloudKitShareMetadata)
    }
}
