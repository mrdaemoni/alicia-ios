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

        // Ink-on-paper typography: navigation titles in serif to match the
        // hand-drawn sketchbook identity (body text gets .fontDesign(.serif)
        // in RootView; UIKit-owned nav bars need the appearance proxy).
        if let large = UIFontDescriptor
            .preferredFontDescriptor(withTextStyle: .largeTitle)
            .withDesign(.serif) {
            UINavigationBar.appearance().largeTitleTextAttributes = [
                .font: UIFont(descriptor: large, size: 34),
                .foregroundColor: UIColor(Theme.ink),
            ]
        }
        if let title = UIFontDescriptor
            .preferredFontDescriptor(withTextStyle: .headline)
            .withDesign(.serif) {
            UINavigationBar.appearance().titleTextAttributes = [
                .font: UIFont(descriptor: title, size: 17),
                .foregroundColor: UIColor(Theme.ink),
            ]
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .tint(Theme.accent)
                // Paper wants light: the drawings are ink on bone, and the
                // whole app is now that sketchbook.
                .preferredColorScheme(.light)
                .task {
                    ProactiveNotifier.requestPermission()
                    ProactiveNotifier.schedule()
                }
                .onChange(of: scenePhase) { _, phase in
                    switch phase {
                    case .active:
                        // Reconnect: refetch everything when the app comes
                        // back to the foreground (backend may have restarted
                        // or sent proactive messages since), and start the
                        // live poll that makes her presence real-time.
                        // He's looking at her — the icon badge has done
                        // its job.
                        ProactiveNotifier.clearBadge()
                        Task { await store.load() }
                        store.startProactivePolling()
                    case .background:
                        // Re-arm background refresh EVERY time — submitting
                        // once at launch (the old behavior) meant iOS never
                        // had a fresh window and no notification ever fired.
                        store.stopProactivePolling()
                        ProactiveNotifier.schedule()
                    default:
                        break
                    }
                }
        }
    }
}
