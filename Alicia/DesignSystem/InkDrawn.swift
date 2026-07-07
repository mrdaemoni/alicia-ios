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
    var opacity: Double = 0.19   // v22: quieter — present, not insistent
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
                                         overshoot: 4.5, bow: 1.8)
                ctx.stroke(path, with: ink,
                           style: StrokeStyle(lineWidth: 0.85, lineCap: .round))
            }
            // The re-trace: two edges get a second, fainter pass, slightly
            // off — the pen going back over the line.
            for i in [0, 2] {
                let path = InkPen.stroke(from: corners[i],
                                         to: corners[(i + 1) % 4],
                                         rand: &rand,
                                         overshoot: 2, bow: 2.6)
                ctx.stroke(path, with: .color(color.opacity(opacity * 0.4)),
                           style: StrokeStyle(lineWidth: 0.55, lineCap: .round))
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

// MARK: - Hand-drawn glyph set (v22 — no more stock icons)

/// Play / pause, pulled by hand. `ringed` circles it for big affordances.
struct InkPlayPause: View {
    var playing: Bool
    var size: CGFloat = 22
    var color: Color = Theme.ink
    var seed: Int = 31
    var ringed: Bool = false

    var body: some View {
        Canvas { ctx, s in
            var rand = InkRand(seed &+ (playing ? 7 : 0))
            let ink = GraphicsContext.Shading.color(color)
            if ringed {
                let ring = InkPen.ring(center: CGPoint(x: s.width / 2, y: s.height / 2),
                                       radius: s.width / 2 - 1.5, rand: &rand,
                                       sweep: 2 * .pi * 1.03, breathe: 1.0)
                ctx.stroke(ring, with: .color(color.opacity(0.8)),
                           style: StrokeStyle(lineWidth: 1.1, lineCap: .round))
            }
            let w = s.width, h = s.height
            let lw = max(1.3, s.width * 0.055)
            if playing {
                for x in [0.40, 0.60] {
                    let bar = InkPen.stroke(
                        from: CGPoint(x: w * x, y: h * 0.32),
                        to: CGPoint(x: w * x, y: h * 0.68),
                        rand: &rand, overshoot: 1, bow: 0.8, wobble: 0.4,
                        segments: 6)
                    ctx.stroke(bar, with: ink,
                               style: StrokeStyle(lineWidth: lw, lineCap: .round))
                }
            } else {
                let a = CGPoint(x: w * 0.40, y: h * 0.30)
                let b = CGPoint(x: w * 0.40, y: h * 0.70)
                let c = CGPoint(x: w * 0.70, y: h * 0.50)
                for (p, q) in [(a, b), (b, c), (c, a)] {
                    let edge = InkPen.stroke(from: p, to: q, rand: &rand,
                                             overshoot: 1.2, bow: 0.7,
                                             wobble: 0.35, segments: 6)
                    ctx.stroke(edge, with: ink,
                               style: StrokeStyle(lineWidth: lw, lineCap: .round))
                }
            }
        }
        .frame(width: size, height: size)
    }
}

/// A chevron with a wrist in it — list affordances and back buttons.
struct InkChevron: View {
    enum Direction { case left, right }
    var pointing: Direction = .right
    var size: CGFloat = 14
    var color: Color = Theme.inkSoft
    var seed: Int = 41

    var body: some View {
        Canvas { ctx, s in
            var rand = InkRand(seed)
            let w = s.width, h = s.height
            let tipX = pointing == .right ? w * 0.62 : w * 0.38
            let baseX = pointing == .right ? w * 0.38 : w * 0.62
            let tip = CGPoint(x: tipX, y: h * 0.5)
            for endY in [0.22, 0.78] {
                let stroke = InkPen.stroke(
                    from: CGPoint(x: baseX, y: h * endY), to: tip,
                    rand: &rand, overshoot: 1.2, bow: 0.7, wobble: 0.35,
                    segments: 6)
                ctx.stroke(stroke, with: .color(color),
                           style: StrokeStyle(lineWidth: 1.3, lineCap: .round))
            }
        }
        .frame(width: size, height: size)
    }
}

/// ±15s skip: a hand-drawn arc arrow around a tiny mono "15".
struct InkSkip: View {
    var forward: Bool
    var size: CGFloat = 26
    var color: Color = Theme.ink
    var seed: Int = 53

    var body: some View {
        ZStack {
            Canvas { ctx, s in
                var rand = InkRand(seed &+ (forward ? 3 : 0))
                let c = CGPoint(x: s.width / 2, y: s.height / 2)
                let r = s.width / 2 - 2.5
                // Most of a circle, opening at the top; direction decides
                // which way the arrowhead flicks.
                var path = Path()
                let start = -Double.pi * (forward ? 0.82 : 0.18)
                let sweep = 2 * Double.pi * 0.72 * (forward ? 1 : -1)
                var endPoint = CGPoint.zero
                var endAngle = 0.0
                var randCopy = rand
                for i in 0...44 {
                    let t = Double(i) / 44
                    let a = start + sweep * t
                    let rr = r + CGFloat(sin(a * 3 + 1)) * 0.9
                        + CGFloat(randCopy.range(-0.3, 0.3))
                    let p = CGPoint(x: c.x + CGFloat(cos(a)) * rr,
                                    y: c.y + CGFloat(sin(a)) * rr)
                    if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
                    endPoint = p; endAngle = a
                }
                ctx.stroke(path, with: .color(color),
                           style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
                // Arrowhead at the arc's end, tangent to travel.
                let tangent = endAngle + (forward ? 1 : -1) * Double.pi / 2
                for spread in [-0.5, 0.55] {
                    let a = tangent + .pi + spread
                    let end = CGPoint(x: endPoint.x + CGFloat(cos(a)) * s.width * 0.2,
                                      y: endPoint.y + CGFloat(sin(a)) * s.width * 0.2)
                    let flick = InkPen.stroke(from: endPoint, to: end,
                                              rand: &rand, overshoot: 0.5,
                                              bow: 0.5, wobble: 0.3, segments: 5)
                    ctx.stroke(flick, with: .color(color),
                               style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
                }
            }
            Text("15")
                .font(.system(size: size * 0.3, design: .monospaced).weight(.semibold))
                .foregroundStyle(color)
        }
        .frame(width: size, height: size)
    }
}

/// A small ink asterisk — the mark she leaves where an emoji used to be.
struct InkSpark: View {
    var size: CGFloat = 12
    var color: Color = Theme.accent
    var seed: Int = 61

    var body: some View {
        Canvas { ctx, s in
            var rand = InkRand(seed)
            let c = CGPoint(x: s.width / 2, y: s.height / 2)
            let r = s.width * 0.42
            let base = rand.range(0, .pi)
            for k in 0..<3 {
                let a = base + Double(k) * .pi / 3 + rand.range(-0.08, 0.08)
                let p0 = CGPoint(x: c.x - CGFloat(cos(a)) * r,
                                 y: c.y - CGFloat(sin(a)) * r)
                let p1 = CGPoint(x: c.x + CGFloat(cos(a)) * r,
                                 y: c.y + CGFloat(sin(a)) * r)
                let stroke = InkPen.stroke(from: p0, to: p1, rand: &rand,
                                           overshoot: 0.6, bow: 0.5,
                                           wobble: 0.3, segments: 5)
                ctx.stroke(stroke, with: .color(color),
                           style: StrokeStyle(lineWidth: 1.1, lineCap: .round))
            }
        }
        .frame(width: size, height: size)
    }
}

/// Trembling vertical bars — the "this is sound" mark (replaces waveform).
struct InkWaveBars: View {
    var size: CGFloat = 18
    var color: Color = Theme.ink
    var seed: Int = 71

    var body: some View {
        Canvas { ctx, s in
            var rand = InkRand(seed)
            let heights: [CGFloat] = [0.45, 0.85, 0.6, 0.95, 0.5]
            let step = s.width / CGFloat(heights.count + 1)
            for (i, hFrac) in heights.enumerated() {
                let x = step * CGFloat(i + 1) + CGFloat(rand.range(-0.6, 0.6))
                let h = s.height * hFrac
                let bar = InkPen.stroke(
                    from: CGPoint(x: x, y: (s.height - h) / 2),
                    to: CGPoint(x: x, y: (s.height + h) / 2),
                    rand: &rand, overshoot: 0.8, bow: 0.6, wobble: 0.35,
                    segments: 5)
                ctx.stroke(bar, with: .color(color),
                           style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
            }
        }
        .frame(width: size, height: size)
    }
}

/// The back affordance for pushed pages — her chevron + a small word,
/// replacing the system back button.
struct InkBackButton: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Button { dismiss() } label: {
            HStack(spacing: 4) {
                InkChevron(pointing: .left, size: 15, color: Theme.ink, seed: 29)
                Text("BACK")
                    .font(.system(size: 9, design: .monospaced).weight(.semibold))
                    .tracking(1.6)
                    .foregroundStyle(Theme.ink)
                    .fixedSize()   // the toolbar slot must not truncate it
            }
            .fixedSize()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
