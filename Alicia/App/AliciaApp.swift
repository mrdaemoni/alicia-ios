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
            Group {
#if DEBUG
                if ProcessInfo.processInfo.arguments.contains("--motion-lab") {
                    MotionLabView()
                } else {
                    RootView()
                }
#else
                RootView()
#endif
            }
                .environment(store)
#if DEBUG
                // Repeatable per-tab capture: `--tab us|dialogue|alicia|studio|
                // knowledge` opens straight onto one surface. Comparing five
                // presences otherwise means five hand-driven screenshots, which
                // is neither repeatable nor something an agent can do headlessly.
                // Same shape as --motion-lab, and gone from Release.
                .task {
                    let args = ProcessInfo.processInfo.arguments
                    guard let flag = args.firstIndex(of: "--tab"),
                          args.index(after: flag) < args.endIndex,
                          let section = AppSection(launchName: args[args.index(after: flag)])
                    else { return }
                    store.selectedSection = section
                }
#endif
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
