import CloudKit
import SwiftUI

/// Picks the first screen: your name, then a household, then the app.
struct RootView: View {
    @AppStorage(SettingsKey.myName) private var myName = ""
    @FetchRequest(fetchRequest: Household.all()) private var households: FetchedResults<Household>

    init() { GHAppearance.apply() }

    var body: some View {
        Group {
            if myName.trimmingCharacters(in: .whitespaces).isEmpty {
                NameEntryView()
            } else if let household = Persistence.shared.pickHousehold(from: Array(households)) {
                MainTabView(household: household)
                    // A different household (e.g. after accepting an invite)
                    // gets fresh screens rather than reusing old state.
                    .id(household.objectID)
            } else {
                WelcomeView()
            }
        }
        .tint(GH.Palette.leaf)
    }
}

struct MainTabView: View {
    @ObservedObject var household: Household
    @ObservedObject private var router = NotificationRouter.shared
    @Environment(\.scenePhase) private var scenePhase
    /// The plant a tapped photo check-in is asking for a photo of.
    @State private var checkInPlant: Plant?
    @State private var checkInAskedAt = Date.distantPast
    @StateObject private var keyboard = KeyboardWatcher()
    #if DEBUG
    @State private var tab = DemoData.openTab
    #else
    @State private var tab = 0
    #endif

    private static let tabs = [
        GHTabItem(tag: 0, title: "Plants", icon: "leaf", selectedIcon: "leaf.fill"),
        GHTabItem(tag: 1, title: "Care", icon: "drop", selectedIcon: "drop.fill"),
        GHTabItem(tag: 2, title: "Plans", icon: "list.star", selectedIcon: "list.star"),
        GHTabItem(tag: 3, title: "Settings", icon: "gearshape", selectedIcon: "gearshape.fill"),
    ]

    var body: some View {
        // A TabView still holds the four screens (each keeps its scroll
        // position and navigation stack); its own bar is hidden and the
        // floating glass bar below drives the selection instead.
        TabView(selection: $tab) {
            PlantsView(household: household)
                .toolbar(.hidden, for: .tabBar)
                .tag(0)
            CareView(household: household)
                .toolbar(.hidden, for: .tabBar)
                .tag(1)
            PlansView(household: household)
                .toolbar(.hidden, for: .tabBar)
                .tag(2)
            SettingsView(household: household)
                .toolbar(.hidden, for: .tabBar)
                .tag(3)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            // Steps aside while typing so it never rides on top of the keyboard.
            if !keyboard.isVisible {
                GHTabBar(items: Self.tabs, selection: $tab)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: keyboard.isVisible)
        .onAppear {
            NotificationPlanner.requestAuthorization()
            NotificationPlanner.reschedule()
            if PlantPhotos.saveMissingCovers(in: household) > 0, let context = household.managedObjectContext {
                Persistence.shared.save(context)
            }
            openPhotoCheckIn()
        }
        .onChange(of: router.photoCheckInPlantID) { openPhotoCheckIn() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { openPhotoCheckIn() }
        }
        .sheet(item: $checkInPlant) { plant in
            AddPhotoSheet(plant: plant, household: household)
                // Only now is the tap handled. Until the sheet is really up
                // (another sheet was open, or this view was being rebuilt),
                // the plant stays in the router for the next try.
                .onAppear { router.photoCheckInPlantID = nil }
        }
    }

    /// Opens Add photo for the plant a tapped check-in named, or for the plant
    /// it was combined into since. Tried again when this view appears and
    /// when the app comes forward, in case the sheet couldn't show the first
    /// time.
    private func openPhotoCheckIn() {
        guard let id = router.photoCheckInPlantID else { return }
        guard let plant = NotificationPlanner.photoCheckInTarget(plantID: id, in: household) else {
            router.photoCheckInPlantID = nil  // deleted, or split: nothing to open
            return
        }
        if checkInPlant == nil {
            checkInPlant = plant
            checkInAskedAt = .now
        } else if Date.now.timeIntervalSince(checkInAskedAt) > 2 {
            // Asked for a while ago but never shown (showing clears the
            // router), e.g. another sheet was up: reset so it presents again.
            // A sheet still sliding up is left alone.
            checkInPlant = nil
            DispatchQueue.main.async {
                checkInPlant = plant
                checkInAskedAt = .now
            }
        }
    }
}

struct NameEntryView: View {
    @AppStorage(SettingsKey.myName) private var myName = ""
    @State private var draft = ""

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "leaf.circle.fill")
                .font(.system(size: 72))
                .foregroundStyle(GH.Palette.leaf)
            Text("Welcome to Greenhouse")
                .font(.ghRounded(.largeTitle))
                .foregroundStyle(GH.Palette.ink)
                .multilineTextAlignment(.center)
            Text("What should we call you? It shows up next to things you do, like “Watered by \(draft.isEmpty ? "you" : draft)”.")
                .multilineTextAlignment(.center)
                .foregroundStyle(GH.Palette.ink2)
            TextField("Your first name", text: $draft)
                .padding(GH.Space.s)
                .background(GH.Palette.surface2, in: RoundedRectangle(cornerRadius: GH.Radius.control, style: .continuous))
                .textContentType(.givenName)
                .submitLabel(.continue)
                .onSubmit(save)
            Button("Continue", action: save)
                .buttonStyle(.ghProminent)
                .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
            Spacer()
        }
        .padding(32)
        .background(GH.Palette.paper.ignoresSafeArea())
    }

    private func save() {
        let name = draft.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        myName = name
    }
}

struct WelcomeView: View {
    @Environment(\.managedObjectContext) private var context
    @State private var waitingForInvite = false
    @State private var showingHelp = false

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "house.and.flag.fill")
                .font(.system(size: 60))
                .foregroundStyle(GH.Palette.leaf)
            if waitingForInvite {
                Text("Waiting for your invite")
                    .font(.ghRounded(.title))
                    .foregroundStyle(GH.Palette.ink)
                Text("Open the Greenhouse invite link you were sent in Messages and tap it. The shared plants will show up here, usually within a minute.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(GH.Palette.ink2)
                ProgressView()
                ICloudStatusView()
                Button("Back") { waitingForInvite = false }
            } else {
                Text("Set up your plants")
                    .font(.ghRounded(.title))
                    .foregroundStyle(GH.Palette.ink)
                Text("Start a household and invite someone to share it, or join one you were invited to.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(GH.Palette.ink2)
                Button {
                    Persistence.shared.createHousehold(name: "Our plants", in: context)
                } label: {
                    Text("Start a household").frame(maxWidth: .infinity)
                }
                .buttonStyle(.ghProminent)
                Button {
                    waitingForInvite = true
                } label: {
                    Text("I was invited").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            Button("How Greenhouse works") { showingHelp = true }
                .font(.footnote)
            Spacer()
        }
        .padding(32)
        .background(GH.Palette.paper.ignoresSafeArea())
        .sheet(isPresented: $showingHelp) {
            NavigationStack { HelpView() }
        }
    }
}

/// Warns when the phone isn't signed in to iCloud, since nothing syncs then.
struct ICloudStatusView: View {
    @State private var status: CKAccountStatus?

    var body: some View {
        Group {
            switch status {
            case .available, nil:
                EmptyView()
            default:
                Label("This iPhone isn't signed in to iCloud, so nothing can sync. Sign in under Settings → your name.", systemImage: "exclamationmark.icloud")
                    .font(.footnote)
                    .foregroundStyle(GH.Palette.terraInk)
            }
        }
        .task {
            guard !Persistence.isRunningTests else { return }
            status = try? await Persistence.shared.ckContainer.accountStatus()
        }
    }
}
