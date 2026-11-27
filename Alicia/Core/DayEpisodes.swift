import Foundation

/// Afternoon and Evening with Alicia (backend CL-20261125-day-episodes), shown
/// on Us under the morning briefing (CL-20261126-us-day-episodes).
///
/// GET /api/day_episodes is read-only: opening a card prepares or renders
/// nothing, and neither a view nor playback is evidence that he listened.
struct DayEpisode: Codable, Equatable, Identifiable {
    var id: String = ""
    var day: String = ""
    var slot: String = ""
    var timezone: String = ""
    var title: String = ""
    var text: String = ""
    var status: String = "unavailable"
    var audio_url: String = ""
    /// Measured length of the saved recording in seconds, never an estimate.
    var duration: Double = 0
    var playlist_id: String = ""
    var error: String = ""
    /// The configured start, "HH:MM" in `timezone`.
    var starts_at: String = ""
    var sources: [MorningBriefing.Source] = []
    /// The cached reading of the same words, when the backend has a complete one.
    var speech: MorningBriefing.Speech?
    /// Authenticated URLs resolved by the service, never a view.
    var speechChunks: [SpeechChunk] = []

    enum CodingKeys: String, CodingKey {
        case id, day, slot, timezone, title, text, status, audio_url, duration, playlist_id, error, starts_at, sources, speech
    }

    init(id: String = "", day: String = "", slot: String = "", title: String = "", text: String = "",
         status: String = "unavailable", audio_url: String = "", duration: Double = 0, playlist_id: String = "",
         error: String = "", starts_at: String = "", timezone: String = "", sources: [MorningBriefing.Source] = []) {
        self.id = id
        self.day = day
        self.slot = slot
        self.title = title
        self.text = text
        self.status = status
        self.audio_url = audio_url
        self.duration = duration
        self.playlist_id = playlist_id
        self.error = error
        self.starts_at = starts_at
        self.timezone = timezone
        self.sources = sources
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decodeIfPresent(String.self, forKey: .id) ?? ""
        day = try values.decodeIfPresent(String.self, forKey: .day) ?? ""
        slot = try values.decodeIfPresent(String.self, forKey: .slot) ?? ""
        timezone = try values.decodeIfPresent(String.self, forKey: .timezone) ?? ""
        title = try values.decodeIfPresent(String.self, forKey: .title) ?? ""
        text = try values.decodeIfPresent(String.self, forKey: .text) ?? ""
        status = try values.decodeIfPresent(String.self, forKey: .status) ?? "unavailable"
        audio_url = try values.decodeIfPresent(String.self, forKey: .audio_url) ?? ""
        duration = try values.decodeIfPresent(Double.self, forKey: .duration) ?? 0
        playlist_id = try values.decodeIfPresent(String.self, forKey: .playlist_id) ?? ""
        error = try values.decodeIfPresent(String.self, forKey: .error) ?? ""
        starts_at = try values.decodeIfPresent(String.self, forKey: .starts_at) ?? ""
        // A malformed source list or reading never costs him the episode itself.
        sources = (try? values.decodeIfPresent([MorningBriefing.Source].self, forKey: .sources)) ?? []
        speech = try? values.decodeIfPresent(MorningBriefing.Speech.self, forKey: .speech)
    }

    /// The same reading as its Studio playlist item (`Playlist.Item.readable`).
    var readingID: String { "day:" + id }

    var slotName: String {
        switch slot {
        case "afternoon": return "Afternoon with Alicia"
        case "evening": return "Evening with Alicia"
        default: return "With Alicia"
        }
    }

    var displayTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? slotName : title
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
        return components.host == nil && !components.path.isEmpty
    }

    var hasText: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var hasPlaylist: Bool { !playlist_id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// The configured start written the way the phone writes times, in the
    /// episode's own time zone ("1:00 PM"). Nil when the backend sent none.
    func startLabel(locale: Locale = .current) -> String? {
        let parts = starts_at.split(separator: ":", omittingEmptySubsequences: false).map { Int($0) }
        guard parts.count == 2, let hour = parts[0], let minute = parts[1],
              (0..<24).contains(hour), (0..<60).contains(minute) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timezone) ?? .current
        guard let date = calendar.date(from: DateComponents(year: 2026, month: 1, day: 15, hour: hour, minute: minute))
        else { return nil }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = calendar.timeZone
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    func availabilityText(locale: Locale = .current) -> String {
        if hasPlayableAudio { return "Ready to listen." }
        let reason = error.trimmingCharacters(in: .whitespacesAndNewlines)
        switch status {
        case "scheduled":
            return startLabel(locale: locale).map { "Prepared from \($0)." } ?? "Prepared later today."
        case "preparing", "draft", "rendering":
            return "Being prepared now."
        case "ready":
            return "The audio isn't ready to play yet."
        default:
            return reason.isEmpty ? "Not available right now." : reason
        }
    }

    /// True when its saved day is the phone's today, so a card left on screen
    /// past midnight never passes yesterday's episode off as today's.
    func isToday(_ now: Date, calendar: Calendar = .current) -> Bool {
        let parser = DateFormatter()
        parser.calendar = Calendar(identifier: .gregorian)
        parser.timeZone = calendar.timeZone
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.dateFormat = "yyyy-MM-dd"
        parser.isLenient = false
        guard let date = parser.date(from: day), parser.string(from: date) == day else { return false }
        return calendar.isDate(date, inSameDayAs: now)
    }
}

/// GET /api/day_episodes: the day's slots in order, afternoon then evening.
struct DayEpisodes: Codable, Equatable {
    var day: String = ""
    var timezone: String = ""
    var episodes: [DayEpisode] = []

    init(day: String = "", timezone: String = "", episodes: [DayEpisode] = []) {
        self.day = day
        self.timezone = timezone
        self.episodes = episodes
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        day = try values.decodeIfPresent(String.self, forKey: .day) ?? ""
        timezone = try values.decodeIfPresent(String.self, forKey: .timezone) ?? ""
        episodes = try values.decodeIfPresent([DayEpisode].self, forKey: .episodes) ?? []
    }
}

#if DEBUG
/// Invented fixture (this repo is public): a ready afternoon and a scheduled evening.
enum DayEpisodesPreview {
    static var value: DayEpisodes {
        // The phone's own date: ISO-8601 formatting would give UTC's, which is
        // already tomorrow on a Pacific evening.
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: .now)
        let today = String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
        let zone = TimeZone.current.identifier
        return DayEpisodes(day: today, timezone: zone, episodes: [
            DayEpisode(id: "preview-afternoon", day: today, slot: "afternoon", title: "Preview · What the room leaves open",
                       text: "Preview text of an afternoon episode.", status: "ready",
                       audio_url: "https://fixture.invalid/api/day_episodes/audio/preview-afternoon.m4a", duration: 412,
                       playlist_id: "pl_afternoon_with_alicia", starts_at: "13:00", timezone: zone,
                       sources: [MorningBriefing.Source(id: "fixture", title: "Fixture synthesis",
                                                        excerpt: "An invented passage.")]),
            DayEpisode(id: "preview-evening", day: today, slot: "evening", status: "scheduled",
                       playlist_id: "pl_evening_with_alicia", starts_at: "18:30", timezone: zone),
        ])
    }
}
#endif
