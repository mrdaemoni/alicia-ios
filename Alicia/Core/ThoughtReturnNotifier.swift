import Foundation
import UserNotifications

/// A prepared, optional return to Hector's own words. No background model call.
@MainActor enum ThoughtReturnNotifier {
    private static let key = "alicia.thoughtReturn."
    private static var generation = 0
    private static var inFlight: Set<String> = []

    static func setLocalEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(!enabled, forKey: key + "locallyStopped")
        if !enabled { cancel() }
    }

    static func cancel() {
        generation += 1
        let prior = UserDefaults.standard.string(forKey: key + "pending")
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: Array(inFlight) + (prior.map { [$0] } ?? []))
        UserDefaults.standard.removeObject(forKey: key + "pending")
        UserDefaults.standard.removeObject(forKey: key + "candidate")
        // Hold the day's reservation after cancellation: silence must never
        // create room for an extra nudge later that same day.
    }

    static func sync(_ value: ContextEnrichment) async {
        guard !UserDefaults.standard.bool(forKey: key + "locallyStopped"), value.followups_enabled, let followup = value.followup,
              let date = ThoughtReturnPolicy.date(followup.due_at) else { cancel(); return }
        let days = Set(UserDefaults.standard.stringArray(forKey: key + "reservedDays") ?? [])
        // A known scheduled candidate stays put across foreground polls.
        if UserDefaults.standard.string(forKey: key + "candidate") == followup.id,
           date > Date() { return }
        cancel()
        guard let day = ThoughtReturnPolicy.reservationDay(date: date, now: Date(), reserved: days) else { return }
        let ticket = generation
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard ticket == generation,
              settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
        let identifier = key + UUID().uuidString
        let content = UNMutableNotificationContent()
        content.title = "Alicia"
        content.body = followup.text
        content.sound = .default
        content.userInfo = ["thoughtReturn": followup.id]
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, date.timeIntervalSinceNow), repeats: false)
        inFlight.insert(identifier)
        defer { inFlight.remove(identifier) }
        do {
            try await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
            guard ticket == generation else {
                center.removePendingNotificationRequests(withIdentifiers: [identifier]); return
            }
            UserDefaults.standard.set(identifier, forKey: key + "pending")
            UserDefaults.standard.set(followup.id, forKey: key + "candidate")
            UserDefaults.standard.set(Array(days.union([day])).sorted().suffix(14).map { $0 }, forKey: key + "reservedDays")
        } catch { /* No reservation consumed if scheduling failed. */ }
    }
}

/// Pure policy used by the actual scheduler and acceptance checks.
enum ThoughtReturnPolicy {
    static func date(_ raw: String) -> Date? {
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let value = parser.date(from: raw) { return value }
        parser.formatOptions = [.withInternetDateTime]
        return parser.date(from: raw)
    }
    static func reservationDay(date: Date, now: Date, reserved: Set<String>, calendar: Calendar = .current) -> String? {
        guard date > now, date.timeIntervalSince(now) <= 24 * 60 * 60 else { return nil }
        let hour = calendar.component(.hour, from: date)
        guard (9..<19).contains(hour) else { return nil }
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        let key = String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
        return reserved.contains(key) ? nil : key
    }
}
