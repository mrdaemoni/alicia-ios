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
        return .init(status: "ready", state_status: "ready", privacy: "Synthetic preview", historical_note: "Synthetic preview only", as_of: "2026-09-13", generated_at: "2026-09-13T16:00:00Z", metrics: metrics, sources: [], goals: [goal], events: [])
    }
}
#endif
