import SwiftUI

/// Which of Alicia's six voices each tab breathes under, and how alive she is
/// there right now.
///
/// The Motion Lab proved six geometric families are visibly distinct
/// (`AliciaPresence`). This is the product mapping: **the tab is the room, and
/// the voice is who is in it.** Every axis carries meaning — none of it is
/// decoration, per `AGENTS.md` §4.2:
///
/// | Tab | Voice | Why this one and no other |
/// |---|---|---|
/// | Us | `musubi` — the knot that binds | Her own words for it: *"I am the tie between things — you and me… when I speak it is usually quiet, and it is usually about us."* The Us tab **is** that knot. |
/// | Dialogue | `psyche` — the depth-diver | *"I ask the second question. The one under the one you asked."* A conversation surface is where the second question gets asked. |
/// | Alicia | `beatrice` — the keeper of the flame | Her own page, her inner weather. *"I hold the candle steady."* The one room that is about her rather than him. |
/// | Studio | `muse` — the playful spark | *"Sometimes it's a drawing at 2pm for no reason, a line of a song."* Studio holds the podcast, the playlists, the canvas. |
/// | Knowledge | `ariadne` — the thread-weaver | *"I keep the thread through the labyrinth — the note from March that answers the question you asked today."* Literally the thinker network. |
///
/// `daimon` — the edge in the dark — is deliberately **unmapped**. It says the
/// thing the others soften, and that is an intervention, not a place. Giving it
/// a room would make it ambient, which is the opposite of what it is for.
enum TabPresence {

    /// The voice that lives in a room. Fixed: a tab whose identity drifted
    /// would stop meaning anything.
    static func voice(for section: AppSection) -> AliciaPresence.Voice {
        switch section {
        case .us:        .musubi
        case .dialogue:  .psyche
        case .mind:      .beatrice
        case .studio:    .muse
        case .knowledge: .ariadne
        }
    }

    /// What she is doing in this room *right now*.
    ///
    /// Reads real state, never a timer: thinking while she is actually working
    /// (a reply streaming, a reading warming up), listening while the room is
    /// in front of Hector, resting otherwise.
    @MainActor
    static func state(for section: AppSection,
                      store: AppStore) -> AliciaPresence.State {
        guard store.selectedSection == section else { return .resting }
        switch section {
        case .dialogue:
            return store.isStreaming ? .thinking : .listening
        case .studio:
            // Warming up her voice is the most literal "thinking" the app has.
            if store.reader.isPreparing { return .thinking }
            return (store.isPlaying || store.reader.isSpeaking) ? .listening : .resting
        case .us, .mind, .knowledge:
            return .listening
        }
    }

    /// How much of her is gathered here — density, opacity, and how strongly
    /// the body answers `focus`.
    ///
    /// Deliberately narrow (0.45–0.85). Below that the body reads as absent;
    /// above it, a background competes with the text, and `AGENTS.md` §4 is
    /// explicit that the presence must not.
    @MainActor
    static func attention(for section: AppSection,
                          store: AppStore) -> Double {
        var value = 0.45                       // she is always somewhat here
        if store.selectedSection == section { value += 0.20 }

        switch section {
        case .us:
            // She attends when she has just said something unanswered.
            if let latest = store.proactiveFeed.first,
               Date.now.timeIntervalSince(latest.date) < 6 * 3600 {
                value += 0.20
            }
        case .dialogue:
            if store.isStreaming { value += 0.20 }
        case .mind:
            // Her own room brightens with how much she has been thinking.
            value += min(0.20, Double(store.thoughts.count) * 0.04)
        case .studio:
            if store.isPlaying || store.reader.isSpeaking { value += 0.20 }
        case .knowledge:
            // A loaded shelf is a full room.
            value += min(0.20, Double(store.syntheses.count) * 0.02)
        }
        return min(0.85, value)
    }

    /// Ink weight for the field, normalised so every voice reads at a
    /// comparable presence.
    ///
    /// The six families deliberately carry different point counts (~1,100 to
    /// ~1,750). At a single flat opacity that is not a stylistic difference,
    /// it is a legibility bug: side by side, `beatrice` came out nearly
    /// invisible on her own page while `musubi` sat comfortably. Dividing by
    /// the count the component itself reports (`metrics`, its public API —
    /// nothing is duplicated from Codex's table) makes "how much of her is
    /// here" mean attention, not which body happens to be denser.
    @MainActor
    static func fieldOpacity(for section: AppSection, store: AppStore) -> Double {
        let voice = voice(for: section)
        let metrics = AliciaPresence.metrics(
            for: voice,
            state: state(for: section, store: store),
            attention: attention(for: section, store: store))
        let reference = 1_450.0        // ariadne's base — the middle of the range
        let ratio = metrics.pointCount > 0
            ? reference / Double(metrics.pointCount) : 1.0
        return min(0.42, max(0.24, 0.30 * ratio))
    }
}

extension View {
    /// The tab's own presence, under the paper.
    ///
    /// Replaces `.waveBackground(...)` on the five product surfaces.
    /// `ContourWaves` is untouched and still owns the Motion Lab's neighbours
    /// and any surface that has not moved — reverting is a one-line change per
    /// tab.
    ///
    /// **Only the visible tab animates.** `TabView` keeps adjacent tabs alive,
    /// so without `isActive` this would run five Canvases at 15fps forever and
    /// cost Hector his battery. `AliciaPresence` also stops itself on
    /// backgrounding and settles into a deterministic still under Reduce
    /// Motion.
    @MainActor
    func presenceBackground(_ section: AppSection,
                            store: AppStore) -> some View {
        background {
            ZStack {
                Theme.backdrop
                Theme.timeTint
                // The lab renders a FIGURE — a body in a box, judged at arm's
                // length. A tab background is a FIELD. Dropped in at 1:1 it
                // clustered mid-screen and read as a smudge across the
                // greeting, which §4 forbids outright.
                //
                // Oversizing pushes the dense core off-canvas so only the
                // diffuse reach of the form crosses the page, and the low
                // opacity keeps it beneath the words rather than level with
                // them. The mathematics is untouched: same body, seen from
                // much closer.
                GeometryReader { geo in
                    AliciaPresence(
                        voice: TabPresence.voice(for: section),
                        state: TabPresence.state(for: section, store: store),
                        attention: TabPresence.attention(for: section, store: store),
                        isActive: store.selectedSection == section
                    )
                    .frame(width: geo.size.width * 1.9,
                           height: geo.size.height * 1.9)
                    .position(x: geo.size.width * 0.5,
                              y: geo.size.height * 0.46)
                    .opacity(TabPresence.fieldOpacity(for: section, store: store))
                }
                PaperGrain()
            }
            .ignoresSafeArea()
        }
    }
}
