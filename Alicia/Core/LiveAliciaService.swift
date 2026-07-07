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
///
/// Auth is a bearer token; media URLs (audio, drawings) carry it as a
/// `?token=` query instead, because AVPlayer/AsyncImage can't set headers.
struct LiveAliciaService: AliciaService {
    let baseURL: URL
    let token: String

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
        var comps = URLComponents(url: baseURL.appending(path: path), resolvingAgainstBaseURL: false)
        comps?.queryItems = [URLQueryItem(name: "token", value: token)]
        return comps?.url
    }

    private func fetch<D: Decodable>(_ path: String, as type: [D].Type) async -> [D] {
        do {
            let (data, resp) = try await URLSession.shared.data(for: request(path))
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else { return [] }
            return try JSONDecoder().decode([D].self, from: data)
        } catch {
            return []   // every tab degrades gracefully to empty
        }
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

    func stream(_ prompt: String, voice: Bool) -> AsyncStream<ChatEvent> {
        AsyncStream { continuation in
            let task = Task {
                do {
                    let body = try JSONSerialization.data(
                        withJSONObject: ["text": prompt, "voice": voice])
                    let (bytes, resp) = try await URLSession.shared.bytes(
                        for: request("/api/chat", method: "POST", body: body))
                    guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
                        continuation.yield(.token("(Alicia is unreachable right now — check the backend and your connection.)"))
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
        var error: String?
    }

    // MARK: reactions + proactive feed

    func react(messageID: Int, emoji: String) async {
        guard let body = try? JSONSerialization.data(
            withJSONObject: ["message_id": messageID, "emoji": emoji]) else { return }
        _ = try? await URLSession.shared.data(
            for: request("/api/react", method: "POST", body: body))
    }

    func react(proactiveID: String, emoji: String) async {
        guard let body = try? JSONSerialization.data(
            withJSONObject: ["proactive_id": proactiveID, "emoji": emoji]) else { return }
        _ = try? await URLSession.shared.data(
            for: request("/api/react", method: "POST", body: body))
    }

    private struct ProactiveDTO: Decodable {
        var id, date, text, kind, archetype: String
    }

    func proactive(limit: Int) async -> [ProactiveMessage] {
        await fetch("/api/proactive?limit=\(limit)", as: [ProactiveDTO].self).map {
            ProactiveMessage(id: $0.id, text: $0.text, kind: $0.kind,
                             archetype: $0.archetype,
                             date: Self.parseDate($0.date))
        }
    }

    // MARK: tab data

    private struct ThoughtDTO: Decodable { var title, body, tag, date: String }

    func thoughts() async -> [Thought] {
        await fetch("/api/thoughts", as: [ThoughtDTO].self).map {
            Thought(title: $0.title, body: $0.body, tag: $0.tag,
                    date: Self.parseDate($0.date))
        }
    }

    private struct TrackDTO: Decodable {
        var title, mood, symbol: String
        var duration: Double
        var fileName: String?
        var season: Int?
        var episode: Int?
        var label: String?
        var series: String?
    }

    func tracks() async -> [Track] {
        await fetch("/api/tracks", as: [TrackDTO].self).map {
            Track(title: $0.title, mood: $0.mood, duration: $0.duration,
                  symbol: $0.symbol,
                  fileName: $0.fileName.flatMap { mediaURL($0)?.absoluteString },
                  season: $0.season ?? 0,
                  episode: $0.episode ?? 0,
                  label: $0.label,
                  series: $0.series ?? "")
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
            return try JSONDecoder().decode(ModeActionDTO.self, from: data).message
        } catch { return nil }
    }

    private struct ReplyDTO: Decodable { var ok: Bool; var response: String? }

    func reply(proactiveID: String, text: String) async -> String? {
        do {
            let body = try JSONSerialization.data(
                withJSONObject: ["proactive_id": proactiveID, "text": text])
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
        await fetch("/api/archetypes", as: [ArchetypeStat].self)
    }

    func knowing() async -> KnowingState? {
        do {
            let (data, resp) = try await URLSession.shared.data(for: request("/api/knowing"))
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            return try JSONDecoder().decode(KnowingState.self, from: data)
        } catch { return nil }
    }

    private struct SynthesisDTO: Decodable {
        var title, date, excerpt, body: String
    }

    func syntheses() async -> [FeaturedSynthesis] {
        await fetch("/api/syntheses", as: [SynthesisDTO].self).map {
            FeaturedSynthesis(title: $0.title, excerpt: $0.excerpt,
                              body: $0.body, date: $0.date)
        }
    }

    func thinkers() async -> ThinkerNetwork? {
        do {
            let (data, resp) = try await URLSession.shared.data(for: request("/api/thinkers"))
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            return try JSONDecoder().decode(ThinkerNetwork.self, from: data)
        } catch { return nil }
    }

    func timeline() async -> [TimelineDay] {
        await fetch("/api/timeline", as: [TimelineDay].self)
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
        var season: SeasonDTO?
        var trail: [TrailDTO]?
        var today: TodayDTO?
        var cards: [CardDTO]?
        var context_line: String?
    }

    func homeContext() async -> HomeContext? {
        do {
            let (data, resp) = try await URLSession.shared.data(for: request("/api/home"))
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            let d = try JSONDecoder().decode(HomeDTO.self, from: data)
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
                contextLine: d.context_line ?? "")
        } catch { return nil }
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
        do {
            let (data, resp) = try await URLSession.shared.data(for: request("/api/quote"))
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            let q = try JSONDecoder().decode(QuoteDTO.self, from: data)
            return q.text.isEmpty ? nil : (q.text, q.author)
        } catch { return nil }
    }

    private struct FeaturedDTO: Decodable {
        var title, excerpt, body, date: String
    }

    func featured() async -> FeaturedSynthesis? {
        do {
            let (data, resp) = try await URLSession.shared.data(for: request("/api/featured"))
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            let f = try JSONDecoder().decode(FeaturedDTO.self, from: data)
            return FeaturedSynthesis(title: f.title, excerpt: f.excerpt,
                                     body: f.body, date: f.date)
        } catch { return nil }
    }

    private struct GreetingDTO: Decodable { var greeting: String }

    func greeting() async -> String? {
        do {
            let (data, resp) = try await URLSession.shared.data(
                for: request("/api/greeting"))
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            let g = try JSONDecoder().decode(GreetingDTO.self, from: data).greeting
            return g.isEmpty ? nil : g
        } catch { return nil }
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

    func gallery() async -> [Artwork] {
        await fetch("/api/gallery", as: [ArtworkDTO].self).map(artwork(from:))
    }

    private struct MetricDTO: Decodable {
        var name, display, symbol: String
        var value, hue: Double
    }

    func health() async -> [HealthMetric] {
        await fetch("/api/health", as: [MetricDTO].self).map {
            HealthMetric(name: $0.name, value: $0.value, display: $0.display,
                         symbol: $0.symbol, hue: $0.hue)
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
