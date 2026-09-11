import SwiftUI

@main
struct AliciaApp: App {
    /// Live when Secrets.plist (or UserDefaults) provides a base URL + token,
    /// mock otherwise — see AliciaConfig.
    @State private var store = AppStore(service: {
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--immersive-reading-preview") || ProcessInfo.processInfo.arguments.contains("--collaboration-preview") || ProcessInfo.processInfo.arguments.contains("--voice-evidence-preview") || ProcessInfo.processInfo.arguments.contains("--episode-day-preview") || ProcessInfo.processInfo.arguments.contains("--episode-continuity-preview") || ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix("--dialogue-review-") }) { return MockAliciaService() }
#endif
        return AliciaConfig.makeService()
    }())
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
                if ProcessInfo.processInfo.arguments.contains("--immersive-reading-preview") && ProcessInfo.processInfo.arguments.contains("--reading-bar-preview") {
                    VStack { Spacer(); ReadingBar() }.background(Theme.paper)
                        .task { store.reader.prepareReadingPreview() }
                } else if ProcessInfo.processInfo.arguments.contains("--immersive-reading-preview") {
                    ImmersiveReadingView(previewReduceMotion: ProcessInfo.processInfo.arguments.contains("--reading-reduce-motion"))
                        .task {
                        store.reader.prepareReadingPreview(unavailable: ProcessInfo.processInfo.arguments.contains("--reading-unavailable"))
                    }
                } else if ProcessInfo.processInfo.arguments.contains("--motion-lab") {
                    MotionLabView()
                } else if ProcessInfo.processInfo.arguments.contains("--dialogue-review-sheet-preview") {
                    DialogueReviewView(message: Message(sender: .alicia, text: DialogueReview.preview.reply,
                                                        replyID: DialogueReview.previewID))
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
                    if args.contains("--episode-day-preview") && args.contains("--episode-walk-preview") {
                        store.episodeDay = EpisodeDay.preview
                        store.walkPrompt = "Where would choosing less give you room to go deeper?"
                        store.walkDraft = "Preview reflection: I keep returning to the difference between commitment and control. I want to give this idea a real test today."
                        store.openWalk(probe: "Where would choosing less give you room to go deeper?")
                    }
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
                    if !store.isMock {
                        ProactiveNotifier.requestPermission()
                        ProactiveNotifier.schedule()
                    }
                }
                .onChange(of: scenePhase) { _, phase in
                    switch phase {
                    case .active:
                        // Presence: he is here. The tracker's dwell clock only
                        // runs while the app is foreground, so a tab left open
                        // overnight is not reported as attention.
                        PresenceTracker.shared.appOpened()
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
                        // Close the open tab's dwell and push the batch before
                        // iOS suspends us — an unflushed buffer is lost.
                        PresenceTracker.shared.appBackgrounded()
                        // Re-arm background refresh EVERY time — submitting
                        // once at launch (the old behavior) meant iOS never
                        // had a fresh window and no notification ever fired.
                        store.stopProactivePolling()
                        if !store.isMock { ProactiveNotifier.schedule() }
                    default:
                        break
                    }
                }
        }
    }
}
