import SwiftUI

/// A generative eye — the emblem of what she sees of him. Iris rings
/// wobble like the contour fields, the pupil is dense grain, and every
/// few seconds the lid blinks. Fully procedural, ink on bone.
struct EyeIllustration: View {
    var animated: Bool = true

    var body: some View {
        if animated {
            TimelineView(.animation(minimumInterval: 1.0 / 10.0)) { tl in
                canvas(t: tl.date.timeIntervalSinceReferenceDate
                    .truncatingRemainder(dividingBy: 86_400))
            }
        } else {
            canvas(t: 0)
        }
    }

    private func canvas(t: TimeInterval) -> some View {
        Canvas { ctx, size in
            let cx = size.width / 2, cy = size.height / 2
            let W = min(size.width, size.height)

            // Blink: a fast lid-close every ~7 s.
            let cycle = (t / 7.0).truncatingRemainder(dividingBy: 1.0)
            let blink = cycle > 0.94
                ? sin((cycle - 0.94) / 0.06 * .pi)   // 0→1→0 squeeze
                : 0.0
            let openness = 1.0 - 0.92 * blink

            // Almond outline (two arcs), drawn as wobbling ink.
            var lid = Path()
            let w = W * 0.94, h = W * 0.52 * openness
            lid.move(to: CGPoint(x: cx - w / 2, y: cy))
            lid.addQuadCurve(to: CGPoint(x: cx + w / 2, y: cy),
                             control: CGPoint(x: cx, y: cy - h))
            lid.addQuadCurve(to: CGPoint(x: cx - w / 2, y: cy),
                             control: CGPoint(x: cx, y: cy + h))
            ctx.stroke(lid, with: .color(Theme.ink.opacity(0.85)), lineWidth: 1.6)

            guard openness > 0.2 else { return }

            // Iris: wobbling contour rings, clipped to the lid.
            ctx.clip(to: lid)
            let irisR = W * 0.23
            for ring in 1...6 {
                let rr = irisR * Double(ring) / 6.0
                var path = Path()
                let steps = 48
                for i in 0...steps {
                    let a = Double(i) / Double(steps) * 2 * .pi
                    let wob = 1.0 + 0.06 * sin(a * 5 + t * 0.8 + Double(ring))
                                  + 0.03 * sin(a * 9 - t * 0.5)
                    let p = CGPoint(x: cx + cos(a) * rr * wob,
                                    y: cy + sin(a) * rr * wob)
                    if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
                }
                path.closeSubpath()
                ctx.stroke(path,
                           with: .color(Theme.ink.opacity(0.16 + 0.07 * Double(ring))),
                           lineWidth: 0.9)
            }
            // Pupil: dense grain disc that dilates gently with time.
            let pupilR = W * 0.085 * (1.0 + 0.1 * sin(t * 0.9))
            var seed = UInt64(9176)
            func rnd() -> Double {
                seed = seed &* 6364136223846793005 &+ 1442695040888963407
                return Double(seed >> 11) / Double(UInt64(1) << 53)
            }
            for _ in 0..<420 {
                let a = rnd() * 2 * .pi
                let r = pow(rnd(), 0.5) * pupilR
                let d = 0.6 + rnd() * 1.1
                ctx.fill(Path(ellipseIn: CGRect(x: cx + cos(a) * r,
                                                y: cy + sin(a) * r,
                                                width: d, height: d)),
                         with: .color(Theme.ink.opacity(0.85)))
            }
        }
        .allowsHitTesting(false)
    }
}

/// Us page: what she knows of you — now, recently, always. The eye
/// watches; tapping opens the reading-room sheet.
struct KnowingCard: View {
    @Environment(AppStore.self) private var store
    @State private var reading = false

    var body: some View {
        if let k = store.knowing {
            Button { reading = true } label: {
                VStack(spacing: 10) {
                    Text("WHAT SHE KNOWS OF YOU")
                        .font(.system(size: 10, design: .monospaced).weight(.semibold))
                        .tracking(2.0)
                        .foregroundStyle(Theme.inkSoft)
                    EyeIllustration()
                        .frame(height: 90)
                        .frame(maxWidth: .infinity)
                    HStack(spacing: 0) {
                        stat("\(k.now.count)", "TODAY")
                        stat("\(k.recent_count)", "THIS WEEK")
                        stat("\(k.longterm.learnings)", "ALWAYS")
                    }
                }
                .card(padding: 16, radius: 20)
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $reading) { KnowingSheet(k: k) }
        }
    }

    private func stat(_ number: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(number)
                .font(.system(size: 22, weight: .semibold, design: .serif))
                .foregroundStyle(Theme.ink)
            Text(label)
                .font(.system(size: 8, design: .monospaced))
                .tracking(1.6)
                .foregroundStyle(Theme.inkSoft)
        }
        .frame(maxWidth: .infinity)
    }
}

/// The reading room for her model of you — three horizons, typeset.
struct KnowingSheet: View {
    let k: KnowingState

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                EyeIllustration()
                    .frame(height: 130)
                Text("HOW SHE LEARNS YOU")
                    .font(.system(size: 11, design: .monospaced).weight(.bold))
                    .tracking(3.0)
                    .foregroundStyle(Theme.inkSoft)
                Text("Every conversation leaves a claim. Claims gather into dimensions. Dimensions become the standing model she checks with you each month.")
                    .font(.system(size: 15, design: .serif))
                    .italic()
                    .multilineTextAlignment(.center)
                    .lineSpacing(5)
                Theme.stroke.frame(width: 60, height: 1)

                horizon("NOW — TODAY'S CLAIMS", k.now,
                        empty: "Nothing yet today. Talk to her.")
                horizon("RECENTLY — THE 7-DAY WINDOW (\(k.recent_count) claims)",
                        k.recent, empty: "A quiet week.")

                Text("THE LONG ARC")
                    .font(.system(size: 10, design: .monospaced).weight(.semibold))
                    .tracking(2.0)
                    .foregroundStyle(Theme.accent)
                HStack(spacing: 0) {
                    big("\(k.longterm.learnings)", "learnings")
                    big("\(k.longterm.dimensions.count)", "dimensions")
                    big("\(k.longterm.memory_rules)", "memory rules")
                    big("\(k.longterm.days)", "days breathing")
                }
                Text(k.longterm.dimensions.joined(separator: " · "))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Theme.inkSoft)
                    .multilineTextAlignment(.center)
            }
            .padding(24)
            .padding(.bottom, 40)
        }
        .presentationBackground(Theme.paper)
    }

    private func horizon(_ title: String, _ claims: [KnowingClaim],
                         empty: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 10, design: .monospaced).weight(.semibold))
                .tracking(2.0)
                .foregroundStyle(Theme.accent)
                .frame(maxWidth: .infinity)
            if claims.isEmpty {
                Text(empty)
                    .font(.system(size: 13, design: .serif))
                    .italic()
                    .foregroundStyle(Theme.inkSoft)
                    .frame(maxWidth: .infinity)
            }
            ForEach(claims, id: \.claim) { c in
                VStack(alignment: .leading, spacing: 3) {
                    Text(c.claim.strippedEmojis)
                        .font(.system(size: 14, design: .serif))
                        .lineSpacing(4)
                    Text(c.dimension.uppercased() +
                         String(format: " · CONFIDENCE %.1f", c.confidence))
                        .font(.system(size: 8, design: .monospaced))
                        .tracking(1.4)
                        .foregroundStyle(Theme.inkSoft)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Color.white.opacity(0.28),
                            in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private func big(_ number: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(number)
                .font(.system(size: 24, weight: .semibold, design: .serif))
            Text(label)
                .font(.system(size: 8, design: .monospaced))
                .tracking(1.2)
                .foregroundStyle(Theme.inkSoft)
        }
        .frame(maxWidth: .infinity)
    }
}
