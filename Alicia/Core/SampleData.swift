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
    static let contextGraph = ContextGraph(
        generatedAt: "2026-09-19T18:00:00+00:00",
        nodes: [
            ContextNode(id: "ctx-000000000001", kind: "project", title: "The Boy — the film", status: "stated",
                        summary: "Animation in his own hand; n33 is the only drawing that does not move.",
                        body: "Animation in his own hand; n33 is the only drawing that does not move, and that is the grammar.",
                        updated: "2026-09-18", importance: 8, needs_review: false, themes: ["quality"], links: ["Authors/Josh Waitzkin"],
                        related: ["ctx-000000000002"], receipts: [.init(source: "interactions:ios", ref: "m613", observed_at: "2026-09-18T20:00:00+00:00", excerpt: "I'm cutting the film against the mix")],
                        worth_hits: 2, worth_misses: 0, superseded_by: "", why: ["fresh"]),
            ContextNode(id: "ctx-000000000002", kind: "tension", title: "Depth vs legibility", status: "inferred",
                        summary: "Depth in the making against legibility for others, unresolved.", body: "Depth in the making against legibility for others, unresolved.",
                        updated: "2026-09-10", importance: 7, needs_review: true, themes: ["depth"], links: [], related: ["ctx-000000000001"], receipts: [],
                        worth_hits: 0, worth_misses: 0, superseded_by: "", why: []),
            ContextNode(id: "ctx-000000000003", kind: "situation", title: "Granada until Friday", status: "stated",
                        summary: "In Granada until Friday.", body: "In Granada until Friday.", updated: "2026-09-17", importance: 5, needs_review: false,
                        themes: [], links: [], related: [], receipts: [.init(source: "interactions:ios", ref: "m620", observed_at: "2026-09-17T09:00:00+00:00", excerpt: "I am in Granada until Friday")],
                        worth_hits: 0, worth_misses: 0, superseded_by: "", why: []),
        ],
        core: [], notice: "stated is Hector's; inferred is Alicia's reading and unconfirmed until he keeps or corrects it.", needsReview: 1, total: 3)

    static let contextArrangement = ContextArrangement(
        generatedAt: "2026-09-19T18:00:00+00:00", status: "ready", reason: "",
        notice: "Each item names the node it bears on and the line it was drawn from. A question is the episode's, a finding is a reading of the body data, your words are yours. Nothing here is agreement.",
        date: "2026-09-19", episodeID: "S16E08", refused: false,
        groups: [
            .init(node: .init(id: "ctx-000000000001", kind: "project", title: "The Boy — the film", status: "stated",
                              summary: "Animation in his own hand; n33 is the only drawing that does not move.", updated: "2026-09-18", needs_review: false),
                  items: [
                    .init(kind: "question", title: "Is the film cut against the mix a decision you make in every frame?",
                          why: "the episode asks this near your project — shared: film, mix", ref: "p1", score: 0.8,
                          node_id: "ctx-000000000001", node_title: "The Boy — the film", node_kind: "project",
                          evidence: .init(source: "episode:S16E08", ref: "p1", excerpt: "cutting the film against the mix, animation in his own hand"), date: "2026-09-19"),
                    .init(kind: "thinker", title: "Josh Waitzkin", why: "Josh Waitzkin — linked from your project “The Boy — the film”.", ref: "m613", score: 1.2,
                          node_id: "ctx-000000000001", node_title: "The Boy — the film", node_kind: "project",
                          evidence: .init(source: "interactions:ios", ref: "m613", excerpt: "I'm cutting the film against the mix"), date: ""),
                  ], arranged: true),
            .init(node: .init(id: "ctx-000000000002", kind: "tension", title: "Depth vs legibility", status: "inferred",
                              summary: "Depth in the making against legibility for others, unresolved.", updated: "2026-09-10", needs_review: true),
                  items: [
                    .init(kind: "finding", title: "He asked whether his morning routine is ornamentation; the three days he stopped it answered on sleep and resting heart rate.",
                          why: "a mind/body reading that touches your tension — shared: making, others", ref: "finding-2026-09-19-1", score: 0.9,
                          node_id: "ctx-000000000002", node_title: "Depth vs legibility", node_kind: "tension",
                          evidence: .init(source: "Alicia/Bridge/mind_body_bridge.md", ref: "finding-2026-09-19-1", excerpt: "He asked whether his morning routine is ornamentation"), date: "2026-09-19"),
                  ], arranged: true),
            .init(node: .init(id: "ctx-000000000003", kind: "situation", title: "Granada until Friday", status: "stated",
                              summary: "In Granada until Friday.", updated: "2026-09-17", needs_review: false),
                  items: [
                    .init(kind: "place", title: "Granada · the old town", why: "where you are today, and this situation is about here", ref: "place-2026-09-19", score: 0.9,
                          node_id: "ctx-000000000003", node_title: "Granada until Friday", node_kind: "situation",
                          evidence: .init(source: "app_events:place", ref: "place-2026-09-19", excerpt: "Granada · the old town"), date: "2026-09-19"),
                  ], arranged: true),
        ], arrangedCount: 4)

    static let contextElevation = ContextElevation(
        generatedAt: "2026-09-19T18:00:00+00:00", status: "ready", reason: "",
        notice: "Each item names the node and the line it was drawn from. Selection is not listening; a link is not agreement.",
        refused: false,
        items: [.init(kind: "thinker", title: "Josh Waitzkin", why: "Josh Waitzkin — linked from your project “The Boy — the film”.", score: 1.2,
                      node_id: "ctx-000000000001", node_title: "The Boy — the film", node_kind: "project",
                      evidence: .init(source: "interactions:ios", ref: "m613", excerpt: "I'm cutting the film against the mix"), episode_id: "")],
        episodeID: "S16E07")

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
        .init(name: "Creativity",     value: 0.68, display: "Flowing", symbol: "paintpalette.fill",     hue: 0.85),
        // One unmeasured vital, so the preview shows the state that matters:
        // a signal awaiting evidence draws a dashed empty track, not a stroke
        // at zero.
        .init(name: "Self-improvement", value: 0, display: "not yet assessable",
              symbol: "arrow.up.right.circle.fill", hue: 0.83, assessable: false)
    ]

    static func reply(to prompt: String) -> String {
        "I hear you. Give me a moment with that — I'd rather answer it properly than quickly. Here's where my head is: let's take it one thread at a time, and I'll show you what I make of it."
    }
}
