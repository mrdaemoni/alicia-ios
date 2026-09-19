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
    init() {
        guard ProcessInfo.processInfo.arguments.contains("--work-review-preview") else { return }
        value.goals += [
            .init(id: "preview-goal-two", title: "Peace-time urgency", outcome: "Act with care without a crisis.", why: "A separate goal, close to enough.", status: "active", priority: "normal", revision: 1, created_at: "now", updated_at: "now"),
            .init(id: "preview-goal-three", title: "Write with presence", outcome: "A story worth returning to.", why: "Work I can finish.", status: "active", priority: "normal", revision: 1, created_at: "now", updated_at: "now")]
        let sections: [WorkReviewSection] = [
            .init(id: "preview-q7", title: "Q7. Enough to be present", kind: "question", text: "Q7. Is ‘enough’ the amount that lets me be fully present to what I have?\n\n", content_hash: "fixture-q7", review: .empty),
            .init(id: "preview-candidate", title: "Candidate E", kind: "passage", text: "  Candidate E: Attention may be the constraint. Having more can leave less of you available for what you already have. This is a possibility to test, not an account of what Hector believes.\n\n", content_hash: "fixture-candidate", review: .empty),
            .init(id: "preview-counterexample", title: "A counterexample", kind: "passage", text: "  Counterexample: A scarcity floor still matters. Attention cannot replace the material conditions that let a person live.\n", content_hash: "fixture-counterexample", review: .empty)]
        value.results[0].title = "Shaping enough · Q7 candidate draft"
        value.results[0].body = sections.map(\.text).joined()
        value.results[0].review_sections = sections
        value.results[0].review_progress = .init(total: 3, reviewed: 0, questions: 1, answered: 0)
        value.results[0].evidence = [value.connections[0].evidence[0]]
        value.results[0].project_id = "preview-project"
        value.results[0].project_revision = 8
    }
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
        case "work_review":
            guard let ri = value.results.firstIndex(where: { $0.id == change.result_id }),
                  let si = value.results[ri].review_sections?.firstIndex(where: { $0.id == change.section_id }),
                  var section = value.results[ri].review_sections?[si],
                  section.content_hash == change.content_hash,
                  section.review.revision == change.expected_revision else {
                return .init(ok: false, error: "The passage or review changed. Your draft stays here.", state: value)
            }
            if ProcessInfo.processInfo.arguments.contains("--work-review-save-delay") {
                try? await Task.sleep(for: .seconds(3))
            }
            switch change.verdict {
            case "agree": section.review.stance = "agree"
            case "disagree": section.review.stance = "disagree"
            case "clear_stance": section.review.stance = "unreviewed"
            case "salient": section.review.salient = true
            case "unsalient": section.review.salient = false
            case "hide": section.review.hidden = true
            case "restore": section.review.hidden = false
            case "edit": section.review.edited_text = change.text ?? ""
            case "answer": section.review.answer = change.text ?? ""
            case "comment": section.review.comment = change.text ?? ""
            default: return .init(ok: false, error: "Unknown review", state: value)
            }
            section.review.revision = value.revision
            value.results[ri].review_sections?[si] = section
            let all = value.results[ri].review_sections ?? []
            value.results[ri].review_progress = .init(total: all.count, reviewed: all.filter {
                $0.review.stance != "unreviewed" || $0.review.hidden || !$0.review.edited_text.isEmpty || !$0.review.answer.isEmpty || !$0.review.comment.isEmpty
            }.count, questions: all.filter { $0.kind == "question" }.count,
                answered: all.filter { $0.kind == "question" && !$0.review.answer.isEmpty }.count)
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
