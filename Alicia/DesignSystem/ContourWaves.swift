import SwiftUI

/// The animated contour field from fromfutureself.com, ported from the
/// site's canvas implementation (Playground/script.js): six drifting wave
/// sources per side create a scalar field; marching squares traces its
/// contour levels as faint ink lines that slowly breathe across the paper.
/// Rendered with TimelineView + Canvas, tuned down (fewer levels, coarser
/// grid, 12 fps) so it sips battery instead of drinking it.
struct ContourWaves: View {
    struct Source {
        var anchorX, anchorY, ampX, ampY, driftX, driftY, phase, strength, falloff: Double
    }

    /// Two vocabularies: the topographic contour sea, and expanding
    /// ripples — rings spreading from drifting centers (squash < 1 turns
    /// them into sonar ellipses, a sound-wave feel).
    enum Pattern {
        case contour
        case ripple(squash: Double)
    }

    /// Each tab gets a sister field — same sea, different weather.
    struct Config {
        var speed: Double        // drift multiplier
        var levels: Int          // contour density
        var alphaScale: Double   // ink weight
        var seedOffset: Int      // reshapes the source layout
        var crossBoost: Double   // horizontal current (waveform feel)
        var pattern: Pattern = .contour

        /// Us — the full balanced field.
        static func us(mood: Int = 0) -> Config {
            Config(speed: 1.0, levels: 8, alphaScale: 1.0,
                   seedOffset: mood, crossBoost: 1.0)
        }
        /// Dialogue — barely-there water; the words carry the page.
        static func dialogue(mood: Int = 0) -> Config {
            Config(speed: 0.45, levels: 4, alphaScale: 0.6,
                   seedOffset: 5 + mood, crossBoost: 0.5)
        }
        /// Alicia — thought radiating outward: slow round ripples.
        static func mind(mood: Int = 0) -> Config {
            Config(speed: 0.35, levels: 13, alphaScale: 1.0,
                   seedOffset: 9 + mood, crossBoost: 0.8,
                   pattern: .ripple(squash: 1.0))
        }
        /// Studio — sonar: fast ripples squashed into sound-wave ellipses.
        static func studio(mood: Int = 0) -> Config {
            Config(speed: 1.2, levels: 5, alphaScale: 0.9,
                   seedOffset: 13 + mood, crossBoost: 3.2,
                   pattern: .ripple(squash: 0.42))
        }

        /// The day breathes through every field: brisk mornings, still
        /// nights. Applied on top of the section speed.
        static var timeOfDayFactor: Double {
            switch Calendar.current.component(.hour, from: .now) {
            case 5..<11:  return 1.15
            case 11..<17: return 1.0
            case 17..<22: return 0.65
            default:      return 0.45
            }
        }

        /// Night inks the lines darker — dusk gathers, morning rinses.
        static var inkFactor: Double {
            switch Calendar.current.component(.hour, from: .now) {
            case 5..<11:  return 0.85
            case 11..<17: return 1.0
            case 17..<22: return 1.25
            default:      return 1.5
            }
        }

        /// The season lives in the field too: summer runs dense, winter
        /// sparse and slow; the layout itself re-seeds every month.
        static var season: (levelsDelta: Int, speed: Double, seed: Int) {
            let month = Calendar.current.component(.month, from: .now)
            switch month {
            case 12, 1, 2: return (-2, 0.85, month)   // winter — spare, slow
            case 3...5:    return (+1, 1.10, month)   // spring — quickening
            case 6...8:    return (+2, 1.00, month)   // summer — full water
            default:       return (0, 0.90, month)    // autumn — settling
            }
        }
    }

    var config: Config = .us()

    /// Deterministic "randomness" — a fixed unit-interval table, so the
    /// field needs no @State/onAppear lifecycle (which never fired inside
    /// a .background container) and every launch breathes the same sea.
    private static let jitter: [Double] = [
        0.83, 0.19, 0.55, 0.42, 0.91, 0.07, 0.66, 0.31, 0.74, 0.48,
        0.12, 0.95, 0.27, 0.61, 0.38, 0.86, 0.03, 0.70, 0.52, 0.24,
        0.79, 0.15, 0.58, 0.44,
    ]
    private static func j(_ n: Int) -> Double { jitter[abs(n) % jitter.count] }

    private static func buildSide(_ side: Int, size: CGSize, seedOffset: Int) -> [Source] {
        (0..<6).map { i in
            let fi = Double(i)
            let base = side * 6 + i + seedOffset
            func r(_ k: Int, _ lo: Double, _ hi: Double) -> Double {
                lo + (hi - lo) * j(base * 4 + k)
            }
            return Source(
                anchorX: side == 0
                    ? size.width * (0.16 + fi * 0.055 + 0.03 * j(base))
                    : size.width * (0.84 - fi * 0.055 - 0.03 * j(base)),
                anchorY: size.height * (0.14 + fi * 0.14 + 0.05 * j(base + 7)),
                ampX: size.width * r(0, 0.05, 0.085),
                ampY: size.height * r(1, 0.025, 0.07),
                driftX: r(2, 0.20, 0.48),
                driftY: r(3, 0.18, 0.42),
                phase: 2 * .pi * j(base + 13),
                strength: r(1, 0.9, 1.8),
                falloff: r(2, 145, 190))
        }
    }

    private func sample(_ x: Double, _ y: Double, t: Double,
                        leftSources: [Source], rightSources: [Source]) -> Double {
        var value = 0.0
        for (sources, direction) in [(leftSources, 1.0), (rightSources, -1.0)] {
            for s in sources {
                let ax = s.anchorX + sin(t * s.driftX + s.phase) * s.ampX
                let ay = s.anchorY + cos(t * s.driftY + s.phase) * s.ampY
                let d = ((x - ax) * (x - ax) + (y - ay) * (y - ay)).squareRoot()
                value += sin(d * 0.022 - t * 0.9 + s.phase) * s.strength
                value += direction * s.falloff / (d + 120)
            }
        }
        let cross = (sin(y * 0.011 + t * 0.6) * 0.55
                  + cos(x * 0.008 - t * 0.55) * 0.45
                  + sin((x + y) * 0.0036 + t * 0.35) * 0.35) * config.crossBoost
        return value * 0.58 + cross
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 12.0)) { timeline in
            Canvas { context, size in
                    let season = Config.season
                    let seed = config.seedOffset + season.seed
                    let leftSources = Self.buildSide(0, size: size,
                                                     seedOffset: seed)
                    let rightSources = Self.buildSide(1, size: size,
                                                      seedOffset: seed)
                    let t = timeline.date.timeIntervalSinceReferenceDate
                        .truncatingRemainder(dividingBy: 86_400)
                        * config.speed * Config.timeOfDayFactor * season.speed

                    // Ripples: rings spreading from four drifting centers.
                    if case .ripple(let squash) = config.pattern {
                        let centers = (Array(leftSources.prefix(2)) +
                                       Array(rightSources.prefix(2))).map { s in
                            CGPoint(
                                x: s.anchorX + sin(t * s.driftX + s.phase) * s.ampX,
                                y: s.anchorY + cos(t * s.driftY + s.phase) * s.ampY)
                        }
                        let spacing = 36.0
                        let maxR = max(size.width, size.height) * 0.7
                        let phase = (t * 10).truncatingRemainder(dividingBy: spacing)
                        for c in centers {
                            var r = phase
                            while r < maxR {
                                let fade = 1 - r / maxR
                                let alpha = (0.08 + 0.18 * fade)
                                    * config.alphaScale * Config.inkFactor
                                var ring = Path()
                                ring.addEllipse(in: CGRect(
                                    x: c.x - r, y: c.y - r * squash,
                                    width: 2 * r, height: 2 * r * squash))
                                context.stroke(
                                    ring,
                                    with: .color(Theme.ink.opacity(min(0.5, alpha))),
                                    lineWidth: 0.9)
                                r += spacing
                            }
                        }
                        return
                    }
                    let cell = max(18.0, min(24.0, size.width / 18))
                    let cols = Int(size.width / cell) + 2
                    let rows = Int(size.height / cell) + 2

                    var values = [[Double]](
                        repeating: [Double](repeating: 0, count: cols), count: rows)
                    for r in 0..<rows {
                        for c in 0..<cols {
                            values[r][c] = sample(Double(c) * cell, Double(r) * cell, t: t,
                                                  leftSources: leftSources,
                                                  rightSources: rightSources)
                        }
                    }

                    let n = max(3, config.levels + season.levelsDelta)
                    let levels: [Double] = (0..<n).map { i in
                        -1.35 + 2.7 * Double(i) / Double(n - 1)
                    }
                    for level in levels {
                        var path = Path()
                        for r in 0..<(rows - 1) {
                            for c in 0..<(cols - 1) {
                                let x = Double(c) * cell, y = Double(r) * cell
                                let corners = [
                                    (CGPoint(x: x, y: y), values[r][c]),
                                    (CGPoint(x: x + cell, y: y), values[r][c + 1]),
                                    (CGPoint(x: x + cell, y: y + cell), values[r + 1][c + 1]),
                                    (CGPoint(x: x, y: y + cell), values[r + 1][c]),
                                ]
                                var hits: [CGPoint] = []
                                for i in 0..<4 {
                                    let (pa, va) = corners[i]
                                    let (pb, vb) = corners[(i + 1) % 4]
                                    if (va < level) != (vb < level) {
                                        let ratio = (level - va) / (vb - va)
                                        hits.append(CGPoint(
                                            x: pa.x + (pb.x - pa.x) * ratio,
                                            y: pa.y + (pb.y - pa.y) * ratio))
                                    }
                                }
                                if hits.count >= 2 {
                                    path.move(to: hits[0]); path.addLine(to: hits[1])
                                }
                                if hits.count == 4 {
                                    path.move(to: hits[2]); path.addLine(to: hits[3])
                                }
                            }
                        }
                        // Site palette: rgba(191,178,189) on #fffaff — here the
                        // ink tone on our bone paper. Phone screens wash out
                        // faster than the desktop canvas, so ink runs heavier.
                        let alpha = (0.20 + 0.14 * ((level + 1.35) / 2.7))
                            * config.alphaScale * Config.inkFactor
                        context.stroke(path,
                                       with: .color(Theme.ink.opacity(min(0.6, alpha))),
                                       lineWidth: 1.0)
                    }
            }
        }
        .allowsHitTesting(false)
    }
}

extension Theme {
    /// The hour's color, washed over the paper — dawn rose, midday clear,
    /// dusk amber, night indigo. Low-alpha so the paper stays paper.
    static var timeTint: LinearGradient {
        let colors: [Color]
        switch Calendar.current.component(.hour, from: .now) {
        case 5..<8:   colors = [Color(red: 0.93, green: 0.58, blue: 0.50).opacity(0.38),
                                Color(red: 0.95, green: 0.80, blue: 0.60).opacity(0.10)] // dawn rose
        case 8..<11:  colors = [Color(red: 0.95, green: 0.80, blue: 0.45).opacity(0.30),
                                Color(red: 0.95, green: 0.88, blue: 0.66).opacity(0.08)] // morning gold
        case 11..<16: colors = [Color(red: 0.62, green: 0.76, blue: 0.83).opacity(0.26),
                                Color(red: 0.80, green: 0.86, blue: 0.86).opacity(0.07)] // midday sky
        case 16..<19: colors = [Color(red: 0.90, green: 0.60, blue: 0.32).opacity(0.34),
                                Color(red: 0.92, green: 0.76, blue: 0.52).opacity(0.10)] // late ochre
        case 19..<22: colors = [Color(red: 0.66, green: 0.38, blue: 0.38).opacity(0.40),
                                Color(red: 0.28, green: 0.30, blue: 0.44).opacity(0.16)] // dusk
        default:      colors = [Color(red: 0.22, green: 0.25, blue: 0.42).opacity(0.44),
                                Color(red: 0.30, green: 0.26, blue: 0.38).opacity(0.18)] // night indigo
        }
        return LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
    }
}

/// Fine paper grain — a static field of ink specks, like cold-press tooth.
struct PaperGrain: View {
    var density: Int = 1400
    var body: some View {
        Canvas { context, size in
            var state: UInt64 = 0x9E3779B97F4A7C15
            func rnd() -> Double {
                state = state &* 6364136223846793005 &+ 1442695040888963407
                return Double(state >> 11) / Double(UInt64(1) << 53)
            }
            for _ in 0..<density {
                let x = rnd() * size.width
                let y = rnd() * size.height
                let r = 0.4 + rnd() * 0.9
                let a = 0.03 + rnd() * 0.05
                context.fill(
                    Path(ellipseIn: CGRect(x: x, y: y, width: r, height: r)),
                    with: .color(Theme.ink.opacity(a)))
            }
        }
        .allowsHitTesting(false)
    }
}

/// A generative engraving in the Co-Star register: a stippled form built
/// from thousands of ink dots inside a noise-distorted blob. Seeded by the
/// day of year, so the object on the page is never quite yesterday's.
struct StippleIllustration: View {
    var seed: Int = Calendar.current.ordinality(of: .day, in: .year, for: .now) ?? 1
    var dots: Int = 2400
    /// When true the form breathes — lobes drift and the grain shimmers
    /// (8 fps; used on the vitals page).
    var animated: Bool = false

    var body: some View {
        if animated {
            TimelineView(.animation(minimumInterval: 1.0 / 8.0)) { timeline in
                canvas(t: timeline.date.timeIntervalSinceReferenceDate
                    .truncatingRemainder(dividingBy: 86_400))
            }
        } else {
            canvas(t: 0)
        }
    }

    private func canvas(t: TimeInterval) -> some View {
        Canvas { context, size in
            var state = UInt64(truncatingIfNeeded: seed &* 2654435761 &+ 97)
            func rnd() -> Double {
                state = state &* 6364136223846793005 &+ 1442695040888963407
                return Double(state >> 11) / Double(UInt64(1) << 53)
            }
            let cx = size.width / 2, cy = size.height / 2
            // Her heart: a lub-dub every ~1.1 s when animated — two quick
            // swells then rest, like a pulse felt at the wrist.
            var beat = 0.0
            if t > 0 {
                let phase = (t * 0.9).truncatingRemainder(dividingBy: 1.0)
                let lub = exp(-pow((phase - 0.12) * 14, 2))
                let dub = exp(-pow((phase - 0.38) * 14, 2)) * 0.6
                beat = (lub + dub) * 0.085
            }
            let R = min(size.width, size.height) * 0.42 * (1.0 + beat)
            let k3 = 2.0 + rnd() * 3.0        // lobes
            let k5 = 1.0 + rnd() * 4.0
            // The lobes drift very slowly when animated — a form breathing.
            let p3 = rnd() * .pi * 2 + t * 0.10
            let p5 = rnd() * .pi * 2 - t * 0.07
            func edge(_ theta: Double) -> Double {
                R * (0.66
                     + 0.22 * sin(k3 * theta + p3)
                     + 0.12 * sin(k5 * theta + p5))
            }
            var i = 0
            for _ in 0..<dots {
                i += 1
                let theta = rnd() * .pi * 2
                // Bias density toward the rim — engraved shading.
                let rho = pow(rnd(), 0.42) * edge(theta)
                let x = cx + cos(theta) * rho
                let y = cy + sin(theta) * rho * 0.92
                let nearEdge = rho / edge(theta)
                let r = 0.5 + rnd() * (0.6 + nearEdge * 0.9)
                var a = 0.25 + nearEdge * 0.55 + rnd() * 0.15
                if t > 0 {
                    // Grain shimmer: each dot has its own slow phase.
                    a *= 0.78 + 0.22 * sin(t * 1.4 + Double(i) * 0.61)
                }
                context.fill(
                    Path(ellipseIn: CGRect(x: x, y: y, width: r, height: r)),
                    with: .color(Theme.ink.opacity(min(0.9, max(0.05, a)))))
            }
        }
        .allowsHitTesting(false)
    }
}

extension View {
    /// Paper + a breathing field behind a section. `tinted` washes the
    /// hour's color over the paper and lays fine grain on top (Us page).
    func waveBackground(_ config: ContourWaves.Config,
                        tinted: Bool = false) -> some View {
        background {
            ZStack {
                Theme.backdrop
                if tinted { Theme.timeTint }
                ContourWaves(config: config)
                if tinted { PaperGrain() }
            }
            .ignoresSafeArea()
        }
    }
}

extension AppStore {
    /// A stable seed from her current weather — the dominant archetype of
    /// the latest proactive message (falls back to day-of-year). The wave
    /// fields literally reshape with her mood.
    var waveMood: Int {
        let key = proactiveFeed.first?.archetype ?? ""
        if key.isEmpty {
            return Calendar.current.ordinality(of: .day, in: .year, for: .now) ?? 0
        }
        return key.unicodeScalars.reduce(0) { $0 + Int($1.value) }
    }
}

/// App-wide version tag, shown small on the Alicia tab so Hector can tell
/// at a glance whether his phone runs the latest build. BUMP THIS on every
/// app change that ships (see CLAUDE.md).
enum AppVersion {
    static let tag = "v21"
    static let date = "Jul 7"
}
