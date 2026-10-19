import SwiftUI
import Observation

/// Her awareness, as the backend reads it (`GET /api/presence`,
/// `skills/presence_awareness.py`): her own signals, plus a typed Jev reading
/// when her state changes.
struct PresenceAwareness: Codable, Equatable {
    var energy: Double
    var openness: Double
    var coherence: Double
    var direction: String      // toward_hector, toward_work, inward, resting
    var stance: String         // witness, ask, offer, celebrate, hold
    var attending_to: String
    var source: String         // local, jev+local
    var updated_at: String

    static let resting = PresenceAwareness(energy: 0.4, openness: 0.6, coherence: 0.75,
        direction: "inward", stance: "witness", attending_to: "", source: "local", updated_at: "")

    /// `updated_at` is transport metadata, not a change in her awareness.
    /// Ignoring it prevents the minute poll from restarting the field's ease
    /// when every motion-driving value is unchanged.
    static func == (lhs: PresenceAwareness, rhs: PresenceAwareness) -> Bool {
        lhs.energy == rhs.energy && lhs.openness == rhs.openness &&
        lhs.coherence == rhs.coherence && lhs.direction == rhs.direction &&
        lhs.stance == rhs.stance && lhs.attending_to == rhs.attending_to &&
        lhs.source == rhs.source
    }
}

/// One body behind every room.
///
/// Hector, 2026-09-26: the particles should be "a continuous movement of her
/// … like her awareness", not a predetermined shape per section. Before this,
/// each tab drew its own family and switching tabs swapped the whole shape.
/// Now there is one field, held here, that every tab's background reads:
///
/// - **Her stance** chooses the form she leans into (witness → drift, ask →
///   depth, offer → weave, celebrate → bloom, hold → knot, challenge →
///   singular). The **section** only nudges it (a quarter of the weight), so
///   Studio still feels a little more like a spark without resetting her.
/// - **Energy** is tempo, **openness** is spread, **coherence** is how gathered
///   the particles are, **direction** is where the body leans.
/// - Every change eases over seconds from wherever she is, and the phase is
///   integrated rather than recomputed, so a change of speed never jumps.
@MainActor @Observable
final class PresenceField {
    /// The earlier per-room field stays one switch away until Hector approves this.
    var enabled: Bool = UserDefaults.standard.object(forKey: "alicia.presence.awareness") as? Bool ?? true {
        didSet { UserDefaults.standard.set(enabled, forKey: "alicia.presence.awareness") }
    }
    private(set) var awareness = PresenceAwareness.resting
    private(set) var lastUpdate: Date?

    /// The whole screen, measured once at the root. Every surface — a tab, a
    /// pushed page, a sheet, the walk — places her against the glass rather
    /// than against its own container, so moving between them never moves her.
    /// (Build 35 on the phone: "a lack of continuity between different sections.")
    var screen: CGSize = .zero
    /// A walk is open and he is speaking: she turns toward him and opens.
    private(set) var listening = false
    /// His voice, straight from the microphone tap (0…1). Drawn every frame,
    /// never eased, so she breathes with him rather than after him.
    var voiceLevel: Double = 0
    /// She is reading to him (the briefing room): her own pose, not the walk's
    /// listening one. Only the DEBUG Motion Lab sets it until
    /// CL-20261018-organic-field ships after the study.
    private(set) var speaking = false
    /// Paused while speaking: the same form at a lower tempo (a settle, not a morph).
    private(set) var speakingSettled = false
    /// Her measured words, and the playback clock they run on. The organic
    /// candidate reads her voice inside each frame from these, with no poll.
    private var voiceCues: [OrganicVoice.Cue] = []
    private var playbackAnchor: (wall: Date, seconds: Double, running: Bool)?
    /// A steering gesture in flight: +1 Higher (gather and lift), −1 Lower (open and settle).
    private var gestureStart: Date?
    private var gestureSign = 0.0
    static let gestureSeconds = 1.4

    private var section: AppSection = .us
    private var from = Target.initial
    private var to = Target.initial
    private var changedAt = Date.distantPast
    private var phaseAnchor: Double = Date.now.timeIntervalSinceReferenceDate
        .truncatingRemainder(dividingBy: 10_000) * (.pi / 4)
    private var phaseAnchorDate = Date.now
    private var rate: Double = .pi / 4

    /// Seconds a change takes to settle. Long enough to read as her turning,
    /// short enough that a tab switch is answered.
    static let easing: Double = 4.5

    struct Target: Equatable {
        var weights: [Double]           // indexed by AliciaPresence.Family.allCases
        var energy, openness, coherence: Double
        var focus: CGPoint              // unit space; (0.5, 0.5) is centred
        static let initial = Target(weights: [0, 0, 0, 0, 0, 1], energy: 0.4, openness: 0.6,
                                    coherence: 0.75, focus: CGPoint(x: 0.5, y: 0.5))
    }

    /// What one frame needs (PresenceGeometry.swift), drawn off the main thread.
    typealias Frame = PresenceFrame

    func setListening(_ on: Bool, now: Date = .now) {
        guard on != listening else { return }
        listening = on
        if !on { voiceLevel = 0 }
        retarget(now: now)
    }

    func setSpeaking(_ on: Bool, now: Date = .now) {
        guard on != speaking else { return }
        speaking = on
        speakingSettled = false
        retarget(now: now)
    }

    func setSpeakingSettled(_ settled: Bool, now: Date = .now) {
        guard speaking, settled != speakingSettled else { return }
        speakingSettled = settled
        retarget(now: now)
    }

    /// `cues` must be sorted by start, on the same clock as `syncPlayback`.
    func setVoice(cues: [OrganicVoice.Cue]) { voiceCues = cues }

    func syncPlayback(seconds: Double, running: Bool, now: Date = .now) {
        guard seconds.isFinite else { return }
        playbackAnchor = (now, seconds, running)
    }

    func gesture(higher: Bool, now: Date = .now) {
        gestureSign = higher ? 1 : -1
        gestureStart = now
    }

    func receive(_ reading: PresenceAwareness, now: Date = .now) {
        awareness = reading
        lastUpdate = now
        retarget(now: now)
    }

    func enter(_ section: AppSection, now: Date = .now) {
        guard section != self.section else { return }
        self.section = section
        retarget(now: now)
    }

    private func retarget(now: Date) {
        from = current(at: now)
        to = target()
        changedAt = now
        // Re-anchor the phase at the present speed, then change speed from here.
        phaseAnchor = phase(at: now)
        phaseAnchorDate = now
        rate = (.pi / 4) * (0.45 + to.energy * 1.1)
    }

    private func target() -> Target {
        var weights = Array(repeating: 0.0, count: AliciaPresence.Family.allCases.count)
        if listening {
            // Really listening: the knot that binds — "you and me" — carrying
            // what she already holds, opened wide and gathered toward him.
            weights[AliciaPresence.Family.knot.index] += 0.6
            weights[Self.family(forStance: awareness.stance).index] += 0.4
            return Target(weights: weights, energy: 0.62, openness: 1, coherence: 0.9,
                          focus: CGPoint(x: 0.5, y: 0.44))
        }
        if speaking {
            // Reading to him: her own form, open but held, leaning toward him.
            // A pause keeps the form and only slows her (a settle, not a morph).
            weights[Self.family(forStance: awareness.stance).index] += 0.85
            weights[Self.family(forSection: section).index] += 0.15
            return Target(weights: weights, energy: speakingSettled ? 0.3 : 0.56, openness: 0.72,
                          coherence: 0.84, focus: CGPoint(x: 0.5, y: 0.42))
        }
        // The section only nudges: at a quarter it read as a different body per
        // room; at this weight a room tints her without moving her.
        weights[Self.family(forStance: awareness.stance).index] += 0.85
        weights[Self.family(forSection: section).index] += 0.15
        let focus: CGPoint
        switch awareness.direction {
        case "toward_hector": focus = CGPoint(x: 0.5, y: 0.22)   // up, toward the words he reads
        case "toward_work": focus = CGPoint(x: 0.8, y: 0.6)
        case "resting": focus = CGPoint(x: 0.5, y: 0.74)
        default: focus = CGPoint(x: 0.5, y: 0.5)                 // inward: gathered on herself
        }
        return Target(weights: weights, energy: clamp(awareness.energy), openness: clamp(awareness.openness),
                      coherence: clamp(awareness.coherence), focus: focus)
    }

    private func phase(at date: Date) -> Double {
        phaseAnchor + date.timeIntervalSince(phaseAnchorDate) * rate
    }

    private func current(at date: Date) -> Target {
        let t = min(1, max(0, date.timeIntervalSince(changedAt) / Self.easing))
        let e = t * t * (3 - 2 * t)                               // smoothstep
        func mix(_ a: Double, _ b: Double) -> Double { a + (b - a) * e }
        return Target(weights: zip(from.weights, to.weights).map { mix($0, $1) },
                      energy: mix(from.energy, to.energy), openness: mix(from.openness, to.openness),
                      coherence: mix(from.coherence, to.coherence),
                      focus: CGPoint(x: mix(from.focus.x, to.focus.x), y: mix(from.focus.y, to.focus.y)))
    }

    func frame(at date: Date) -> Frame {
        let now = current(at: date)
        let ranked = now.weights.enumerated().sorted { $0.element > $1.element }
        let a = ranked[0], b = ranked[1]
        let mix = a.element + b.element > 0 ? b.element / (a.element + b.element) : 0
        var frame = Frame(primary: a.offset, secondary: b.offset, mix: mix, phase: phase(at: date),
                          energy: now.energy, openness: now.openness, coherence: now.coherence, focus: now.focus,
                          listening: listening, level: listening && voiceLevel.isFinite ? min(1, max(0, voiceLevel)) : 0)
        frame.speaking = speaking
        if speaking, let anchor = playbackAnchor {
            let t = anchor.seconds + (anchor.running ? date.timeIntervalSince(anchor.wall) : 0)
            let near = OrganicVoice.window(voiceCues, around: t)
            frame.word = OrganicVoice.word(near, at: t)
            frame.phraseTrail = OrganicVoice.trail(near, at: t)
        }
        if let start = gestureStart {
            let progress = date.timeIntervalSince(start) / Self.gestureSeconds
            if progress >= 0, progress <= 1 {
                let bump = sin(.pi * progress)
                frame.gesture = gestureSign * bump * bump
            }
        }
        return frame
    }

    /// Still frame for Reduce Motion: the settled target, at a fixed phase.
    func stillFrame() -> Frame {
        var f = frame(at: changedAt.addingTimeInterval(Self.easing))
        f.phase = 4.2
        // Reduce Motion is still: the open listening pose stays, but his voice
        // level must not keep resizing her (Codex review of #45, 2026-09-27).
        f.level = 0
        // Her words and a gesture are motion too: a still frame holds neither.
        f.word = 0
        f.phraseTrail = []
        f.gesture = 0
        return f
    }

    static func family(forStance stance: String) -> AliciaPresence.Family {
        switch stance {
        case "ask": .depth
        case "offer": .weave
        case "celebrate": .bloom
        case "hold": .knot
        case "challenge": .singular
        default: .drift                                          // witness
        }
    }

    static func family(forSection section: AppSection) -> AliciaPresence.Family {
        switch section {
        case .us: .knot
        case .dialogue, .body: .depth
        case .mind: .drift
        case .studio: .bloom
        case .knowledge: .weave
        }
    }

    private func clamp(_ v: Double) -> Double { min(1, max(0, v)) }
}
