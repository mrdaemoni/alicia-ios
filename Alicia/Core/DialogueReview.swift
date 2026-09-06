import Foundation

/// Public response context; the private model input never crosses this API.
struct DialogueReview: Codable, Identifiable {
    struct Source: Codable, Identifiable {
        var title, url, excerpt: String
        var id: String { url }
    }
    struct Feedback: Codable { var target, verdict, note: String }
    struct Comparison: Codable {
        var status: String
        var request_id, provider, model, reply, detail, error, evaluation_kind: String?
        var same_input: Bool?
    }
    struct Preference: Codable {
        var choice, reason, comparison_id, evaluation_kind: String
        var training_allowed: Bool
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
    var target: String = ""
    var verdict: String = ""
    var note: String = ""
    var choice: String = ""
    var reason: String = ""
    var training_allowed: Bool = false

    var body: [String: Any] {
        ["action": action, "reply_id": reply_id, "event_id": event_id,
         "target": target, "verdict": verdict, "note": note, "choice": choice,
         "reason": reason, "training_allowed": training_allowed]
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
#endif
