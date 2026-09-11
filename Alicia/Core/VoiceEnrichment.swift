import Foundation

struct VoiceEnrichment: Codable {
    struct Evidence: Codable {
        var source, ref, quote: String?
        var start, end: Double?
    }
    struct Insight: Codable, Identifiable {
        var id, text: String
        var kind, uncertainty, support: String?
        var evidence: [Evidence]?
        var goal_ids: [String]?
    }
    enum EvidenceReference: Codable {
        case finding(String), passage(Evidence)
        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let id = try? container.decode(String.self) { self = .finding(id) }
            else { self = .passage(try container.decode(Evidence.self)) }
        }
        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self { case .finding(let id): try container.encode(id)
                case .passage(let evidence): try container.encode(evidence) }
        }
    }
    struct Answer: Codable, Identifiable {
        var id, text, goal_id: String
        var provisional: Bool?
        var evidence: [EvidenceReference]?
    }
    struct Receipt: Codable {
        var pass, provider, model, response_id, stop_reason, status: String?
    }
    struct Coverage: Codable {
        var recorded_seconds, covered_seconds: Double?
        var tail_covered: Bool?
        var insight_count, disputed_count: Int?
    }
    var analysis_state: String
    var analysis_id, ineligible_reason, stale_reason: String?
    var pass_receipts: [Receipt]?
    var insights: [Insight]?
    var candidate_answers: [Answer]?
    var notes: [String]?
    var coverage: Coverage?
}

/// Immutable mutation survives sheet dismissal, app restart, and an uncertain response.
struct VoiceEnrichmentFeedback: Codable {
    var request_id = UUID().uuidString
    var action = "enrichment_feedback"
    var recording_id, analysis_id, item_id, verdict, text: String
    var body: [String: Any] {
        ["request_id": request_id, "action": action, "recording_id": recording_id,
         "analysis_id": analysis_id, "item_id": item_id, "verdict": verdict, "text": text]
    }
    var storageKey: String { "alicia.voiceEnrichmentFeedback." + recording_id + "." + analysis_id + "." + item_id }
    func persist() {
        if let data = try? JSONEncoder().encode(self) { UserDefaults.standard.set(data, forKey: storageKey) }
    }
}
