import CloudKit
import SwiftUI
import UserNotifications

struct SettingsView: View {
    @ObservedObject var household: Household
    @Environment(\.managedObjectContext) private var context
    @AppStorage(SettingsKey.myName) private var myName = ""
    @AppStorage(NotificationPlanner.hourKey) private var notifyHour = 9
    @AppStorage(NotificationPlanner.minuteKey) private var notifyMinute = 0
    @AppStorage(Persistence.schemaStatusKey) private var schemaStatus = "Not run"

    @State private var zip = ""
    @State private var lookingUp = false
    @State private var zoneError: String?
    @State private var sharing = false
    @State private var shareError: String?
    @State private var participants: Int?
    @State private var notificationsAllowed: Bool?

    private var isMember: Bool { Persistence.shared.isShared(household) }

    var body: some View {
        NavigationStack {
            Form {
                Section("You") {
                    TextField("Your first name", text: $myName)
                }

                Section {
                    TextField("Household name", text: Binding(
                        get: { household.name ?? "" },
                        set: { household.name = $0 }
                    ))
                    .onSubmit { Persistence.shared.save(context) }
                    if isMember {
                        Label("You joined this household from an invite.", systemImage: "person.2")
                    } else {
                        Button {
                            Task { await invite() }
                        } label: {
                            if sharing {
                                ProgressView()
                            } else {
                                Label(participants.map { $0 > 0 ? "Manage sharing (\($0) joined)" : "Invite to household" } ?? "Invite to household",
                                      systemImage: "person.badge.plus")
                            }
                        }
                        .disabled(sharing)
                    }
                    if let shareError {
                        Text(shareError).font(.caption).foregroundStyle(.red)
                    }
                    ICloudStatusView()
                } header: {
                    Text("Household")
                } footer: {
                    if !isMember {
                        Text("Sends an iCloud link (by Messages, for example). Whoever taps it sees and edits the same plants on their iPhone.")
                    }
                }

                Section {
                    HStack {
                        TextField("ZIP code", text: $zip)
                            .keyboardType(.numberPad)
                        Button("Look up") { Task { await lookUpZone() } }
                            .disabled(lookingUp || zip.count != 5)
                    }
                    if lookingUp { ProgressView() }
                    if let zoneError {
                        Text(zoneError).font(.caption).foregroundStyle(.red)
                    }
                    Picker("Zone", selection: Binding(
                        get: { household.hardinessZone ?? "" },
                        set: {
                            household.hardinessZone = $0.isEmpty ? nil : $0
                            Persistence.shared.save(context)
                        }
                    )) {
                        Text("Not set").tag("")
                        ForEach(USDAZone.all, id: \.self) { Text($0).tag($0) }
                    }
                } header: {
                    Text("Grow zone")
                } footer: {
                    Text("USDA hardiness zone, from your ZIP code or picked by hand. Outdoor and seasonal plants use it to tell you whether they survive winter outside. Both phones share it.")
                }

                Section {
                    DatePicker("Remind me at", selection: Binding(
                        get: { Calendar.current.date(bySettingHour: notifyHour, minute: notifyMinute, second: 0, of: .now) ?? .now },
                        set: {
                            notifyHour = Calendar.current.component(.hour, from: $0)
                            notifyMinute = Calendar.current.component(.minute, from: $0)
                            NotificationPlanner.reschedule()
                        }
                    ), displayedComponents: .hourAndMinute)
                    if notificationsAllowed == false {
                        Button("Turn on notifications in Settings") {
                            if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                    }
                } header: {
                    Text("Reminders")
                } footer: {
                    Text("Care reminders and plant anniversaries arrive at this time on the day they're due.")
                }

                #if DEBUG
                Section {
                    LabeledContent("CloudKit schema", value: schemaStatus)
                    Button("Upload schema again") {
                        Persistence.shared.initializeCloudKitSchemaIfNeeded(force: true)
                    }
                } header: {
                    Text("Developer")
                } footer: {
                    Text("Debug builds only. After this says Ready, deploy the schema to Production in the CloudKit Console so TestFlight builds can sync (see README).")
                }
                #endif

                Section {
                    LabeledContent("Version", value: Self.version)
                }
            }
            .navigationTitle("Settings")
            .onAppear { zip = household.zip ?? "" }
            .task { await refresh() }
        }
    }

    private static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    private func refresh() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notificationsAllowed = settings.authorizationStatus == .authorized
        if let share = Persistence.shared.existingShare(for: household) {
            participants = share.participants.filter { $0.role != .owner && $0.acceptanceStatus == .accepted }.count
        }
    }

    private func invite() async {
        sharing = true
        shareError = nil
        defer { sharing = false }
        do {
            let share = try await Persistence.shared.shareForInvite(household)
            SharingPresenter.present(share: share)
        } catch {
            shareError = error.localizedDescription
        }
    }

    private func lookUpZone() async {
        lookingUp = true
        zoneError = nil
        defer { lookingUp = false }
        do {
            let zone = try await ZoneLookup.zone(forZIP: zip)
            household.zip = zip
            household.hardinessZone = zone
            Persistence.shared.save(context)
        } catch {
            zoneError = error.localizedDescription
        }
    }
}
