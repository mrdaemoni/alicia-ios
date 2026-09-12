import Foundation

struct EpisodePlaybackReceipt: Codable {
    var episode_id: String
    var observed_at: String
    var date: Date? {
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: observed_at) { return date }
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: observed_at)
    }
}

/// Continuation follows positive playback evidence, independent of topic selection.
enum EpisodeContinuation {
    static func latest(local: EpisodePlaybackReceipt?, server: EpisodePlaybackReceipt?) -> EpisodePlaybackReceipt? {
        guard let local else { return server }
        guard let server else { return local }
        guard let localDate = local.date else { return server }
        guard let serverDate = server.date else { return local }
        return localDate >= serverDate ? local : server
    }
    static func next(after label: String, tracks: [Track]) -> Track? {
        guard let previous = tracks.first(where: { $0.label == label }) else { return nil }
        let available = tracks.filter { $0.fileName != nil && $0.label != nil }
        if previous.season > 0 {
            return available.filter {
                $0.season > 0 && $0.series == previous.series &&
                ($0.season > previous.season || ($0.season == previous.season && $0.episode > previous.episode))
            }.sorted { ($0.season, $0.episode) < ($1.season, $1.episode) }.first
        }
        // Named runs have their own episode ordering; never jump arbitrarily to a season.
        return available.filter {
            $0.collection == previous.collection && $0.episode > previous.episode
        }.sorted { $0.episode < $1.episode }.first
    }
}
