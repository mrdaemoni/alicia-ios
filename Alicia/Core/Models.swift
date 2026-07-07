import SwiftUI

struct Message: Identifiable, Hashable {
    enum Sender { case me, alicia }
    let id = UUID()
    var sender: Sender
    var text: String
    var date: Date = .now
    /// Backend id for reacting to this reply (negative ints, iOS-minted).
    var messageID: Int? = nil
    /// Emoji the user reacted with (shown as a badge on the bubble).
    var reaction: String? = nil
    /// TTS voice note of this reply, when voice replies are on.
    var voiceURL: URL? = nil
    /// Non-nil for proactive messages pulled from her circulation feed
    /// (e.g. "morning · ariadne") — rendered as a small caption.
    var proactiveLabel: String? = nil
    /// Circulation decision id — reactions on proactive messages attach to
    /// this (per-synthesis reception signal), not a chat message id.
    var proactiveID: String? = nil
}

/// One event in a streamed chat reply.
enum ChatEvent {
    case token(String)
    case voice(URL)
    case done(messageID: Int?)
}

/// A proactive message Alicia sent on her own initiative (from the
/// backend's circulation feed).
/// The synthesis of the day — one finished thought from her shelf,
/// rotating at midnight (Us page).
struct FeaturedSynthesis: Hashable, Identifiable {
    var id: String { title }
    var title: String
    var excerpt: String
    var body: String
    var date: String
}

struct ProactiveMessage: Identifiable, Hashable {
    let id: String
    var text: String
    var kind: String
    var archetype: String
    var date: Date
}

/// One of Alicia's introspective notes — what she is thinking / working on.
struct Thought: Identifiable, Hashable {
    let id = UUID()
    var title: String
    var body: String
    var tag: String
    var date: Date = .now
}

/// A piece of audio Alicia has made for you (wav / mp3).
struct Track: Identifiable, Hashable {
    let id = UUID()
    var title: String
    var mood: String
    var duration: TimeInterval
    var symbol: String          // SF Symbol used as artwork placeholder
    var fileName: String?       // bundled/downloaded audio file, when available
    // Podcast metadata (0/nil for non-episode tracks e.g. sample data)
    var season: Int = 0
    var episode: Int = 0
    var label: String? = nil    // "S11E04" — keys the shownotes lookup
    var series: String = ""
}

/// A drawing — either one you made or one Alicia made for you.
struct Artwork: Identifiable, Hashable {
    enum Author { case me, alicia }
    let id = UUID()
    var title: String
    var note: String
    var symbol: String
    var author: Author
    /// Remote render of the piece (Alicia's real drawings, served by the
    /// backend). Nil for sample data — cells fall back to `symbol`.
    var imageURL: URL? = nil
}

/// The Us tab's loop-architecture payload (`/api/home`) — three concentric
/// loops around right now: the season arc she holds around Hector, the
/// trail of the previous days' episodes, and today's episode — plus the
/// knowledge cards mined from it.
struct HomeContext {
    struct SeasonEpisode: Hashable, Identifiable {
        var episode: Int
        var label: String
        var title: String
        var claim: String
        var heard: Bool
        var isToday: Bool
        var id: String { label }
    }
    struct Movement: Hashable {
        var numeral: String
        var title: String
        var fromEpisode: Int
        var toEpisode: Int
        var summary: String
    }
    struct Season {
        var season: Int
        var series: String
        var title: String
        var subtitle: String
        var premise: String
        var movements: [Movement]
        var movementNow: String
        var episodes: [SeasonEpisode]
        var heardCount: Int
        var total: Int
    }
    struct TrailItem: Hashable, Identifiable {
        var label: String
        var title: String
        var pickedDate: String
        var daysAgo: Int?
        var claim: String
        var id: String { label }
    }
    struct Today {
        var label: String
        var title: String
        var pickedDate: String
        var isToday: Bool
        var focus: String
        var claim: String
        var about: String
        var quote: String
    }
    /// One knowledge card — a thinker in his ears, the episode's quote, or
    /// a new idea. `id` is stable for the day ("S11E08:thinker:zhuangzi")
    /// so feedback lands on the exact card.
    struct Card: Hashable, Identifiable {
        var id: String
        var kind: String        // "quote" | "thinker" | "idea"
        var title: String
        var body: String
        var thinker: String
        var tagline: String
        var themes: [String]
        var source: String      // episode label
        var badge: String       // e.g. "new to the vault"
    }
    var season: Season?
    var trail: [TrailItem]
    var today: Today?
    var cards: [Card]
    /// One sentence: what Alicia thinks we're talking about today.
    var contextLine: String
}

/// A traversal edge of the thinker graph — who connects to whom, and why
/// (vault co-citation + shared themes, precomputed on the backend).
struct RelatedThinker: Decodable, Hashable {
    var name: String
    var why: String
}

/// A single vital in Alicia's health dashboard.
struct HealthMetric: Identifiable, Hashable {
    let id = UUID()
    var name: String
    var value: Double           // 0...1 for rings / bars
    var display: String         // human-readable value
    var symbol: String
    var hue: Double             // 0...1 mapped to a color
}

extension HealthMetric {
    /// Ink-wash rendering: muted saturation and depth so gauges read like
    /// pigment on paper, not neon on glass.
    var color: Color { Color(hue: hue, saturation: 0.38, brightness: 0.52) }
}
extension String {
    /// Proactive messages arrive with her Telegram emoji prefix (🕯️, 🧵…).
    /// The app draws its own emblems — shed leading pictographs here.
    var strippedLeadingEmoji: String {
        var scalars = unicodeScalars.drop(while: { s in
            s.properties.isEmojiPresentation || s.properties.isEmoji &&
            !("a"..."z").contains(Character(s).lowercased().first.map(String.init) ?? "0")
            || s == " " || s == "\u{FE0F}"
        })
        return String(String.UnicodeScalarView(scalars))
            .trimmingCharacters(in: .whitespaces)
    }
}

