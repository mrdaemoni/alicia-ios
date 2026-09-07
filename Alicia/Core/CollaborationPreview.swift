#if DEBUG
import Foundation

/// Inert, process-local fixture selected only by --collaboration-preview.
@MainActor final class CollaborationPreview {
    static let shared = CollaborationPreview()
    static let goalID = "preview-goal", connectionID = "preview-connection"
    private var value = CollaborationState(revision: 1,
        goals: [.init(id: goalID, title: "Preview · Make room for what matters", outcome: "Name the outcome before deciding what to remove.", why: "A useful test of subtraction.", status: "active", priority: "more", revision: 1, created_at: "2026-09-07T15:00:00Z", updated_at: "2026-09-07T15:00:00Z")],
        connections: [.init(id: connectionID, goal_id: goalID, title: "Preview · Subtraction needs an outcome", claim: "Removing something is useful when it makes the intended outcome clearer.", why_now: "This returns to your question about what remains after removal.", question: "What would you want to remain?", proposed_action: "Compare one choice to keep with one choice to remove.", action_owner: "together", review_condition: "When we can explain what the removal serves.", status: "proposed", evidence: [
            .init(id: "preview-source", kind: "episode", title: "Preview · Sculpture and subtraction", path: "fixture/episode.md", excerpt: "Preview passage: removal serves the outcome; it is not an end in itself.", line_start: 2, line_end: 2, sha256: "fixture", episode_id: "S15E03", recording_id: "", relation: "Proposed connection"),
            .init(id: "preview-voice", kind: "voice", title: "Preview · Your recorded question", path: "", excerpt: "Preview words: what remains after removal?", line_start: 0, line_end: 0, sha256: "fixture", episode_id: "S15E07", recording_id: VoiceArchive.previewID, relation: "Explicit words")], origin_text: "Preview · I want to understand what remains after removal.", origin_id: "preview-human", created_at: "2026-09-07T15:00:00Z", revision: 1)],
        agreements: [], results: [.init(id: "preview-goal-result", agreement_id: "", title: "Preview · What the saved goal suggests", body: "A first comparison: decide what should remain before deciding what to remove. This is a draft toward your saved goal, without a new commitment.", status: "prepared", evidence: [], created_at: "2026-09-07T15:00:00Z", goal_id: goalID)], signals: [.init(id: "preview-signal", kind: "self_report", title: "Preview · You said", value: "I have space to think this through today.", source: "Your explicit context", observed_at: "2026-09-07T15:00:00Z", notice: "Fixture, not an inference from audio.")], pending: false, error: "", followups_enabled: true, telegram_returns_enabled: false)
    private var receipts = [String: CollaborationMutation]()
    func read() -> CollaborationState { value }
    func save(_ change: CollaborationMutation) async -> CollaborationResponse {
        if change.action == "signal", ProcessInfo.processInfo.arguments.contains("--collaboration-save-delay-preview") {
            try? await Task.sleep(for: .seconds(6))
        }
        if let prior = receipts[change.event_id] {
            return .init(ok: prior == change, error: prior == change ? nil : "Conflicting fixture receipt", state: value)
        }
        value.revision += 1
        let now = "2026-09-07T15:00:00Z"
        switch change.action {
        case "goal":
            let goal = CollaborationState.Goal(id: change.goal_id ?? change.event_id, title: change.title ?? "", outcome: change.outcome ?? "", why: change.why ?? "", status: change.status ?? "active", priority: change.priority ?? "normal", revision: value.revision, created_at: now, updated_at: now)
            if let index = value.goals.firstIndex(where: { $0.id == goal.id }) { value.goals[index] = goal } else { value.goals.append(goal) }
        case "connection":
            if let index = value.connections.firstIndex(where: { $0.id == change.connection_id }) {
                value.connections[index].status = change.verdict == "dismiss" ? "dismissed" : change.verdict == "use" ? "used" : value.connections[index].status
                value.connections[index].revision = value.revision
                if change.verdict == "clarify" { value.connections[index].question = "Preview clarification · Which outcome would make this removal worthwhile?" }
            }
        case "commit":
            value.agreements.append(.init(id: change.event_id, goal_id: Self.goalID, connection_id: change.connection_id ?? "", action: change.action_text ?? "", owner: change.owner ?? "together", review_condition: change.review_condition ?? "", review_at: change.review_at, status: "active", outcome: "", revision: value.revision, created_at: now, updated_at: now))
            value.results.append(.init(id: "preview-result-" + change.event_id, agreement_id: change.event_id, title: "Preview · A comparison to review", body: "Keep the outcome visible. Compare what the choice enables before judging how much it removes.", status: "prepared", evidence: value.connections[0].evidence, created_at: now))
        case "agreement", "outcome":
            if let index = value.agreements.firstIndex(where: { $0.id == change.agreement_id }) {
                if let status = change.status { value.agreements[index].status = status }
                if let text = change.text { value.agreements[index].outcome = text }
                value.agreements[index].revision = value.revision
            }
        case "signal":
            value.signals.append(.init(id: change.event_id, kind: "self_report", title: "You added · preview", value: change.text ?? "", source: "Your words", observed_at: now, notice: "An explicit report, not an inferred state."))
        case "settings":
            value.followups_enabled = change.followups_enabled ?? value.followups_enabled
            value.telegram_returns_enabled = change.telegram_returns_enabled ?? value.telegram_returns_enabled
        default: break
        }
        receipts[change.event_id] = change
        return .init(ok: true, state: value)
    }
}
#endif
