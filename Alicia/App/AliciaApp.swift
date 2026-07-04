import SwiftUI

@main
struct AliciaApp: App {
    /// Live when Secrets.plist (or UserDefaults) provides a base URL + token,
    /// mock otherwise — see AliciaConfig.
    @State private var store = AppStore(service: AliciaConfig.makeService())

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .tint(Theme.accent)
                .preferredColorScheme(.dark)
        }
    }
}
