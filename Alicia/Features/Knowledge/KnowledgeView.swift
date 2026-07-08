import SwiftUI

/// Knowledge — the tab where the vault comes to the phone: the freshest
/// syntheses off the shelf, and the thinker network with faces.
struct KnowledgeView: View {
    @Environment(AppStore.self) private var store
    @State private var themeFilter: String?
    @State private var reading: FeaturedSynthesis?
    @State private var openThinker: Thinker?
    @State private var searchText = ""

    private var thinkers: [Thinker] {
        let all = store.thinkerNetwork?.thinkers ?? []
        guard let themeFilter else { return all }
        return all.filter { $0.themes.contains(themeFilter) }
    }

    /// The words Hector keeps circling (v28): counted across the fresh
    /// shelf, the recurring substantial words — value, quality, willingness
    /// — get her squiggle wherever they appear in the titles.
    private var hotWords: Set<String> {
        let stop: Set<String> = [
            "the", "and", "that", "with", "this", "from", "into", "what",
            "when", "which", "must", "because", "only", "every", "their",
            "there", "about", "itself", "between", "becomes", "being",
            "most", "then", "than", "them", "does", "doing", "makes",
            "cannot", "where", "under", "after", "before", "against",
        ]
        var counts: [String: Int] = [:]
        for syn in store.syntheses {
            let words = (syn.title + " " + syn.excerpt).lowercased()
                .split(whereSeparator: { !$0.isLetter })
            for raw in words {
                let w = String(raw)
                guard w.count >= 5, !stop.contains(w) else { continue }
                counts[w, default: 0] += 1
            }
        }
        return Set(counts.filter { $0.value >= 3 }
            .sorted { $0.value > $1.value }
            .prefix(8)
            .map(\.key))
    }

    var body: some View {
        @Bindable var store = store
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    SectionHeader(title: store.knowledgeSegment == 0
                                  ? "Knowledge" : "The Thinkers",
                                  kicker: store.knowledgeSegment == 0
                                  ? "the vault, in your pocket"
                                  : "\(thinkers.count) minds, hand in hand")

                    // v21: two rooms, one door — her underline marks which.
                    InkTabs(items: ["Knowledge", "Thinkers"],
                            selection: $store.knowledgeSegment)
                        .padding(.bottom, 4)

                    if store.knowledgeSegment == 0 {
                        shelf
                    } else {
                        thinkersRoom
                    }
                }
                .padding(16)
                .padding(.bottom, 24)
            }
            .refreshable { await store.load() }
            // v27: not water here — a constellation of idea-nodes drifting
            // and faintly finding each other.
            .waveBackground(.knowledge(mood: store.waveMood + 3), tinted: true)
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
            store.knowledgeSegment = 1
            openThinker = store.thinkerNetwork?.thinkers
                .first(where: { $0.name == name })
            store.pendingThinker = nil
        }
        .onAppear {
            if let name = store.pendingThinker {
                store.knowledgeSegment = 1
                openThinker = store.thinkerNetwork?.thinkers
                    .first(where: { $0.name == name })
                store.pendingThinker = nil
            }
        }
    }

    /// Segment 0 — the syntheses shelf.
    @ViewBuilder private var shelf: some View {
        if !store.syntheses.isEmpty {
            Text("FRESH FROM THE SHELF")
                .font(.system(size: 10, design: .monospaced).weight(.semibold))
                .tracking(2.0)
                .foregroundStyle(Theme.inkSoft)
            let hot = hotWords
            ForEach(Array(store.syntheses.enumerated()), id: \.element.title) { i, syn in
                SynthesisRow(syn: syn, rank: i, hot: hot) { reading = syn }
            }
        } else {
            ProgressView("Reaching the shelf…")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
        }
    }

    /// Segment 1 — the whole network, searchable + filterable by theme.
    @ViewBuilder private var thinkersRoom: some View {
        // v29: 313 minds need a way in — a simple line to write a name on.
        VStack(spacing: 2) {
            HStack(spacing: 8) {
                InkSpark(size: 11, color: Theme.inkSoft, seed: 43)
                TextField("find a mind…", text: $searchText)
                    .font(.system(size: 14, design: .serif))
                    .italic()
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                if !searchText.isEmpty {
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) { searchText = "" }
                    } label: {
                        Text("CLEAR")
                            .font(.system(size: 8, design: .monospaced).weight(.semibold))
                            .tracking(1.2)
                            .underline()
                            .foregroundStyle(Theme.inkSoft)
                    }
                    .buttonStyle(.plain)
                }
            }
            InkUnderline(color: Theme.ink.opacity(0.35), seed: 43)
                .frame(height: 5)
        }
        .padding(.bottom, 4)

        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                themeChip(nil, label: "ALL")
                ForEach(store.thinkerNetwork?.themes ?? [], id: \.self) { th in
                    themeChip(th, label: th.uppercased())
                }
            }
        }
        let visible = searched
        if visible.isEmpty, !searchText.isEmpty {
            Text("no mind by that name yet")
                .font(.system(size: 13, design: .serif))
                .italic()
                .foregroundStyle(Theme.inkSoft)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 30)
        }
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 14),
                            GridItem(.flexible(), spacing: 14)],
                  spacing: 14) {
            ForEach(visible) { thinker in
                ThinkerCell(thinker: thinker)
                    .onTapGesture { openThinker = thinker }
            }
        }
    }

    /// Theme filter + typed search, folded (case/diacritic-blind).
    private var searched: [Thinker] {
        let q = searchText.inkFolded
        guard !q.isEmpty else { return thinkers }
        return thinkers.filter {
            $0.name.inkFolded.contains(q) || $0.tagline.inkFolded.contains(q)
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
/// v28: the words he keeps repeating wear her squiggle.
struct SynthesisRow: View {
    let syn: FeaturedSynthesis
    let rank: Int
    var hot: Set<String> = []
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            VStack(alignment: rank.isMultiple(of: 2) ? .leading : .trailing,
                   spacing: 5) {
                Text(syn.date)
                    .font(.system(size: 9, design: .monospaced))
                    .tracking(1.4)
                    .foregroundStyle(Theme.inkSoft)
                InkHighlightedText(text: syn.title.strippedEmojis,
                                   emphasize: hot,
                                   size: rank == 0 ? 20 : 15,
                                   weight: .semibold,
                                   trailing: !rank.isMultiple(of: 2))
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
/// v29: looks up through the network's corrected wiki slug when one
/// exists (Seneca → Seneca_the_Younger, typo fixes, ...), so the audit's
/// 26 repaired portraits actually repair.
struct WikiPortrait: View {
    @Environment(AppStore.self) private var store
    let name: String
    var size: CGFloat = 72

    @State private var url: URL?
    @State private var failed = false

    private var lookupName: String {
        (store.thinkerNetwork?.thinkers
            .first(where: { $0.name == name })?.wiki ?? name)
            .replacingOccurrences(of: "_", with: " ")
    }

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
        // v21: her pen over the photograph — an unfinished tracing ring and
        // a few tangent hatches, as if she's surfacing the face. Replaces
        // the geometric hairline.
        .overlay(PortraitTrace(name: name).padding(-size * 0.09))
        .task { url = await WikiCache.shared.thumbnail(for: lookupName) }
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

/// The thinker's page: face, how they matter to Hector, their work, the
/// door to the open web — and the graph underneath: the thinkers most
/// connected to this one, each a tap away, so you can keep walking the
/// network without ever leaving the sheet.
struct ThinkerSheet: View {
    @Environment(AppStore.self) private var store
    let thinker: Thinker
    @State private var current: Thinker?
    @State private var path: [Thinker] = []   // hops behind the current one
    @State private var extract = ""
    @State private var page: URL?

    private var shown: Thinker { current ?? thinker }

    /// Resolve a related-thinker edge to the full record in the network.
    private func resolve(_ name: String) -> Thinker? {
        store.thinkerNetwork?.thinkers.first(where: { $0.name == name })
    }

    private func hop(to name: String) {
        guard let next = resolve(name) else { return }
        withAnimation(.easeInOut(duration: 0.18)) {
            path.append(shown)
            current = next
        }
    }

    /// What leaves the page when he shares this mind (v29).
    private var thinkerShareText: String {
        var lines = [shown.name]
        if !shown.tagline.isEmpty { lines.append(shown.tagline) }
        if !shown.relation.isEmpty { lines.append(shown.relation) }
        let slug = shown.wiki
            ?? shown.name.replacingOccurrences(of: " ", with: "_")
        lines.append("https://en.wikipedia.org/wiki/\(slug)")
        lines.append("— from Alicia's thinker map")
        return lines.joined(separator: "\n")
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                if !path.isEmpty {
                    // The walked path, latest hop last — tap ← to step back.
                    HStack(spacing: 6) {
                        Button {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                current = path.popLast()
                            }
                        } label: {
                            InkChevron(pointing: .left, size: 14,
                                       color: Theme.accent, seed: 37)
                        }
                        .buttonStyle(.plain)
                        Text((path.map(\.name) + [shown.name])
                            .joined(separator: " → "))
                            .font(.system(size: 9, design: .monospaced))
                            .tracking(0.6)
                            .foregroundStyle(Theme.inkSoft)
                            .lineLimit(1)
                            .truncationMode(.head)
                        Spacer()
                    }
                    .padding(.top, 14)
                }
                WikiPortrait(name: shown.name, size: 130)
                    .padding(.top, path.isEmpty ? 12 : 0)
                    .id(shown.name)   // fresh portrait per hop
                    // v29: send this mind to a friend.
                    .overlay(alignment: .topLeading) {
                        ShareLink(item: thinkerShareText) {
                            InkShareGlyph(size: 24, seed: shown.name.inkSeed &+ 5)
                        }
                        .buttonStyle(.plain)
                        .offset(x: -34, y: -6)
                    }
                    // v26: hold this thinker on the home screen — the dot
                    // becomes her star, and she notes the interest.
                    .overlay(alignment: .topTrailing) {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                store.togglePin(
                                    id: "thinker:" + shown.name.inkSlug,
                                    kind: "thinker", title: shown.name,
                                    body: shown.tagline,
                                    thinker: shown.name, source: "thinkers")
                            }
                        } label: {
                            InkPinMark(
                                pinned: store.isPinned("thinker:" + shown.name.inkSlug),
                                size: 26, seed: shown.name.inkSeed)
                        }
                        .buttonStyle(.plain)
                        .offset(x: 34, y: -6)
                    }
                // The name in her hand — cursive, not a label (v27).
                InkTitleLine(text: shown.name, size: 24)
                Text(shown.tagline)
                    .font(.system(size: 16, design: .serif))
                    .italic()
                    .multilineTextAlignment(.center)
                    .lineSpacing(5)
                // Wraps instead of squeezing — six themes broke mid-word.
                FlexWrap(spacing: 6) {
                    ForEach(shown.themes, id: \.self) { th in
                        Text(th.uppercased())
                            .font(.system(size: 8, design: .monospaced))
                            .tracking(1.4)
                            .fixedSize()
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.white.opacity(0.35), in: Capsule())
                    }
                }
                .frame(maxWidth: 300)
                if !shown.relation.isEmpty {
                    InkDividerCurl(seed: shown.name.inkSeed)
                        .frame(width: 96, height: 14)
                    Text("IN YOUR VAULT")
                        .font(.system(size: 10, design: .monospaced).weight(.semibold))
                        .tracking(2.0)
                        .foregroundStyle(Theme.accent)
                    // Her marginalia: the load-bearing words underlined,
                    // a faint thread arcing between them (v27).
                    InkAnnotatedText(text: shown.relation, size: 14)
                }
                if !extract.isEmpty {
                    InkDividerCurl(seed: shown.name.inkSeed &+ 7)
                        .frame(width: 96, height: 14)
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

                // ── The graph, hand-stitched: her threads connecting the
                // minds, faces staggered like a constellation she drew ──
                if let related = shown.related, !related.isEmpty {
                    InkDividerCurl(seed: shown.name.inkSeed &+ 13)
                        .frame(width: 96, height: 14)
                    Text("MINDS LIKE THIS ONE")
                        .font(.system(size: 10, design: .monospaced).weight(.semibold))
                        .tracking(2.0)
                        .foregroundStyle(Theme.accent)
                        .padding(.top, 8)
                    ThinkerConstellation(
                        related: related,
                        isResolvable: { resolve($0) != nil },
                        hop: { hop(to: $0) })
                }
            }
            .padding(24)
            .padding(.bottom, 40)
        }
        .presentationBackground(Theme.paper)
        .task(id: shown.name) {
            extract = ""
            page = nil
            let lookup = (shown.wiki ?? shown.name)
                .replacingOccurrences(of: "_", with: " ")
            if let s = await WikiCache.shared.summary(for: lookup) {
                extract = String(s.extract.prefix(500))
                page = s.page
            }
        }
    }
}

// ThinkersPage (the old pushed subpage) folded into KnowledgeView's
// THINKERS segment in v21 — one door, two rooms.

