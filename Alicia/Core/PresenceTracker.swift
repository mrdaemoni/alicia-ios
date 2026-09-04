import Foundation

/// Tells Alicia what Hector actually does in the app.
///
/// Until 2026-09-04 the API was a broadcast: every GET rendered her state onto
/// the phone, and every POST needed a deliberate tap (react, reply, pin, card
/// verdict). Nothing reported *presence*. So her model of the day counted her
/// own sends, her own tool calls and his emoji — three of those four being
/// facts about her — and a day he spent reading and listening here reached her
/// as silence. On 2026-09-01 her evening message opened "Quiet day — no
/// messages, signals stayed low and still" about a day he had been present for.
///
/// The backend already records playback on its own, from the GET that streams
/// the audio (`ios_api._record_play`), so that half works on builds older than
/// this file. What only the app can know is where he *was*: which tab, for how
/// long, and which cards he actually read.
///
/// Design rules, in order of how badly breaking them would hurt:
///
/// 1. **Never block or fail the UI.** A dwell report is worth less than a
///    smooth tab change. Everything here is fire-and-forget; a send that fails
///    drops its batch and says nothing.
/// 2. **Batch, don't chatter.** Events buffer and flush on background, on a
///    size threshold, and when the app goes away. A POST per tab tap would be
///    a request storm for a signal nobody reads in real time.
/// 3. **Never report a dwell the phone cannot vouch for.** A tab left open
///    while the app is backgrounded is not attention. The clock stops at
///    `.background` and restarts at `.active`, and the backend clamps anything
///    over 90 minutes anyway.
/// 4. **A swipe through a tab is not a visit.** Under 1.5s is dropped, matching
///    the backend's own floor so the two agree about what counts.
@MainActor
final class PresenceTracker {
    static let shared = PresenceTracker()

    /// Flush once the buffer reaches this, so a long session still reports
    /// before it ends.
    private let flushThreshold = 12
    /// Matches `skills/app_events.MIN_DWELL_MS` — if the two drift, the app
    /// sends dwells the backend silently discards.
    private let minDwellMS = 1500

    private var buffer: [[String: Any]] = []
    private var currentSection: String?
    private var sectionEnteredAt: Date?
    private var service: AliciaService?

    private init() {}

    func configure(service: AliciaService) {
        self.service = service
    }

    // MARK: events

    func appOpened() {
        append(kind: "app_open")
        // Re-open the clock on whatever tab is showing: the section did not
        // change, but the time he was away must not be counted as dwell.
        sectionEnteredAt = Date()
    }

    /// Call when the visible tab changes, and with the same value on
    /// foreground/background so the open section is closed out honestly.
    func section(_ name: String) {
        closeCurrentSection()
        currentSection = name
        sectionEnteredAt = Date()
    }

    func cardSeen(_ id: String, seconds: TimeInterval) {
        append(kind: "card_view", ref: id, ms: Int(seconds * 1000))
    }

    /// The app going away: close the open section and push everything now.
    func appBackgrounded() {
        closeCurrentSection()
        sectionEnteredAt = nil          // stop the clock while he is gone
        flush()
    }

    private func closeCurrentSection() {
        guard let name = currentSection, let since = sectionEnteredAt else { return }
        let ms = Int(Date().timeIntervalSince(since) * 1000)
        guard ms >= minDwellMS else { return }
        append(kind: "screen_view", ref: name, ms: ms)
    }

    // MARK: plumbing

    private func append(kind: String, ref: String = "", ms: Int = 0) {
        var event: [String: Any] = ["kind": kind]
        if !ref.isEmpty { event["ref"] = ref }
        if ms > 0 { event["ms"] = ms }
        buffer.append(event)
        if buffer.count >= flushThreshold { flush() }
    }

    func flush() {
        guard let service, !buffer.isEmpty else { return }
        let batch = buffer
        buffer.removeAll()
        // Detached and unawaited on purpose — see rule 1. If it fails, the
        // batch is gone and nothing surfaces; presence is a convenience, and
        // a retry queue here would be more machinery than the signal is worth.
        Task.detached { await service.recordEvents(batch) }
    }
}
