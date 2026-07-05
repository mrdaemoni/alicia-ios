import Foundation

/// The single seam between the UI and Alicia's backend.
/// Swap `MockAliciaService` for a real URLSession-backed implementation and
/// the whole app is "networked" without touching any view.
protocol AliciaService {
    /// Streams a reply as events: tokens, an optional voice-note URL, and a
    /// final `.done` carrying the backend message id (for reactions).
    func stream(_ prompt: String, voice: Bool) -> AsyncStream<ChatEvent>
    func thoughts() async -> [Thought]
    func tracks() async -> [Track]
    func gallery() async -> [Artwork]
    func health() async -> [HealthMetric]
    /// Messages Alicia sent proactively (her own initiative) — newest first.
    func proactive(limit: Int) async -> [ProactiveMessage]
    /// React to one of her replies with an emoji. Feeds her learning loops.
    func react(messageID: Int, emoji: String) async
    /// React to a proactive message — attaches to its circulation entry.
    func react(proactiveID: String, emoji: String) async
    /// Ask Alicia to respond to a drawing you made. `imageData` is the
    /// canvas as PNG so she can see what you actually drew.
    func complement(_ title: String, imageData: Data?) async -> Artwork
    /// Shownotes markdown for a podcast episode ("S11E04"). Empty if none.
    func episodeNotes(label: String) async -> String
    /// Current thinking-mode state — ("walk"|"drive"|"idle", word count).
    func modeState() async -> (mode: String, words: Int)
    /// Start/end a thinking mode ("start_walk"/"end_walk"). Returns her
    /// acknowledgment message, or nil on failure.
    func modeAction(_ action: String, topic: String) async -> String?
    /// Home-screen greeting grounded in the live conversation; nil offline
    /// (the view falls back to a time-of-day line).
    func greeting() async -> String?
    /// Reply to one of her proactive messages. Lands as Tier-3 capture +
    /// shared history + memory on the backend; returns her answer.
    func reply(proactiveID: String, text: String) async -> String?
    /// Co-creation: send the current canvas composite and where the pencil
    /// stopped (normalized 0…1, nil if unknown); she draws from that point.
    func cocreate(image: Data, width: Int, height: Int,
                  anchor: CGPoint?) async -> (overlay: URL, caption: String)?
    /// The synthesis of the day (rotates at midnight); nil offline.
    func featured() async -> FeaturedSynthesis?
    /// Quote of the moment (three rotations a day); nil offline.
    func quote() async -> (text: String, author: String)?
    /// The real voice ranking from her archetype loop (7-day attributions
    /// + evidence-weighted effectiveness). Empty offline.
    func archetypes() async -> [ArchetypeStat]
    /// What she knows of Hector — now / recently / long term. Nil offline.
    func knowing() async -> KnowingState?
    /// The freshest syntheses off the shelf, readable in full.
    func syntheses() async -> [FeaturedSynthesis]
    /// The vault's thinker network (curated master map).
    func thinkers() async -> ThinkerNetwork?
    /// Every lived day since her birth, growth moments marked.
    func timeline() async -> [TimelineDay]
}

struct TimelineDay: Decodable, Hashable, Identifiable {
    var date: String
    var headline: String
    var what: [String]
    var growth: [String]
    var milestone: Bool
    var id: String { date }
}

struct KnowingClaim: Decodable, Hashable {
    var claim: String
    var dimension: String
    var confidence: Double
}

struct KnowingLongterm: Decodable, Hashable {
    var learnings: Int
    var dimensions: [String]
    var memory_rules: Int
    var days: Int
}

struct KnowingState: Decodable, Hashable {
    var now: [KnowingClaim]
    var recent: [KnowingClaim]
    var recent_count: Int
    var longterm: KnowingLongterm
}

struct Thinker: Decodable, Hashable, Identifiable {
    var name: String
    var anchor: Bool
    var tagline: String
    var themes: [String]
    var works: String
    var relation: String
    var id: String { name }
}

struct ThinkerNetwork: Decodable {
    var themes: [String]
    var thinkers: [Thinker]
}

/// One voice's live loop state.
struct ArchetypeStat: Decodable, Hashable {
    var name: String
    var count: Int
    var effectiveness: Double
}

/// In-memory stand-in so the app runs with zero backend.
struct MockAliciaService: AliciaService {
    func stream(_ prompt: String, voice: Bool) -> AsyncStream<ChatEvent> {
        let reply = SampleData.reply(to: prompt)
        return AsyncStream { continuation in
            Task {
                for word in reply.split(separator: " ", omittingEmptySubsequences: false) {
                    try? await Task.sleep(for: .milliseconds(45))
                    continuation.yield(.token(String(word) + " "))
                }
                continuation.yield(.done(messageID: nil))
                continuation.finish()
            }
        }
    }

    func thoughts() async -> [Thought] { SampleData.thoughts }
    func tracks() async -> [Track] { SampleData.tracks }
    func gallery() async -> [Artwork] { SampleData.gallery }
    func health() async -> [HealthMetric] { SampleData.health }
    func proactive(limit: Int) async -> [ProactiveMessage] { [] }
    func react(messageID: Int, emoji: String) async {}
    func react(proactiveID: String, emoji: String) async {}

    func complement(_ title: String, imageData: Data?) async -> Artwork {
        try? await Task.sleep(for: .milliseconds(700))
        return Artwork(title: "Reply to \"\(title)\"",
                       note: "Alicia's response to your sketch",
                       symbol: "sparkle",
                       author: .alicia)
    }

    func episodeNotes(label: String) async -> String { "" }
    func modeState() async -> (mode: String, words: Int) { ("idle", 0) }
    func modeAction(_ action: String, topic: String) async -> String? { nil }
    func greeting() async -> String? { nil }
    func reply(proactiveID: String, text: String) async -> String? {
        try? await Task.sleep(for: .milliseconds(600))
        return "I hear you — say more when you're ready."
    }

    func cocreate(image: Data, width: Int, height: Int,
                  anchor: CGPoint?) async -> (overlay: URL, caption: String)? {
        nil   // co-creation needs the live backend
    }

    func quote() async -> (text: String, author: String)? {
        ("The end of a melody is not its goal.", "Friedrich Nietzsche")
    }

    func archetypes() async -> [ArchetypeStat] { [] }
    func knowing() async -> KnowingState? { nil }
    func syntheses() async -> [FeaturedSynthesis] { [] }
    func thinkers() async -> ThinkerNetwork? { nil }
    func timeline() async -> [TimelineDay] { [] }

    func featured() async -> FeaturedSynthesis? {
        FeaturedSynthesis(
            title: "The map is a promise the territory keeps breaking",
            excerpt: "A sample synthesis so the card has a shape in mock mode — the live shelf holds nine hundred of these.",
            body: "A sample synthesis so the card has a shape in mock mode.",
            date: "2026-07-05")
    }
}
