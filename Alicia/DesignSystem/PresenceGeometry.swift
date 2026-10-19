import Foundation
import CoreGraphics

/// Her body's pure geometry: the six forms, the frame a surface draws, and where
/// the current field places each particle. Foundation and CoreGraphics only, so
/// the same math runs in the app, in the Motion Lab's audits and in offline
/// renders (CL-20261018-organic-field). The formulas moved here verbatim from
/// `AliciaPresence`; that view keeps thin wrappers.

/// The six forms, in `AliciaPresence.Family` order.
enum PresenceForm: Int, CaseIterable, Sendable {
    case drift
    case weave
    case depth
    case singular
    case bloom
    case knot

    /// Source resolution and a rendering budget per form (as the voices use).
    var sourceCount: Int {
        switch self {
        case .drift, .singular: 10_000
        default: 20_000
        }
    }
    var basePoints: Int {
        switch self {
        case .drift: 1_200
        case .weave: 1_450
        case .depth: 1_650
        case .singular, .bloom: 1_100
        case .knot: 1_750
        }
    }
}

/// What one frame needs. A value, so a Canvas can draw it off the main thread.
/// The first ten fields are the field as it ships. The rest feed only the DEBUG
/// organic candidate and default to "absent".
struct PresenceFrame: Sendable {
    var primary: Int, secondary: Int, mix: Double
    var phase, energy, openness, coherence: Double
    var focus: CGPoint
    var listening = false
    var level: Double = 0
    /// She is speaking (the briefing room), as opposed to listening to him.
    var speaking = false
    /// Her voice on two timescales (OrganicVoice): each word, and the phrase.
    var word: Double = 0
    /// Phrase energy now and at later delays, for the radial breath wave.
    var phraseTrail: [Double] = []
    /// A steering gesture in flight: +1 Higher, −1 Lower, scaled by its bump.
    var gesture: Double = 0
}

enum PresenceGeometry {
    /// Where the field as it ships places each particle: the body of
    /// `AliciaPresence.drawField` before CL-20261018-organic-field, unchanged.
    struct CurrentPoints { var points: [CGPoint]; var dot: CGFloat; var opacity: Double }

    static func currentPoints(frame: PresenceFrame, size: CGSize) -> CurrentPoints {
        let families = PresenceForm.allCases
        let a = families[frame.primary], b = families[frame.secondary]
        let base = Double(a.basePoints) * (1 - frame.mix) + Double(b.basePoints) * frame.mix
        let total = min(3_000, max(950, Int(base * (0.92 + frame.energy * 0.55))))
        // Listening, she opens wide and breathes with his voice.
        let breath = frame.listening ? 1 + 0.22 * frame.level : 1
        // Listening she opens further than any room: the widest she gets.
        let contraction = (0.9 + frame.openness * 0.24) * (frame.listening ? 1.28 : 1) * breath
        let jitter = (1 - frame.coherence) * 20
        let side = min(size.width, size.height)
        let origin = CGPoint(x: (size.width - side) / 2, y: (size.height - side) / 2)
        let bounds = CGRect(origin: .zero, size: size)
        let dot = max(0.85, side / 330)
        let target = CGPoint(x: frame.focus.x * 400, y: frame.focus.y * 400)
        let pull = 0.12 * (1.15 - frame.openness * 0.5)
        var points: [CGPoint] = []
        points.reserveCapacity(total)
        for index in 1...total {
            let pa = sourcePoint(family: a, sourceIndex: Double(index) * Double(a.sourceCount) / Double(total), time: frame.phase)
            let pb = frame.mix > 0.001
                ? sourcePoint(family: b, sourceIndex: Double(index) * Double(b.sourceCount) / Double(total), time: frame.phase)
                : pa
            guard pa.x.isFinite, pa.y.isFinite, pb.x.isFinite, pb.y.isFinite else { continue }
            // Two forms, one body: every particle travels between its place in each.
            var x = pa.x + (pb.x - pa.x) * frame.mix
            var y = pa.y + (pb.y - pa.y) * frame.mix
            x = 200 + (x - 200) * contraction
            y = 200 + (y - 200) * contraction
            // Scattered when she is unsettled, gathered when she is coherent.
            let n = Double(index)
            x += jitter * sin(n * 12.9898 + frame.phase * 1.7)
            y += jitter * cos(n * 78.233 + frame.phase * 1.3)
            // Where her attention points, the body leans.
            let dx = target.x - x, dy = target.y - y
            let amount = min(1, 150 / max(1, hypot(dx, dy))) * pull
            x += dx * amount; y += dy * amount
            let point = CGPoint(x: origin.x + x / 400 * side, y: origin.y + y / 400 * side)
            guard point.x.isFinite, point.y.isFinite, bounds.contains(point) else { continue }
            points.append(point)
        }
        // Firmer than build 35 ("a bit too faint on my phone").
        return CurrentPoints(points: points, dot: dot, opacity: 0.42 + frame.coherence * 0.2)
    }

    static func sourcePoint(family: PresenceForm, sourceIndex: Double,
                                    time: Double) -> CGPoint {
        switch family {
        case .drift:
            return driftPoint(sourceIndex: sourceIndex, time: time)
        case .depth:
            return depthPoint(sourceIndex: sourceIndex, time: time)
        case .singular:
            return singularPoint(sourceIndex: sourceIndex, time: time)
        case .weave, .bloom, .knot:
            return projectedOriginalPoint(family: family, sourceIndex: sourceIndex,
                                          time: time)
        }
    }

    /// Inspiration one: a vertically drifting body with long gestures.
    private static func driftPoint(sourceIndex: Double, time: Double) -> CGPoint {
        let y = sourceIndex / 253
        let k = 5 * cos(sourceIndex / 56)
        let e = y / 3 - 16
        let d = hypot(k, e) / 3
        let c = d / 2 - time / 3
        let denominator = y < 9 ? 7 : safe(203 * sin(e / 2))
        return CGPoint(
            x: (d * 19 + 29 + k * k) * sin(c) + 200,
            y: 66 * sin(c / 3) + 4 * sin(k * 2)
                + pow(d, 3) / 3 * sin(time * 3 - d * d / 4)
                + y / denominator * k * e + 200
        )
    }

    /// Inspiration two: a gridded field folded through tangent and radial terms.
    private static func depthPoint(sourceIndex: Double, time: Double) -> CGPoint {
        let xIndex = Double(Int(sourceIndex) % 100)
        let y = sourceIndex / 233
        let k = xIndex / 4 - 12.5
        let e = y / 9 + 6
        let o = hypot(k, e) / 9
        let q = 3 * (tan(y / 2) / 2 + cos(y)) / safe(k)
            + k * (5 / o + o * sin(y) * sin(e + o * 4 - time))
        let c = o / 2 + e / 2 - time / 4
        return CGPoint(x: q + 40 * cos(c) + 200,
                       y: q * sin(c) - k * k * o / 6 + e * o * 12)
    }

    /// Inspiration three: a controlled singular term produces needles and edges.
    private static func singularPoint(sourceIndex: Double, time: Double) -> CGPoint {
        let y = sourceIndex / 265
        let k = (4 + cos(y - time)) * cos(sourceIndex / 29)
        let e = y / 6 - 13
        let d = pow(hypot(k, e), 2) / 22
        let q = 3 * sin(k * 2) + 0.3 / safe(k)
            + y / 22 * k * (9 + 2 * sin(e * 49 - d * 4 + time))
        let c = d - time / 2
        return CGPoint(x: q + 50 * cos(c) + 200,
                       y: q * sin(c) + d * 40 + 40 * sin(time / 4 + e + 4))
    }

    private static func projectedOriginalPoint(family: PresenceForm,
                                               sourceIndex: Double,
                                               time: Double) -> CGPoint {
        let y = sourceIndex / 500
        let k = cos(y * 9) * (y < 9 ? sin(time + y) * 28 : 11)
        let e = y / 8 - 13
        let o = hypot(k, e) / 6
        let q = k * y / 15 + 79
            + k * sin(y) * (1 + sin(o * 4 - e - time * 8))
        let c = o / 2 - e / 4 - time

        switch family {
        case .weave:
            let thread = c + sin(y * 0.46 + time) * 0.13
            return CGPoint(x: 200 + q * 0.82 * sin(thread * 2)
                           + 28 * sin(thread / 3),
                           y: 200 + q * 0.68 * cos(thread * 3))
        case .bloom:
            let petal = 0.34 + 0.72 * abs(cos(c * 2.5 + time * 0.18))
            return CGPoint(x: 200 + q * 1.35 * petal * sin(c),
                           y: 200 + q * 1.35 * petal * cos(c) * 0.9)
        case .knot:
            let s = sin(c)
            let denominator = 1 + s * s
            return CGPoint(x: 200 + q * 1.54 * cos(c) / denominator,
                           y: 200 + q * 2.06 * s * cos(c) / denominator)
        default:
            return CGPoint(x: 200, y: 200)
        }
    }

    private static func safe(_ value: Double) -> Double {
        guard abs(value) < 0.025 else { return value }
        return value < 0 ? -0.025 : 0.025
    }
}
