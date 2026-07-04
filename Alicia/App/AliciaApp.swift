import SwiftUI

@main
struct AliciaApp: App {
    /// Live when Secrets.plist (or UserDefaults) provides a base URL + token,
    /// mock otherwise — see AliciaConfig.
    @State private var store = AppStore(service: AliciaConfig.makeService())
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Must happen before launch finishes.
        ProactiveNotifier.register()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .tint(Theme.accent)
                .preferredColorScheme(.dark)
                .task {
                    ProactiveNotifier.requestPermission()
                    ProactiveNotifier.schedule()
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        // Reconnect: refetch everything when the app comes
                        // back to the foreground (backend may have restarted
                        // or sent proactive messages since).
                        Task { await store.load() }
                    }
                }
        }
    }
}
