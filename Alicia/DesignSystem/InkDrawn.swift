import SwiftUI

/// Hand-drawn chrome — the move away from UI widgets (v21).
///
/// Everything here is procedural Canvas pretending to be Alicia's pen:
/// borders that overshoot their corners, underlines that tremble, arrows
/// with a wrist in them, tracing strokes over the thinkers' faces, and the
/// constellation lines that stitch the thinker graph together. All of it is
/// DETERMINISTICALLY seeded (no @State, no lifecycle) — the same card
/// always wears the same stroke, and nothing shimmers on scroll.

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

    /// An imperfect circle/ellipse arc around `center` — radius breathes,
    /// the ends don't have to meet. Alicia circling something that matters.
    static func ring(center: CGPoint, radius: CGFloat,
                     rand: inout InkRand,
                     sweep: Double = 2 * .pi,
                     squashX: CGFloat = 1, squashY: CGFloat = 1,
                     breathe: CGFloat = 1.6,
                     segments: Int = 64) -> Path {
        var path = Path()
        let start = rand.range(0, .pi * 2)
        let phase = rand.range(0, .pi * 2)
        let drift = CGFloat(rand.range(-0.8, 0.8))
        for i in 0...segments {
            let t = Double(i) / Double(segments)
            let angle = start + t * sweep
            let r = radius
                + CGFloat(sin(angle * 3 + phase)) * breathe
                + drift * CGFloat(t)              // spiral out a hair
            let p = CGPoint(x: center.x + cos(angle) * r * squashX,
                            y: center.y + sin(angle) * r * squashY)
            if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        return path
    }
}

// MARK: - Hand-drawn card border

/// A sketched frame that doesn't fully respect its container: four
/// individually-pulled edges, overshot corners, and a lighter re-trace on
/// two sides — the way a border looks when a hand draws one around a
/// thought it wants to keep.
struct HandDrawnBorder: View {
    var color: Color = Theme.ink
    var opacity: Double = 0.34
    var inset: CGFloat = 3

    var body: some View {
        Canvas { ctx, size in
            var rand = InkRand(Int(size.width * 3 + size.height * 7))
            let x0 = inset, y0 = inset
            let x1 = size.width - inset, y1 = size.height - inset
            let corners = [CGPoint(x: x0, y: y0), CGPoint(x: x1, y: y0),
                           CGPoint(x: x1, y: y1), CGPoint(x: x0, y: y1)]
            let ink = GraphicsContext.Shading.color(color.opacity(opacity))
            for i in 0..<4 {
                let path = InkPen.stroke(from: corners[i],
                                         to: corners[(i + 1) % 4],
                                         rand: &rand,
                                         overshoot: 7, bow: 2.2)
                ctx.stroke(path, with: ink,
                           style: StrokeStyle(lineWidth: 1.1, lineCap: .round))
            }
            // The re-trace: two edges get a second, fainter pass, slightly
            // off — the pen going back over the line.
            for i in [0, 2] {
                let path = InkPen.stroke(from: corners[i],
                                         to: corners[(i + 1) % 4],
                                         rand: &rand,
                                         overshoot: 3, bow: 3.4)
                ctx.stroke(path, with: .color(color.opacity(opacity * 0.45)),
                           style: StrokeStyle(lineWidth: 0.7, lineCap: .round))
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Hand-drawn underline

/// A trembling underline — selection, emphasis, presence.
struct InkUnderline: View {
    var color: Color = Theme.ink
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

// MARK: - Hand-drawn tabs (TODAY | THE ARC, KNOWLEDGE | THINKERS)

/// Mono-caps words; the chosen one gets Alicia's underline. Replaces the
/// system segmented picker everywhere.
struct InkTabs: View {
    let items: [String]
    @Binding var selection: Int

    var body: some View {
        HStack(spacing: 30) {
            ForEach(items.indices, id: \.self) { i in
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { selection = i }
                } label: {
                    VStack(spacing: 3) {
                        Text(items[i].uppercased())
                            .font(.system(size: 11, design: .monospaced)
                                .weight(selection == i ? .bold : .regular))
                            .tracking(2.0)
                            .foregroundStyle(selection == i
                                             ? Theme.ink : Theme.inkSoft.opacity(0.75))
                        InkUnderline(seed: (i + 1) * 97)
                            .frame(height: 6)
                            .opacity(selection == i ? 1 : 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Hand-drawn submit arrow

/// The send affordance: a circled arrow, both pulled by hand — no filled
/// disc, no SF Symbol.
struct InkSubmitArrow: View {
    var size: CGFloat = 32
    var color: Color = Theme.ink
    var seed: Int = 11

    var body: some View {
        Canvas { ctx, canvasSize in
            var rand = InkRand(seed)
            let c = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
            let ring = InkPen.ring(center: c, radius: canvasSize.width / 2 - 2,
                                   rand: &rand, sweep: 2 * .pi * 1.04,
                                   breathe: 1.1)
            ctx.stroke(ring, with: .color(color.opacity(0.85)),
                       style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
            // Shaft, bottom → top, with a wrist in it
            let tip = CGPoint(x: c.x + CGFloat(rand.range(-1, 1)),
                              y: canvasSize.height * 0.26)
            let tail = CGPoint(x: c.x + CGFloat(rand.range(-1.5, 1.5)),
                               y: canvasSize.height * 0.74)
            let shaft = InkPen.stroke(from: tail, to: tip, rand: &rand,
                                      overshoot: 1.5, bow: 1.6, wobble: 0.5)
            ctx.stroke(shaft, with: .color(color),
                       style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
            // Head: two flicks
            for side: CGFloat in [-1, 1] {
                let end = CGPoint(x: tip.x + side * canvasSize.width * 0.17,
                                  y: tip.y + canvasSize.height * 0.17)
                let flick = InkPen.stroke(from: tip, to: end, rand: &rand,
                                          overshoot: 1, bow: 1, wobble: 0.4,
                                          segments: 6)
                ctx.stroke(flick, with: .color(color),
                           style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Traced portraits

/// Alicia's pen over a thinker's photograph — an incomplete ring or two and
/// a few tangent hatches, as if she is surfacing the face from the paper.
/// Deterministic per name.
struct PortraitTrace: View {
    let name: String
    var accented: Bool = true

    var body: some View {
        Canvas { ctx, size in
            var rand = InkRand(name.inkSeed)
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let baseR = size.width / 2
            // The main tracing ring — most of a circle, never all of it.
            let ring1 = InkPen.ring(
                center: c, radius: baseR - CGFloat(rand.range(0.5, 2.5)),
                rand: &rand, sweep: 2 * .pi * rand.range(0.72, 0.93),
                squashX: CGFloat(rand.range(0.97, 1.04)),
                squashY: CGFloat(rand.range(0.97, 1.04)),
                breathe: 1.4)
            ctx.stroke(ring1, with: .color(Theme.ink.opacity(0.6)),
                       style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
            // A second thought in sea-slate, drifting a little wider.
            if accented {
                let ring2 = InkPen.ring(
                    center: c, radius: baseR + CGFloat(rand.range(0.5, 3)),
                    rand: &rand, sweep: 2 * .pi * rand.range(0.3, 0.55),
                    squashX: CGFloat(rand.range(0.95, 1.06)),
                    squashY: CGFloat(rand.range(0.95, 1.06)),
                    breathe: 1.8)
                ctx.stroke(ring2, with: .color(Theme.accent.opacity(0.55)),
                           style: StrokeStyle(lineWidth: 0.9, lineCap: .round))
            }
            // Tangent hatches — three quick strokes where the pen rested.
            let hatchAngle = rand.range(0, 2 * .pi)
            for k in 0..<3 {
                let a = hatchAngle + Double(k) * 0.16
                let r0 = baseR * CGFloat(rand.range(0.92, 1.0))
                let r1 = baseR * CGFloat(rand.range(1.1, 1.28))
                let p0 = CGPoint(x: c.x + CGFloat(cos(a)) * r0,
                                 y: c.y + CGFloat(sin(a)) * r0)
                let p1 = CGPoint(x: c.x + CGFloat(cos(a)) * r1,
                                 y: c.y + CGFloat(sin(a)) * r1)
                let hatch = InkPen.stroke(from: p0, to: p1, rand: &rand,
                                          overshoot: 0.5, bow: 0.8,
                                          wobble: 0.3, segments: 5)
                ctx.stroke(hatch, with: .color(Theme.ink.opacity(0.45)),
                           style: StrokeStyle(lineWidth: 0.9, lineCap: .round))
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - The constellation (thinker graph, hand-stitched)

/// The related thinkers drawn as a walked path: nodes staggered left and
/// right, stitched together by trembling ink threads — a constellation she
/// drew while thinking, not a table view.
struct ThinkerConstellation: View {
    let related: [RelatedThinker]
    let isResolvable: (String) -> Bool
    let hop: (String) -> Void

    private let rowHeight: CGFloat = 92
    private let nodeX: CGFloat = 52          // portrait center inset

    var body: some View {
        ZStack(alignment: .top) {
            // The threads — drawn first, under the faces.
            Canvas { ctx, size in
                var rand = InkRand(related.reduce(17) { $0 &+ $1.name.inkSeed })
                var prev = CGPoint(x: size.width / 2, y: -6)  // from the thinker above
                for i in related.indices {
                    let cx = i.isMultiple(of: 2) ? nodeX : size.width - nodeX
                    let node = CGPoint(x: cx,
                                       y: CGFloat(i) * rowHeight + rowHeight / 2)
                    // Two passes, pulled hard: a real ink thread and an
                    // accent shadow bowing the other way — the pen went
                    // there and came back.
                    let thread = InkPen.stroke(from: prev, to: node, rand: &rand,
                                               overshoot: 4,
                                               bow: CGFloat(rand.range(16, 38)),
                                               wobble: 1.6, segments: 26)
                    ctx.stroke(thread, with: .color(Theme.ink.opacity(0.44)),
                               style: StrokeStyle(lineWidth: 1.35, lineCap: .round))
                    let shadow = InkPen.stroke(from: prev, to: node, rand: &rand,
                                               overshoot: 2,
                                               bow: CGFloat(rand.range(-34, -12)),
                                               wobble: 1.8, segments: 26)
                    ctx.stroke(shadow, with: .color(Theme.accent.opacity(0.32)),
                               style: StrokeStyle(lineWidth: 1.0, lineCap: .round))
                    // A knot where the thread lands — a quick half-ring
                    // around the face, like tying the connection off.
                    let knot = InkPen.ring(center: node,
                                           radius: 34 + CGFloat(rand.range(0, 3)),
                                           rand: &rand,
                                           sweep: 2 * .pi * rand.range(0.3, 0.6),
                                           breathe: 2.0, segments: 32)
                    ctx.stroke(knot, with: .color(Theme.ink.opacity(0.3)),
                               style: StrokeStyle(lineWidth: 1.0, lineCap: .round))
                    prev = node
                }
            }
            .allowsHitTesting(false)

            VStack(spacing: 0) {
                ForEach(related.indices, id: \.self) { i in
                    let edge = related[i]
                    let leading = i.isMultiple(of: 2)
                    Button {
                        hop(edge.name)
                    } label: {
                        HStack(spacing: 12) {
                            if !leading { textBlock(edge, leading: false) }
                            WikiPortrait(name: edge.name, size: 56)
                            if leading { textBlock(edge, leading: true) }
                        }
                        .frame(maxWidth: .infinity,
                               alignment: leading ? .leading : .trailing)
                        .padding(.horizontal, nodeX - 52 + 24)
                        .frame(height: rowHeight)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!isResolvable(edge.name))
                    .opacity(isResolvable(edge.name) ? 1 : 0.45)
                }
            }
        }
        .frame(height: rowHeight * CGFloat(related.count))
    }

    @ViewBuilder
    private func textBlock(_ edge: RelatedThinker, leading: Bool) -> some View {
        VStack(alignment: leading ? .leading : .trailing, spacing: 2) {
            Text(edge.name)
                .font(.system(size: 14, design: .serif).weight(.medium))
                .foregroundStyle(Theme.ink)
            Text(edge.why)
                .font(.system(size: 10.5, design: .serif))
                .italic()
                .foregroundStyle(Theme.inkSoft)
                .lineLimit(2)
                .multilineTextAlignment(leading ? .leading : .trailing)
        }
        .frame(maxWidth: .infinity, alignment: leading ? .leading : .trailing)
    }
}
