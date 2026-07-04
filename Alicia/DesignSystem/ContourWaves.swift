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

    /// Deterministic "randomness" — a fixed unit-interval table, so the
    /// field needs no @State/onAppear lifecycle (which never fired inside
    /// a .background container) and every launch breathes the same sea.
    private static let jitter: [Double] = [
        0.83, 0.19, 0.55, 0.42, 0.91, 0.07, 0.66, 0.31, 0.74, 0.48,
        0.12, 0.95, 0.27, 0.61, 0.38, 0.86, 0.03, 0.70, 0.52, 0.24,
        0.79, 0.15, 0.58, 0.44,
    ]
    private static func j(_ n: Int) -> Double { jitter[n % jitter.count] }

    private static func buildSide(_ side: Int, size: CGSize) -> [Source] {
        (0..<6).map { i in
            let fi = Double(i)
            let base = side * 6 + i
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
        let cross = sin(y * 0.011 + t * 0.6) * 0.55
                  + cos(x * 0.008 - t * 0.55) * 0.45
                  + sin((x + y) * 0.0036 + t * 0.35) * 0.35
        return value * 0.58 + cross
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 12.0)) { timeline in
            Canvas { context, size in
                    let leftSources = Self.buildSide(0, size: size)
                    let rightSources = Self.buildSide(1, size: size)
                    let t = timeline.date.timeIntervalSinceReferenceDate
                        .truncatingRemainder(dividingBy: 86_400)
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

                    let levels: [Double] = [-1.35, -0.95, -0.55, -0.18, 0.18, 0.55, 0.95, 1.35]
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
                        let alpha = 0.20 + 0.14 * ((level + 1.35) / 2.7)
                        context.stroke(path,
                                       with: .color(Theme.ink.opacity(alpha)),
                                       lineWidth: 1.0)
                    }
            }
        }
        .allowsHitTesting(false)
    }
}

/// App-wide version tag, shown small on the Alicia tab so Hector can tell
/// at a glance whether his phone runs the latest build. BUMP THIS on every
/// app change that ships (see CLAUDE.md).
enum AppVersion {
    static let tag = "v8"
    static let date = "Jul 4"
}
