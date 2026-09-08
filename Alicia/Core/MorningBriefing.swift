import Foundation

/// A prepared reading, separate from a chosen episode or evidence of listening.
/// GET /api/morning_briefing is read-only; opening this value does not generate audio.
struct MorningBriefing: Codable, Equatable, Identifiable {
    struct Source: Codable, Equatable {
        var id: String? = nil
        var title: String? = nil
        var path: String? = nil
        var excerpt: String? = nil
    }

    var id: String = ""
    var day: String = ""
    var title: String = ""
    var text: String = ""
    var status: String = "unavailable"
    var audio_url: String = ""
    /// Actual rendered audio length in seconds, never an estimated reading time.
    var duration: Double = 0
    var playlist_id: String = ""
    var error: String = ""
    var sources: [Source] = []

    enum CodingKeys: String, CodingKey {
        case id, day, title, text, status, audio_url, duration, playlist_id, error, sources
    }

    init(id: String = "", day: String = "", title: String = "", text: String = "",
         status: String = "unavailable", audio_url: String = "", duration: Double = 0,
         playlist_id: String = "", error: String = "", sources: [Source] = []) {
        self.id = id
        self.day = day
        self.title = title
        self.text = text
        self.status = status
        self.audio_url = audio_url
        self.duration = duration
        self.playlist_id = playlist_id
        self.error = error
        self.sources = sources
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decodeIfPresent(String.self, forKey: .id) ?? ""
        day = try values.decodeIfPresent(String.self, forKey: .day) ?? ""
        title = try values.decodeIfPresent(String.self, forKey: .title) ?? ""
        text = try values.decodeIfPresent(String.self, forKey: .text) ?? ""
        status = try values.decodeIfPresent(String.self, forKey: .status) ?? "unavailable"
        audio_url = try values.decodeIfPresent(String.self, forKey: .audio_url) ?? ""
        duration = try values.decodeIfPresent(Double.self, forKey: .duration) ?? 0
        playlist_id = try values.decodeIfPresent(String.self, forKey: .playlist_id) ?? ""
        error = try values.decodeIfPresent(String.self, forKey: .error) ?? ""
        sources = try values.decodeIfPresent([Source].self, forKey: .sources) ?? []
    }

    var displayTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Your morning briefing" : title
    }

    var measuredSeconds: Int? {
        guard duration.isFinite, duration > 0, let seconds = Int(exactly: duration.rounded()) else { return nil }
        return max(1, seconds)
    }

    var durationLabel: String? {
        guard let seconds = measuredSeconds else { return nil }
        if seconds >= 3600 {
            return "\(seconds / 3600):" + String(format: "%02d:%02d", (seconds % 3600) / 60, seconds % 60)
        }
        return "\(seconds / 60):" + String(format: "%02d", seconds % 60)
    }

    var spokenDuration: String? {
        guard let seconds = measuredSeconds else { return nil }
        let minutes = seconds / 60
        let remainder = seconds % 60
        var parts: [String] = []
        if minutes > 0 { parts.append("\(minutes) \(minutes == 1 ? "minute" : "minutes")") }
        if remainder > 0 { parts.append("\(remainder) \(remainder == 1 ? "second" : "seconds")") }
        return parts.joined(separator: ", ")
    }

    var hasPlayableAudio: Bool {
        guard status == "ready", !id.isEmpty, measuredSeconds != nil else { return false }
        let path = audio_url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty, let components = URLComponents(string: path) else { return false }
        if let scheme = components.scheme {
            return ["http", "https"].contains(scheme.lowercased()) && !(components.host ?? "").isEmpty
        }
        // Private-backend media paths are normally relative to the configured service.
        return components.host == nil && !components.path.isEmpty
    }

    var hasText: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var hasPlaylist: Bool { !playlist_id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var availabilityText: String {
        if hasPlayableAudio { return "Ready to listen." }
        if status == "preparing" { return "The audio is being prepared." }
        if status == "ready" { return "The audio isn't ready to play yet." }
        return "The briefing isn't available right now."
    }

    enum DayRelation { case today, earlier, later, unknown }

    func dayRelation(to now: Date, calendar: Calendar = .current) -> DayRelation {
        guard let date = date(calendar: calendar) else { return .unknown }
        switch calendar.compare(date, to: now, toGranularity: .day) {
        case .orderedSame: return .today
        case .orderedAscending: return .earlier
        case .orderedDescending: return .later
        }
    }

    func dateLabel(calendar: Calendar = .current, locale: Locale = .current) -> String {
        guard let date = date(calendar: calendar) else { return "Date unavailable" }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = locale
        formatter.dateStyle = .full
        return formatter.string(from: date)
    }

    private func date(calendar: Calendar) -> Date? {
        let parser = DateFormatter()
        parser.calendar = Calendar(identifier: .gregorian)
        parser.timeZone = calendar.timeZone
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.dateFormat = "yyyy-MM-dd"
        parser.isLenient = false
        guard let date = parser.date(from: day), parser.string(from: date) == day else { return nil }
        return date
    }
}
