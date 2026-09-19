import Foundation

/// URLSession-backed implementation of `AliciaService` against the Alicia
/// backend's iOS API (`skills/ios_api.py`, port 8766 on the Mac Mini —
/// reachable over home Wi-Fi or Tailscale).
///
/// Wire format:
///   POST /api/chat        {"text": …} → SSE stream of {"t": token} / {"done": true}
///   GET  /api/thoughts    → [{title, body, tag, date}]
///   GET  /api/tracks      → [{title, mood, duration, symbol, fileName}]
///   GET  /api/gallery     → [{title, note, symbol, author, imageURL}]
///   GET  /api/health      → [{name, value, display, symbol, hue}]
///   POST /api/complement  {"title": …} → one gallery item
///   POST /api/events      {"events": [{kind, ref, ms}]} → presence telemetry
///   GET  /api/mind        → {text, has_note} — her weekly mind note
///
/// Auth is a bearer token; media URLs (audio, drawings) carry it as a
/// `?token=` query instead, because AVPlayer/AsyncImage can't set headers.
struct LiveAliciaService: AliciaService {
    let baseURL: URL
    let token: String

    func askBody(_ text: String) async -> BodyAnswer? {
        let data = try? JSONSerialization.data(withJSONObject: ["text": text])
        return await privateBodyRequest(method: "POST", data: data, path: "/api/body/ask")
    }
    func bodySource(id: String, offset: Int, expectedHash: String) async -> BodySourcePage? {
        var components = URLComponents()
        components.queryItems = [URLQueryItem(name: "id", value: id), URLQueryItem(name: "offset", value: String(offset)), URLQueryItem(name: "sha256", value: expectedHash)]
        return await privateBodyRequest(method: "GET", data: nil, path: "/api/body/source?" + (components.percentEncodedQuery ?? ""))
    }
    func bodyOverview() async -> BodyOverview? {
        await privateBodyRequest(method: "GET", data: nil)
    }
    func saveBodyEvent(_ event: BodyEvent) async -> BodySaveResult? {
        guard let data = try? JSONEncoder().encode(event) else { return nil }
        return await privateBodyRequest(method: "POST", data: data)
    }
    private func privateBodyRequest<T: Decodable>(method: String, data: Data?, path: String = "/api/body") async -> T? {
        var req = request(path, method: method, body: data)
        req.cachePolicy = .reloadIgnoringLocalCacheData
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.timeoutIntervalForRequest = path == "/api/body/ask" ? 210 : 15
        config.timeoutIntervalForResource = path == "/api/body/ask" ? 210 : 20
        let session = URLSession(configuration: config, delegate: PrivateBodySessionDelegate(), delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        guard let (bytes, response) = try? await session.data(for: req),
              [200, 409].contains((response as? HTTPURLResponse)?.statusCode ?? 0) else { return nil }
        return try? JSONDecoder().decode(T.self, from: bytes)
    }

    // MARK: request plumbing

    private func request(_ path: String, method: String = "GET", body: Data? = nil) -> URLRequest {
        // URL(string:relativeTo:) keeps query strings intact —
        // appending(path:) would percent-encode the "?".
        var req = URLRequest(url: URL(string: path, relativeTo: baseURL) ?? baseURL)
        req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body {
            req.httpBody = body
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return req
    }

    /// Absolute, token-carrying URL for a media path the API returned
    /// (e.g. "/api/drawing/x.png" → "http://host:8766/api/drawing/x.png?token=…").
    private func mediaURL(_ path: String) -> URL? {
        guard !path.isEmpty else { return nil }
        // A queued podcast episode was stored with its full, already-tokened
        // URL, so it comes back absolute. Appending it to baseURL would
        // produce nonsense — pass it straight through.
        if path.hasPrefix("http://") || path.hasPrefix("https://") {
            return URL(string: path)
        }
        var comps = URLComponents(url: baseURL.appending(path: path), resolvingAgainstBaseURL: false)
        comps?.queryItems = [URLQueryItem(name: "token", value: token)]
        return comps?.url
    }

    /// One GET + decode. Returns nil on ANY failure — network, non-200,
    /// auth, decode — and reports what happened to `ConnectionStatus` so a
    /// dead backend or rotated token is visible instead of rendering as an
    /// empty-but-alive-looking app. Decode failures log in DEBUG so field
    /// drift between `skills/ios_api.py` and these DTOs is diagnosable.
    /// How many times a read is attempted before the app says she cannot be
    /// reached, and how long it waits between attempts.
    ///
    /// On 2026-09-18 the phone left the Wi-Fi and Tailscale fell back from a
    /// direct route to a relay — 34ms became 400ms. One request lost to that
    /// transition put "she's unreachable" on the screen, and because the
    /// banner only cleared on a later success and nothing retried, it stayed
    /// there until Hector pulled to refresh. A transient network change should
    /// not need him to do anything.
    ///
    /// Three attempts over roughly three seconds: enough to ride out a route
    /// change or a relay hiccup, short enough that a genuinely dead backend is
    /// still reported promptly rather than hidden behind a spinner.
    private static let readAttempts = 3
    private static let retryDelays: [Duration] = [.milliseconds(400), .seconds(2)]

    private func fetchOne<D: Decodable>(_ path: String) async -> D? {
        for attempt in 0..<Self.readAttempts {
            do {
                let (data, resp) = try await URLSession.shared.data(for: request(path))
                let status = (resp as? HTTPURLResponse)?.statusCode ?? -1
                if status == 401 || status == 403 {
                    // A rejected token is not a network problem, and trying
                    // again with the same token is just three rejections.
                    ConnectionStatus.note(.unauthorized)
                    return nil
                }
                guard status == 200 else {
                    if await retry(attempt, path: path, because: "HTTP \(status)") { continue }
                    ConnectionStatus.note(.unreachable)
                    return nil
                }
                ConnectionStatus.note(.ok)   // reachable + authorized
                do {
                    return try JSONDecoder().decode(D.self, from: data)
                } catch {
                    // Reached her and she answered; the shape disagreed. That
                    // is drift between this DTO and skills/ios_api.py, not a
                    // connection problem, and retrying would only repeat it.
                    #if DEBUG
                    print("[LiveAliciaService] decode failed for \(path): \(error)")
                    #endif
                    return nil
                }
            } catch {
                if await retry(attempt, path: path, because: error.localizedDescription) { continue }
                ConnectionStatus.note(.unreachable)
                return nil
            }
        }
        ConnectionStatus.note(.unreachable)
        return nil
    }

    /// True when another attempt is due; sleeps first and says we are trying.
    private func retry(_ attempt: Int, path: String, because reason: String) async -> Bool {
        guard attempt < Self.readAttempts - 1 else { return false }
        #if DEBUG
        print("[LiveAliciaService] \(path) attempt \(attempt + 1) failed: \(reason)")
        #endif
        ConnectionStatus.note(.reaching)
        try? await Task.sleep(for: Self.retryDelays[min(attempt, Self.retryDelays.count - 1)])
        return true
    }

    private func fetch<D: Decodable>(_ path: String, as type: [D].Type) async -> [D]? {
        await fetchOne(path)
    }

    private static func parseDate(_ raw: String) -> Date {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: raw) { return d }
        iso.formatOptions = [.withInternetDateTime]
        if let d = iso.date(from: raw) { return d }
        let day = DateFormatter()
        day.dateFormat = "yyyy-MM-dd"
        day.timeZone = .current
        return day.date(from: raw) ?? .now
    }

    // MARK: chat (SSE)

    func episodeDay(day: String = "") async -> EpisodeDay? {
        let suffix = day.isEmpty ? "" : "?day=" + day
        return await fetchOne("/api/episode_day" + suffix)
    }

    private func post<D: Decodable>(_ path: String, body: [String: Any]) async -> D? {
        do {
            let bytes = try JSONSerialization.data(withJSONObject: body)
            let (data, response) = try await URLSession.shared.data(
                for: request(path, method: "POST", body: bytes))
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            return try JSONDecoder().decode(D.self, from: data)
        } catch { return nil }
    }

    private func voiceRequest<T: Decodable>(_ type: T.Type, path: String, body: Data? = nil,
                                             allowNotFound: Bool = false) async -> VoiceTransport<T> {
        do {
            var req = request(path, method: body == nil ? "GET" : "POST", body: body)
            req.timeoutInterval = 120
            let (data, response) = try await URLSession.shared.data(for: req)
            return decodeVoiceResponse(type, data: data, status: (response as? HTTPURLResponse)?.statusCode ?? 0,
                                       allowNotFound: allowNotFound)
        } catch { return .unavailable }
    }
    func finalizeVoice(_ finalization: VoiceFinalization) async -> VoiceTransport<VoiceProcessingResponse> {
        guard let body = try? JSONEncoder().encode(finalization) else { return .unavailable }
        return await voiceRequest(VoiceProcessingResponse.self, path: "/api/voice_evidence", body: body)
    }
    func retryVoiceTranscription(_ retry: VoiceTranscriptionRetry) async -> VoiceTransport<VoiceProcessingResponse> {
        guard let body = try? JSONEncoder().encode(retry) else { return .unavailable }
        return await voiceRequest(VoiceProcessingResponse.self, path: "/api/voice_evidence", body: body)
    }
    func voiceSubmissionStatus(_ requestID: String) async -> VoiceTransport<VoiceSubmissionStatus> {
        guard UUID(uuidString: requestID) != nil else { return .rejected("Invalid send receipt.") }
        return await voiceRequest(VoiceSubmissionStatus.self, path: "/api/voice_submission?request_id=" + requestID,
                                  allowNotFound: true)
    }
    func submitVoice(_ submission: VoiceSubmission) async -> VoiceTransport<VoiceSubmissionStatus> {
        guard let body = try? JSONSerialization.data(withJSONObject: submission.body) else { return .unavailable }
        if submission.destination == "walk" {
            let result = await voiceRequest(WalkReceipt.self, path: "/api/mode", body: body)
            switch result {
            case .value(let receipt):
                return receipt.ok ? .value(VoiceSubmissionStatus(request_id: submission.requestID, state: "completed"))
                    : .rejected(receipt.message ?? "The walk was not accepted. Your words are kept.")
            case .rejected(let error): return .rejected(error)
            default: return .unavailable
            }
        }
        // Drain the SSE/JSON response without treating a partial token as a saved reply.
        // The durable status endpoint supplies the exact completed public answer.
        do {
            var req = request(submission.destination == "proactive" ? "/api/reply" : "/api/chat", method: "POST", body: body)
            req.timeoutInterval = 180
            let (bytes, response) = try await URLSession.shared.bytes(for: req)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 400 || status == 409 {
                var data = Data()
                for try await byte in bytes { if data.count < 65536 { data.append(byte) } }
                return decodeVoiceResponse(VoiceSubmissionStatus.self, data: data, status: status)
            }
            guard status == 200 else { return .unavailable }
            var streamedReply = VoiceReplyStreamReceipt()
            if submission.destination == "dialogue" {
                for try await line in bytes.lines {
                    if Task.isCancelled { return .unavailable }
                    if streamedReply.receive(line) { break }
                }
            } else {
                for try await _ in bytes { if Task.isCancelled { return .unavailable } }
            }
            let saved = await voiceSubmissionStatus(submission.requestID)
            if case .value(let receipt) = saved, submission.destination == "dialogue", submission.voice {
                return .value(streamedReply.confirmed(receipt, requestID: submission.requestID))
            }
            return saved
        } catch { return .unavailable }
    }

    func voiceReplyURL(_ path: String) -> URL? { mediaURL(path) }

    func episodeAction(_ body: [String: Any]) async -> EpisodeDayResponse? {
        await post("/api/episode_day", body: body)
    }

    func finishWalk(text: String, episodeID: String, requestID: String, prompt: String) async -> WalkReceipt? {
        await finishWalk(text: text, episodeID: episodeID, requestID: requestID, prompt: prompt, recordingID: "")
    }

    func finishWalk(text: String, episodeID: String, requestID: String, prompt: String, recordingID: String) async -> WalkReceipt? {
        await finishWalk(text: text, episodeID: episodeID, requestID: requestID, prompt: prompt,
                         recordingID: recordingID, surface: "")
    }

    func finishWalk(text: String, episodeID: String, requestID: String, prompt: String, recordingID: String, surface: String) async -> WalkReceipt? {
        await post("/api/mode", body: ["action": "end_walk", "text": text,
                                     "episode_id": episodeID, "request_id": requestID, "topic": prompt,
                                     "recording_id": recordingID, "surface": surface])
    }

    func conversationHistory() async -> ConversationHistory? {
        await fetchOne("/api/history")
    }

    func voiceAction(_ body: [String: Any]) async -> VoiceEvidenceResult? {
        await post("/api/voice_evidence", body: body)
    }

    func voiceRecordings(recordingID: String) async -> VoiceEvidencePayload? {
        guard recordingID.isEmpty || UUID(uuidString: recordingID) != nil else { return nil }
        return await fetchOne("/api/voice_evidence" + (recordingID.isEmpty ? "" : "?recording_id=" + recordingID))
    }

    func uploadVoice(recordingID: String, segment: VoiceSegment, file: URL) async -> VoiceEvidenceResult? {
        guard UUID(uuidString: recordingID) != nil, UUID(uuidString: segment.id) != nil else { return nil }
        do {
            var req = request("/api/voice_evidence/audio/" + recordingID + "/" + segment.id, method: "PUT")
            req.setValue("audio/x-caf", forHTTPHeaderField: "Content-Type")
            req.setValue(try JSONEncoder().encode(segment).base64EncodedString(), forHTTPHeaderField: "X-Alicia-Audio")
            req.timeoutInterval = 90
            let (data, response) = try await URLSession.shared.upload(for: req, fromFile: file)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            return try JSONDecoder().decode(VoiceEvidenceResult.self, from: data)
        } catch { return nil }
    }

    func downloadVoice(recordingID: String, segmentID: String) async -> Data? {
        guard UUID(uuidString: recordingID) != nil, UUID(uuidString: segmentID) != nil else { return nil }
        do {
            var req = request("/api/voice_evidence/audio/" + recordingID + "/" + segmentID)
            req.cachePolicy = .reloadIgnoringLocalCacheData
            let (bytes, response) = try await URLSession.shared.data(for: req)
            return (response as? HTTPURLResponse)?.statusCode == 200 ? bytes : nil
        } catch { return nil }
    }

    func collaboration() async -> CollaborationState? { await fetchOne("/api/collaboration") }
    func collaborationAction(_ mutation: CollaborationMutation) async -> CollaborationResponse? {
        do {
            let bytes = try JSONEncoder().encode(mutation)
            let (data, response) = try await URLSession.shared.data(
                for: request("/api/collaboration", method: "POST", body: bytes))
            return CollaborationResponse.decode(data, status: (response as? HTTPURLResponse)?.statusCode)
        } catch { return nil }
    }
    func collaborationSource(connectionID: String, resultID: String, evidenceID: String) async -> ContextSource? {
        var components = URLComponents()
        components.queryItems = [URLQueryItem(name: resultID.isEmpty ? "connection_id" : "result_id", value: resultID.isEmpty ? connectionID : resultID), URLQueryItem(name: "evidence_id", value: evidenceID)]
        guard let query = components.percentEncodedQuery else { return nil }
        return await fetchOne("/api/collaboration/source?" + query)
    }

    func contextEnrichment(replyID: String) async -> ContextEnrichment? {
        guard replyID.isEmpty || UUID(uuidString: replyID) != nil else { return nil }
        return await fetchOne("/api/context_enrichment?reply_id=" + replyID)
    }

    func changeContext(_ change: ContextChange) async -> ContextChangeResult? {
        await post("/api/context_enrichment", body: change.body)
    }

    func contextSource(replyID: String, itemID: String) async -> ContextSource? {
        guard UUID(uuidString: replyID) != nil,
              let encoded = itemID.addingPercentEncoding(withAllowedCharacters: .alphanumerics) else { return nil }
        return await fetchOne("/api/context_enrichment?reply_id=" + replyID + "&item_id=" + encoded)
    }

    func dialogueReview(replyID: String) async -> DialogueReview? {
        guard UUID(uuidString: replyID) != nil else { return nil }
        return await fetchOne("/api/dialogue_review?reply_id=" + replyID)
    }

    func dialogueReviewAction(_ mutation: DialogueMutation) async -> DialogueMutationResult? {
        await post("/api/dialogue_review", body: mutation.body)
    }

    func stream(_ prompt: String, voice: Bool) -> AsyncStream<ChatEvent> {
        stream(prompt, voice: voice, recordingID: "")
    }

    func stream(_ prompt: String, voice: Bool, recordingID: String) -> AsyncStream<ChatEvent> {
        stream(prompt, voice: voice, recordingID: recordingID, workContext: nil)
    }

    func stream(_ prompt: String, voice: Bool, recordingID: String, workContext: WorkDialogueContext?) -> AsyncStream<ChatEvent> {
        stream(prompt, voice: voice, recordingID: recordingID, workContext: workContext, surfaceContext: nil)
    }

    func stream(_ prompt: String, voice: Bool, recordingID: String, workContext: WorkDialogueContext?, surfaceContext: SurfaceContext?) -> AsyncStream<ChatEvent> {
        AsyncStream { continuation in
            let task = Task {
                do {
                    var payload: [String: Any] = ["text": prompt, "voice": voice, "recording_id": recordingID]
                    if let workContext { payload["work_context"] = workContext.wire }
                    if let surfaceContext { payload["surface_context"] = surfaceContext.wire }
                    let body = try JSONSerialization.data(withJSONObject: payload)
                    let (bytes, resp) = try await URLSession.shared.bytes(
                        for: request("/api/chat", method: "POST", body: body))
                    guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
                        continuation.yield(.token(workContext != nil && (resp as? HTTPURLResponse)?.statusCode == 400
                            ? "This passage could not be confirmed. Your message was not sent to a model. Open the current work in Together, then try again."
                            : "(Alicia is unreachable right now — check the backend and your connection.)"))
                        continuation.yield(.done(messageID: nil))
                        continuation.finish()
                        return
                    }
                    var finished = false
                    for try await line in bytes.lines {
                        guard line.hasPrefix("data: "),
                              let data = line.dropFirst(6).data(using: .utf8),
                              let event = try? JSONDecoder().decode(WireEvent.self, from: data)
                        else { continue }
                        if let t = event.t { continuation.yield(.token(t)) }
                        if let id = event.reply_id { continuation.yield(.details(id)) }
                        if let v = event.voice, let url = mediaURL(v) {
                            continuation.yield(.voice(url))
                        }
                        if let err = event.error, !err.isEmpty {
                            continuation.yield(.token("\n(connection hiccup: \(err))"))
                        }
                        if event.done == true {
                            continuation.yield(.done(messageID: event.message_id))
                            finished = true
                            break
                        }
                    }
                    if !finished { continuation.yield(.done(messageID: nil)) }
                } catch {
                    continuation.yield(.token("(Alicia is unreachable right now — check the backend and your connection.)"))
                    continuation.yield(.done(messageID: nil))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private struct WireEvent: Decodable {
        var t: String?
        var voice: String?
        var done: Bool?
        var message_id: Int?
        var reply_id: String?
        var error: String?
    }

    // MARK: reactions + proactive feed

    func react(messageID: Int, emoji: String) async {
        guard let body = try? JSONSerialization.data(
            withJSONObject: ["message_id": messageID, "emoji": emoji]) else { return }
        _ = try? await URLSession.shared.data(
            for: request("/api/react", method: "POST", body: body))
    }

    func recordEvents(_ events: [[String: Any]]) async {
        guard !events.isEmpty,
              let body = try? JSONSerialization.data(
                withJSONObject: ["events": events]) else { return }
        _ = try? await URLSession.shared.data(
            for: request("/api/events", method: "POST", body: body))
    }

    private struct MindNoteDTO: Decodable {
        var text: String
        var has_note: Bool
    }

    func mindNote() async -> String {
        guard let dto: MindNoteDTO = await fetchOne("/api/mind") else { return "" }
        return dto.has_note ? dto.text : ""
    }

    func react(proactiveID: String, emoji: String) async {
        guard let body = try? JSONSerialization.data(
            withJSONObject: ["proactive_id": proactiveID, "emoji": emoji]) else { return }
        _ = try? await URLSession.shared.data(
            for: request("/api/react", method: "POST", body: body))
    }

    private struct ProactiveDTO: Decodable {
        var id, date, text, kind, archetype: String
        var is_ask: Bool?
    }

    func proactive(limit: Int) async -> [ProactiveMessage] {
        (await fetch("/api/proactive?limit=\(limit)", as: [ProactiveDTO].self) ?? []).map {
            ProactiveMessage(id: $0.id, text: $0.text, kind: $0.kind,
                             archetype: $0.archetype,
                             date: Self.parseDate($0.date),
                             isAsk: $0.is_ask ?? false)
        }
    }

    // MARK: tab data

    private struct ThoughtDTO: Decodable { var title, body, tag, date: String }

    func thoughts() async -> [Thought]? {
        (await fetch("/api/thoughts", as: [ThoughtDTO].self))?.map {
            Thought(title: $0.title, body: $0.body, tag: $0.tag,
                    date: Self.parseDate($0.date))
        }
    }

    // Note: `collection` groups Studio's shelf (see Models.Track).
    private struct TrackDTO: Decodable {
        var title, mood, symbol: String
        var duration: Double
        var fileName: String?
        var season: Int?
        var episode: Int?
        var label: String?
        var series: String?
        var collection: String?
        var collectionTitle: String?
    }

    func tracks() async -> [Track]? {
        (await fetch("/api/tracks", as: [TrackDTO].self))?.map {
            Track(title: $0.title, mood: $0.mood, duration: $0.duration,
                  symbol: $0.symbol,
                  fileName: $0.fileName.flatMap { mediaURL($0)?.absoluteString },
                  season: $0.season ?? 0,
                  episode: $0.episode ?? 0,
                  label: $0.label,
                  series: $0.series ?? "",
                  collection: $0.collection ?? "S\($0.season ?? 0)",
                  collectionTitle: $0.collectionTitle
                      ?? "Season \($0.season ?? 0)")
        }
    }

    private struct NotesDTO: Decodable { var label, markdown: String }

    func episodeNotes(label: String) async -> String {
        do {
            let (data, resp) = try await URLSession.shared.data(
                for: request("/api/episode/\(label)"))
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else { return "" }
            return try JSONDecoder().decode(NotesDTO.self, from: data).markdown
        } catch { return "" }
    }

    private struct ModeDTO: Decodable { var mode: String; var words: Int }

    func modeState() async -> (mode: String, words: Int) {
        do {
            let (data, resp) = try await URLSession.shared.data(
                for: request("/api/mode"))
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else { return ("idle", 0) }
            let m = try JSONDecoder().decode(ModeDTO.self, from: data)
            return (m.mode, m.words)
        } catch { return ("idle", 0) }
    }

    private struct ModeActionDTO: Decodable { var ok: Bool; var message: String? }

    func modeAction(_ action: String, topic: String) async -> String? {
        do {
            var payload: [String: Any] = ["action": action]
            if !topic.isEmpty { payload["topic"] = topic }
            let body = try JSONSerialization.data(withJSONObject: payload)
            let (data, resp) = try await URLSession.shared.data(
                for: request("/api/mode", method: "POST", body: body))
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            let receipt = try JSONDecoder().decode(ModeActionDTO.self, from: data)
            return receipt.ok ? receipt.message : nil
        } catch { return nil }
    }

    private struct ReplyDTO: Decodable { var ok: Bool; var response: String? }

    func reply(proactiveID: String, text: String) async -> String? {
        await reply(proactiveID: proactiveID, text: text, recordingID: "", episodeID: "")
    }

    func reply(proactiveID: String, text: String, recordingID: String, episodeID: String) async -> String? {
        do {
            let body = try JSONSerialization.data(
                withJSONObject: ["proactive_id": proactiveID, "text": text, "recording_id": recordingID, "episode_id": episodeID])
            let (data, resp) = try await URLSession.shared.data(
                for: request("/api/reply", method: "POST", body: body))
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            let r = try JSONDecoder().decode(ReplyDTO.self, from: data)
            return r.ok ? r.response : nil
        } catch { return nil }
    }

    private struct CocreateDTO: Decodable { var imageURL: String; var caption: String }

    func cocreate(image: Data, width: Int, height: Int,
                  anchor: CGPoint?) async -> (overlay: URL, caption: String)? {
        do {
            var payload: [String: Any] = [
                "image": image.base64EncodedString(),
                "width": width, "height": height,
            ]
            if let anchor {
                payload["anchor_x"] = Double(anchor.x)
                payload["anchor_y"] = Double(anchor.y)
            }
            let body = try JSONSerialization.data(withJSONObject: payload)
            var req = request("/api/cocreate", method: "POST", body: body)
            req.timeoutInterval = 120   // vision + render can take a while
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            let r = try JSONDecoder().decode(CocreateDTO.self, from: data)
            guard let url = mediaURL(r.imageURL) else { return nil }
            return (url, r.caption)
        } catch { return nil }
    }

    func archetypes() async -> [ArchetypeStat] {
        await fetch("/api/archetypes", as: [ArchetypeStat].self) ?? []
    }

    func knowing() async -> KnowingState? {
        await fetchOne("/api/knowing")
    }

    private struct SynthesisDTO: Decodable {
        var title, date, excerpt, body: String
        var speech: SpeechDTO?
    }

    func syntheses() async -> [FeaturedSynthesis] {
        (await fetch("/api/syntheses", as: [SynthesisDTO].self) ?? []).map {
            FeaturedSynthesis(title: $0.title, excerpt: $0.excerpt,
                              body: $0.body, date: $0.date,
                              speechChunks: speechChunks($0.speech?.chunks, spokenText: $0.speech?.spoken_text, timingStatus: $0.speech?.timing_status),
                              speechDuration: $0.speech?.duration ?? 0)
        }
    }

    func thinkers() async -> ThinkerNetwork? {
        await fetchOne("/api/thinkers")
    }

    func timeline() async -> [TimelineDay] {
        await fetch("/api/timeline", as: [TimelineDay].self) ?? []
    }

    // MARK: home context (the Us tab's loops)

    private struct HomeDTO: Decodable {
        struct EpisodeDTO: Decodable {
            var episode: Int?
            var label, title, claim: String?
            var heard, is_today: Bool?
        }
        struct MovementDTO: Decodable {
            var numeral, title, summary: String?
            var from_episode, to_episode: Int?
        }
        struct SeasonDTO: Decodable {
            var season, heard_count, total: Int?
            var series, title, subtitle, premise, movement_now: String?
            var movements: [MovementDTO]?
            var episodes: [EpisodeDTO]?
        }
        struct TrailDTO: Decodable {
            var label, title, picked_date, claim: String?
            var days_ago: Int?
        }
        struct TodayDTO: Decodable {
            var label, title, picked_date, focus, claim, about, quote: String?
            var is_today: Bool?
        }
        struct CardDTO: Decodable {
            var id, kind, title, body, thinker, tagline, source, badge: String?
            var themes: [String]?
        }
        struct PinnedDTO: Decodable {
            var id, kind, title, body, thinker, source: String?
        }
        var season: SeasonDTO?
        var trail: [TrailDTO]?
        var today: TodayDTO?
        var cards: [CardDTO]?
        var pinned: [PinnedDTO]?
        var context_line: String?
    }

    func homeContext() async -> HomeContext? {
        guard let d: HomeDTO = await fetchOne("/api/home") else { return nil }
        // A failing /api/home returns `{}`, which decodes as a HomeDTO
        // with every field nil — a "successful" fetch of nothing that
        // would clobber good data in the store. No season, no today,
        // no trail, no cards ⇒ treat it as a failed fetch.
        if d.season == nil, d.today == nil,
           (d.trail ?? []).isEmpty, (d.cards ?? []).isEmpty {
            return nil
        }
        let season: HomeContext.Season? = d.season.flatMap { s in
            guard let n = s.season, n > 0 else { return nil }
            return HomeContext.Season(
                season: n, series: s.series ?? "", title: s.title ?? "",
                subtitle: s.subtitle ?? "", premise: s.premise ?? "",
                movements: (s.movements ?? []).map {
                    .init(numeral: $0.numeral ?? "", title: $0.title ?? "",
                          fromEpisode: $0.from_episode ?? 0,
                          toEpisode: $0.to_episode ?? 0,
                          summary: $0.summary ?? "")
                },
                movementNow: s.movement_now ?? "",
                episodes: (s.episodes ?? []).map {
                    .init(episode: $0.episode ?? 0, label: $0.label ?? "",
                          title: $0.title ?? "", claim: $0.claim ?? "",
                          heard: $0.heard ?? false,
                          isToday: $0.is_today ?? false)
                },
                heardCount: s.heard_count ?? 0, total: s.total ?? 0)
        }
        let today: HomeContext.Today? = d.today.flatMap { t in
            guard let label = t.label, !label.isEmpty else { return nil }
            return HomeContext.Today(
                label: label, title: t.title ?? "",
                pickedDate: t.picked_date ?? "",
                isToday: t.is_today ?? false,
                focus: t.focus ?? "", claim: t.claim ?? "",
                about: t.about ?? "", quote: t.quote ?? "")
        }
        return HomeContext(
            season: season,
            trail: (d.trail ?? []).compactMap { t in
                guard let label = t.label else { return nil }
                return HomeContext.TrailItem(
                    label: label, title: t.title ?? "",
                    pickedDate: t.picked_date ?? "",
                    daysAgo: t.days_ago, claim: t.claim ?? "")
            },
            today: today,
            cards: (d.cards ?? []).compactMap { c in
                guard let id = c.id, let kind = c.kind else { return nil }
                return HomeContext.Card(
                    id: id, kind: kind, title: c.title ?? "",
                    body: c.body ?? "", thinker: c.thinker ?? "",
                    tagline: c.tagline ?? "", themes: c.themes ?? [],
                    source: c.source ?? "", badge: c.badge ?? "")
            },
            pinned: (d.pinned ?? []).compactMap { p in
                guard let id = p.id else { return nil }
                return HomeContext.Card(
                    id: id, kind: p.kind ?? "note", title: p.title ?? "",
                    body: p.body ?? "", thinker: p.thinker ?? "",
                    tagline: "", themes: [],
                    source: p.source ?? "", badge: "held")
            },
            contextLine: d.context_line ?? "")
    }

    private struct PinDTO: Decodable { var ok: Bool }

    func pin(action: String, id: String, kind: String, title: String,
             body: String, thinker: String, source: String) async -> Bool {
        do {
            let payload: [String: Any] = [
                "action": action, "id": id, "kind": kind, "title": title,
                "body": body, "thinker": thinker, "source": source,
            ]
            let data = try JSONSerialization.data(withJSONObject: payload)
            let (resp, http) = try await URLSession.shared.data(
                for: request("/api/pin", method: "POST", body: data))
            guard (http as? HTTPURLResponse)?.statusCode == 200 else { return false }
            return try JSONDecoder().decode(PinDTO.self, from: resp).ok
        } catch { return false }
    }

    private struct CardFeedbackDTO: Decodable { var ok: Bool }

    func cardFeedback(cardID: String, kind: String, verdict: String,
                      note: String) async -> Bool {
        do {
            var payload: [String: Any] = [
                "card_id": cardID, "kind": kind, "verdict": verdict,
            ]
            if !note.isEmpty { payload["note"] = note }
            let body = try JSONSerialization.data(withJSONObject: payload)
            let (data, resp) = try await URLSession.shared.data(
                for: request("/api/card_feedback", method: "POST", body: body))
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else { return false }
            return try JSONDecoder().decode(CardFeedbackDTO.self, from: data).ok
        } catch { return false }
    }

    private struct QuoteDTO: Decodable { var text: String; var author: String }

    func quote() async -> (text: String, author: String)? {
        guard let q: QuoteDTO = await fetchOne("/api/quote") else { return nil }
        return q.text.isEmpty ? nil : (q.text, q.author)
    }

    /// A reading the backend already rendered ({} when it hasn't — the
    /// payload builders look in the cache but never start a render, and
    /// advertise only COMPLETE readings).
    private struct ChunkDTO: Decodable {
        var url: String?
        var duration: Double?
        var text: String?
        var cues: [NarrationCue]?
        var timing_status: String?
        var speech_backend: String?
    }

    private struct SpeechDTO: Decodable {
        var spoken_text: String?
        var timing_status: String?
        var chunks: [ChunkDTO]?
        var duration: Double?
    }

    private struct FeaturedDTO: Decodable {
        var title, excerpt, body, date: String
        var speech: SpeechDTO?
    }

    func featured() async -> FeaturedSynthesis? {
        guard let f: FeaturedDTO = await fetchOne("/api/featured") else { return nil }
        return FeaturedSynthesis(title: f.title, excerpt: f.excerpt,
                                 body: f.body, date: f.date,
                                 speechChunks: speechChunks(f.speech?.chunks, spokenText: f.speech?.spoken_text, timingStatus: f.speech?.timing_status),
                                 speechDuration: f.speech?.duration ?? 0)
    }

    // MARK: playlists

    func morningBriefing() async -> MorningBriefing? {
        guard var briefing: MorningBriefing = await fetchOne("/api/morning_briefing") else { return nil }
        if !briefing.audio_url.isEmpty { briefing.audio_url = mediaURL(briefing.audio_url)?.absoluteString ?? "" }
        briefing.speechChunks = (briefing.speech?.chunks ?? []).compactMap { chunk in
            guard let url = mediaURL(chunk.url) else { return nil }
            return SpeechChunk(url: url, duration: chunk.duration ?? 0, text: chunk.text ?? "",
                cues: chunk.cues ?? [], timingStatus: chunk.timing_status ?? briefing.speech?.timing_status ?? "unavailable",
                spokenText: briefing.speech?.spoken_text ?? "", speechBackend: chunk.speech_backend ?? briefing.speech?.speech_backend ?? "")
        }
        return briefing
    }

    private struct PlaylistDTO: Decodable {
        struct ItemDTO: Decodable {
            var id, kind, title: String?
            var body, source: String?
            var duration: Double?
            var speech: SpeechDTO?
        }
        var id, name: String?
        var items: [ItemDTO]?
        var duration: Double?
        var ready: Int?
    }

    private func playlist(from dto: PlaylistDTO) -> Playlist {
        Playlist(
            id: dto.id ?? "",
            name: dto.name ?? "Untitled",
            items: (dto.items ?? []).map { i in
                Playlist.Item(id: i.id ?? "",
                              kind: i.kind ?? "synthesis",
                              title: i.title ?? "",
                              body: i.body ?? "",
                              source: i.source ?? "",
                              duration: i.duration ?? 0,
                              speechChunks: speechChunks(i.speech?.chunks, spokenText: i.speech?.spoken_text, timingStatus: i.speech?.timing_status))
            },
            duration: dto.duration ?? 0,
            ready: dto.ready ?? 0)
    }

    func playlists() async -> [Playlist] {
        (await fetch("/api/playlists", as: [PlaylistDTO].self) ?? []).map(playlist(from:))
    }

    private struct PlaylistActionDTO: Decodable {
        var ok: Bool
        var error: String?
        var playlists: [PlaylistDTO]?
    }

    func playlistAction(_ action: String, body: [String: Any]) async -> [Playlist]? {
        do {
            var payload = body
            payload["action"] = action
            let data = try JSONSerialization.data(withJSONObject: payload)
            let (resp, http) = try await URLSession.shared.data(
                for: request("/api/playlist", method: "POST", body: data))
            guard (http as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            let dto = try JSONDecoder().decode(PlaylistActionDTO.self, from: resp)
            guard dto.ok else {
                #if DEBUG
                print("[LiveAliciaService] playlist \(action) refused: \(dto.error ?? "")")
                #endif
                return nil
            }
            return (dto.playlists ?? []).map(playlist(from:))
        } catch {
            return nil
        }
    }

    // MARK: read aloud

    private struct SpeakDTO: Decodable {
        var spoken_text: String?
        var timing_status: String?
        var speech_backend: String?
        var status: String
        var chunks: [ChunkDTO]?
        var duration: Double?
    }

    private func speechChunks(_ dtos: [ChunkDTO]?, spokenText: String? = nil, timingStatus: String? = nil) -> [SpeechChunk] {
        (dtos ?? []).compactMap { c in
            guard let url = mediaURL(c.url ?? "") else { return nil }
            return SpeechChunk(url: url, duration: c.duration ?? 0, text: c.text ?? "",
                cues: c.cues ?? [], timingStatus: c.timing_status ?? timingStatus ?? "unavailable", spokenText: spokenText ?? "", speechBackend: c.speech_backend ?? "")
        }
    }

    // MARK: - Shared context (the Us orbit)

    private struct MomentDTO: Decodable {
        var id: String?; var date: String?; var channel: String?; var text: String?
    }
    private struct ContextNodeDTO: Decodable {
        var id: String?; var label: String?; var salience: Double?
        var horizon: String?; var recurring: Bool?; var mentions: Int?
        var first_seen: String?; var last_seen: String?; var days_since: Int?
        var channels: [String: Int]?; var examples: [MomentDTO]?
    }
    // MARK: Context graph — CL-20260918-context-graph-behaviours
    // Every DTO field is optional on purpose: an older backend, or a node
    // with a missing key, must never take the whole graph down.
    private struct GraphReceiptDTO: Decodable { var source, ref, observed_at, excerpt: String? }
    private struct GraphNodeDTO: Decodable {
        var id, kind, title, status, summary, body, updated, superseded_by: String?
        var importance, worth_hits, worth_misses: Int?
        var needs_review: Bool?
        var themes, links, related, why: [String]?
        var receipts: [GraphReceiptDTO]?
    }
    private struct ContextGraphDTO: Decodable {
        struct Manifest: Decodable { var nodes, needs_review: Int? }
        var generated_at, notice: String?
        var nodes, core: [GraphNodeDTO]?
        var manifest: Manifest?
    }
    private struct GraphNodeDetailDTO: Decodable {
        var id, kind, title, status, summary, body, updated, superseded_by: String?
        var importance, worth_hits, worth_misses: Int?
        var needs_review: Bool?
        var themes, links, related, why: [String]?
        var receipts: [GraphReceiptDTO]?
        var related_nodes: [GraphNodeDTO]?
    }
    private struct ContextElevationDTO: Decodable {
        struct Item: Decodable {
            struct Evidence: Decodable { var source, ref, excerpt: String? }
            var kind, title, why, node_id, node_title, node_kind, episode_id: String?
            var score: Double?
            var evidence: Evidence?
        }
        struct Episode: Decodable { var id: String? }
        var generated_at, status, reason, notice: String?
        var refused: Bool?
        var items: [Item]?
        var episode: Episode?
    }
    private struct ContextTranslationDTO: Decodable {
        var refused: Bool?
        var reason, title, why, passage_excerpt, node_excerpt: String?
        var node: GraphNodeDTO?
        var shared_terms: [String]?
    }
    private struct ContextGraphMutationDTO: Decodable {
        var ok: Bool?
        var node: GraphNodeDTO?
        var error: String?
        var updated: Int?
    }

    private func contextNode(_ d: GraphNodeDTO) -> ContextNode? {
        guard let id = d.id, let title = d.title, !title.isEmpty else { return nil }
        return ContextNode(id: id, kind: d.kind ?? "situation", title: title, status: d.status ?? "inferred",
                           summary: d.summary ?? "", body: d.body ?? d.summary ?? "", updated: String((d.updated ?? "").prefix(10)),
                           importance: d.importance ?? 5, needs_review: d.needs_review ?? (d.status == "inferred"),
                           themes: d.themes ?? [], links: d.links ?? [], related: d.related ?? [],
                           receipts: (d.receipts ?? []).map { .init(source: $0.source ?? "", ref: $0.ref ?? "", observed_at: $0.observed_at ?? "", excerpt: $0.excerpt ?? "") },
                           worth_hits: d.worth_hits ?? 0, worth_misses: d.worth_misses ?? 0,
                           superseded_by: d.superseded_by ?? "", why: d.why ?? [])
    }

    func contextGraph() async -> ContextGraph? {
        guard let d: ContextGraphDTO = await fetchOne("/api/context_graph") else { return nil }
        let nodes = (d.nodes ?? []).compactMap(contextNode)
        let core = (d.core ?? []).compactMap(contextNode)
        // {} from a failing backend must not wipe the last good graph.
        if nodes.isEmpty && core.isEmpty && d.manifest == nil { return nil }
        return ContextGraph(generatedAt: d.generated_at ?? "", nodes: nodes, core: core,
                            notice: d.notice ?? "", needsReview: d.manifest?.needs_review ?? 0,
                            total: d.manifest?.nodes ?? nodes.count)
    }

    func contextNode(id: String) async -> (node: ContextNode, related: [ContextNode])? {
        guard id.range(of: "^ctx-[0-9a-f]{12}$", options: .regularExpression) != nil,
              let d: GraphNodeDetailDTO = await fetchOne("/api/context_graph/" + id) else { return nil }
        let base = GraphNodeDTO(id: d.id, kind: d.kind, title: d.title, status: d.status, summary: d.summary, body: d.body,
                                  updated: d.updated, superseded_by: d.superseded_by, importance: d.importance,
                                  worth_hits: d.worth_hits, worth_misses: d.worth_misses, needs_review: d.needs_review,
                                  themes: d.themes, links: d.links, related: d.related, why: d.why, receipts: d.receipts)
        guard let node = contextNode(base) else { return nil }
        return (node, (d.related_nodes ?? []).compactMap(contextNode))
    }

    func contextGraphAct(_ mutation: ContextGraphMutation) async -> ContextGraphMutationResult? {
        guard let d: ContextGraphMutationDTO = await post("/api/context_graph", body: mutation.body) else { return nil }
        return ContextGraphMutationResult(ok: d.ok ?? false, node: d.node.flatMap(contextNode), error: d.error, updated: d.updated)
    }

    func contextElevation() async -> ContextElevation? {
        guard let d: ContextElevationDTO = await fetchOne("/api/context_graph/elevate") else { return nil }
        let items: [ContextElevation.Item] = (d.items ?? []).compactMap { i in
            guard let kind = i.kind, let title = i.title, !title.isEmpty else { return nil }
            return .init(kind: kind, title: title, why: i.why ?? "", score: i.score ?? 0,
                         node_id: i.node_id ?? "", node_title: i.node_title ?? "", node_kind: i.node_kind ?? "",
                         evidence: .init(source: i.evidence?.source ?? "", ref: i.evidence?.ref ?? "", excerpt: i.evidence?.excerpt ?? ""),
                         episode_id: i.episode_id ?? "")
        }
        return ContextElevation(generatedAt: d.generated_at ?? "", status: d.status ?? "ready", reason: d.reason ?? "",
                                notice: d.notice ?? "", refused: d.refused ?? items.isEmpty, items: items,
                                episodeID: d.episode?.id ?? "")
    }

    func contextTranslate(title: String) async -> ContextTranslation? {
        guard let encoded = title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let d: ContextTranslationDTO = await fetchOne("/api/context_graph/translate?title=" + encoded) else { return nil }
        return ContextTranslation(refused: d.refused ?? true, reason: d.reason ?? "", title: d.title ?? title, why: d.why ?? "",
                                  passageExcerpt: d.passage_excerpt ?? "", nodeExcerpt: d.node_excerpt ?? "",
                                  node: d.node.flatMap(contextNode), sharedTerms: d.shared_terms ?? [])
    }

    private struct ContextArrangementDTO: Decodable {
        struct Item: Decodable {
            struct Evidence: Decodable { var source, ref, excerpt: String? }
            var kind, title, why, ref, node_id, node_title, node_kind, date: String?
            var score: Double?
            var evidence: Evidence?
        }
        struct NodeRef: Decodable { var id, kind, title, status, summary, updated: String?; var needs_review: Bool? }
        struct Group: Decodable { var node: NodeRef?; var items: [Item]?; var arranged: Bool? }
        struct Episode: Decodable { var id: String? }
        var generated_at, status, reason, notice, date: String?
        var refused: Bool?
        var groups: [Group]?
        var arranged_count: Int?
        var episode: Episode?
    }

    func contextArrangement() async -> ContextArrangement? {
        guard let d: ContextArrangementDTO = await fetchOne("/api/context_graph/arrangement") else { return nil }
        let groups: [ContextArrangement.Group] = (d.groups ?? []).compactMap { g in
            guard let n = g.node, let id = n.id, let title = n.title, !title.isEmpty else { return nil }
            let items: [ContextArrangement.Item] = (g.items ?? []).compactMap { i in
                guard let kind = i.kind, let t = i.title, !t.isEmpty else { return nil }
                return .init(kind: kind, title: t, why: i.why ?? "", ref: i.ref ?? "", score: i.score ?? 0,
                             node_id: i.node_id ?? id, node_title: i.node_title ?? title, node_kind: i.node_kind ?? (n.kind ?? ""),
                             evidence: .init(source: i.evidence?.source ?? "", ref: i.evidence?.ref ?? "", excerpt: i.evidence?.excerpt ?? ""),
                             date: i.date ?? "")
            }
            return .init(node: .init(id: id, kind: n.kind ?? "situation", title: title, status: n.status ?? "inferred",
                                     summary: n.summary ?? "", updated: String((n.updated ?? "").prefix(10)),
                                     needs_review: n.needs_review ?? (n.status == "inferred")),
                         items: items, arranged: g.arranged ?? !items.isEmpty)
        }
        return ContextArrangement(generatedAt: d.generated_at ?? "", status: d.status ?? "ready", reason: d.reason ?? "",
                                  notice: d.notice ?? "", date: d.date ?? "", episodeID: d.episode?.id ?? "",
                                  refused: d.refused ?? groups.allSatisfy { !$0.arranged }, groups: groups,
                                  arrangedCount: d.arranged_count ?? groups.reduce(0) { $0 + $1.items.count })
    }

    private struct ContextDTO: Decodable {
        var nodes: [ContextNodeDTO]?; var message_count: Int?; var generated_at: String?
    }

    private func moments(_ dtos: [MomentDTO]?) -> [SharedContext.Moment] {
        (dtos ?? []).compactMap { m in
            guard let text = m.text, !text.isEmpty else { return nil }
            return .init(id: m.id ?? UUID().uuidString, date: m.date ?? "",
                         channel: m.channel ?? "telegram", text: text)
        }
    }

    func sharedContext() async -> SharedContext? {
        guard let d: ContextDTO = await fetchOne("/api/context") else { return nil }
        // A failing /api/context returns {} — a "successful" fetch of nothing
        // that would wipe a populated orbit. No nodes ⇒ treat as failed, the
        // same keep-last-known rule /api/home follows.
        let raw = d.nodes ?? []
        if raw.isEmpty { return nil }
        let nodes: [SharedContext.Node] = raw.compactMap { n in
            guard let id = n.id, let label = n.label, !label.isEmpty else { return nil }
            return .init(id: id, label: label,
                         salience: min(max(n.salience ?? 0, 0), 1),
                         horizon: n.horizon ?? "long",
                         recurring: n.recurring ?? false,
                         mentions: n.mentions ?? 0,
                         firstSeen: n.first_seen ?? "", lastSeen: n.last_seen ?? "",
                         daysSince: n.days_since ?? 0,
                         channels: n.channels ?? [:],
                         moments: moments(n.examples))
        }
        if nodes.isEmpty { return nil }
        return SharedContext(nodes: nodes, messageCount: d.message_count ?? 0,
                             generatedAt: d.generated_at ?? "")
    }

    // MARK: - Her self-reflections

    /// Every field optional on purpose. SpeakDTO.status is non-optional, so
    /// a `"speech": {}` from an older backend would throw and take the whole
    /// reflections list down with it — one missing reading must not cost the
    /// journal.
    private struct ReflectionSpeechDTO: Decodable {
        var spoken_text: String?
        var timing_status: String?
        var status: String?; var chunks: [ChunkDTO]?; var duration: Double?
    }
    private struct ReflectionDTO: Decodable {
        var id: String?; var kind: String?; var date: String?; var text: String?
        var speech: ReflectionSpeechDTO?
    }

    func reflections() async -> [Reflection]? {
        guard let rows: [ReflectionDTO] = await fetchOne("/api/reflections") else {
            return nil
        }
        return rows.compactMap { r in
            guard let text = r.text, !text.isEmpty else { return nil }
            var status: SpeechStatus?
            // The backend only advertises COMPLETE readings here, so anything
            // present is playable start to finish; a tap falls back to
            // /api/speak when it is not.
            if let sp = r.speech, sp.status == "ready" {
                let chunks = speechChunks(sp.chunks, spokenText: sp.spoken_text, timingStatus: sp.timing_status)
                if !chunks.isEmpty {
                    status = .ready(chunks: chunks, duration: sp.duration ?? 0)
                }
            }
            return Reflection(id: r.id ?? UUID().uuidString,
                              kind: r.kind ?? "evening", date: r.date ?? "",
                              text: text, speech: status)
        }
    }

    func requestSpeech(text: String, kind: String) async -> SpeechStatus {
        do {
            let body = try JSONSerialization.data(
                withJSONObject: ["text": text, "kind": kind, "required_backend": "gemini"])
            let (data, resp) = try await URLSession.shared.data(
                for: request("/api/speak", method: "POST", body: body))
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
                return .unavailable
            }
            let dto = try JSONDecoder().decode(SpeakDTO.self, from: data)
            let chunks = speechChunks(dto.chunks).map { chunk in
                var copy = chunk
                copy.spokenText = dto.spoken_text ?? ""
                if copy.timingStatus == "unavailable" { copy.timingStatus = dto.timing_status ?? "unavailable" }
                if copy.speechBackend.isEmpty { copy.speechBackend = dto.speech_backend ?? "" }
                return copy
            }
            switch dto.status {
            case "ready":
                guard !chunks.isEmpty else { return .failed }
                return .ready(chunks: chunks, duration: dto.duration ?? 0)
            case "streaming":
                guard !chunks.isEmpty else { return .rendering }
                return .streaming(chunks: chunks, duration: dto.duration ?? 0)
            case "rendering":
                return .rendering
            default:
                // "failed" (every TTS backend fell over) and "empty"
                // (nothing speakable after cleaning) both end the poll.
                return .failed
            }
        } catch {
            return .unavailable
        }
    }

    func episodeReading(episodeID: String, prepare: Bool) async -> SpeechStatus {
        do {
            let body = prepare ? try JSONSerialization.data(withJSONObject: ["episode_id": episodeID]) : nil
            let escaped = episodeID.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            let path = prepare ? "/api/episode_reading" : "/api/episode_reading?episode_id=" + escaped
            let (data, response) = try await URLSession.shared.data(for: request(path, method: prepare ? "POST" : "GET", body: body))
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return .unavailable }
            let dto = try JSONDecoder().decode(SpeakDTO.self, from: data)
            if dto.status == "rendering" || dto.status == "pending" { return .rendering }
            guard dto.status == "ready", let text = dto.spoken_text, !text.isEmpty else { return .failed }
            let chunks = speechChunks(dto.chunks).map { chunk in
                var copy = chunk; copy.spokenText = text
                copy.timingStatus = dto.timing_status ?? copy.timingStatus
                copy.speechBackend = dto.speech_backend ?? "prerecorded"
                return copy
            }
            guard !chunks.isEmpty else { return .failed }
            return .ready(chunks: chunks, duration: dto.duration ?? 0)
        } catch { return .unavailable }
    }

    private struct GreetingDTO: Decodable { var greeting: String }

    func greeting() async -> String? {
        guard let g: GreetingDTO = await fetchOne("/api/greeting") else { return nil }
        return g.greeting.isEmpty ? nil : g.greeting
    }

    private struct ArtworkDTO: Decodable {
        var title, note, symbol, author: String
        var imageURL: String?
    }

    private func artwork(from dto: ArtworkDTO) -> Artwork {
        Artwork(title: dto.title, note: dto.note, symbol: dto.symbol,
                author: dto.author == "alicia" ? .alicia : .me,
                imageURL: dto.imageURL.flatMap { mediaURL($0) })
    }

    func gallery() async -> [Artwork]? {
        (await fetch("/api/gallery", as: [ArtworkDTO].self))?.map(artwork(from:))
    }

    private struct MetricDTO: Decodable {
        var name, display, symbol: String
        var value, hue: Double
        var assessable: Bool?      // absent on payloads before 2026-08-30
    }

    func health() async -> [HealthMetric]? {
        (await fetch("/api/health", as: [MetricDTO].self))?.map {
            HealthMetric(name: $0.name, value: $0.value, display: $0.display,
                         symbol: $0.symbol, hue: $0.hue,
                         assessable: $0.assessable ?? true)
        }
    }

    // MARK: complement

    func complement(_ title: String, imageData: Data?) async -> Artwork {
        do {
            var payload: [String: Any] = ["title": title]
            if let imageData {
                payload["image"] = imageData.base64EncodedString()
            }
            let body = try JSONSerialization.data(withJSONObject: payload)
            var req = request("/api/complement", method: "POST", body: body)
            req.timeoutInterval = 120   // vision pass + render take a while
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }
            return artwork(from: try JSONDecoder().decode(ArtworkDTO.self, from: data))
        } catch {
            return Artwork(title: "Reply to “\(title)”",
                           note: "couldn't reach Alicia — try again",
                           symbol: "wifi.slash",
                           author: .alicia)
        }
    }
}


/// Body requests stay at the configured Mac endpoint; redirects cannot replay
/// a private question or authored goal to a different host.
private final class PrivateBodySessionDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
