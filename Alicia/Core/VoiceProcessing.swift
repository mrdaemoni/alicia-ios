import Foundation

/// Mac processing is evidence, never a human transcript or a sent message.
struct VoiceJSON: Codable, Equatable {
    var value: Value
    indirect enum Value: Equatable { case null, bool(Bool), number(Double), string(String), array([VoiceJSON]), object([String: VoiceJSON]) }
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { value = .null }
        else if let v = try? c.decode(Bool.self) { value = .bool(v) }
        else if let v = try? c.decode(Double.self) { value = .number(v) }
        else if let v = try? c.decode(String.self) { value = .string(v) }
        else if let v = try? c.decode([VoiceJSON].self) { value = .array(v) }
        else { value = .object(try c.decode([String: VoiceJSON].self)) }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch value {
        case .null: try c.encodeNil()
        case .bool(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        }
    }
}
struct VoiceManifestSegment: Codable, Equatable {
    var id: String
    var sequence: Int
    var sha256: String
    var bytes: Int
}
struct VoiceFinalization: Codable, Equatable {
    var action = "finalize"
    var recording_id, request_id, ended_at: String
    var capture_status = "finished"
    var expected_segments: [VoiceManifestSegment]
    var language_hint = "auto"
}
struct VoiceTranscriptionRetry: Codable, Equatable {
    var action = "retry_transcription"
    var recording_id, request_id, event_id: String
}
struct VoiceMachineDraft: Codable, Equatable {
    var id, text, kind: String
    var provenance: [String: VoiceJSON]?
}
struct VoiceTranscription: Codable, Equatable {
    var request_id, recording_id, state: String
    var manifest_sha256: String?
    var missing_segment_ids: [String]?
    var attempt: Int?
    var transcript_id, error_code, error: String?
    var retryable: Bool?
    var recorded_seconds, processed_seconds: Double?
    var model, language: String?
    var draft: VoiceMachineDraft?
    /// A bounded automatic retry budget does not remove the user's explicit retry choice.
    var canRetryExplicitly: Bool {
        state == "failed" && (retryable == true || error_code == "attempts_exhausted")
    }
    var ready: Bool {
        state == "ready" && draft?.kind == "mac_whisper"
            && !(draft?.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            && transcript_id == draft?.id
    }
}
struct VoiceProcessingResponse: Decodable {
    var ok: Bool
    var transcription: VoiceTranscription?
    var error: String?
}
/// The target is frozen before the microphone opens, not chosen at send time.
struct VoiceReview: Codable, Equatable {
    var destination: String // dialogue | proactive | walk
    var proactiveID = ""
    var proactiveExcerpt = ""
    var text = ""
    var seededTranscriptID: String?
    var edited = false
    mutating func receive(_ state: VoiceTranscription) {
        guard state.ready, !edited, seededTranscriptID == nil, let draft = state.draft else { return }
        text = draft.text; seededTranscriptID = draft.id
    }
}
struct VoiceSubmission: Codable, Equatable {
    var requestID, recordingID, transcriptionRequestID, transcriptID, text, destination: String
    var episodeID, prompt, proactiveID: String
    var voice: Bool
    var attempted = false
    var body: [String: Any] {
        var result: [String: Any] = ["recording_id": recordingID, "transcription_request_id": transcriptionRequestID,
            "transcript_id": transcriptID, "text": text]
        if destination == "walk" {
            result["action"] = "end_walk"; result["request_id"] = requestID
            result["episode_id"] = episodeID; result["topic"] = prompt
        } else {
            result["client_request_id"] = requestID; result["episode_id"] = episodeID
            if destination == "dialogue" { result["voice"] = voice }
            if destination == "proactive" { result["proactive_id"] = proactiveID; result["episode_id"] = episodeID }
        }
        return result
    }
}
struct VoiceSubmissionStatus: Codable, Equatable {
    var request_id, state: String
    var reply_id, text: String?
    var message_id: Int?
    var error: String?
    /// Client-retained media from this request's stream, after its saved receipt agrees.
    var voice_path: String?

    func retainingVoiceMedia(from previous: VoiceSubmissionStatus?) -> VoiceSubmissionStatus {
        var result = self
        guard state == "completed" else { result.voice_path = nil; return result }
        if voice_path == nil, let previous, previous.state == "completed",
           request_id == previous.request_id, let reply_id, !reply_id.isEmpty,
           reply_id == previous.reply_id { result.voice_path = previous.voice_path }
        return result
    }
}
extension VoiceSubmissionStatus {
    enum CodingKeys: String, CodingKey { case request_id, state, reply_id, text, message_id, error, voice_path }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        request_id = try c.decode(String.self, forKey: .request_id)
        state = try c.decode(String.self, forKey: .state)
        reply_id = try c.decodeIfPresent(String.self, forKey: .reply_id)
        text = try c.decodeIfPresent(String.self, forKey: .text)
        error = try c.decodeIfPresent(String.self, forKey: .error)
        voice_path = try c.decodeIfPresent(String.self, forKey: .voice_path)
        if let value = try? c.decode(Int.self, forKey: .message_id) { message_id = value }
        else if let raw = try? c.decode(String.self, forKey: .message_id) { message_id = Int(raw) }
        else { message_id = nil }
    }
}

/// A stream belongs to one POST. Audio is usable only once that POST has a matching saved reply.
struct VoiceReplyStreamReceipt {
    private var voicePath: String?
    private var replyID: String?
    private var conflictingReply = false

    mutating func receive(_ line: String) -> Bool {
        guard let event = voiceStreamEvent(line) else { return false }
        if let id = event["reply_id"] as? String, !id.isEmpty {
            if let replyID, replyID != id { conflictingReply = true }
            replyID = id
        }
        if let path = event["voice"] as? String, !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            voicePath = path
        }
        return voiceStreamFinished(line)
    }

    func confirmed(_ status: VoiceSubmissionStatus, requestID: String) -> VoiceSubmissionStatus {
        var result = status
        guard status.request_id == requestID, status.state == "completed",
              let savedReply = status.reply_id, !savedReply.isEmpty,
              !conflictingReply, replyID == nil || replyID == savedReply else { return result }
        result.voice_path = voicePath
        return result
    }
}
enum VoiceTransport<T> {
    case value(T), rejected(String), notFound, unavailable
}
/// Only 400/409 are definite mutation rejection. Auth and 5xx remain uncertain.
func decodeVoiceResponse<T: Decodable>(_ type: T.Type, data: Data, status: Int, allowNotFound: Bool = false) -> VoiceTransport<T> {
    if status == 200, let value = try? JSONDecoder().decode(T.self, from: data) { return .value(value) }
    if allowNotFound && status == 404 { return .notFound }
    if status == 400 || status == 409 {
        let error = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        return .rejected(error?["error"] as? String ?? "This request was not accepted. Your words are kept.")
    }
    return .unavailable
}

/// A terminal stream frame only ends transport waiting. The saved receipt still decides completion.
func voiceStreamFinished(_ line: String) -> Bool {
    guard let event = voiceStreamEvent(line) else { return false }
    return event["done"] as? Bool == true || !(event["error"] as? String ?? "").isEmpty
}
private func voiceStreamEvent(_ line: String) -> [String: Any]? {
    guard line.hasPrefix("data:"),
          let data = line.dropFirst(5).trimmingCharacters(in: .whitespaces).data(using: .utf8),
          let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
    return event
}
