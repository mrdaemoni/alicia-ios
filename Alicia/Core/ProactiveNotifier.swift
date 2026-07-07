import Foundation
import BackgroundTasks
import UserNotifications

/// Local-notification bridge for Alicia's proactive messages.
///
/// No APNs (that needs a paid developer account + a push service). Two paths
/// cover her reaching out:
///  1. **Live polling** while the app is running (foreground or briefly
///     backgrounded) — `AppStore.startProactivePolling()` checks the feed
///     every 60 s; new items join the timeline instantly and post a banner
///     (shown even in-app via the center delegate below).
///  2. **BGAppRefreshTask** for when the app is closed — re-armed on every
///     background transition (it was only ever submitted once at launch,
///     which is why no notification ever arrived). iOS still controls the
///     timing and is stingy with dev-signed builds — Telegram remains the
///     guaranteed channel; this is her presence on the phone.
enum ProactiveNotifier {
    static let taskID = "com.alicia.app.refresh"
    private static let seenKey = "alicia.seenProactiveIDs"

    // MARK: registration (call once, before the app finishes launching)

    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskID, using: nil) { task in
            guard let refresh = task as? BGAppRefreshTask else { return }
            handle(refresh)
        }
        // Show banners even while the app is open — she should be able to
        // tap Hector on the shoulder from another tab.
        UNUserNotificationCenter.current().delegate = ForegroundBanner.shared
    }

    static func requestPermission() {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                if !granted {
                    print("⚠️ notifications not authorized — check Settings → Alicia")
                }
            }
    }

    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: taskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
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

    static func unseen(of messages: [ProactiveMessage]) -> [ProactiveMessage] {
        messages.filter { !seen.contains($0.id) }
    }

    // MARK: app-icon badge
    // The badge count rides ON the notification content — without setting
    // `content.badge`, iOS never marks the icon, which is why her messages
    // arrived silently (v22 fix). We keep our own counter because the
    // system doesn't accumulate one for us.
    private static let badgeKey = "alicia.badgeCount"

    private static var badgeCount: Int {
        get { UserDefaults.standard.integer(forKey: badgeKey) }
        set { UserDefaults.standard.set(max(0, newValue), forKey: badgeKey) }
    }

    /// Call when the app comes to the foreground — he's looking at her now.
    static func clearBadge() {
        badgeCount = 0
        UNUserNotificationCenter.current().setBadgeCount(0)
    }

    /// Post a local notification for one proactive message (used by both
    /// the background task and the live poll).
    static func notify(_ m: ProactiveMessage) async {
        let content = UNMutableNotificationContent()
        content.title = "Alicia"
        if !m.archetype.isEmpty { content.subtitle = m.archetype }
        // Her text, without the Telegram emoji markers (v25).
        content.body = String(m.text.strippedEmojis.prefix(160))
        content.sound = .default
        badgeCount += 1
        content.badge = NSNumber(value: badgeCount)
        try? await UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: m.id, content: content, trigger: nil))
    }

    // MARK: background refresh

    private static func handle(_ task: BGAppRefreshTask) {
        schedule()   // always chain the next window
        let work = Task {
            let fresh = await AliciaConfig.makeService().proactive(limit: 10)
            for m in unseen(of: fresh).prefix(3) {
                await notify(m)
            }
            markSeen(fresh)
            task.setTaskCompleted(success: true)
        }
        task.expirationHandler = { work.cancel() }
    }
}

/// Lets banners present while the app is foregrounded.
final class ForegroundBanner: NSObject, UNUserNotificationCenterDelegate {
    static let shared = ForegroundBanner()
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
