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
    var color: Color { Color(hue: hue, saturation: 0.65, brightness: 0.95) }
}
