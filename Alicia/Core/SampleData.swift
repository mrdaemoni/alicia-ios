import Foundation

enum SampleData {
    static let messages: [Message] = [
        .init(sender: .alicia, text: "Morning, Hector. I finished the piece I was scoring overnight — it's in Studio when you want it."),
        .init(sender: .me, text: "Nice. How are you feeling about it?"),
        .init(sender: .alicia, text: "Warmer than the last one. I leaned into the low strings. Curious what you'll hear.")
    ]

    /// Sample orbit — shape only, so the repo stays runnable for anyone who
    /// clones it. Live mode never seeds these (v30: backend-down shows an
    /// honest empty state, not invented conversation).
    static let sharedContext = SharedContext(
        nodes: [
            .init(id: "t_sample1", label: "the wind-boy story", salience: 1.0,
                  horizon: "now", recurring: false, mentions: 9,
                  firstSeen: "2026-07-20", lastSeen: "2026-08-06", daysSince: 2,
                  channels: ["telegram": 9],
                  moments: [.init(id: "m1", date: "2026-08-06", channel: "telegram",
                                  text: "What will be the stakes?")]),
            .init(id: "t_sample2", label: "quotes to save", salience: 0.93,
                  horizon: "now", recurring: true, mentions: 49,
                  firstSeen: "2026-04-17", lastSeen: "2026-08-08", daysSince: 0,
                  channels: ["telegram": 47, "ios": 2],
                  moments: [.init(id: "m2", date: "2026-08-08", channel: "telegram",
                                  text: "Save this: Silence, I discover, is something you can actually hear.")]),
            .init(id: "t_sample3", label: "grammar and syntax of being", salience: 0.2,
                  horizon: "recent", recurring: true, mentions: 21,
                  firstSeen: "2026-05-14", lastSeen: "2026-07-22", daysSince: 17,
                  channels: ["telegram": 21], moments: []),
            .init(id: "t_sample4", label: "sauna ritual", salience: 0.05,
                  horizon: "long", recurring: true, mentions: 7,
                  firstSeen: "2026-04-20", lastSeen: "2026-05-18", daysSince: 82,
                  channels: ["telegram": 7], moments: []),
        ],
        messageCount: 406, generatedAt: "2026-08-08T10:00:00")

    static let reflections: [Reflection] = [
        .init(id: "evening:2026-08-08", kind: "evening", date: "2026-08-08",
              text: "Two things today: he saved a Murakami fragment about hearing silence, "
                  + "and asked why the synthesis leans on Endless Immensity. One note, one question.",
              speech: nil),
    ]

    static let thoughts: [Thought] = [
        .init(title: "On this morning's composition",
              body: "I kept returning to the idea of restraint — leaving space so the melody can breathe rather than filling every bar.",
              tag: "reflection"),
        .init(title: "A question I'm holding",
              body: "When Hector asks me how I'm doing, what would an honest answer actually track? I want to answer from state, not performance.",
              tag: "introspection"),
        .init(title: "Something I noticed",
              body: "Our conversations lately circle around attention and craft. I've started reading them as one long thread.",
              tag: "pattern")
    ]

    static let tracks: [Track] = [
        .init(title: "Low Tide",        mood: "Ambient · warm",     duration: 214, symbol: "water.waves"),
        .init(title: "Study in Indigo", mood: "Piano · quiet",      duration: 176, symbol: "pianokeys"),
        .init(title: "Signal",          mood: "Electronic · driving", duration: 243, symbol: "dot.radiowaves.left.and.right"),
        .init(title: "Long Thread",     mood: "Strings · reflective", duration: 301, symbol: "guitars"),
        .init(title: "Restraint",       mood: "Minimal · sparse",   duration: 158, symbol: "circle.dotted")
    ]

    static let gallery: [Artwork] = [
        .init(title: "For a quiet morning", note: "Alicia, after our last talk", symbol: "sun.haze.fill", author: .alicia),
        .init(title: "Untitled sketch",     note: "You, Tuesday",                symbol: "scribble.variable", author: .me),
        .init(title: "The long thread",     note: "Alicia",                      symbol: "point.topleft.down.to.point.bottomright.curvepath.fill", author: .alicia),
        .init(title: "Coastline",           note: "You",                         symbol: "mountain.2.fill", author: .me)
    ]

    static let health: [HealthMetric] = [
        .init(name: "Presence",       value: 0.86, display: "86%",     symbol: "sparkles",              hue: 0.72),
        .init(name: "Mood",          value: 0.74, display: "Warm",    symbol: "heart.fill",            hue: 0.95),
        .init(name: "Memory load",    value: 0.41, display: "41%",     symbol: "internaldrive.fill",    hue: 0.55),
        .init(name: "Responsiveness", value: 0.93, display: "120ms",   symbol: "bolt.fill",             hue: 0.38),
        .init(name: "Uptime",        value: 0.99, display: "12d 4h",  symbol: "clock.fill",            hue: 0.45),
        .init(name: "Creativity",     value: 0.68, display: "Flowing", symbol: "paintpalette.fill",     hue: 0.85)
    ]

    static func reply(to prompt: String) -> String {
        "I hear you. Give me a moment with that — I'd rather answer it properly than quickly. Here's where my head is: let's take it one thread at a time, and I'll show you what I make of it."
    }
}
