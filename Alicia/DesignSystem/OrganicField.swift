import Foundation
import CoreGraphics

/// The briefing room's field, made organic: a DEBUG Motion Lab candidate
/// (CL-20261018-organic-field). Nothing in a product surface draws it until
/// Hector picks it in the lab after the steering study ends on 2026-11-14.
///
/// Hector, 2026-10-18, on TestFlight 49: "the particles feel too forced. They
/// don't feel organic … more natural, more responsive when it's full screen."
/// Each toggle answers one cause found in the shipped field:
struct OrganicStyle: Equatable, Sendable {
    /// A. **Smooth time.** It draws at `framesPerSecond` instead of 15, and her
    /// voice is read inside each frame from the playback clock. Before, a
    /// second 15 Hz poll aliased with the frames.
    var smoothTime = true
    /// B. **Two timescales.** The phrase breathes as a wave that spreads from
    /// her centre (±4.5%, reaching the edge about 0.35 s later), and each word
    /// only stirs texture. Before, every word inflated the whole body.
    var twoTimescales = true
    /// C. **Each particle lives.** It has its own lag behind the form, its own
    /// slow drift and its own jitter rhythm. Before, every dot rode one rigid
    /// formula and the scatter wobbled in unison.
    var particleLife = true
    /// D. **Matter, not pixels.** Round dots in three sizes and three depths
    /// of ink. Before, there were identical squares in one opacity.
    var organicDots = true
    /// E. **Her own speaking pose.** It is not the walk's listening one: a
    /// pause settles instead of morphing, and Higher or Lower gets one gesture.
    var speakingPose = true
    /// F. **Framed for the full screen.** The body grows toward the screen's
    /// height (about 1.3× in the room), with a sparse drifting dust across the
    /// glass.
    var roomFraming = true
    var framesPerSecond = 30

    static let all = OrganicStyle()
    /// Every toggle off reproduces the shipped field's behaviour in the lab.
    static let shipped = OrganicStyle(smoothTime: false, twoTimescales: false, particleLife: false,
                                      organicDots: false, speakingPose: false, roomFraming: false,
                                      framesPerSecond: AliciaPresenceCadence.shipped)
}

/// The shipped cadence, shared with `AliciaPresence.framesPerSecond`.
enum AliciaPresenceCadence { static let shipped = 15 }

/// Her voice on two timescales, from measured word cues. Every value is a pure
/// function of the cues and the playback clock. So it is the same at 30 or 60
/// frames a second, the same in a still frame, and needs no polling task.
enum OrganicVoice {
    struct Cue: Sendable, Equatable { var start, end: Double }

    /// A word rises with a 60 ms attack while it sounds and falls with a
    /// 400 ms release after it.
    static let attack = 0.06, release = 0.4
    /// The phrase is how much of the last two seconds she spent speaking. The
    /// weighting u²(1 − u) is zero at both ends, so a word starting or ending
    /// never jolts it. It peaks two thirds of the way toward now (about 0.7 s
    /// back), rises through a phrase, and falls in the gap between sentences.
    static let phraseWindow = 2.0
    /// The breath reaches the edge of her body this much later than her centre.
    static let trailDelays: [Double] = stride(from: 0.0, through: 0.35, by: 0.05).map { $0 }

    /// The cues that can matter at `t`: those starting within the phrase window,
    /// plus one release tail. `cues` must be sorted by start.
    static func window(_ cues: [Cue], around t: Double) -> ArraySlice<Cue> {
        let from = t - phraseWindow - release * 6
        var lo = 0, hi = cues.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if cues[mid].end < from { lo = mid + 1 } else { hi = mid }
        }
        var end = lo
        while end < cues.count, cues[end].start <= t { end += 1 }
        return cues[lo..<end]
    }

    static func word(_ cues: ArraySlice<Cue>, at t: Double) -> Double {
        guard t.isFinite else { return 0 }
        var level = 0.0
        for cue in cues where cue.start.isFinite && cue.end.isFinite && cue.start <= t {
            let held = min(t, cue.end) - cue.start
            var value = 1 - exp(-max(0, held) / attack)
            if t > cue.end { value *= exp(-(t - cue.end) / release) }
            level = max(level, value)
        }
        return clamp(level)
    }

    static func phrase(_ cues: ArraySlice<Cue>, at t: Double) -> Double {
        guard t.isFinite else { return 0 }
        let lo = t - phraseWindow
        // ∫ u²(1 − u) du over each spoken stretch, with u = (τ − lo) / W.
        func area(_ u: Double) -> Double { u * u * u / 3 - u * u * u * u / 4 }
        var sum = 0.0
        for cue in cues where cue.start.isFinite && cue.end.isFinite {
            let a = max(lo, cue.start), b = min(t, cue.end)
            guard b > a else { continue }
            sum += area((b - lo) / phraseWindow) - area((a - lo) / phraseWindow)
        }
        return clamp(sum / (1.0 / 12))
    }

    /// Phrase energy now and at each later delay, for the radial breath.
    static func trail(_ cues: ArraySlice<Cue>, at t: Double) -> [Double] {
        trailDelays.map { phrase(cues, at: t - $0) }
    }

    static func clamp(_ v: Double) -> Double { v.isFinite ? min(1, max(0, v)) : 0 }
}

/// Where the organic candidate places each particle, and how it is inked.
enum OrganicField {
    struct Dot: Sendable { var point: CGPoint; var size: CGFloat; var layer: Int }
    struct Placed: Sendable {
        var dots: [Dot]
        /// Ink for the three depths: near, middle, far.
        var opacities: [Double]
        var dust: [Dot]
        var dustOpacity: Double
        var round: Bool
    }

    /// A stable per-particle number in [0, 1), the same on every frame.
    @inline(__always)
    static func hash(_ n: Double, _ salt: Double) -> Double {
        let v = sin(n * 12.9898 + salt * 78.233) * 43_758.5453
        return v - floor(v)
    }

    /// The phrase energy a particle at relative radius `r` (0 centre, 1 edge)
    /// feels: the centre hears it first.
    static func phraseAt(_ trail: [Double], radius r: Double) -> Double {
        guard !trail.isEmpty else { return 0 }
        let position = min(1, max(0, r)) * Double(trail.count - 1)
        let i = Int(position), f = position - Double(i)
        let a = trail[i], b = trail[min(trail.count - 1, i + 1)]
        return OrganicVoice.clamp(a + (b - a) * f)
    }

    static func points(frame: PresenceFrame, size: CGSize, style: OrganicStyle,
                       source: (PresenceForm, Double, Double) -> CGPoint) -> Placed {
        let forms = PresenceForm.allCases
        let a = forms[max(0, min(forms.count - 1, frame.primary))]
        let b = forms[max(0, min(forms.count - 1, frame.secondary))]
        let base = Double(a.basePoints) * (1 - frame.mix) + Double(b.basePoints) * frame.mix
        let total = min(3_000, max(950, Int(base * (0.92 + frame.energy * 0.55))))
        let speaking = style.speakingPose && frame.speaking
        // How open she is: the walk's listening stays widest. Speaking is open
        // but held.
        let pose = frame.listening ? 1.28 : speaking ? 1.12 : 1
        // The shipped field pumps the whole body with the voice level. The
        // two-timescale candidate breathes per particle below instead.
        let pump = style.twoTimescales ? 1 : (frame.listening || frame.speaking ? 1 + 0.22 * frame.level : 1)
        // A steering gesture: Higher gathers and lifts, Lower opens and settles.
        let gesture = style.speakingPose && frame.gesture.isFinite ? max(-1, min(1, frame.gesture)) : 0
        let contraction = (0.9 + frame.openness * 0.24) * pose * pump * (1 - 0.07 * gesture)
        let lift = -26 * gesture
        let shared = (1 - frame.coherence) * 20
        // F: on a tall screen she grows toward the height (about 1.3× the shipped
        // body in the room), keeping her centre and most of her on the glass.
        let side: CGFloat = style.roomFraming
            ? max(min(size.width, size.height), size.height * 0.6)
            : min(size.width, size.height)
        let origin = CGPoint(x: (size.width - side) / 2, y: (size.height - side) / 2)
        let bounds = CGRect(origin: .zero, size: size)
        let dot = max(0.85, min(size.width, size.height) / 330)
        let target = CGPoint(x: frame.focus.x * 400, y: frame.focus.y * 400 + lift)
        let pull = 0.12 * (1.15 - frame.openness * 0.5)
        let word = style.twoTimescales ? OrganicVoice.clamp(frame.word) : 0
        var dots: [Dot] = []
        dots.reserveCapacity(total)
        for index in 1...total {
            let n = Double(index)
            let h1 = hash(n, 1), h2 = hash(n, 2), h3 = hash(n, 3), h4 = hash(n, 4), h5 = hash(n, 5)
            // C: each particle trails the form by its own small lag.
            let time = style.particleLife ? frame.phase - 0.45 * h1 : frame.phase
            let pa = source(a, n * Double(a.sourceCount) / Double(total), time)
            let pb = frame.mix > 0.001 ? source(b, n * Double(b.sourceCount) / Double(total), time) : pa
            guard pa.x.isFinite, pa.y.isFinite, pb.x.isFinite, pb.y.isFinite else { continue }
            var x = pa.x + (pb.x - pa.x) * frame.mix
            var y = pa.y + (pb.y - pa.y) * frame.mix
            var scale = contraction
            if style.twoTimescales {
                // B: the phrase breathes outward from her centre.
                let r = Double(hypot(x - 200, y - 200)) / 200
                scale *= 1 + 0.045 * phraseAt(frame.phraseTrail, radius: r)
            }
            x = 200 + (x - 200) * scale
            y = 200 + (y - 200) * scale + lift
            if style.particleLife {
                // C: a slow drift of its own, plus a texture each word stirs in some particles.
                let amplitude = (1 - frame.coherence) * 14 + 2.5 + 7 * word * h3
                let w1 = 0.7 + 1.1 * h3, w2 = 0.9 + 0.8 * h5
                x += amplitude * (sin(w1 * frame.phase + 6.283 * h2) + 0.55 * sin(w2 * frame.phase * 1.7 + 6.283 * h4))
                y += amplitude * (cos(w2 * frame.phase + 6.283 * h4) + 0.55 * cos(w1 * frame.phase * 1.3 + 6.283 * h2))
            } else {
                x += shared * sin(n * 12.9898 + frame.phase * 1.7)
                y += shared * cos(n * 78.233 + frame.phase * 1.3)
            }
            let dx = target.x - x, dy = target.y - y
            let amount = min(1, 150 / max(1, hypot(dx, dy))) * pull
            x += dx * amount; y += dy * amount
            let point = CGPoint(x: origin.x + x / 400 * side, y: origin.y + y / 400 * side)
            guard point.x.isFinite, point.y.isFinite, bounds.contains(point) else { continue }
            // D: three sizes (70 / 25 / 5%) and three depths of ink.
            let size = style.organicDots ? dot * (h5 < 0.70 ? 1 : h5 < 0.95 ? 1.65 : 2.5) : dot
            let layer = style.organicDots ? (h2 < 0.45 ? 2 : h2 < 0.85 ? 1 : 0) : 1
            dots.append(Dot(point: point, size: size, layer: layer))
        }
        let ink = 0.42 + frame.coherence * 0.2
        let shimmer = 0.06 * word
        let opacities = style.organicDots
            ? [min(0.9, ink * 1.35 + shimmer), min(0.9, ink + shimmer), min(0.9, ink * 0.62 + shimmer)]
            : [ink, ink, ink]
        // F: a sparse dust across the whole glass that drifts and feels the phrase faintly.
        var dust: [Dot] = []
        var dustOpacity = 0.0
        if style.roomFraming {
            let phrase = style.twoTimescales ? phraseAt(frame.phraseTrail, radius: 0) : 0
            dustOpacity = 0.14 + 0.1 * phrase
            dust.reserveCapacity(150)
            for index in 1...150 {
                let n = Double(index) + 9_000
                let u = hash(n, 6), v = hash(n, 7), w = hash(n, 8)
                let drift = 0.025 * (1 + 0.6 * phrase)
                let x = (u + drift * sin(frame.phase * (0.15 + 0.2 * w) + 6.283 * v)) * size.width
                let y = (v + drift * cos(frame.phase * (0.12 + 0.18 * u) + 6.283 * w)) * size.height
                let point = CGPoint(x: x, y: y)
                guard point.x.isFinite, point.y.isFinite, bounds.contains(point) else { continue }
                dust.append(Dot(point: point, size: dot * (w < 0.8 ? 1 : 1.6), layer: 0))
            }
        }
        return Placed(dots: dots, opacities: opacities, dust: dust, dustOpacity: dustOpacity,
                      round: style.organicDots)
    }
}
