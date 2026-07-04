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
