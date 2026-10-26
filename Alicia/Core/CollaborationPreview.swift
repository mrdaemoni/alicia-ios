#if DEBUG
import Foundation

/// Inert, process-local fixture selected only by --collaboration-preview.
@MainActor final class CollaborationPreview {
    static let shared = CollaborationPreview()
    static let goalID = "preview-goal", connectionID = "preview-connection"
    private static let impulseReveal = ImpulseResearch.Reveal(
        outcome: "ok", model: "jev-1.13.0", question_version: "jev-impulse-v1",
        suggested_expression: "notify", suggested_expression_confidence: 0.72,
        stance: "offer", answers: [
            "worth_receiving_now": .init(type: "noul", noul: 0.78),
            "expression_mode": .init(type: "choice", choice: "notify",
                probabilities: ["hold": 0.05, "carry": 0.08, "surface": 0.12, "notify": 0.72, "interrupt": 0.03], confidence: 0.72),
            "stance": .init(type: "choice", choice: "offer",
                probabilities: ["witness": 0.12, "ask": 0.08, "challenge": 0.03, "offer": 0.70, "celebrate": 0.04, "abstain": 0.03], confidence: 0.70),
        ])
    private var value = CollaborationState(revision: 1,
        goals: [.init(id: goalID, title: "Preview · Make room for what matters", outcome: "Name the outcome before deciding what to remove.", why: "A useful test of subtraction.", status: "active", priority: "more", revision: 1, created_at: "2026-09-07T15:00:00Z", updated_at: "2026-09-07T15:00:00Z")],
        connections: [.init(id: connectionID, goal_id: goalID, title: "Preview · Subtraction needs an outcome", claim: "Removing something is useful when it makes the intended outcome clearer.", why_now: "This returns to your question about what remains after removal.", question: "What would you want to remain?", proposed_action: "Compare one choice to keep with one choice to remove.", action_owner: "together", review_condition: "When we can explain what the removal serves.", status: "proposed", evidence: [
            .init(id: "preview-source", kind: "episode", title: "Preview · Sculpture and subtraction", path: "fixture/episode.md", excerpt: "Preview passage: removal serves the outcome; it is not an end in itself.", line_start: 2, line_end: 2, sha256: "fixture", episode_id: "S15E03", recording_id: "", relation: "Proposed connection"),
            .init(id: "preview-voice", kind: "voice", title: "Preview · Your recorded question", path: "", excerpt: "Preview words: what remains after removal?", line_start: 0, line_end: 0, sha256: "fixture", episode_id: "S15E07", recording_id: VoiceArchive.previewID, relation: "Explicit words")], origin_text: "Preview · I want to understand what remains after removal.", origin_id: "preview-human", created_at: "2026-09-07T15:00:00Z", revision: 1)],
        agreements: [], results: [.init(id: "preview-goal-result", agreement_id: "", title: "Preview · What the saved goal suggests", body: "A first comparison: decide what should remain before deciding what to remove. This is a draft toward your saved goal, without a new commitment.", status: "prepared", evidence: [], created_at: "2026-09-07T15:00:00Z", goal_id: goalID)], signals: [.init(id: "preview-signal", kind: "self_report", title: "Preview · You said", value: "I have space to think this through today.", source: "Your explicit context", observed_at: "2026-09-07T15:00:00Z", notice: "Fixture, not an inference from audio.")], pending: false, error: "", followups_enabled: true, telegram_returns_enabled: false)
    private var receipts = [String: CollaborationMutation]()
    init() {
        value.impulse_research = ImpulseResearch(status: .init(
            active: true, enabled: true, mode: "shadow", model: "jev-1.13.0",
            question_version: "jev-impulse-v1", feedback_version: "jev-human-v1",
            observations: 2, valid_observations: 2, failures: 0, failure_rate: 0,
            labeled: 1, last_observed_at: "2026-09-19T18:01:00Z",
            last_success_at: "2026-09-19T18:01:00Z", blind_until_label: true), items: [
                .init(id: "preview-impulse-unlabeled", source: "collaboration",
                    title: "A current result", text: "There is a new result worth seeing.",
                    observed_at: "2026-09-19T18:01:00Z", state_hash: String(repeating: "a", count: 64),
                    outcome: "ok", labeled: false),
                .init(id: "preview-impulse-labeled", source: "circulation",
                    title: "A thought Alicia sent", text: "This connection may matter to the choice you are making.",
                    observed_at: "2026-09-19T17:01:00Z", state_hash: String(repeating: "b", count: 64),
                    outcome: "ok", labeled: true,
                    feedback: .init(usefulness: "useful_now", stance: "stance_fit",
                        saved_at: "2026-09-19T17:05:00Z", feedback_version: "jev-human-v1",
                        trace_state_hash: String(repeating: "b", count: 64)),
                    reveal: Self.impulseReveal),
            ])
        if ProcessInfo.processInfo.arguments.contains("--finished-goals-preview") { seedFinished() }
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
    /// Invented fixture (the iOS repo is public): one goal closed on a walk,
    /// one still active with an unclear "close it?" question.
    nonisolated static let finishedID = "00000000-0000-4000-8000-00000000c105"
    private func seedFinished() {
        value.goals.append(.init(id: "preview-finished-goal", title: "Preview · Learn to rest between sprints",
            outcome: "Three honest signs that a rest is due.", why: "A rhythm I can keep.", status: "completed",
            priority: "normal", revision: 2, created_at: "2026-08-30T15:00:00Z", updated_at: "2026-09-20T16:40:00Z"))
        value.closures = [.init(closure_id: Self.finishedID, goal_id: "preview-finished-goal",
            title: "Preview · Learn to rest between sprints", outcome: "Three honest signs that a rest is due.",
            created_at: "2026-08-30T15:00:00Z", closed_at: "2026-09-20T16:40:00Z", by: "walk",
            words: "Preview words · I think we have it, let's close the rest goal.", reopened_at: "",
            revisions: 12, his_words: 5, connections: 4, final_artifact_title: "Preview · Three signs of a due rest",
            has_reflection: true,
            acknowledgement: "You closed ‘Preview · Learn to rest between sprints’ on your walk on Sep 20. The work we did together is kept in Finished together, and I'm ready for what's next.")]
        value.closure_proposals = [.init(proposal_id: "preview-proposal", goal_ids: [Self.goalID],
            titles: ["Preview · Make room for what matters"], words: "Preview words · maybe this one is nearly done",
            by: "walk", proposed_at: "2026-09-21T16:00:00Z")]
    }
    nonisolated static var finishedRecord: GoalClosureRecord {
        .init(closure_id: finishedID, title: "Preview · Learn to rest between sprints", by: "walk",
              words: "Preview words · I think we have it, let's close the rest goal.", closed_at: "2026-09-20T16:40:00Z",
              reopened_at: "",
              reflection: .init(text: "Preview reading · It began as a wish for rhythm and landed on three signs in your own words: \"let's close the rest goal\".",
                                next_goal_seeds: ["Preview seed · What does a rest day protect?", "Preview seed · Which sign shows up first?"],
                                notice: "Alicia's reading of the work, written when the goal closed. Not his words."),
              dossier: .init(goal: .init(id: "preview-finished-goal", title: "Preview · Learn to rest between sprints",
                                         outcome: "Three honest signs that a rest is due.", why: "A rhythm I can keep.",
                                         priority: "normal", created_at: "2026-08-30T15:00:00Z"),
                             his_words: [.init(id: "w1", excerpt: "Preview words · I notice I stop reading when I'm tired.", observed_at: "2026-09-02T15:00:00Z"),
                                         .init(id: "w2", excerpt: "Preview words · The body says it before the calendar does.", observed_at: "2026-09-11T15:00:00Z")],
                             steps: [.init(number: 3, at: "2026-09-03T12:00:00Z", title: "Preview · First list of signs", change: ""),
                                     .init(number: 12, at: "2026-09-19T12:00:00Z", title: "Preview · Three signs of a due rest", change: "")],
                             final_artifact: .init(title: "Preview · Three signs of a due rest",
                                                   body: "Preview body · 1. Reading stops. 2. Sleep shortens. 3. Small things feel urgent."),
                             open_questions: [.init(question: "Preview · Does the order of the signs matter?")],
                             references: [.init(title: "Preview · A note on rhythm", path: "preview.md", kind: "synthesis", uses: 6)],
                             connections: [], stats: .init(revisions: 12, his_words: 5, connections: 4),
                             notice: "Assembled from receipts when the goal closed.",
                             closing_input: .init(text: "Preview words · A longer reflection. I think we have it, let's close the rest goal.")))
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
        case "reopen_goal", "close_goal", "closure_decision":
            value.closure_proposals = []
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
        case "impulse_feedback":
            guard let index = value.impulse_research?.items.firstIndex(where: { $0.id == change.candidate_id }),
                  value.impulse_research?.items[index].state_hash == change.trace_state_hash,
                  value.impulse_research?.items[index].labeled == false,
                  let usefulness = change.usefulness, let stance = change.stance else {
                return .init(ok: false, error: "The research item changed. Refresh before saving.", state: value)
            }
            value.impulse_research?.items[index].labeled = true
            value.impulse_research?.items[index].feedback = .init(usefulness: usefulness,
                stance: stance, saved_at: now, feedback_version: "jev-human-v1",
                trace_state_hash: change.trace_state_hash ?? "")
            value.impulse_research?.items[index].reveal = Self.impulseReveal
            value.impulse_research?.status.labeled += 1
        default: break
        }
        receipts[change.event_id] = change
        return .init(ok: true, state: value)
    }
}
#endif
