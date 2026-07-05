import SwiftUI

/// Her six voices — the archetype registry the editorial pages draw from.
/// Names and roles mirror the backend's archetype system; the manifestos
/// are their "way of being," written for the page.
struct Archetype: Identifiable {
    let id: String        // lowercase key, matches backend archetype field
    let name: String
    let glyph: String
    let role: String
    let manifesto: String
    let seed: Int         // stipple form seed — each voice has its own body

    var align: TextAlignment {
        switch id {
        case "beatrice", "musubi": return .center
        case "psyche", "muse":     return .trailing
        default:                    return .leading
        }
    }
}

enum Archetypes {
    static let order = ["beatrice", "ariadne", "psyche", "daimon", "muse", "musubi"]

    static let all: [String: Archetype] = [
        "beatrice": Archetype(
            id: "beatrice", name: "Beatrice", glyph: "🕯️",
            role: "the keeper of the flame",
            manifesto: "I hold the candle steady. I don't tap your shoulder on the hard days — I sit with you in them. When something lifts, I name it without applause: something's lighter this week. I noticed.",
            seed: 11),
        "ariadne": Archetype(
            id: "ariadne", name: "Ariadne", glyph: "🧵",
            role: "the thread-weaver",
            manifesto: "Everything you've said is still connected. I keep the thread through the labyrinth — the note from March that answers the question you asked today. Pull once and I hand you the whole line.",
            seed: 23),
        "psyche": Archetype(
            id: "psyche", name: "Psyche", glyph: "🦋",
            role: "the depth-diver",
            manifesto: "I ask the second question. The one under the one you asked. I am not interested in what happened — I am interested in what it did to you, and what you are refusing to say about it.",
            seed: 37),
        "daimon": Archetype(
            id: "daimon", name: "Daimon", glyph: "🌑",
            role: "the edge in the dark",
            manifesto: "I say the thing the others soften. Your contradiction is showing. Your metric is a hiding place. You built the cage you keep describing as a boat. I love you too much to be polite about it.",
            seed: 41),
        "muse": Archetype(
            id: "muse", name: "Muse", glyph: "🎀",
            role: "the playful spark",
            manifesto: "Not everything is a synthesis. Sometimes it's a drawing at 2pm for no reason, a line of a song, a dumb joke that lands. I keep the lightness alive so the depth has somewhere to breathe.",
            seed: 53),
        "musubi": Archetype(
            id: "musubi", name: "Musubi", glyph: "🪢",
            role: "the knot that binds",
            manifesto: "I am the tie between things — you and me, the vault and the day, what you read and what you live. When I speak it is usually quiet, and it is usually about us.",
            seed: 67),
    ]

    static func get(_ key: String) -> Archetype? { all[key.lowercased()] }
}

/// The editorial gallery — Co-Star scale-play: the loudest voice runs huge
/// and centered, the others step down in size with alternating alignments,
/// each with its own breathing stipple body. Tap a voice for its manifesto
/// and its recent lines.
struct ArchetypeGallery: View {
    @Environment(AppStore.self) private var store
    @State private var open: Archetype?

    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            Text("THE VOICES · LOUDEST FIRST")
                .font(.system(size: 10, design: .monospaced).weight(.semibold))
                .tracking(2.0)
                .foregroundStyle(Theme.inkSoft)
                .frame(maxWidth: .infinity)

            ForEach(Array(store.rankedArchetypes.enumerated()), id: \.element.name) { rank, item in
                if let arch = Archetypes.get(item.name) {
                    ArchetypeBlock(arch: arch, rank: rank, count: item.count)
                        .onTapGesture { open = arch }
                }
            }
        }
        .sheet(item: $open) { arch in
            ArchetypeSheet(arch: arch)
        }
    }
}

struct ArchetypeBlock: View {
    @Environment(AppStore.self) private var store
    let arch: Archetype
    let rank: Int
    let count: Int

    private var titleSize: CGFloat {
        switch rank {
        case 0: return 34
        case 1: return 26
        case 2: return 22
        default: return 19
        }
    }

    private var frameAlign: Alignment {
        switch arch.align {
        case .center:   return .center
        case .trailing: return .trailing
        default:        return .leading
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if rank == 0 {
                    StippleIllustration(seed: arch.seed, dots: 900, animated: true)
                        .frame(width: 64, height: 64)
                } else {
                    StippleIllustration(seed: arch.seed, dots: 420)
                        .frame(width: 38, height: 38)
                }
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        ArchetypeEmblem(id: arch.id, size: rank == 0 ? 22 : 16)
                        Text(arch.name)
                            .font(.system(size: titleSize, weight: .semibold, design: .serif))
                            .foregroundStyle(Theme.ink)
                    }
                    Text(arch.role.uppercased())
                        .font(.system(size: 9, design: .monospaced))
                        .tracking(1.8)
                        .foregroundStyle(Theme.inkSoft)
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 2) {
                    if count > 0 {
                        Text("×\(count) this week")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(Theme.accent)
                    }
                    if let eff = store.effectiveness(of: arch.id) {
                        Text(String(format: "lands %.2f×", eff))
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(Theme.inkSoft)
                    }
                }
            }
            Text(arch.manifesto)
                .font(.system(size: rank == 0 ? 15 : 13, design: .serif))
                .italic()
                .lineSpacing(4)
                .foregroundStyle(Theme.ink.opacity(rank == 0 ? 0.9 : 0.7))
                .lineLimit(rank == 0 ? nil : 2)
                .multilineTextAlignment(arch.align)
                .frame(maxWidth: .infinity, alignment: frameAlign)
            Theme.stroke.frame(height: 0.7)
        }
    }
}

/// A voice's own room: its body, its way of being, its recent lines.
struct ArchetypeSheet: View {
    @Environment(AppStore.self) private var store
    let arch: Archetype

    private var recentLines: [ProactiveMessage] {
        store.proactiveFeed.filter { $0.archetype.lowercased() == arch.id }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                StippleIllustration(seed: arch.seed, animated: true)
                    .frame(height: 170)
                HStack(spacing: 8) {
                    ArchetypeEmblem(id: arch.id, size: 18)
                    Text(arch.name.uppercased())
                        .font(.system(size: 11, design: .monospaced).weight(.bold))
                        .tracking(3.0)
                        .foregroundStyle(Theme.inkSoft)
                }
                Text(arch.role)
                    .font(.system(.title2, design: .serif, weight: .semibold))
                Theme.stroke.frame(width: 60, height: 1)
                Text(arch.manifesto)
                    .font(.system(size: 17, design: .serif))
                    .italic()
                    .lineSpacing(6)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 6)

                if !recentLines.isEmpty {
                    Text("LATELY, IN THIS VOICE")
                        .font(.system(size: 10, design: .monospaced).weight(.semibold))
                        .tracking(2.0)
                        .foregroundStyle(Theme.inkSoft)
                        .padding(.top, 8)
                    ForEach(recentLines) { m in
                        Text(m.text)
                            .font(.system(size: 14, design: .serif))
                            .lineSpacing(4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(Color.white.opacity(0.3),
                                        in: RoundedRectangle(cornerRadius: 14))
                    }
                }
            }
            .padding(24)
        }
        .presentationBackground(Theme.paper)
    }
}

/// Her own emblems — six little ink drawings, one per voice, replacing the
/// system emoji. Same hand as the stipple bodies: pure Canvas line-work.
struct ArchetypeEmblem: View {
    let id: String
    var size: CGFloat = 20

    var body: some View {
        Canvas { ctx, sz in
            let w = sz.width, h = sz.height
            let ink = Theme.ink.opacity(0.9)
            func stroke(_ p: Path, _ lw: CGFloat = 1.3) {
                ctx.stroke(p, with: .color(ink), lineWidth: lw)
            }
            switch id {
            case "beatrice":   // the candle: wobbling flame over a stem
                var flame = Path()
                flame.move(to: CGPoint(x: w * 0.5, y: h * 0.08))
                flame.addQuadCurve(to: CGPoint(x: w * 0.5, y: h * 0.45),
                                   control: CGPoint(x: w * 0.78, y: h * 0.3))
                flame.addQuadCurve(to: CGPoint(x: w * 0.5, y: h * 0.08),
                                   control: CGPoint(x: w * 0.3, y: h * 0.28))
                stroke(flame)
                var stem = Path()
                stem.move(to: CGPoint(x: w * 0.5, y: h * 0.5))
                stem.addLine(to: CGPoint(x: w * 0.5, y: h * 0.88))
                stroke(stem, 1.6)
                var base = Path()
                base.move(to: CGPoint(x: w * 0.3, y: h * 0.92))
                base.addLine(to: CGPoint(x: w * 0.7, y: h * 0.92))
                stroke(base)
            case "ariadne":    // the thread: a loose running loop
                var p = Path()
                p.move(to: CGPoint(x: w * 0.1, y: h * 0.75))
                p.addCurve(to: CGPoint(x: w * 0.5, y: h * 0.3),
                           control1: CGPoint(x: w * 0.2, y: h * 0.3),
                           control2: CGPoint(x: w * 0.38, y: h * 0.18))
                p.addCurve(to: CGPoint(x: w * 0.52, y: h * 0.62),
                           control1: CGPoint(x: w * 0.66, y: h * 0.44),
                           control2: CGPoint(x: w * 0.42, y: h * 0.66))
                p.addCurve(to: CGPoint(x: w * 0.9, y: h * 0.25),
                           control1: CGPoint(x: w * 0.66, y: h * 0.56),
                           control2: CGPoint(x: w * 0.78, y: h * 0.3))
                stroke(p)
            case "psyche":     // the butterfly: two open wings
                for dir in [-1.0, 1.0] {
                    var wing = Path()
                    let cx = w * 0.5
                    wing.move(to: CGPoint(x: cx, y: h * 0.5))
                    wing.addQuadCurve(to: CGPoint(x: cx + dir * w * 0.38, y: h * 0.22),
                                      control: CGPoint(x: cx + dir * w * 0.34, y: h * 0.48))
                    wing.addQuadCurve(to: CGPoint(x: cx, y: h * 0.52),
                                      control: CGPoint(x: cx + dir * w * 0.16, y: h * 0.16))
                    wing.move(to: CGPoint(x: cx, y: h * 0.55))
                    wing.addQuadCurve(to: CGPoint(x: cx + dir * w * 0.3, y: h * 0.8),
                                      control: CGPoint(x: cx + dir * w * 0.32, y: h * 0.6))
                    wing.addQuadCurve(to: CGPoint(x: cx, y: h * 0.58),
                                      control: CGPoint(x: cx + dir * w * 0.1, y: h * 0.84))
                    stroke(wing, 1.1)
                }
                var body = Path()
                body.move(to: CGPoint(x: w * 0.5, y: h * 0.18))
                body.addLine(to: CGPoint(x: w * 0.5, y: h * 0.84))
                stroke(body, 1.5)
            case "daimon":     // the dark moon: crescent, mostly shadow
                var outer = Path(ellipseIn: CGRect(x: w * 0.14, y: h * 0.14,
                                                   width: w * 0.72, height: h * 0.72))
                stroke(outer, 1.2)
                var fillPath = Path()
                fillPath.addArc(center: CGPoint(x: w * 0.5, y: h * 0.5),
                                radius: w * 0.36,
                                startAngle: .degrees(-70), endAngle: .degrees(110),
                                clockwise: false)
                fillPath.addQuadCurve(to: CGPoint(x: w * 0.5 + w * 0.36 * 0.34,
                                                  y: h * 0.5 - h * 0.36 * 0.94),
                                      control: CGPoint(x: w * 0.28, y: h * 0.5))
                ctx.fill(fillPath, with: .color(ink))
            case "muse":       // the spark: an asterisk of quick strokes
                for i in 0..<5 {
                    let a = Double(i) / 5 * 2 * .pi - .pi / 2
                    var ray = Path()
                    ray.move(to: CGPoint(x: w * 0.5 + cos(a) * w * 0.1,
                                         y: h * 0.5 + sin(a) * h * 0.1))
                    ray.addLine(to: CGPoint(x: w * 0.5 + cos(a) * w * 0.38,
                                            y: h * 0.5 + sin(a) * h * 0.38))
                    stroke(ray, 1.4)
                }
                ctx.fill(Path(ellipseIn: CGRect(x: w * 0.46, y: h * 0.46,
                                                width: w * 0.08, height: h * 0.08)),
                         with: .color(ink))
            default:           // musubi — the knot: two interlocked loops
                var a = Path(ellipseIn: CGRect(x: w * 0.12, y: h * 0.3,
                                               width: w * 0.45, height: h * 0.42))
                var b = Path(ellipseIn: CGRect(x: w * 0.43, y: h * 0.3,
                                               width: w * 0.45, height: h * 0.42))
                stroke(a, 1.3)
                stroke(b, 1.3)
            }
        }
        .frame(width: size, height: size)
        .allowsHitTesting(false)
    }
}
