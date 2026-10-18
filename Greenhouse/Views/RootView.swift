import CloudKit
import SwiftUI

/// Picks the first screen: your name, then a household, then the app.
struct RootView: View {
    @AppStorage(SettingsKey.myName) private var myName = ""
    @FetchRequest(fetchRequest: Household.all()) private var households: FetchedResults<Household>

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
    }
}

struct MainTabView: View {
    @ObservedObject var household: Household
    #if DEBUG
    @State private var tab = DemoData.openTab
    #else
    @State private var tab = 0
    #endif

    var body: some View {
        TabView(selection: $tab) {
            PlantsView(household: household)
                .tabItem { Label("Plants", systemImage: "leaf") }
                .tag(0)
            CareView(household: household)
                .tabItem { Label("Care", systemImage: "drop") }
                .tag(1)
            PlansView(household: household)
                .tabItem { Label("Plans", systemImage: "list.star") }
                .tag(2)
            SettingsView(household: household)
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(3)
        }
        .onAppear {
            NotificationPlanner.requestAuthorization()
            NotificationPlanner.reschedule()
            if PlantPhotos.saveMissingCovers(in: household) > 0, let context = household.managedObjectContext {
                Persistence.shared.save(context)
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
                .foregroundStyle(.tint)
            Text("Welcome to Greenhouse")
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)
            Text("What should we call you? It shows up next to things you do, like “Watered by \(draft.isEmpty ? "you" : draft)”.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            TextField("Your first name", text: $draft)
                .textFieldStyle(.roundedBorder)
                .textContentType(.givenName)
                .submitLabel(.continue)
                .onSubmit(save)
            Button("Continue", action: save)
                .buttonStyle(.borderedProminent)
                .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
            Spacer()
        }
        .padding(32)
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
                .foregroundStyle(.tint)
            if waitingForInvite {
                Text("Waiting for your invite")
                    .font(.title.bold())
                Text("Open the Greenhouse invite link you were sent in Messages and tap it. The shared plants will show up here, usually within a minute.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                ProgressView()
                ICloudStatusView()
                Button("Back") { waitingForInvite = false }
            } else {
                Text("Set up your plants")
                    .font(.title.bold())
                Text("Start a household and invite someone to share it, or join one you were invited to.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                Button {
                    Persistence.shared.createHousehold(name: "Our plants", in: context)
                } label: {
                    Text("Start a household").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
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
                    .foregroundStyle(.orange)
            }
        }
        .task {
            guard !Persistence.isRunningTests else { return }
            status = try? await Persistence.shared.ckContainer.accountStatus()
        }
    }
}
