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
        var req = URLRequest(url: baseURL.appending(path: path))
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

    func stream(_ prompt: String) -> AsyncStream<String> {
        AsyncStream { continuation in
            let task = Task {
                do {
                    let body = try JSONEncoder().encode(["text": prompt])
                    let (bytes, resp) = try await URLSession.shared.bytes(
                        for: request("/api/chat", method: "POST", body: body))
                    guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
                        continuation.yield("(Alicia is unreachable right now — check the backend and your connection.)")
                        continuation.finish()
                        return
                    }
                    for try await line in bytes.lines {
                        guard line.hasPrefix("data: "),
                              let data = line.dropFirst(6).data(using: .utf8),
                              let event = try? JSONDecoder().decode(ChatEvent.self, from: data)
                        else { continue }
                        if let t = event.t { continuation.yield(t) }
                        if let err = event.error, !err.isEmpty {
                            continuation.yield("\n(connection hiccup: \(err))")
                        }
                        if event.done == true { break }
                    }
                } catch {
                    continuation.yield("(Alicia is unreachable right now — check the backend and your connection.)")
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private struct ChatEvent: Decodable {
        var t: String?
        var done: Bool?
        var error: String?
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
    }

    func tracks() async -> [Track] {
        await fetch("/api/tracks", as: [TrackDTO].self).map {
            Track(title: $0.title, mood: $0.mood, duration: $0.duration,
                  symbol: $0.symbol,
                  fileName: $0.fileName.flatMap { mediaURL($0)?.absoluteString })
        }
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

    func complement(_ title: String) async -> Artwork {
        do {
            let body = try JSONEncoder().encode(["title": title])
            let (data, resp) = try await URLSession.shared.data(
                for: request("/api/complement", method: "POST", body: body))
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
