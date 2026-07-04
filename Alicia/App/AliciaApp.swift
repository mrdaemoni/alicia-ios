import SwiftUI

@main
struct AliciaApp: App {
    @State private var store = AppStore(service: MockAliciaService())

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .tint(Theme.accent)
                .preferredColorScheme(.dark)
        }
    }
}
