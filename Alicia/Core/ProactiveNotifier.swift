import Foundation
import BackgroundTasks
import UserNotifications

/// Local-notification bridge for Alicia's proactive messages.
///
/// No APNs (that needs a paid developer account + a push service): instead a
/// `BGAppRefreshTask` opportunistically polls `/api/proactive` and posts a
/// LOCAL notification for anything Hector hasn't seen. iOS decides the exact
/// timing (more often the more the app is used), and the foreground path
/// (`AppStore.load` → `markSeen`) keeps already-read messages from
/// re-notifying.
enum ProactiveNotifier {
    static let taskID = "com.alicia.app.refresh"
    private static let seenKey = "alicia.seenProactiveIDs"

    // MARK: registration (call once, before the app finishes launching)

    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskID, using: nil) { task in
            guard let refresh = task as? BGAppRefreshTask else { return }
            handle(refresh)
        }
    }

    static func requestPermission() {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: taskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 30 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    // MARK: seen-tracking (shared with the foreground load path)

    private static var seen: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: seenKey) ?? []) }
        set {
            // Cap so the list can't grow unbounded — the feed only ever
            // returns recent items, so 200 ids is plenty of overlap.
            UserDefaults.standard.set(Array(newValue.suffix(200)), forKey: seenKey)
        }
    }

    static func markSeen(_ messages: [ProactiveMessage]) {
        seen.formUnion(messages.map(\.id))
    }

    // MARK: background refresh

    private static func handle(_ task: BGAppRefreshTask) {
        schedule()   // always chain the next window
        let work = Task {
            let fresh = await AliciaConfig.makeService().proactive(limit: 10)
            let unseen = fresh.filter { !seen.contains($0.id) }
            for m in unseen.prefix(3) {
                let content = UNMutableNotificationContent()
                content.title = "Alicia"
                content.body = m.text
                content.sound = .default
                try? await UNUserNotificationCenter.current().add(
                    UNNotificationRequest(identifier: m.id,
                                          content: content,
                                          trigger: nil))
            }
            markSeen(fresh)
            task.setTaskCompleted(success: true)
        }
        task.expirationHandler = { work.cancel() }
    }
}
