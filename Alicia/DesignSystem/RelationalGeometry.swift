#if DEBUG
import Foundation

/// The four recovered equations. Shared fixtures bind these to the room renderer.
enum RelationalGeometry {
    static let count = 2400
    static let populations = [20000.0, 10000, 20000, 10000]
    static let nativeRates = [Double.pi / 4, .pi * 0.75, .pi * 2, .pi]
    static let initialPhases = [2.4, 2.4, 4.2, 3.3]
    static func safe(_ x: Double) -> Double { abs(x) < 0.025 ? (x < 0 ? -0.025 : 0.025) : x }
    static func bound(_ x: Double) -> Double {
        let d = x - 200
        return abs(d) <= 230 ? x : 200 + (d < 0 ? -1 : 1) * (230 + 65 * tanh((abs(d) - 230) / 65))
    }
    static func sample(_ family: Int, _ index: Int) -> Double {
        let i = Double(index)
        return 1 + floor((i + (i * 0.618033988749895 + 0.173).truncatingRemainder(dividingBy: 1)) * ((populations[family] - 1) / Double(count)))
    }
    static func point(_ family: Int, _ i: Double, _ t: Double) -> CGPoint {
        if family == 0 {
            let y = i / 500, k = cos(y * 9) * (y < 9 ? sin(t + y) * 28 : 11), e = y / 8 - 13
            let o = hypot(k, e) / 6, q = k * y / 15 + 79 + k * sin(y) * (1 + sin(o * 4 - e - t * 8))
            let c = o / 2 - e / 4 - t
            return CGPoint(x: q * sin(c) + 70 * sin(c / 3) + 200, y: 200 + q / 0.7 * cos(c))
        }
        if family == 1 {
            let y = i / 253, k = 5 * cos(i / 56), e = y / 3 - 16, d = hypot(k, e) / 3, c = d / 2 - t / 3
            let x = (d * 19 + 29 + k * k) * sin(c) + 200
            let y0 = 66 * sin(c / 3) + 4 * sin(k * 2) + pow(d, 3) / 3 * sin(t * 3 - d * d / 4)
            return CGPoint(x: x, y: y0 + y / (y < 9 ? 7 : safe(203 * sin(e / 2))) * k * e + 200)
        }
        if family == 2 {
            let y = i / 233, k = i.truncatingRemainder(dividingBy: 100) / 4 - 12.5, e = y / 9 + 6, o = hypot(k, e) / 9
            let q = 3 * (tan(y / 2) / 2 + cos(y)) / safe(k) + k * (5 / o + o * sin(y) * sin(e + o * 4 - t))
            let c = o / 2 + e / 2 - t / 4
            return CGPoint(x: q + 40 * cos(c) + 200, y: q * sin(c) - k * k * o / 6 + e * o * 12)
        }
        let y = i / 265, k = (4 + cos(y - t)) * cos(i / 29), e = y / 6 - 13, d = pow(hypot(k, e), 2) / 22
        let q = 3 * sin(k * 2) + 0.3 / safe(k) + y / 22 * k * (9 + 2 * sin(e * 49 - d * 4 + t))
        let c = d - t / 2
        return CGPoint(x: q + 50 * cos(c) + 200, y: q * sin(c) + d * 40 + 40 * sin(t / 4 + e + 4))
    }

    struct Parameters: Equatable, Sendable {
        var weights: [Double], rates: [Double]
        var spread: Double, aspect: Double, lean: Double, tilt: Double, level: Double
        init(_ fact: LivePresenceFact = .unavailable) {
            let expression = fact.expression
            let family = ["witness": 0, "ask": 2, "offer": 1, "celebrate": 1, "hold": 0, "challenge": 3][expression.stance] ?? 0
            func unit(_ x: Double, _ fallback: Double) -> Double { x.isFinite ? min(1, max(0, x)) : fallback }
            let states: [String: [Double]] = ["resting": [0.86, 0.77, 1, 0.025], "listening": [1.06, 0.94, 1.03, -0.025],
                "thinking": [0.77, 1.06, 0.91, 0.015], "speaking": [1, 1.12, 1.03, -0.01], "unavailable": [0.82, 0.6, 1, 0.025]]
            let state = states[fact.activity] ?? states["unavailable"]!
            let tempo = (0.4 + unit(expression.energy, 0.4) * 0.6) * (expression.stance == "hold" ? 0.78 : 1) * state[1]
            weights = (0..<4).map { $0 == family ? 1 : 0 }
            rates = nativeRates.enumerated().map { $0.element * tempo * [1.0, 0.67, 0.44, 0.58][$0.offset] }
            spread = (0.94 + unit(expression.openness, 0.6) * 0.12) * state[0]
            aspect = state[2]; lean = state[3]
            tilt = expression.stance == "ask" ? -0.045 : expression.stance == "challenge" ? 0.015 : 0
            level = ["listening", "speaking"].contains(fact.activity) ? unit(fact.level, 0) : 0
        }
    }
    struct Frame: Sendable {
        var parameters: Parameters
        var phases: [Double]
    }
    static func positions(_ frame: Frame, size: CGSize) -> [(CGPoint, Int)] {
        let f = frame.parameters, side = min(size.width * 0.94, size.height * 1.12)
        let cx = size.width * 0.5, cy = size.height * 0.5 + f.lean * side, ca = cos(f.tilt), sa = sin(f.tilt)
        var result: [(CGPoint, Int)] = []
        result.reserveCapacity(count)
        for i in 0..<count {
            var x = 0.0, y = 0.0
            for family in 0..<4 where f.weights[family] > 0.0000001 {
                let p = point(family, sample(family, i), frame.phases[family])
                x += bound(p.x) * f.weights[family]; y += bound(p.y) * f.weights[family]
            }
            x -= 200; y -= 200
            let edge = exp(-pow((y + 65) / 120, 2)), ripple = f.level * edge
            x *= f.spread * f.aspect * (1 + ripple * 0.075)
            y *= f.spread / f.aspect * (1 + ripple * 0.045)
            let p = CGPoint(x: cx + (x * ca - y * sa) / 400 * side, y: cy + (x * sa + y * ca) / 400 * side)
            if p.x.isFinite && p.y.isFinite && p.x >= 0 && p.y >= 0 && p.x < size.width && p.y < size.height { result.append((p, i)) }
        }
        return result
    }
}

struct RelationalMotion {
    private var from = RelationalGeometry.Parameters()
    private var to = RelationalGeometry.Parameters()
    private var phases = RelationalGeometry.initialPhases
    private var anchor: Double
    init(now: Double) { anchor = now }
    func frame(now: Double, reduced: Bool = false) -> RelationalGeometry.Frame {
        let t = max(0, now-anchor), tau = 1.15, e = reduced ? 1 : 1-exp(-t/tau), fast = reduced ? 1 : 1-exp(-t/0.38)
        func mix(_ a: Double, _ b: Double, _ q: Double) -> Double { a + (b-a)*q }
        var p = from
        p.weights = zip(from.weights, to.weights).map { mix($0, $1, e) }
        p.rates = zip(from.rates, to.rates).map { mix($0, $1, e) }
        p.spread = mix(from.spread, to.spread, fast); p.aspect = mix(from.aspect, to.aspect, fast)
        p.lean = mix(from.lean, to.lean, fast); p.tilt = mix(from.tilt, to.tilt, fast)
        p.level = reduced ? 0 : mix(from.level, to.level, 1-exp(-t/(to.level > from.level ? 0.045 : 0.24)))
        let phase = reduced ? RelationalGeometry.initialPhases : phases.enumerated().map { i, value in
            value + from.rates[i]*t + (to.rates[i]-from.rates[i])*(t-tau*(1-exp(-t/tau)))
        }
        return .init(parameters: p, phases: phase)
    }
    mutating func update(_ fact: LivePresenceFact, now: Double) {
        let next = RelationalGeometry.Parameters(fact)
        guard next != to else { return }
        let current = frame(now: now)
        from = current.parameters; phases = current.phases; to = next; anchor = now
    }
}
#endif
