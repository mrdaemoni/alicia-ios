import SwiftUI

struct Message: Identifiable, Hashable {
    enum Sender { case me, alicia }
    let id = UUID()
    var sender: Sender
    var text: String
    var date: Date = .now
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
