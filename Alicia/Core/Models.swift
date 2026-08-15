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
    /// True when this is one of her explicit asks — Dialogue gives it a
    /// full bubble and an "answer her" affordance (v23).
    var isAsk: Bool = false
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
    /// A reading already rendered in her voice by the overnight pre-render
    /// (`skills/reading_voice.py`) — empty means the reader asks the backend
    /// for it and starts on the lead chunk a few seconds later.
    var speechChunks: [SpeechChunk] = []
    var speechDuration: TimeInterval = 0

    /// This piece as something to press play on.
    var readable: Readable {
        Readable(title: title, body: body, kind: "synthesis",
                 speechChunks: speechChunks, speechDuration: speechDuration)
    }

    /// Pin identity. Keyed on the title because that's what survives the
    /// piece rotating off the shelf — the whole point of pinning one.
    var pinID: String { "synthesis:\(title)" }
}

// In an extension so the memberwise initialiser survives.
extension FeaturedSynthesis {
    /// A pinned synthesis, read back out of the home payload.
    init(pinned card: HomeContext.Card) {
        self.init(title: card.title,
                  excerpt: String(card.body.prefix(220)),
                  body: card.body,
                  date: card.source)
    }
}

struct ProactiveMessage: Identifiable, Hashable {
    let id: String
    var text: String
    var kind: String
    var archetype: String
    var date: Date
    /// She is explicitly asking — an open-ended answer is the point.
    /// Dialogue renders these as answerable messages, not whispers.
    var isAsk: Bool = false
}

/// One of Alicia's introspective notes — what she is thinking / working on.
struct Thought: Identifiable, Hashable {
    let id = UUID()
    var title: String
    var body: String
    var tag: String
    var date: Date = .now
}

/// A listening queue Hector assembled — syntheses (and episodes) lined up to
/// play one after another on a drive or a walk. Order is kept server-side
/// (`skills/playlists.py`) so it survives reinstalls and she can see what he
/// is choosing to spend an hour with.
struct Playlist: Identifiable, Hashable {
    struct Item: Identifiable, Hashable {
        var id: String
        var kind: String          // "synthesis" | "episode" | …
        var title: String
        var body: String
        var source: String
        var duration: TimeInterval
        /// Audio that already exists. Empty means it still needs rendering —
        /// the reader asks for it and streams the lead chunk.
        var speechChunks: [SpeechChunk]

        var isReady: Bool { !speechChunks.isEmpty }

        var readable: Readable {
            Readable(title: title, body: body, kind: kind,
                     speechChunks: speechChunks, speechDuration: duration)
        }
    }

    var id: String
    var name: String
    var items: [Item]
    /// Whole-queue length, and how many pieces can play right now.
    var duration: TimeInterval
    var ready: Int

    var isFullyReady: Bool { ready >= items.count }
    var readables: [Readable] { items.map(\.readable) }
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
    var label: String? = nil    // "S11E04" / "NIGHT2" — keys the shownotes lookup
    var series: String = ""
    /// What Studio shelves this under. A numbered season ("S13") or a named
    /// run ("NIGHTS") — not every run of the podcast has a number, and
    /// grouping on the integer made a whole season invisible.
    var collection: String = ""
    var collectionTitle: String = ""

    /// This episode as a playlist entry — already-rendered audio, so it
    /// needs no voicing and plays the moment it's queued.
    var playlistItemID: String { "episode:\(label ?? title)" }
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
    /// What Hector is holding — pinned cards/thinkers, newest first (v26).
    var pinned: [Card] = []
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
/// The Us tab's live orbit (`/api/context`) — what we actually talk about,
/// mined from the real record rather than authored in advance.
///
/// Two axes, deliberately separate. `horizon` is the RING (now / recent /
/// long — the short-to-long-term binding the three orbits draw) and
/// `recurring` is a MARK for a subject that keeps coming back across
/// months. A thread can be both: something raised today that he has also
/// been circling since May sits on the inner ring wearing the mark.
struct SharedContext {
    struct Moment: Hashable, Identifiable {
        var id: String
        var date: String
        var channel: String     // "telegram" | "ios"
        var text: String
    }
    struct Node: Hashable, Identifiable {
        var id: String
        var label: String
        /// 0…1. Drives ink density — this is the "darker when it matters"
        /// the orbit is built around.
        var salience: Double
        var horizon: String     // "now" | "recent" | "long"
        var recurring: Bool
        var mentions: Int
        var firstSeen: String
        var lastSeen: String
        var daysSince: Int
        var channels: [String: Int]
        /// The receipts: real dated lines he wrote. A node that cannot show
        /// these is a node something invented.
        var moments: [Moment]

        var ringIndex: Int {
            switch horizon {
            case "now": return 0
            case "recent": return 1
            default: return 2
            }
        }
        var onIOS: Bool { (channels["ios"] ?? 0) > 0 }
    }
    var nodes: [Node]
    var messageCount: Int
    var generatedAt: String

    func nodes(on ring: Int) -> [Node] { nodes.filter { $0.ringIndex == ring } }
}

/// One of her self-reflections (`/api/reflections`) — morning or evening,
/// text plus a reading when her voice has already been rendered.
// Equatable rather than Hashable: SpeechStatus carries chunk payloads
// and is only Equatable. ForEach needs Identifiable, which is what matters.
struct Reflection: Equatable, Identifiable {
    var id: String
    var kind: String            // "morning" | "evening"
    var date: String
    var text: String
    var speech: SpeechStatus?

    var isEvening: Bool { kind == "evening" }
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

    /// No emoji anywhere in her displayed text (v24) — Telegram messages
    /// carry 💭/✨/🎙 markers inline, but on paper her ink does that work.
    /// Digits/#/* survive (they're technically emoji-capable scalars).
    var strippedEmojis: String {
        let kept = unicodeScalars.filter { s in
            !(s.properties.isEmojiPresentation ||
              (s.properties.isEmoji && s.value >= 0x1F000) ||
              s.value == 0xFE0F || s.value == 0x200D)
        }
        return String(String.UnicodeScalarView(kept))
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespaces)
    }
}

