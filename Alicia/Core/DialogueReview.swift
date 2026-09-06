import Foundation

/// Public response context; the private model input never crosses this API.
struct DialogueReview: Codable, Identifiable {
    struct Source: Codable, Identifiable {
        var title, url, excerpt: String
        var id: String { url }
    }
    struct Feedback: Codable { var target, verdict, note: String; var answer, comparison_id: String? }
    struct Comparison: Codable {
        var status: String
        var request_id, provider, model, reply, detail, error, evaluation_kind: String?
        var reading, lens, context_note: String?
        var same_input: Bool?
    }
    struct Preference: Codable {
        var choice, reason, comparison_id, evaluation_kind: String
        var training_allowed: Bool
        var reason_tags: [String]?
    }
    var id, reply, reading, detail, lens, user_text, provider, model: String
    var shortened, comparison_eligible: Bool
    var comparison_reason: String
    var sources: [Source]
    var context_modules, tools: [String]
    var feedback: [String: Feedback]
    var comparison: Comparison
    var preference: Preference?
    var training_status: String

    var providerLabel: String { provider == "qwen" ? "Qwen · Mac mini" : "Claude" }
}

struct DialogueMutation: Codable, Equatable {
    var action, reply_id: String
    var event_id: String = UUID().uuidString
    var answer: String = "original"
    var reason_tags: [String] = []
    var target: String = ""
    var verdict: String = ""
    var note: String = ""
    var choice: String = ""
    var reason: String = ""
    var training_allowed: Bool = false

    var body: [String: Any] {
        ["action": action, "reply_id": reply_id, "event_id": event_id,
         "answer": answer, "reason_tags": reason_tags, "target": target, "verdict": verdict, "note": note, "choice": choice,
         "reason": reason, "training_allowed": training_allowed]
    }
}

extension DialogueMutation {
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        action = try values.decode(String.self, forKey: .action)
        reply_id = try values.decode(String.self, forKey: .reply_id)
        event_id = try values.decode(String.self, forKey: .event_id)
        answer = try values.decodeIfPresent(String.self, forKey: .answer) ?? "original"
        reason_tags = try values.decodeIfPresent([String].self, forKey: .reason_tags) ?? []
        target = try values.decode(String.self, forKey: .target)
        verdict = try values.decode(String.self, forKey: .verdict)
        note = try values.decode(String.self, forKey: .note)
        choice = try values.decode(String.self, forKey: .choice)
        reason = try values.decode(String.self, forKey: .reason)
        training_allowed = try values.decode(Bool.self, forKey: .training_allowed)
    }
}

struct DialogueMutationResult: Decodable {
    var ok: Bool
    var response: DialogueReview?
    var error: String?
}

extension Message {
    /// Old reports also open compactly. Their exact original remains in the sheet.
    var conversationalPreview: String {
        guard sender == .alicia else { return text }
        let words = text.split(whereSeparator: \.isWhitespace)
        guard words.count > 70 || text.count > 600 else { return text }
        let prefix = words.prefix(70).joined(separator: " ")
        return String(prefix.prefix(600)) + "…"
    }
}

#if DEBUG
extension DialogueReview {
    static let previewID = "d5723d88-9d82-46b6-839b-12d7a5bb69c1"
    static var preview: DialogueReview {
        var value = DialogueReview(id: previewID,
            reply: "Good to have you home. What stayed with you from this morning’s episode?",
            reading: "You’re home and want to continue learning together. I don’t know yet which idea you want to follow.",
            detail: "We can begin with the idea that stayed with you, or something you disagreed with. Your reaction can take us away from the episode’s frame.",
            lens: "musubi", user_text: "I’m back home and excited to learn with you.",
            provider: "qwen", model: "Preview fixture · Qwen", shortened: false,
            comparison_eligible: true, comparison_reason: "", sources: [],
            context_modules: ["dialogue_delivery", "episode_day", "memory", "evidence"], tools: [], feedback: [:],
            comparison: .init(status: "not_requested"), preference: nil,
            training_status: "not_selected")
        if ProcessInfo.processInfo.arguments.contains("--dialogue-review-comparison-preview") {
            value.comparison = .init(status: "ready", request_id: "fixture-comparison", provider: "claude",
                model: "Preview fixture · Claude", reply: "Welcome home. Which idea do you want to take further together?",
                detail: "We can follow your curiosity from here.", evaluation_kind: "contextual_preference", same_input: true)
        }
        return value
    }
}
/// Isolated, process-local fixture for exercising real controls in Simulator.
actor DialogueReviewPreviewStore {
    static let shared = DialogueReviewPreviewStore()
    private var value = DialogueReview.preview
    func read() -> DialogueReview { value }
    func save(_ mutation: DialogueMutation) -> DialogueMutationResult {
        if mutation.action == "compare" {
            value.comparison = .init(status: "ready", request_id: "fixture-comparison", provider: "claude",
                model: "Preview fixture · Claude", reply: "Welcome home. Which idea do you want to take further together?",
                detail: "We can follow your curiosity from here.", evaluation_kind: "contextual_preference", same_input: true)
        } else if mutation.action == "preference" {
            value.preference = .init(choice: mutation.choice, reason: mutation.reason,
                comparison_id: "fixture-comparison", evaluation_kind: "contextual_preference",
                training_allowed: mutation.training_allowed, reason_tags: mutation.reason_tags)
            value.training_status = mutation.training_allowed ? "pending_review" : "not_selected"
        } else if mutation.action == "feedback" {
            let key = (mutation.answer == "alternative" ? "alternative:" : "") + mutation.target
            value.feedback[key] = .init(target: mutation.target, verdict: mutation.verdict, note: mutation.note,
                answer: mutation.answer, comparison_id: mutation.answer == "alternative" ? "fixture-comparison" : "")
        }
        return .init(ok: true, response: value)
    }
}

#endif
