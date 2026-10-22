import SwiftUI

enum AppTab: Hashable {
    case home, activity, plan, insights, settings
}

struct RootView: View {
    @Environment(DataStore.self) private var store
    @Environment(AppLock.self) private var lock
    @Environment(\.scenePhase) private var scenePhase
    @State private var tab: AppTab = .home
    /// Only prompt for Face ID automatically after a real trip to the background,
    /// otherwise cancelling the prompt would immediately show it again.
    @State private var returningFromBackground = false

    var body: some View {
        Group {
            if lock.isLocked {
                // Replacing the whole UI also closes any open forms while locked.
                PrivacyCover(showUnlock: scenePhase == .active)
            } else {
                tabs.overlay {
                    // Hide balances in the app switcher.
                    if scenePhase != .active { PrivacyCover(showUnlock: false) }
                }
            }
        }
        .fullScreenCover(isPresented: Binding(
            get: { !store.settings.hasOnboarded },
            set: { _ in }
        )) {
            OnboardingView()
        }
        .alert("Something went wrong", isPresented: Binding(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.errorMessage ?? "")
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                returningFromBackground = true
                if store.settings.appLockEnabled { lock.lock() }
            case .active:
                guard returningFromBackground else { break }
                returningFromBackground = false
                store.appBecameActive()
                if lock.isLocked { Task { await lock.authenticate() } }
            default:
                break
            }
        }
        .task {
            store.appBecameActive()
            if lock.isLocked { await lock.authenticate() }
        }
    }

    private var tabs: some View {
        TabView(selection: $tab) {
            DashboardView(selectedTab: $tab)
                .tabItem { Label("Home", systemImage: "house.fill") }
                .tag(AppTab.home)
            TransactionsView()
                .tabItem { Label("Activity", systemImage: "list.bullet.rectangle.portrait.fill") }
                .tag(AppTab.activity)
            PlanView()
                .tabItem { Label("Plan", systemImage: "calendar") }
                .tag(AppTab.plan)
            InsightsView()
                .tabItem { Label("Insights", systemImage: "chart.pie.fill") }
                .tag(AppTab.insights)
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                .tag(AppTab.settings)
        }
    }
}

private struct PrivacyCover: View {
    @Environment(AppLock.self) private var lock
    let showUnlock: Bool

    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(Theme.accent)
                Text("Budget Planner")
                    .font(.title2.bold())
                if showUnlock {
                    Text("Your budget is locked.")
                        .foregroundStyle(.secondary)
                    Button {
                        Task { await lock.authenticate() }
                    } label: {
                        Label("Unlock with \(AppLock.methodName)", systemImage: "faceid")
                            .frame(maxWidth: 260)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(lock.isAuthenticating)
                }
            }
            .padding()
        }
    }
}

#Preview {
    RootView()
        .environment(DataStore.preview())
        .environment(AppLock(enabled: false))
}
