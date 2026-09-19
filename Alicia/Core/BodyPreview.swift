#if DEBUG
import Foundation

enum BodyPreview {
    static var overview: BodyOverview {
        let metrics: [BodyOverview.Metric] = [
            .init(id: "sleep_hours", label: "Sleep", unit: "hours", value: 7.4, baseline: 7.1, date: "2026-09-13", baseline_from: "2026-08-15", baseline_to: "2026-09-13", baseline_days: 30, series: [.init(date: "2026-09-12", value: 7.0), .init(date: "2026-09-13", value: 7.4)]),
            .init(id: "readiness_score", label: "Readiness", unit: "/100", value: 81, baseline: 79, date: "2026-09-13", baseline_from: "2026-08-15", baseline_to: "2026-09-13", baseline_days: 30, series: []),
            .init(id: "average_hrv_ms", label: "HRV", unit: "ms", value: 44, baseline: 42, date: "2026-09-13", baseline_from: "2026-08-15", baseline_to: "2026-09-13", baseline_days: 30, series: []),
            .init(id: "steps", label: "Movement", unit: "steps", value: nil, baseline: 6500, date: nil, baseline_from: "2026-08-15", baseline_to: "2026-09-13", baseline_days: 30, series: [])]
        var goal = BodyEvent(kind: "goal", goal_id: "synthetic-goal-one")
        goal.text = "Notice what helps me feel rested"
        goal.criterion = "I can describe the conditions that help my energy and attention."
        goal.metric = "sleep_hours"
        return .init(status: "ready", state_status: "ready", privacy: "Synthetic preview", historical_note: "Synthetic preview only", as_of: "2026-09-13", generated_at: "2026-09-13T16:00:00Z", last_built: nil, last_measurement: nil, stale_days: nil, metrics: metrics, sources: [], goals: [goal], events: [])
    }

    /// The state Hector actually met on build 18: the Mac had not rebuilt the
    /// bridge in five days, so the backend refused it and the app printed one
    /// word. Kept as a preview so the sentence that replaced that word is
    /// inspectable without waiting for a real bridge to go stale.
    static var staleOverview: BodyOverview {
        .init(status: "stale", state_status: "ready", privacy: "Synthetic preview",
              historical_note: "Synthetic preview only", as_of: nil, generated_at: nil,
              last_built: "2026-09-13T16:19:29Z", last_measurement: "2026-09-13", stale_days: 5,
              metrics: [], sources: [], goals: [], events: [])
    }
}
#endif
