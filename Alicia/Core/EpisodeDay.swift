import Foundation

/// The episode's proposals and Hector's explicit words remain separate.
struct EpisodeDay: Decodable, Identifiable {
    struct Episode: Decodable { var id, title: String; var source_paths: [String] }
    struct Probe: Decodable, Identifiable {
        var id, question, anchor, source_path, verdict: String
    }
    struct Entry: Decodable, Identifiable {
        var id, ts, day, kind, episode_id, text, target_id, verdict, source: String
    }
    var date: String
    var episode: Episode?
    var episodes: [String]
    var focus: String
    var probes: [Probe]
    var understanding, frame_id, frame_verdict, frame_status: String
    var reactions, learnings, corrections: [Entry]
    var played_ms, position_ms: Int
    var days: [String]
    var vault_note: String
    var id: String { date }
}

struct EpisodeDayResponse: Decodable {
    var ok: Bool
    var error: String?
    var day: EpisodeDay?
}

struct WalkReceipt: Decodable {
    var ok: Bool
    var message: String?
}

struct ConversationHistory: Decodable {
    struct Turn: Decodable {
        var id, ts, role, content, source: String
        var reply_id: String?
    }
    var messages: [Turn]
}

#if DEBUG
extension EpisodeDay {
    /// Deliberately labelled fixture; available only through an explicit debug launch argument.
    static var preview: EpisodeDay {
        let args = ProcessInfo.processInfo.arguments
        let empty = args.contains("--episode-empty")
        let failed = args.contains("--episode-failed")
        return EpisodeDay(
            date: "2026-09-05",
            episode: empty ? nil : Episode(id: "S15E06", title: "Preview · The Discard Log", source_paths: []),
            episodes: empty ? [] : ["S15E06"],
            focus: "What deserves your attention—and what can you leave unfinished?",
            probes: empty ? [] : [
                Probe(id: "preview:probe:0", question: "What are you keeping alive mainly because you've already invested in it?",
                      anchor: "Preview passage: a record of what you chose to leave unfinished.", source_path: "Preview fixture", verdict: ""),
                Probe(id: "preview:probe:1", question: "Where would choosing less give you room to go deeper?",
                      anchor: "Preview passage: commitment and control ask different things of us.", source_path: "Preview fixture", verdict: "")],
            understanding: "The question I'm holding is how choosing what to stop can make a commitment clearer. I want to hear where that distinction meets your day.",
            frame_id: "preview", frame_verdict: "", frame_status: failed ? "unavailable" : "ready",
            reactions: [], learnings: [], corrections: [], played_ms: 180000, position_ms: 180000,
            days: ["2026-09-05"], vault_note: "")
    }
}
#endif
