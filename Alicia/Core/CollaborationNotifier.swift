import Foundation
import UserNotifications

/// Purposeful returns have stable candidate identities, not daily reservations.
@MainActor enum CollaborationNotifier {
    private static let key = "alicia.collaboration.notification."
    private static var generation = 0
    private static var inFlight = Set<String>()
    static var hasSharedState: Bool {
        UserDefaults.standard.object(forKey: key + "revision") != nil || UserDefaults.standard.data(forKey: "alicia.collaboration.state") != nil
    }
    static func stop() { UserDefaults.standard.set(true, forKey: key + "stopped"); cancel() }
    static func allow() { UserDefaults.standard.set(false, forKey: key + "stopped") }
    static func cancel() {
        generation += 1
        let prior = UserDefaults.standard.string(forKey: key + "pending")
        if let prior, let date = UserDefaults.standard.object(forKey: key + "due") as? Date, date > Date() {
            let scheduled = UserDefaults.standard.stringArray(forKey: key + "scheduled") ?? []
            UserDefaults.standard.set(scheduled.filter { $0 != prior }, forKey: key + "scheduled")
        }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: Array(inFlight) + (prior.map { [$0] } ?? []))
        UserDefaults.standard.removeObject(forKey: key + "pending")
    }
    static func sync(_ state: CollaborationState, now: () -> Date = { Date() }) async {
        guard !Task.isCancelled else { return }
        ThoughtReturnNotifier.cancel()
        if let prior = UserDefaults.standard.object(forKey: key + "revision") as? Int, state.revision < prior { return }
        UserDefaults.standard.set(state.revision, forKey: key + "revision")
        guard !UserDefaults.standard.bool(forKey: key + "stopped"), state.followups_enabled,
              let candidate = state.followup, scheduleDate(candidate, now: now()) != nil else { cancel(); return }
        let identity = candidate.id + ":" + String(candidate.revision)
        if UserDefaults.standard.string(forKey: key + "pending") == identity { return }
        let scheduled = Set(UserDefaults.standard.stringArray(forKey: key + "scheduled") ?? [])
        guard !scheduled.contains(identity) else { cancel(); return }
        cancel()
        let ticket = generation
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard !Task.isCancelled, ticket == generation, settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional,
              let date = scheduleDate(candidate, now: now()) else { return }
        let content = UNMutableNotificationContent()
        content.title = candidate.title; content.body = candidate.message; content.sound = .default
        content.userInfo = ["collaborationCandidate": candidate.id, "goalID": candidate.goal_id,
                            "connectionID": candidate.connection_id, "agreementID": candidate.agreement_id]
        let components = Calendar.current.dateComponents([.year,.month,.day,.hour,.minute,.second,.timeZone], from: date)
        inFlight.insert(identity); defer { inFlight.remove(identity) }
        do {
            try await center.add(UNNotificationRequest(identifier: identity, content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)))
            guard !Task.isCancelled, ticket == generation else { center.removePendingNotificationRequests(withIdentifiers: [identity]); return }
            UserDefaults.standard.set(identity, forKey: key + "pending")
            UserDefaults.standard.set(date, forKey: key + "due")
            // cancel() may have removed an undelivered prior candidate. Read its
            // updated ledger, keeping recent identities in scheduling order.
            let recent = UserDefaults.standard.stringArray(forKey: key + "scheduled") ?? []
            UserDefaults.standard.set(Array((recent.filter { $0 != identity } + [identity]).suffix(200)), forKey: key + "scheduled")
        } catch { /* An unconfirmed schedule is retryable; it is never delivery. */ }
    }
    static func scheduleDate(_ candidate: CollaborationState.Followup, now: Date, calendar: Calendar = .current) -> Date? {
        guard let earliest = ThoughtReturnPolicy.date(candidate.not_before) else { return nil }
        var date = max(earliest, now.addingTimeInterval(2))
        let hour = calendar.component(.hour, from: date)
        if hour < 9 { date = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: date)! }
        if hour >= 19 {
            guard let next = calendar.date(byAdding: .day, value: 1, to: date),
                  let morning = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: next) else { return nil }
            date = morning
        }
        if let raw = candidate.expires_at {
            guard let expiry = ThoughtReturnPolicy.date(raw), date < expiry else { return nil }
        }
        return date
    }
}
