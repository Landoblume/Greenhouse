import CloudKit
import SwiftUI
import UserNotifications

struct SettingsView: View {
    @ObservedObject var household: Household
    @Environment(\.managedObjectContext) private var context
    @AppStorage(SettingsKey.myName) private var myName = ""
    @AppStorage(NotificationPlanner.hourKey) private var notifyHour = 9
    @AppStorage(NotificationPlanner.minuteKey) private var notifyMinute = 0
    @AppStorage(NotificationPlanner.photoCheckInKey) private var photoCheckInMonths = NotificationPlanner.defaultPhotoCheckInMonths
    @AppStorage(PhotoLibrarySaver.enabledKey) private var savePhotos = true
    @AppStorage(Persistence.schemaStatusKey) private var schemaStatus = "Not run"
    @Environment(\.scenePhase) private var scenePhase

    @State private var zip = ""
    @State private var lookingUp = false
    @State private var zoneError: String?
    @State private var zoneNote: String?
    @State private var sharing = false
    @State private var shareError: String?
    @State private var participants: Int?
    /// Turned off for this app in the Settings app (not just never asked).
    @State private var notificationsDenied = false
    @State private var photosDenied = false
    @State private var mutedCount = 0
    #if DEBUG
    @State private var debugSample: DebugSampleKind?
    #endif
    @FetchRequest(fetchRequest: Household.all()) private var households: FetchedResults<Household>

    private var isMember: Bool { Persistence.shared.isShared(household) }

    var body: some View {
        NavigationStack {
            ScrollViewReader { scroller in
                Form {
                    Section {
                        NavigationLink {
                            HelpView()
                        } label: {
                            Label("How Greenhouse works", systemImage: "questionmark.circle")
                        }
                    }
                    .listRowBackground(GH.Palette.surface)

                    Section("You") {
                        TextField("Your first name", text: $myName)
                    }
                    .listRowBackground(GH.Palette.surface)

                    Section {
                        NavigationLink {
                            MilestoneOptionsView(household: household)
                        } label: {
                            Label("Milestone quick picks", systemImage: "flag")
                        }
                        NavigationLink {
                            ArchivedCollectionsView(household: household)
                        } label: {
                            Label("Archived collections", systemImage: "archivebox")
                        }
                    }
                    .listRowBackground(GH.Palette.surface)

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
                            ErrorText(text: shareError)
                        }
                        ICloudStatusView()
                        SyncStatusRow()
                    } header: {
                        Text("Household")
                    } footer: {
                        if !isMember {
                            Text("Sends an iCloud link (by Messages, for example). Whoever taps it sees and edits the same plants on their iPhone.")
                        }
                    }
                    .listRowBackground(GH.Palette.surface)

                    Section {
                        HStack {
                            TextField("ZIP code", text: $zip)
                                .keyboardType(.numberPad)
                            Button("Look up") { Task { await lookUpZone() } }
                                .disabled(lookingUp || zip.count != 5)
                        }
                        Button {
                            Task { await lookUpZoneHere() }
                        } label: {
                            Label("Use my location", systemImage: "location")
                        }
                        .disabled(lookingUp)
                        if lookingUp { ProgressView() }
                        if let zoneError {
                            Text(zoneError).font(.caption).foregroundStyle(GH.Palette.terraInk)
                        }
                        if let zoneNote {
                            Text(zoneNote).font(.caption).foregroundStyle(GH.Palette.ink2)
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
                    .listRowBackground(GH.Palette.surface)

                    let others = HouseholdMerge.others(of: household, in: Array(households))
                    if !others.isEmpty {
                        Section {
                            ForEach(others) { other in
                                OtherHouseholdRow(source: other, target: household)
                            }
                        } header: {
                            Text("Your other households")
                        } footer: {
                            Text("Plants you added before joining \(household.name ?? "this household"). Bringing them here moves their photos, reminders and history too.")
                        }
                        .listRowBackground(GH.Palette.surface)
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
                        .tint(GH.Palette.leafDeep)
                        if notificationsDenied {
                            Button("Turn on notifications in Settings") {
                                if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                                    UIApplication.shared.open(url)
                                }
                            }
                        }
                    } header: {
                        Text("Reminders")
                    } footer: {
                        Text("Care reminders and plant anniversaries arrive at this time on the day they're due. Photo check-ins do too.")
                    }
                    .listRowBackground(GH.Palette.surface)

                    Section {
                        Picker("Photo check-in", selection: $photoCheckInMonths) {
                            ForEach(NotificationPlanner.photoCheckInOptions, id: \.self) { months in
                                Text(months == 0 ? "Off" : "After \(months) months").tag(months)
                            }
                        }
                        .disabled(notificationsDenied)
                        .onChange(of: photoCheckInMonths) { NotificationPlanner.reschedule() }
                        if notificationsDenied {
                            Text("Notifications are off for Greenhouse, so check-ins can't arrive. Turn them on above to choose.")
                                .font(.footnote)
                                .foregroundStyle(GH.Palette.ink2)
                        }
                        if mutedCount > 0 {
                            NavigationLink {
                                MutedPlantsView(household: household)
                            } label: {
                                LabeledContent("Muted plants", value: "\(mutedCount)")
                            }
                        }
                        Toggle("Save new photos to Photos", isOn: $savePhotos)
                            .tint(GH.Palette.leafDeep)
                        if savePhotos, photosDenied {
                            Text("Photos access is off, so new photos stay in Greenhouse only. Allow it in Settings → Greenhouse → Photos.")
                                .font(.footnote)
                                .foregroundStyle(GH.Palette.ink2)
                        }
                    } header: {
                        Text("Photos").id("photos")
                    } footer: {
                        Text("Photo check-in: once a plant has gone this long without a new photo, you get a nudge at your reminder time. About 3 a week at most (Tuesday, Thursday and Saturday), the plant that's waited longest first, and the same plant no more than once a week. A photo from either phone resets the wait.\n\nPhotos you take with the camera in Greenhouse also go to a “Greenhouse” album on this iPhone. Photos you pick from your library, or that come from the other phone, aren't copied.")
                    }
                    .listRowBackground(GH.Palette.surface)

                    #if DEBUG
                    Section {
                        LabeledContent("CloudKit schema", value: schemaStatus)
                        Button("Upload schema again") {
                            Persistence.shared.initializeCloudKitSchemaIfNeeded(force: true)
                        }
                        ForEach(DebugSampleKind.allCases) { kind in
                            Button("Preview: \(kind.title)") { debugSample = kind }
                        }
                    } header: {
                        Text("Developer")
                    } footer: {
                        Text("Debug builds only. After this says Ready, deploy the schema to Production in the CloudKit Console so TestFlight builds can sync (see README).")
                    }
                    .listRowBackground(GH.Palette.surface)
                    #endif

                    Section {
                        LabeledContent("Version", value: Self.version)
                    }
                    .listRowBackground(GH.Palette.surface)
                }
                .ghScreen()
                .ghTabBarClearance()
                .navigationTitle("Settings")
                .onAppear {
                    zip = household.zip ?? ""
                    refreshMuted()
                }
                .task { await refresh() }
                .onChange(of: scenePhase) { _, phase in
                    // Back from the Settings app, maybe with notifications or Photos turned on.
                    if phase == .active { Task { await refresh() } }
                }
                #if DEBUG
                .sheet(item: $debugSample) { DebugSampleSheet(kind: $0) }
                .task {
                    // `-scrollTo photos`, for simulator screenshots.
                    guard let target = UserDefaults.standard.string(forKey: "scrollTo") else { return }
                    try? await Task.sleep(for: .milliseconds(400))
                    scroller.scrollTo(target, anchor: .top)
                }
                #endif
            }
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
        notificationsDenied = settings.authorizationStatus == .denied
        photosDenied = SystemPhotoLibrary().access() == .denied
        refreshMuted()
        if let share = Persistence.shared.existingShare(for: household) {
            participants = share.participants.filter { $0.role != .owner && $0.acceptanceStatus == .accepted }.count
        }
    }

    /// Muted plants that are still around (see `MutedPlantsView`).
    private func refreshMuted() {
        let muted = NotificationPlanner.mutedPlantIDs()
        mutedCount = (household.plants ?? []).filter { $0.isActive && muted.contains($0.uuid?.uuidString ?? "") }.count
    }

    private func invite() async {
        sharing = true
        shareError = nil
        defer { sharing = false }
        do {
            let share = try await Persistence.shared.shareForInvite(household)
            SharingPresenter.present(share: share)
        } catch {
            print("Greenhouse: invite failed: \(SyncMonitor.describe(error))")
            shareError = SyncMonitor.describe(error)
        }
    }

    private func lookUpZone() async {
        lookingUp = true
        zoneError = nil
        zoneNote = nil
        defer { lookingUp = false }
        do {
            let match = try await ZoneLookup.zone(forZIP: zip)
            household.zip = zip
            household.hardinessZone = match.zone
            if let nearby = match.nearbyZIP {
                zoneNote = "\(zip) is newer than the USDA zone map, so this is \(match.zone) from nearby \(nearby)."
            }
            Persistence.shared.save(context)
        } catch {
            zoneError = error.localizedDescription
        }
    }

    /// For ZIPs too new for any map: the zone of the nearest ZIP the USDA map
    /// knows around the phone. The location is used once and not saved.
    private func lookUpZoneHere() async {
        lookingUp = true
        zoneError = nil
        zoneNote = nil
        defer { lookingUp = false }
        do {
            let here = try await OneTimeLocation().coordinate()
            let match = try await ZoneLookup.zone(near: here)
            if zip.count == 5 { household.zip = zip }
            household.hardinessZone = match.zone
            Persistence.shared.save(context)
            zoneNote = "Zone \(match.zone), from \(match.nearbyZIP ?? "the ZIP") near you."
        } catch {
            zoneError = error.localizedDescription
        }
    }
}

/// Plants whose check-ins were stopped from a notification on this phone,
/// each with a way to turn them back on.
struct MutedPlantsView: View {
    @ObservedObject var household: Household
    @State private var muted: Set<String>

    init(household: Household) {
        self.household = household
        _muted = State(initialValue: NotificationPlanner.mutedPlantIDs())
    }

    private var plants: [Plant] {
        (household.plants ?? [])
            .filter { $0.isActive && muted.contains($0.uuid?.uuidString ?? "") }
            .sorted { ($0.displayName, $0.uuid?.uuidString ?? "") < ($1.displayName, $1.uuid?.uuidString ?? "") }
    }

    var body: some View {
        List {
            Section {
                if plants.isEmpty {
                    Text("No muted plants. Check-ins come for every plant.")
                        .foregroundStyle(GH.Palette.ink2)
                }
                ForEach(plants) { plant in
                    MutedPlantRow(plant: plant) {
                        guard let id = plant.uuid else { return }
                        NotificationPlanner.setMuted(false, plantID: id)
                        muted.remove(id.uuidString)
                        NotificationPlanner.reschedule()
                    }
                }
            } footer: {
                Text("“Stop for this plant” on a photo check-in mutes it on this iPhone only. Unmute it to get its check-ins again.")
            }
            .listRowBackground(GH.Palette.surface)
        }
        .ghScreen()
        .navigationTitle("Muted plants")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct MutedPlantRow: View {
    @ObservedObject var plant: Plant
    let onUnmute: () -> Void

    var body: some View {
        HStack {
            Label(plant.displayName, systemImage: "bell.slash")
                .foregroundStyle(GH.Palette.ink)
            Spacer()
            Button("Unmute", action: onUnmute)
                .buttonStyle(.bordered)
                .tint(GH.Palette.leafInk)
                .frame(minHeight: 44)
                .accessibilityLabel("Unmute \(plant.displayName)")
        }
    }
}

/// Last iCloud sync result: a time when it's working, the full reason when not.
struct SyncStatusRow: View {
    @ObservedObject private var monitor = SyncMonitor.shared

    var body: some View {
        if let error = monitor.lastError {
            ErrorText(text: error)
        } else if let success = monitor.lastSuccess {
            Label("Synced with iCloud \(success.formatted(.relative(presentation: .named)))", systemImage: "checkmark.icloud")
                .font(.caption)
                .foregroundStyle(GH.Palette.ink2)
        }
    }
}

/// Error details you can select and copy, to paste into a bug report.
struct ErrorText: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(text)
                .font(.caption.monospaced())
                .foregroundStyle(GH.Palette.terraInk)
                .textSelection(.enabled)
            Button("Copy details") { UIPasteboard.general.string = text }
                .font(.caption)
        }
    }
}

/// One of your own households, with a button to bring its plants here.
struct OtherHouseholdRow: View {
    @ObservedObject var source: Household
    let target: Household
    @Environment(\.managedObjectContext) private var context
    @State private var confirming = false

    private var count: Int { (source.plants ?? []).filter(\.isActive).count }
    private var joined: Int { Persistence.shared.joinedCount(for: source) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(source.name ?? "Untitled household")
            Text("\(count) plant\(count == 1 ? "" : "s")" + (joined > 0 ? " · \(joined) other \(joined == 1 ? "person" : "people") joined it" : ""))
                .font(.caption)
                .foregroundStyle(GH.Palette.ink2)
            Button("Bring \(count == 1 ? "it" : "them") into \(target.name ?? "this household")") { confirming = true }
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .confirmationDialog("Move \(count) plant\(count == 1 ? "" : "s") into \(target.name ?? "this household")?",
                            isPresented: $confirming, titleVisibility: .visible) {
            Button("Move them") {
                HouseholdMerge.move(source, into: target, context: context)
                Persistence.shared.save(context)
                NotificationPlanner.reschedule()
            }
        } message: {
            Text(joined > 0
                 ? "\(joined) other \(joined == 1 ? "person" : "people") joined \(source.name ?? "that household") and will no longer see these plants there."
                 : "Everyone here will see them. \(source.name ?? "Your other household") is removed once they've moved.")
        }
    }
}
