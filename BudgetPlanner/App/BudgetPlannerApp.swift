import SwiftUI

@main
struct BudgetPlannerApp: App {
    @State private var store: DataStore
    @State private var lock: AppLock

    init() {
        let store = DataStore()
        _store = State(initialValue: store)
        _lock = State(initialValue: AppLock(enabled: store.settings.appLockEnabled))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(lock)
                .environment(\.locale, AppLocale.locale)
                .tint(Theme.accent)
        }
    }
}
