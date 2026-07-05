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
                    Text(arch.name)
                        .font(.system(size: titleSize, weight: .semibold, design: .serif))
                        .foregroundStyle(Theme.ink)
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
                Text(arch.name.uppercased())
                    .font(.system(size: 11, design: .monospaced).weight(.bold))
                    .tracking(3.0)
                    .foregroundStyle(Theme.inkSoft)
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
