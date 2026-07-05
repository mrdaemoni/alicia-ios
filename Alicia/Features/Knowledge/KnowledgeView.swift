import SwiftUI

/// Knowledge — the tab where the vault comes to the phone: the freshest
/// syntheses off the shelf, and the thinker network with faces.
struct KnowledgeView: View {
    @Environment(AppStore.self) private var store
    @State private var themeFilter: String?
    @State private var reading: FeaturedSynthesis?
    @State private var openThinker: Thinker?

    private var thinkers: [Thinker] {
        let all = store.thinkerNetwork?.thinkers ?? []
        guard let themeFilter else { return all }
        return all.filter { $0.themes.contains(themeFilter) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    SectionHeader(title: "Knowledge",
                                  kicker: "the vault, in your pocket")

                    if !store.syntheses.isEmpty {
                        Text("FRESH FROM THE SHELF")
                            .font(.system(size: 10, design: .monospaced).weight(.semibold))
                            .tracking(2.0)
                            .foregroundStyle(Theme.inkSoft)
                        ForEach(Array(store.syntheses.enumerated()), id: \.element.title) { i, syn in
                            SynthesisRow(syn: syn, rank: i) { reading = syn }
                        }
                    }

                    Text("THE THINKERS")
                        .font(.system(size: 10, design: .monospaced).weight(.semibold))
                        .tracking(2.0)
                        .foregroundStyle(Theme.inkSoft)
                        .padding(.top, 10)

                    // Theme filter — mono chips, Co-Star flat.
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            themeChip(nil, label: "ALL")
                            ForEach(store.thinkerNetwork?.themes ?? [], id: \.self) { th in
                                themeChip(th, label: th.uppercased())
                            }
                        }
                    }

                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 14),
                                        GridItem(.flexible(), spacing: 14)],
                              spacing: 14) {
                        ForEach(thinkers) { thinker in
                            ThinkerCell(thinker: thinker)
                                .onTapGesture { openThinker = thinker }
                        }
                    }
                }
                .padding(16)
                .padding(.bottom, 24)
            }
            .refreshable { await store.load() }
            .waveBackground(.mind(mood: store.waveMood + 3), tinted: true)
            .toolbar(.hidden, for: .navigationBar)
        }
        .sheet(item: $reading) { syn in
            SynthesisReader(featured: syn)
        }
        .sheet(item: $openThinker) { t in
            ThinkerSheet(thinker: t)
        }
        .onChange(of: store.pendingThinker) { _, name in
            guard let name else { return }
            openThinker = store.thinkerNetwork?.thinkers
                .first(where: { $0.name == name })
            store.pendingThinker = nil
        }
        .onAppear {
            if let name = store.pendingThinker {
                openThinker = store.thinkerNetwork?.thinkers
                    .first(where: { $0.name == name })
                store.pendingThinker = nil
            }
        }
    }

    private func themeChip(_ value: String?, label: String) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) { themeFilter = value }
        } label: {
            Text(label)
                .font(.system(size: 10, design: .monospaced)
                    .weight(themeFilter == value ? .bold : .regular))
                .tracking(1.4)
                .foregroundStyle(themeFilter == value ? Theme.paper : Theme.ink)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(themeFilter == value ? Theme.ink : Color.white.opacity(0.3),
                            in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// One synthesis on the shelf — editorial row, alternating alignment.
struct SynthesisRow: View {
    let syn: FeaturedSynthesis
    let rank: Int
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            VStack(alignment: rank.isMultiple(of: 2) ? .leading : .trailing,
                   spacing: 5) {
                Text(syn.date)
                    .font(.system(size: 9, design: .monospaced))
                    .tracking(1.4)
                    .foregroundStyle(Theme.inkSoft)
                Text(syn.title)
                    .font(.system(size: rank == 0 ? 20 : 15,
                                  weight: .semibold, design: .serif))
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(rank.isMultiple(of: 2) ? .leading : .trailing)
                Theme.stroke.frame(height: 0.7)
            }
            .frame(maxWidth: .infinity,
                   alignment: rank.isMultiple(of: 2) ? .leading : .trailing)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// A thinker's face from Wikipedia, rendered in the app's duotone.
struct WikiPortrait: View {
    let name: String
    var size: CGFloat = 72

    @State private var url: URL?
    @State private var failed = false

    var body: some View {
        Group {
            if let url, !failed {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable().scaledToFill()
                            .saturation(0)                     // engraving gray
                            .colorMultiply(Color(red: 0.96, green: 0.93, blue: 0.87))
                            .contrast(1.08)
                    case .failure:
                        placeholder.onAppear { failed = true }
                    default:
                        Rectangle().fill(Theme.paperDeep)
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(Theme.stroke))
        .task { url = await WikiCache.shared.thumbnail(for: name) }
    }

    private var placeholder: some View {
        ZStack {
            Circle().fill(Theme.paperDeep)
            StippleIllustration(seed: name.count * 13, dots: 260)
                .frame(width: size * 0.8, height: size * 0.8)
        }
    }
}

/// Tiny Wikipedia summary cache: thumbnail + extract + page URL per name.
actor WikiCache {
    static let shared = WikiCache()
    struct Summary { var thumb: URL?; var extract: String; var page: URL? }
    private var cache: [String: Summary] = [:]

    func summary(for name: String) async -> Summary? {
        if let hit = cache[name] { return hit }
        let slug = name.replacingOccurrences(of: " ", with: "_")
            .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name
        guard let url = URL(string: "https://en.wikipedia.org/api/rest_v1/page/summary/\(slug)")
        else { return nil }
        do {
            let (data, resp) = try await URLSession.shared.data(from: url)
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            struct DTO: Decodable {
                struct Thumb: Decodable { var source: String }
                struct URLs: Decodable {
                    struct Page: Decodable { var page: String }
                    var desktop: Page
                }
                var thumbnail: Thumb?
                var extract: String?
                var content_urls: URLs?
            }
            let dto = try JSONDecoder().decode(DTO.self, from: data)
            let s = Summary(
                thumb: dto.thumbnail.flatMap { URL(string: $0.source) },
                extract: dto.extract ?? "",
                page: dto.content_urls.flatMap { URL(string: $0.desktop.page) })
            cache[name] = s
            return s
        } catch { return nil }
    }

    func thumbnail(for name: String) async -> URL? {
        await summary(for: name)?.thumb
    }
}

/// Grid cell: face, name, first theme.
struct ThinkerCell: View {
    let thinker: Thinker

    var body: some View {
        VStack(spacing: 8) {
            WikiPortrait(name: thinker.name, size: 84)
            Text(thinker.name)
                .font(.system(size: 15, weight: .semibold, design: .serif))
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.center)
                .lineLimit(2)
            Text((thinker.anchor ? "ANCHOR" : thinker.themes.first ?? "").uppercased())
                .font(.system(size: 8, design: .monospaced))
                .tracking(1.6)
                .foregroundStyle(thinker.anchor ? Theme.accent : Theme.inkSoft)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Color.white.opacity(0.22),
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .contentShape(Rectangle())
    }
}

/// The thinker's page: face, how they matter to Hector, their work, and
/// the door to the open web.
struct ThinkerSheet: View {
    let thinker: Thinker
    @State private var extract = ""
    @State private var page: URL?

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                WikiPortrait(name: thinker.name, size: 130)
                    .padding(.top, 12)
                Text(thinker.name.uppercased())
                    .font(.system(size: 12, design: .monospaced).weight(.bold))
                    .tracking(2.6)
                Text(thinker.tagline)
                    .font(.system(size: 16, design: .serif))
                    .italic()
                    .multilineTextAlignment(.center)
                    .lineSpacing(5)
                HStack(spacing: 6) {
                    ForEach(thinker.themes, id: \.self) { th in
                        Text(th.uppercased())
                            .font(.system(size: 8, design: .monospaced))
                            .tracking(1.4)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.white.opacity(0.35), in: Capsule())
                    }
                }
                if !thinker.relation.isEmpty {
                    Theme.stroke.frame(width: 60, height: 1)
                    Text("IN YOUR VAULT")
                        .font(.system(size: 10, design: .monospaced).weight(.semibold))
                        .tracking(2.0)
                        .foregroundStyle(Theme.accent)
                    Text(thinker.relation)
                        .font(.system(size: 14, design: .serif))
                        .lineSpacing(5)
                        .multilineTextAlignment(.center)
                }
                if !extract.isEmpty {
                    Theme.stroke.frame(width: 60, height: 1)
                    Text("THE WORK")
                        .font(.system(size: 10, design: .monospaced).weight(.semibold))
                        .tracking(2.0)
                        .foregroundStyle(Theme.accent)
                    Text(extract)
                        .font(.system(size: 14, design: .serif))
                        .lineSpacing(5)
                        .multilineTextAlignment(.center)
                }
                if let page {
                    Link(destination: page) {
                        Text("READ MORE ON THE OPEN WEB")
                            .font(.system(size: 10, design: .monospaced).weight(.semibold))
                            .tracking(1.6)
                            .underline()
                            .foregroundStyle(Theme.accent)
                    }
                    .padding(.top, 6)
                }
            }
            .padding(24)
            .padding(.bottom, 40)
        }
        .presentationBackground(Theme.paper)
        .task {
            if let s = await WikiCache.shared.summary(for: thinker.name) {
                extract = String(s.extract.prefix(500))
                page = s.page
            }
        }
    }
}
