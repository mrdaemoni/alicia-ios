import SwiftUI

/// Alicia's pen, shared by the app and the home-screen widget.
///
/// These lived in `Alicia/DesignSystem/InkDrawn.swift`, which only the app
/// target compiles. The widget could not reach a single one of her strokes,
/// so it drew machine rectangles and hardcoded its own near-black —
/// (0.12, 0.15, 0.13), a greener ink than `Theme.ink` — which is how two
/// surfaces of one sketchbook end up in two different colours. Anything both
/// targets need in order to draw in her hand belongs here.

/// The two colours neither target may restate.
enum InkPalette {
    /// Bone paper.
    static let paper = Color(red: 0.953, green: 0.933, blue: 0.890)
    /// Warm near-black.
    static let ink = Color(red: 0.165, green: 0.153, blue: 0.137)
}

// MARK: - Seeded randomness

/// Tiny deterministic PRNG (xorshift) — stable strokes per seed.
struct InkRand {
    private var state: UInt64
    init(_ seed: Int) {
        state = UInt64(bitPattern: Int64(seed)) &* 2654435761 &+ 0x9E3779B97F4A7C15
        if state == 0 { state = 0xBADC0FFEE }
    }
    mutating func next() -> Double {
        state ^= state << 13; state ^= state >> 7; state ^= state << 17
        return Double(state % 100_000) / 100_000
    }
    mutating func range(_ lo: Double, _ hi: Double) -> Double {
        lo + next() * (hi - lo)
    }
}

extension String {
    /// Stable per-name seed (hashValue is randomized per launch — don't).
    var inkSeed: Int {
        unicodeScalars.reduce(5381) { ($0 << 5) &+ $0 &+ Int($1.value) }
    }
}

// MARK: - Stroke helpers

enum InkPen {
    /// A trembling line from a→b: overshoots both ends, bows at the middle,
    /// wobbles along its length. One pass of a human wrist.
    static func stroke(from a: CGPoint, to b: CGPoint,
                       rand: inout InkRand,
                       overshoot: CGFloat = 5,
                       bow: CGFloat = 2.5,
                       wobble: CGFloat = 0.7,
                       segments: Int = 14) -> Path {
        var path = Path()
        let dx = b.x - a.x, dy = b.y - a.y
        let len = max(1, hypot(dx, dy))
        let ux = dx / len, uy = dy / len          // along
        let px = -uy, py = ux                     // perpendicular
        let o0 = CGFloat(rand.range(0.2, 1.0)) * overshoot
        let o1 = CGFloat(rand.range(0.2, 1.0)) * overshoot
        let start = CGPoint(x: a.x - ux * o0, y: a.y - uy * o0)
        let end   = CGPoint(x: b.x + ux * o1, y: b.y + uy * o1)
        let bowAmt = CGFloat(rand.range(-1, 1)) * bow
        let phase = rand.range(0, .pi * 2)
        path.move(to: start)
        for i in 1...segments {
            let t = CGFloat(i) / CGFloat(segments)
            let arc = sin(.pi * t) * bowAmt       // single bow
            let tremble = CGFloat(sin(Double(t) * 9 + phase)) * wobble
                        + CGFloat(rand.range(-0.4, 0.4))
            let x = start.x + (end.x - start.x) * t + px * (arc + tremble)
            let y = start.y + (end.y - start.y) * t + py * (arc + tremble)
            path.addLine(to: CGPoint(x: x, y: y))
        }
        return path
    }
}

// MARK: - Hand-drawn underline

/// A trembling underline — selection, emphasis, presence.
struct InkUnderline: View {
    var color: Color = InkPalette.ink
    var seed: Int = 1
    var lineWidth: CGFloat = 1.6

    var body: some View {
        Canvas { ctx, size in
            var rand = InkRand(seed &+ Int(size.width))
            let y = size.height * 0.55
            let path = InkPen.stroke(
                from: CGPoint(x: 1, y: y),
                to: CGPoint(x: size.width - 1, y: y),
                rand: &rand, overshoot: 2.5, bow: 1.8, wobble: 0.6)
            ctx.stroke(path, with: .color(color),
                       style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
        }
        .allowsHitTesting(false)
    }
}

extension View {
    /// Her line under a word, in the word's own colour — so it is dark on
    /// paper and light on an ink ground, never a tint of its own.
    func inkUnderlined(seed: String, color: Color,
                       lineWidth: CGFloat = 1.3, gap: CGFloat = 5) -> some View {
        padding(.bottom, gap)
            .overlay(alignment: .bottom) {
                InkUnderline(color: color, seed: seed.inkSeed, lineWidth: lineWidth)
                    .frame(height: gap)
            }
    }
}
