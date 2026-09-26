import Foundation

/// A finished goal, as `GET /api/collaboration` summarises it
/// (CL-20260926-goal-closure). Every field the backend might add later is
/// optional here, so an older or newer payload never fails the whole decode.
struct GoalClosureSummary: Codable, Identifiable, Equatable {
    var closure_id, goal_id, title: String
    var outcome: String?
    var created_at: String?
    var closed_at, by, words: String
    var reopened_at: String?
    var revisions, his_words, connections: Int?
    var final_artifact_title: String?
    var has_reflection: Bool?
    var acknowledgement: String?
    var id: String { closure_id }
    var isReopened: Bool { !(reopened_at ?? "").isEmpty }

    /// How it closed, in his terms.
    var howClosed: String {
        switch by {
        case "walk": "Closed on your walk"
        case "chat": "Closed in conversation"
        default: "Closed in the app"
        }
    }
}

/// An unclear request: he said something close to "close it", and she asks.
struct GoalClosureProposal: Codable, Identifiable, Equatable {
    var proposal_id: String
    var goal_ids: [String]
    var titles: [String]
    var words, by, proposed_at: String
    var id: String { proposal_id }
}

/// The frozen record of one finished goal: `GET /api/goal_closure?closure_id=`.
struct GoalClosureRecord: Codable, Identifiable {
    struct Reflection: Codable {
        var text: String
        var next_goal_seeds: [String]?
        var notice: String?
    }
    struct Dossier: Codable {
        struct Goal: Codable { var id, title, outcome: String; var why, priority, created_at: String? }
        struct Words: Codable, Identifiable {
            var id, excerpt: String
            var kind, observed_at, recording_id, episode_id: String?
        }
        struct Step: Codable, Identifiable {
            var number: Int?
            var at, title, change: String
            var id: String { at + "·" + String(number ?? 0) }
        }
        struct Artifact: Codable { var title, body: String; var at: String?; var revision: Int? }
        struct Question: Codable, Identifiable { var question: String; var kind: String?; var id: String { question } }
        struct Reference: Codable, Identifiable {
            var title, path, kind: String; var uses: Int
            var id: String { path.isEmpty ? title : path }
        }
        struct Connection: Codable, Identifiable {
            var title, status: String; var verdict: String?
            var id: String { title + status }
        }
        struct ClosingInput: Codable { var text: String; var observed_at: String? }
        struct Stats: Codable { var revisions, his_words, connections: Int; var connections_used, agreements: Int? }
        var goal: Goal
        var his_words: [Words]
        var steps: [Step]
        var final_artifact: Artifact
        var open_questions: [Question]
        var references: [Reference]
        var connections: [Connection]?
        var stats: Stats
        var notice: String?
        var closing_input: ClosingInput?
    }
    var closure_id, title, by, words, closed_at: String
    var reopened_at: String?
    var reflection: Reflection?
    var dossier: Dossier
    var id: String { closure_id }
}

extension CollaborationState {
    /// Finished goals he has not reopened, newest first (the backend's order).
    var finishedGoals: [GoalClosureSummary] { (closures ?? []).filter { !$0.isReopened } }
    /// The one line she says after a close, while it is still news.
    var closureAcknowledgement: GoalClosureSummary? {
        finishedGoals.first { !($0.acknowledgement ?? "").isEmpty }
    }
    /// A goal that has a finished record is shown there, not as a stale card.
    func hasRecord(_ goal: Goal) -> Bool { finishedGoals.contains { $0.goal_id == goal.id } }
}

/// "12 Sep 2026" from any ISO timestamp the backend sends; empty when absent.
func goalDay(_ timestamp: String?) -> String {
    guard let timestamp, !timestamp.isEmpty else { return "" }
    let date = voiceDate(timestamp)
    guard date != .distantPast else { return String(timestamp.prefix(10)) }
    return date.formatted(.dateTime.day().month(.abbreviated).year())
}
