import SwiftUI

/// One mathematical body for Alicia, expressed through six visibly distinct
/// geometric families. Archetype chooses the family and native tempo;
/// attention controls density, opacity, gathering, and response to focus.
struct AliciaPresence: View {
    enum State: String, CaseIterable, Identifiable {
        case resting = "RESTING"
        case listening = "LISTENING"
        case thinking = "THINKING"

        var id: String { rawValue }

        fileprivate var tempoScale: Double {
            switch self {
            case .resting: 0.72
            case .listening: 1.0
            case .thinking: 1.18
            }
        }
    }

    enum Voice: String, CaseIterable, Identifiable {
        case beatrice
        case ariadne
        case psyche
        case daimon
        case muse
        case musubi

        var id: String { rawValue }
        var name: String { rawValue.uppercased() }

        var role: String {
            switch self {
            case .beatrice: "THE KEEPER OF THE FLAME"
            case .ariadne: "THE THREAD-WEAVER"
            case .psyche: "THE DEPTH-DIVER"
            case .daimon: "THE EDGE IN THE DARK"
            case .muse: "THE PLAYFUL SPARK"
            case .musubi: "THE KNOT THAT BINDS"
            }
        }

        fileprivate var configuration: Configuration {
            switch self {
            case .beatrice:
                Configuration(family: .drift, tempo: 1.20,
                              basePoints: 1_200, sourceCount: 10_000,
                              stillPhase: 2.4)
            case .ariadne:
                Configuration(family: .weave, tempo: 1.00,
                              basePoints: 1_450, sourceCount: 20_000,
                              stillPhase: 4.1)
            case .psyche:
                Configuration(family: .depth, tempo: 1.40,
                              basePoints: 1_650, sourceCount: 20_000,
                              stillPhase: 5.2)
            case .daimon:
                Configuration(family: .singular, tempo: 1.80,
                              basePoints: 1_100, sourceCount: 10_000,
                              stillPhase: 3.3)
            case .muse:
                Configuration(family: .bloom, tempo: 1.50,
                              basePoints: 1_100, sourceCount: 20_000,
                              stillPhase: 1.6)
            case .musubi:
                Configuration(family: .knot, tempo: 0.90,
                              basePoints: 1_750, sourceCount: 20_000,
                              stillPhase: 4.7)
            }
        }
    }

    struct Metrics: Equatable {
        let tempo: Double
        let pointCount: Int
        let framesPerSecond: Int
    }

    struct Audit: Equatable {
        let total: Int
        let finite: Int
        let visible: Int
        let visibleBounds: CGRect?

        var visibleFraction: Double {
            total == 0 ? 0 : Double(visible) / Double(total)
        }

        /// Outliers are part of the source equations and are clipped before
        /// drawing. A safe body is wholly finite and mostly on the page.
        var isSafe: Bool {
            finite == total && visibleFraction >= 0.72 && visibleBounds != nil
        }
    }

    struct AuditSummary: Equatable {
        let combinations: Int
        let failures: Int
        let lowestVisibleFraction: Double

        var isSafe: Bool { failures == 0 }
    }

    fileprivate enum Family {
        case drift
        case weave
        case depth
        case singular
        case bloom
        case knot
    }

    fileprivate struct Configuration {
        let family: Family
        let tempo: Double
        let basePoints: Int
        let sourceCount: Int
        let stillPhase: Double
    }

    private struct Mapping {
        let tempo: Double
        let points: Int
        let contraction: Double
        let opacity: Double
    }

    static let framesPerSecond = 15

    var voice: Voice = .ariadne
    var state: State = .listening
    var attention: Double = 0.72
    /// A normalized point that the body gathers toward as attention rises.
    var focus: UnitPoint?
    /// Set for deterministic stills and phase-by-phase lab inspection.
    var phase: Double?
    /// A future product surface can turn this off while covered or offscreen.
    var isActive = true
    var showsConstruction = false
    /// DEBUG lab seam for exercising the intentional still state even when
    /// the simulator's system Reduce Motion setting is off.
    var previewsReduceMotion = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        let shouldReduceMotion = reduceMotion || previewsReduceMotion
        let paused = phase != nil || shouldReduceMotion || !isActive || scenePhase != .active
        TimelineView(.animation(
            minimumInterval: 1.0 / Double(Self.framesPerSecond),
            paused: paused
        )) { timeline in
            Canvas(opaque: false, colorMode: .linear,
                   rendersAsynchronously: true) { context, size in
                let mapping = Self.mapping(for: voice, state: state,
                                           attention: attention)
                let time: Double
                if let phase {
                    time = phase
                } else if shouldReduceMotion || !isActive || scenePhase != .active {
                    time = voice.configuration.stillPhase
                } else {
                    let seconds = timeline.date.timeIntervalSinceReferenceDate
                        .truncatingRemainder(dividingBy: 10_000)
                    time = seconds * (.pi / 4) * mapping.tempo
                }
                Self.draw(
                    in: &context,
                    size: size,
                    voice: voice,
                    state: state,
                    attention: attention,
                    focus: focus,
                    time: time,
                    showsConstruction: showsConstruction
                )
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "Alicia as \(voice.name.capitalized), \(state.rawValue.lowercased())"
        )
    }

    static func metrics(for voice: Voice, state: State,
                        attention: Double) -> Metrics {
        let mapping = mapping(for: voice, state: state, attention: attention)
        return Metrics(tempo: mapping.tempo, pointCount: mapping.points,
                       framesPerSecond: framesPerSecond)
    }

    static func audit(voice: Voice, state: State, attention: Double,
                      phase: Double, focus: UnitPoint? = nil,
                      size: CGSize = CGSize(width: 400, height: 400)) -> Audit {
        let mapping = mapping(for: voice, state: state, attention: attention)
        let frame = CGRect(origin: .zero, size: size)
        var finite = 0
        var visible = 0
        var bounds: CGRect?

        for index in 1...mapping.points {
            guard let point = mappedPoint(index: index, total: mapping.points,
                                          voice: voice, attention: attention,
                                          contraction: mapping.contraction,
                                          focus: focus, time: phase, size: size) else {
                continue
            }
            finite += 1
            guard frame.contains(point) else { continue }
            visible += 1
            let dot = CGRect(x: point.x, y: point.y, width: 1, height: 1)
            bounds = bounds?.union(dot) ?? dot
        }
        return Audit(total: mapping.points, finite: finite, visible: visible,
                     visibleBounds: bounds)
    }

    /// Audits every semantic combination at representative phases. This is
    /// intentionally callable from the DEBUG lab before screenshots or review.
    static func auditAll(attention: Double,
                         size: CGSize = CGSize(width: 400, height: 400)) -> AuditSummary {
        let phases = [0.0, 1.7, 3.4, 5.1]
        var combinations = 0
        var failures = 0
        var lowestVisible = 1.0
        for voice in Voice.allCases {
            for state in State.allCases {
                for phase in phases {
                    let result = audit(voice: voice, state: state,
                                       attention: attention, phase: phase,
                                       size: size)
                    combinations += 1
                    lowestVisible = min(lowestVisible, result.visibleFraction)
                    if !result.isSafe { failures += 1 }
                }
            }
        }
        return AuditSummary(combinations: combinations, failures: failures,
                            lowestVisibleFraction: lowestVisible)
    }

    private static func mapping(for voice: Voice, state: State,
                                attention: Double) -> Mapping {
        let configuration = voice.configuration
        let focus = min(1, max(0, attention))
        let tempo = configuration.tempo
            * (0.80 + focus * 0.40)
            * state.tempoScale
        let points = min(2_800, max(700, Int(
            (Double(configuration.basePoints) * (0.58 + focus * 1.04)).rounded()
        )))
        return Mapping(tempo: tempo, points: points,
                       contraction: 1.08 - focus * 0.13,
                       opacity: 0.28 + focus * 0.16)
    }

    private static func draw(in context: inout GraphicsContext, size: CGSize,
                             voice: Voice, state: State, attention: Double,
                             focus: UnitPoint?, time: Double,
                             showsConstruction: Bool) {
        let mapping = mapping(for: voice, state: state, attention: attention)
        let frame = CGRect(origin: .zero, size: size)
        let dotSize = max(0.65, min(size.width, size.height) / 400)
        var points = Path()

        for index in 1...mapping.points {
            guard let point = mappedPoint(index: index, total: mapping.points,
                                          voice: voice, attention: attention,
                                          contraction: mapping.contraction,
                                          focus: focus, time: time, size: size),
                  frame.contains(point) else { continue }
            points.addRect(CGRect(x: point.x, y: point.y,
                                  width: dotSize, height: dotSize))
        }
        // One fill call for the entire field: thousands of point calculations,
        // but one Canvas operation at a capped 15 frames per second.
        context.fill(points, with: .color(Theme.ink.opacity(mapping.opacity)))

        guard showsConstruction else { return }
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        var axes = Path()
        axes.move(to: CGPoint(x: center.x, y: 0))
        axes.addLine(to: CGPoint(x: center.x, y: size.height))
        axes.move(to: CGPoint(x: 0, y: center.y))
        axes.addLine(to: CGPoint(x: size.width, y: center.y))
        context.stroke(axes, with: .color(Theme.accent.opacity(0.22)),
                       style: StrokeStyle(lineWidth: 0.6, dash: [3, 5]))
        if let focus {
            let target = CGPoint(x: focus.x * size.width, y: focus.y * size.height)
            var line = Path()
            line.move(to: center)
            line.addLine(to: target)
            context.stroke(line, with: .color(Theme.rose.opacity(0.45)),
                           style: StrokeStyle(lineWidth: 0.7, dash: [2, 4]))
        }
    }

    private static func mappedPoint(index: Int, total: Int, voice: Voice,
                                    attention: Double, contraction: Double,
                                    focus: UnitPoint?,
                                    time: Double, size: CGSize) -> CGPoint? {
        let configuration = voice.configuration
        let sourceIndex = Double(index) * Double(configuration.sourceCount)
            / Double(total)
        let raw = sourcePoint(family: configuration.family,
                              sourceIndex: sourceIndex, time: time)
        guard raw.x.isFinite, raw.y.isFinite else { return nil }

        var reference = CGPoint(
            x: 200 + (raw.x - 200) * contraction,
            y: 200 + (raw.y - 200) * contraction
        )
        if let focus {
            let target = CGPoint(x: focus.x * 400, y: focus.y * 400)
            let dx = target.x - reference.x
            let dy = target.y - reference.y
            let distance = max(1, hypot(dx, dy))
            let amount = min(1, 150 / distance) * min(1, max(0, attention)) * 0.085
            reference.x += dx * amount
            reference.y += dy * amount
        }

        let side = min(size.width, size.height)
        let origin = CGPoint(x: (size.width - side) / 2,
                             y: (size.height - side) / 2)
        let point = CGPoint(x: origin.x + reference.x / 400 * side,
                            y: origin.y + reference.y / 400 * side)
        guard point.x.isFinite, point.y.isFinite else { return nil }
        return point
    }

    private static func sourcePoint(family: Family, sourceIndex: Double,
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

    private static func projectedOriginalPoint(family: Family,
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

#Preview("Alicia Presence") {
    AliciaPresence(voice: .ariadne, state: .listening, attention: 0.72,
                   focus: UnitPoint(x: 0.72, y: 0.32), phase: 4.2,
                   showsConstruction: false)
        .frame(width: 360, height: 520)
        .background(Theme.backdrop)
        .preferredColorScheme(.light)
}
