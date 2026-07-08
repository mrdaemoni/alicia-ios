import SwiftUI

/// Us — the landing page. Hector's `memories` drawing (the figure before
/// the sea) washes down from the top of the page; beneath it: her greeting,
/// the latest thing she said, what her day held, and a quiet status strip.
struct HomeView: View {
    @Environment(AppStore.self) private var store

    /// Her line, when the backend has one — grounded in what you two are
    /// actually talking about. Time-of-day only as the offline fallback.
    private var greeting: String {
        if let live = store.greeting, !live.isEmpty { return live.strippedEmojis }
        switch Calendar.current.component(.hour, from: .now) {
        case 5..<12:  return "Good morning, Hector"
        case 12..<18: return "Good afternoon, Hector"
        default:      return "Good evening, Hector"
        }
    }

    /// Her most recent proactive message (the timeline seeds oldest-first).
    private var latestWord: Message? {
        store.messages.last(where: { $0.proactiveLabel != nil })
    }

    private var seasonThought: Thought? {
        store.thoughts.first(where: { $0.tag == "emergence" })
    }

    private var dayThought: Thought? {
        store.thoughts.first(where: { $0.tag != "emergence" })
    }

    @State private var showTimeline = false

    var body: some View {
        @Bindable var store = store
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Button { showTimeline = true } label: {
                        SectionHeader(title: "Us",
                                      kicker: Date.now.formatted(date: .complete, time: .omitted))
                    }
                    .buttonStyle(.plain)
                    header

                    if let track = store.nowPlaying {
                        nowPlayingChip(track)
                    }

                    if let latest = store.proactiveFeed.first {
                        ProactiveReplyCard(proactive: latest)
                    } else if let word = latestWord {
                        card(icon: "quote.opening",
                             title: word.proactiveLabel ?? "from Alicia",
                             body: word.text)
                    }

                    // ── What he's holding — pinned until he lets go ──
                    if let held = store.homeContext?.pinned, !held.isEmpty {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("HELD · STILL TALKING ABOUT")
                                .font(.system(size: 10, design: .monospaced).weight(.semibold))
                                .tracking(2.0)
                                .foregroundStyle(Theme.accent)
                                .padding(.leading, 2)
                            ForEach(held) { card in
                                KnowledgeCardView(card: card)
                            }
                        }
                    }

                    // ── The loops — widest to innermost, zooming in ──
                    if let home = store.homeContext {
                        if let season = home.season {
                            SeasonArcCard(season: season)
                        }
                        if !home.trail.isEmpty {
                            TrailCard(trail: home.trail)
                        }
                        if let today = home.today {
                            TodayEpisodeCard(today: today)
                        }
                        if !home.cards.isEmpty {
                            KnowledgeCardsSection(cards: home.cards)
                        }
                    }

                    if let featured = store.featured {
                        FeaturedSynthesisCard(featured: featured)
                    }

                    if let quote = store.quote {
                        QuoteCard(quote: quote)
                    }

                    BestDrawingCard(candidates: store.gallery.filter { $0.imageURL != nil })

                    if let top = store.rankedArchetypes.first,
                       let arch = Archetypes.get(top.name) {
                        ArchetypeCard(arch: arch, count: top.count)
                    }

                    KnowingCard()

                    // Only when the loops don't already carry today's pick.
                    if store.homeContext?.today == nil,
                       !store.suggestedTracks.isEmpty {
                        EpisodeAskCard()
                    }

                    if !store.episodeThinkers.isEmpty {
                        ThinkerStrip(thinkers: store.episodeThinkers)
                    }

                    if let day = dayThought {
                        card(icon: "sun.horizon.fill",
                             title: day.title,
                             body: day.body)
                    }

                    statusStrip
                }
                .padding(16)
                .padding(.bottom, 24)
            }
            .refreshable { await store.load() }
            // The living field — contour waves under the hour's color and
            // a fine paper grain. Dawn washes rose, night runs indigo.
            .waveBackground(.us(mood: store.waveMood), tinted: true)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showTimeline) { UsSheet() }
            // Thinkers open where you are (v27).
            .sheet(item: $store.presentThinker) { t in ThinkerSheet(thinker: t) }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Her greeting in her own hand (v26) — each glyph leans and
            // settles a hair off the baseline.
            InkTitle(text: greeting, size: 32)
            if let season = seasonThought {
                Text(season.body.strippedEmojis)
                    .font(.system(.subheadline, design: .serif))
                    .italic()
                    .foregroundStyle(Theme.ink.opacity(0.65))
            } else {
                Text(Date.now.formatted(date: .complete, time: .omitted))
                    .font(.system(.subheadline, design: .serif))
                    .italic()
                    .foregroundStyle(Theme.ink.opacity(0.65))
            }
        }
        // Let the wave field breathe above the greeting.
        .padding(.top, 96)
    }

    private func nowPlayingChip(_ track: Track) -> some View {
        HStack(spacing: 10) {
            Group {
                if store.isPlaying {
                    InkWaveBars(size: 22, seed: track.title.inkSeed)
                } else {
                    InkPlayPause(playing: false, size: 22,
                                 seed: track.title.inkSeed)
                }
            }
            .frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text(track.title).font(.footnote.weight(.semibold)).lineLimit(1)
                Text(track.mood).font(.caption2).foregroundStyle(Theme.inkSoft).lineLimit(1)
            }
            Spacer()
            Button { store.togglePlay() } label: {
                InkPlayPause(playing: store.isPlaying, size: 30,
                             color: Theme.accent, ringed: true)
            }
        }
        .card(padding: 10, radius: 18)
    }

    private func card(icon: String, title: String, body rawText: String) -> some View {
        let text = rawText.strippedEmojis
        return VStack(alignment: .leading, spacing: 8) {
            // Her spark where a system glyph used to sit (v22).
            HStack(spacing: 6) {
                InkSpark(size: 11, seed: title.inkSeed)
                Text(title.strippedEmojis)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(Theme.accentSoft)
            .lineLimit(1)
            Text((try? AttributedString(
                    markdown: text,
                    options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
                 ?? AttributedString(text))
                .font(.subheadline)
                .lineLimit(8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 14, radius: 20)
    }

    private var statusStrip: some View {
        NavigationLink {
            HealthView()
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    HStack(spacing: 6) {
                        InkWaveBars(size: 13, color: Theme.accentSoft, seed: 5)
                        Text("Status")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.accentSoft)
                    Spacer()
                    InkChevron(pointing: .right, size: 13,
                               color: Theme.inkSoft.opacity(0.75), seed: 9)
                }
                ForEach(store.health.prefix(4)) { metric in
                    HStack(spacing: 10) {
                        Image(systemName: metric.symbol)
                            .font(.caption)
                            .foregroundStyle(metric.color)
                            .frame(width: 18)
                        Text(metric.name).font(.caption)
                        Spacer()
                        Text(metric.display)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(Theme.inkSoft)
                        ProgressView(value: metric.value)
                            .tint(metric.color)
                            .frame(width: 64)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card(padding: 14, radius: 20)
        }
        .buttonStyle(.plain)
    }
}

/// Her latest word on the Us page, with a reply field right underneath —
/// answering here lands in her memory, the shared history, and the
/// relationship's learning loops, exactly like a Telegram reply.
struct ProactiveReplyCard: View {
    @Environment(AppStore.self) private var store
    let proactive: ProactiveMessage
    @State private var draft = ""
    @State private var sending = false
    @State private var herReply: String?
    @FocusState private var focused: Bool

    private var label: String {
        [proactive.kind.replacingOccurrences(of: "_", with: " "),
         proactive.archetype]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 5) {
                Image("RabbitMark")
                    .resizable().scaledToFit()
                    .frame(width: 15, height: 15)
                    .foregroundStyle(Theme.accentSoft)
                Text(label.isEmpty ? "from Alicia" : label)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(Theme.accentSoft)

            Text((try? AttributedString(
                    markdown: proactive.text.strippedEmojis,
                    options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
                 ?? AttributedString(proactive.text.strippedEmojis))
                .font(.subheadline)
                .lineLimit(10)

            if let herReply {
                Divider().overlay(Theme.stroke)
                Text(herReply)
                    .font(.subheadline)
                    .italic()
                    .foregroundStyle(Theme.ink.opacity(0.85))
            }

            HStack(spacing: 8) {
                TextField("Answer her…", text: $draft, axis: .vertical)
                    .lineLimit(1...4)
                    .focused($focused)
                    .font(.subheadline)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.30), in: Capsule())
                Button {
                    let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty, !sending else { return }
                    draft = ""
                    focused = false
                    sending = true
                    Task {
                        herReply = await store.replyToProactive(proactive, text: text)
                            ?? "(couldn't reach her — try again)"
                        sending = false
                    }
                } label: {
                    if sending {
                        ProgressView().frame(width: 32, height: 32)
                    } else {
                        InkSubmitArrow(size: 32, seed: proactive.id.inkSeed)
                    }
                }
                .disabled(sending || draft.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 14, radius: 20)
    }
}

/// The synthesis of the day — an editorial reading card in the Co-Star
/// register: mono-caps kicker, big serif display title, a stipple engraving,
/// and the whole thing opens into a full reader.
struct FeaturedSynthesisCard: View {
    let featured: FeaturedSynthesis
    @State private var reading = false

    var body: some View {
        Button { reading = true } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("FEATURED SYNTHESIS")
                        .font(.system(.caption2, design: .monospaced).weight(.semibold))
                        .tracking(1.6)
                        .foregroundStyle(Theme.inkSoft)
                    Spacer()
                    StippleIllustration(dots: 700, animated: true)
                        .frame(width: 44, height: 44)
                }
                Text(featured.title.strippedEmojis)
                    .font(.system(.title3, design: .serif, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Text(featured.excerpt.strippedEmojis)
                    .font(.system(.footnote, design: .serif))
                    .foregroundStyle(Theme.ink.opacity(0.75))
                    .lineLimit(4)
                    .multilineTextAlignment(.leading)
                Text("READ")
                    .font(.system(.caption, design: .monospaced).weight(.semibold))
                    .tracking(1.4)
                    .underline()
                    .foregroundStyle(Theme.accent)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card(padding: 16, radius: 20)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $reading) {
            SynthesisReader(featured: featured)
        }
    }
}

#Preview {
    HomeView()
        .environment(AppStore(service: MockAliciaService()))
        .tint(Theme.accent)
        .preferredColorScheme(.dark)
}

/// The reading room: the synthesis typeset like an essay, not dumped as
/// text. Headings become centered mono-caps rules, paragraphs breathe,
/// bold sources stand out, and every thinker linked in the piece becomes a
/// chip — tap one and you're in Dialogue asking her about them.
struct SynthesisReader: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let featured: FeaturedSynthesis

    /// A parsed block of the synthesis body.
    private enum Block: Identifiable {
        case heading(String)
        case paragraph(AttributedString)
        var id: UUID { UUID() }
    }

    /// [[Books/On Quality/OnQuality-21]] → "On Quality"; [[writing/X]] → "X".
    private static func thinkers(in body: String) -> [String] {
        var names: [String] = []
        var searchRange = body.startIndex..<body.endIndex
        while let open = body.range(of: "[[", range: searchRange),
              let close = body.range(of: "]]", range: open.upperBound..<body.endIndex) {
            let target = String(body[open.upperBound..<close.lowerBound])
            let parts = target.split(separator: "/")
            let name = String(parts.count >= 2 ? parts[1] : parts.first ?? "")
                .replacingOccurrences(of: "-", with: " ")
            if !name.isEmpty, !names.contains(name) { names.append(name) }
            searchRange = close.upperBound..<body.endIndex
        }
        return Array(names.prefix(6))
    }

    /// Strip wikilink brackets for reading; keep the inner display name.
    private static func cleanInline(_ text: String) -> String {
        var t = text
        while let open = t.range(of: "[["),
              let close = t.range(of: "]]", range: open.upperBound..<t.endIndex) {
            let target = String(t[open.upperBound..<close.lowerBound])
            let display = target.split(separator: "/").last.map(String.init) ?? target
            t.replaceSubrange(open.lowerBound..<close.upperBound, with: display)
        }
        return t
    }

    private var blocks: [Block] {
        featured.body.strippedEmojis.components(separatedBy: "\n\n").compactMap { raw in
            let p = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !p.isEmpty else { return nil }
            if p.hasPrefix("## ") {
                return .heading(String(p.dropFirst(3)))
            }
            let cleaned = Self.cleanInline(p)
            let attr = (try? AttributedString(
                markdown: cleaned,
                options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
                ?? AttributedString(cleaned)
            return .paragraph(attr)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                StippleIllustration(animated: true)
                    .frame(height: 140)
                    .frame(maxWidth: .infinity)
                Text("SYNTHESIS · \(featured.date)")
                    .font(.system(size: 10, design: .monospaced))
                    .tracking(2.0)
                    .foregroundStyle(Theme.inkSoft)
                    .frame(maxWidth: .infinity)
                Text(featured.title)
                    .font(.system(.title2, design: .serif, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                Theme.stroke.frame(width: 60, height: 1)
                    .frame(maxWidth: .infinity)

                ForEach(blocks) { block in
                    switch block {
                    case .heading(let h):
                        Text(h.uppercased())
                            .font(.system(size: 11, design: .monospaced).weight(.semibold))
                            .tracking(2.0)
                            .foregroundStyle(Theme.accent)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 10)
                    case .paragraph(let p):
                        Text(p)
                            .font(.system(size: 16, design: .serif))
                            .lineSpacing(6.5)
                            .foregroundStyle(Theme.ink.opacity(0.92))
                    }
                }

                let thinkers = Self.thinkers(in: featured.body)
                if !thinkers.isEmpty {
                    Text("VOICES IN THIS PIECE")
                        .font(.system(size: 10, design: .monospaced).weight(.semibold))
                        .tracking(2.0)
                        .foregroundStyle(Theme.inkSoft)
                        .padding(.top, 14)
                    FlowChips(items: thinkers) { name in
                        // Ask her about the thinker, right in Dialogue.
                        dismiss()
                        store.selectedSection = .dialogue
                        store.send("Tell me about \(name) and why this synthesis leans on them.")
                    }
                }
            }
            .padding(24)
            .padding(.bottom, 40)
        }
        .presentationBackground(Theme.paper)
    }
}

/// Simple wrapping chip row.
struct FlowChips: View {
    let items: [String]
    let action: (String) -> Void

    var body: some View {
        FlexWrap(spacing: 8) {
            ForEach(items, id: \.self) { name in
                Button { action(name) } label: {
                    Text(name)
                        .font(.system(size: 12, design: .monospaced))
                        .underline()
                        .foregroundStyle(Theme.accent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.35), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// Minimal wrap layout for chips and hand-set words. v28: optional
/// trailing alignment (rows hug the right edge) so the editorial
/// alternating-alignment shelf can carry highlighted words too.
struct FlexWrap: Layout {
    var spacing: CGFloat = 8
    var trailing: Bool = false

    /// Group subview indices into rows for the given width.
    private func rows(_ subviews: Subviews, width: CGFloat) -> [[Int]] {
        var out: [[Int]] = [[]]
        var x: CGFloat = 0
        for (i, sub) in subviews.enumerated() {
            let s = sub.sizeThatFits(.unspecified)
            if x + s.width > width, !out[out.count - 1].isEmpty {
                out.append([])
                x = 0
            }
            out[out.count - 1].append(i)
            x += s.width + spacing
        }
        return out
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 320
        var y: CGFloat = 0
        for row in rows(subviews, width: width) {
            let h = row.map { subviews[$0].sizeThatFits(.unspecified).height }.max() ?? 0
            y += h + (y > 0 ? spacing : 0)
        }
        return CGSize(width: width, height: y)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(subviews, width: bounds.width) {
            let sizes = row.map { subviews[$0].sizeThatFits(.unspecified) }
            let rowW = sizes.map(\.width).reduce(0, +)
                + spacing * CGFloat(max(0, row.count - 1))
            let rowH = sizes.map(\.height).max() ?? 0
            var x = trailing ? bounds.maxX - rowW : bounds.minX
            for (k, i) in row.enumerated() {
                subviews[i].place(at: CGPoint(x: x, y: y), proposal: .unspecified)
                x += sizes[k].width + spacing
            }
            y += rowH + spacing
        }
    }
}

/// Her best recent drawing, elevated — a full-bleed image card with her
/// caption as the label. The rotation of the drawing algorithm now leads
/// ink-on-bone, so these read as part of the same page.
struct BestDrawingCard: View {
    /// Newest-first candidates; a failed/pruned image falls through to the
    /// next instead of leaving an empty frame (the "nothing rendered" bug).
    let candidates: [Artwork]
    @State private var idx = 0

    private var art: Artwork? {
        candidates.indices.contains(idx) ? candidates[idx] : nil
    }

    var body: some View {
        if let art, let url = art.imageURL {
            VStack(alignment: .leading, spacing: 10) {
                Text("FROM HER HAND")
                    .font(.system(size: 10, design: .monospaced).weight(.semibold))
                    .tracking(2.0)
                    .foregroundStyle(Theme.inkSoft)
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .failure:
                        Color.clear.onAppear { idx += 1 }
                    default:
                        Rectangle().fill(Theme.paperDeep)
                    }
                }
                .frame(height: 230)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                Text(art.title)
                    .font(.system(.footnote, design: .serif))
                    .italic()
                    .foregroundStyle(Theme.ink.opacity(0.7))
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card(padding: 14, radius: 22)
        }
    }
}

/// The quote of the moment — copyable, editorial, centered.
struct QuoteCard: View {
    let quote: (text: String, author: String)
    @State private var copied = false

    var body: some View {
        VStack(spacing: 12) {
            Text("QUOTE OF THE MOMENT")
                .font(.system(size: 10, design: .monospaced).weight(.semibold))
                .tracking(2.0)
                .foregroundStyle(Theme.inkSoft)
            Text("“" + quote.text.strippedEmojis + "”")
                .font(.system(size: 17, design: .serif))
                .italic()
                .lineSpacing(5)
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.ink)
            if !quote.author.isEmpty {
                Text("— " + quote.author)
                    .font(.system(size: 11, design: .monospaced))
                    .tracking(1.2)
                    .foregroundStyle(Theme.inkSoft)
            }
            Button {
                UIPasteboard.general.string = "“" + quote.text + "”"
                    + (quote.author.isEmpty ? "" : " — " + quote.author)
                withAnimation { copied = true }
                Task {
                    try? await Task.sleep(for: .seconds(2))
                    withAnimation { copied = false }
                }
            } label: {
                Text(copied ? "COPIED" : "COPY")
                    .font(.system(size: 10, design: .monospaced).weight(.semibold))
                    .tracking(1.6)
                    .underline()
                    .foregroundStyle(copied ? Theme.mint : Theme.accent)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .card(padding: 18, radius: 20)
    }
}

/// The voice speaking loudest right now — her body, her role; tapping
/// opens her page on the Alicia tab.
struct ArchetypeCard: View {
    @Environment(AppStore.self) private var store
    let arch: Archetype
    let count: Int

    var body: some View {
        Button {
            store.selectedSection = .mind
        } label: {
            HStack(spacing: 16) {
                StippleIllustration(seed: arch.seed, dots: 1100, animated: true)
                    .frame(width: 84, height: 84)
                VStack(alignment: .leading, spacing: 4) {
                    Text("THE VOICE OF THE MOMENT")
                        .font(.system(size: 9, design: .monospaced).weight(.semibold))
                        .tracking(1.8)
                        .foregroundStyle(Theme.inkSoft)
                    Text(arch.name)
                        .font(.system(size: 24, weight: .semibold, design: .serif))
                        .foregroundStyle(Theme.ink)
                    Text(arch.role)
                        .font(.system(size: 13, design: .serif))
                        .italic()
                        .foregroundStyle(Theme.ink.opacity(0.7))
                }
                Spacer()
                InkChevron(pointing: .right, size: 14,
                           color: Theme.inkSoft, seed: arch.seed)
            }
            .card(padding: 14, radius: 20)
        }
        .buttonStyle(.plain)
    }
}

/// "What am I listening to today?" — her top three, one tap to play.
struct EpisodeAskCard: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("TODAY'S LISTENING")
                .font(.system(size: 10, design: .monospaced).weight(.semibold))
                .tracking(2.0)
                .foregroundStyle(Theme.inkSoft)
            Text("Which episode is today's walk?")
                .font(.system(.headline, design: .serif))
                .foregroundStyle(Theme.ink)
            ForEach(store.suggestedTracks) { track in
                Button {
                    store.playFromHome(track)
                } label: {
                    HStack(spacing: 10) {
                        InkPlayPause(playing: false, size: 24,
                                     color: Theme.accent,
                                     seed: track.title.inkSeed, ringed: true)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(track.title)
                                .font(.system(size: 14, design: .serif).weight(.medium))
                                .foregroundStyle(Theme.ink)
                                .lineLimit(1)
                            Text((track.label ?? "") +
                                 (track.mood.contains("today's pick") ? " · her pick" : ""))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(Theme.inkSoft)
                        }
                        Spacer()
                        Text(track.duration.asClock)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Theme.inkSoft)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 16, radius: 20)
    }
}

/// The minds inside today's episode — tap a face to open their page in
/// Knowledge.
struct ThinkerStrip: View {
    @Environment(AppStore.self) private var store
    let thinkers: [Thinker]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("IN YOUR EARS TODAY")
                    .font(.system(size: 10, design: .monospaced).weight(.semibold))
                    .tracking(2.0)
                    .foregroundStyle(Theme.inkSoft)
                Spacer()
                Button {
                    store.knowledgeSegment = 1
                    store.selectedSection = .knowledge
                } label: {
                    Text("ALL THINKERS →")
                        .font(.system(size: 10, design: .monospaced).weight(.semibold))
                        .tracking(1.4)
                        .underline()
                        .foregroundStyle(Theme.accent)
                }
                .buttonStyle(.plain)
            }
            HStack(spacing: 14) {
                ForEach(thinkers) { t in
                    Button {
                        store.showThinker(named: t.name)   // in place (v27)
                    } label: {
                        VStack(spacing: 6) {
                            WikiPortrait(name: t.name, size: 64)
                            Text(t.name.split(separator: " ").last.map(String.init) ?? t.name)
                                .font(.system(size: 11, design: .serif).weight(.medium))
                                .foregroundStyle(Theme.ink)
                        }
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 14, radius: 20)
    }
}

// ═══ The loops — the Us tab's concentric context ═══════════════════════════

/// The widest loop she holds around Hector: the current podcast season —
/// its theme, and a spine of episode nodes showing where in the arc he is.
struct SeasonArcCard: View {
    let season: HomeContext.Season

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("THE WIDEST LOOP · SEASON \(season.season)")
                    .font(.system(size: 10, design: .monospaced).weight(.semibold))
                    .tracking(2.0)
                    .foregroundStyle(Theme.inkSoft)
                Spacer()
                Text("\(season.heardCount)/\(season.total)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Theme.inkSoft)
            }
            Text(season.title)
                .font(.system(.title3, design: .serif, weight: .semibold))
                .foregroundStyle(Theme.ink)
            if !season.subtitle.isEmpty {
                Text(season.subtitle)
                    .font(.system(.footnote, design: .serif))
                    .italic()
                    .foregroundStyle(Theme.ink.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
            }

            // The spine: one node per episode, filled once heard, the
            // accent ring on today's.
            HStack(spacing: 0) {
                ForEach(Array(season.episodes.enumerated()), id: \.element.id) { i, ep in
                    if i > 0 {
                        Rectangle()
                            .fill(Theme.stroke)
                            .frame(height: 1)
                            .frame(maxWidth: .infinity)
                    }
                    VStack(spacing: 5) {
                        Circle()
                            .fill(ep.isToday ? Theme.accent
                                  : ep.heard ? Theme.ink.opacity(0.75)
                                  : Color.clear)
                            .overlay(Circle().strokeBorder(
                                ep.isToday ? Theme.accent : Theme.inkSoft.opacity(0.5),
                                lineWidth: 1.2))
                            .frame(width: ep.isToday ? 13 : 9,
                                   height: ep.isToday ? 13 : 9)
                        Text("\(ep.episode)")
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundStyle(ep.isToday ? Theme.accent : Theme.inkSoft)
                    }
                }
            }
            .padding(.vertical, 2)

            if !season.movementNow.isEmpty {
                Text(season.movementNow.uppercased())
                    .font(.system(size: 9, design: .monospaced).weight(.semibold))
                    .tracking(1.6)
                    .foregroundStyle(Theme.accent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 16, radius: 20)
    }
}

/// The middle loop: the episodes of the previous days — the path that led
/// to today.
struct TrailCard: View {
    let trail: [HomeContext.TrailItem]

    private func when(_ item: HomeContext.TrailItem) -> String {
        guard let d = item.daysAgo else { return item.pickedDate }
        switch d {
        case 0:  return "today"
        case 1:  return "yesterday"
        default: return "\(d) days ago"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("THE TRAIL · PREVIOUS DAYS")
                .font(.system(size: 10, design: .monospaced).weight(.semibold))
                .tracking(2.0)
                .foregroundStyle(Theme.inkSoft)
            ForEach(trail) { item in
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(item.label)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(Theme.inkSoft)
                        Text(item.title)
                            .font(.system(size: 14, design: .serif).weight(.medium))
                            .foregroundStyle(Theme.ink)
                            .lineLimit(1)
                        Spacer()
                        Text(when(item))
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(Theme.inkSoft)
                    }
                    if !item.claim.isEmpty {
                        Text(item.claim)
                            .font(.system(size: 12, design: .serif))
                            .italic()
                            .foregroundStyle(Theme.ink.opacity(0.6))
                            .lineLimit(2)
                    }
                    if item.id != trail.last?.id {
                        Theme.stroke.frame(height: 0.7).padding(.top, 5)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 16, radius: 20)
    }
}

/// The innermost loop: the episode in his ears today — the thought the
/// whole day leans against. One tap to play.
struct TodayEpisodeCard: View {
    @Environment(AppStore.self) private var store
    let today: HomeContext.Today

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(today.isToday ? "TODAY · IN YOUR EARS"
                     : "STILL OPEN · PICKED \(today.pickedDate)")
                    .font(.system(size: 10, design: .monospaced).weight(.semibold))
                    .tracking(2.0)
                    .foregroundStyle(Theme.accent)
                Spacer()
                Text(today.label)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Theme.inkSoft)
            }
            Text(today.title)
                .font(.system(.title2, design: .serif, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            if !today.focus.isEmpty {
                Text(today.focus)
                    .font(.system(.subheadline, design: .serif))
                    .italic()
                    .foregroundStyle(Theme.ink.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let track = store.track(forLabel: today.label) {
                Button {
                    store.playFromHome(track)
                } label: {
                    HStack(spacing: 8) {
                        InkPlayPause(
                            playing: store.isPlaying && store.nowPlaying?.id == track.id,
                            size: 24, color: Theme.accent,
                            seed: today.label.inkSeed, ringed: true)
                        Text(store.nowPlaying?.id == track.id ? "PLAYING" : "LISTEN")
                            .font(.system(size: 10, design: .monospaced).weight(.semibold))
                            .tracking(1.6)
                            .underline()
                            .foregroundStyle(Theme.accent)
                        Text(track.duration.asClock)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(Theme.inkSoft)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 16, radius: 22)
    }
}

/// The knowledge she is surfacing from today's episode — thinkers, the
/// quote, the ideas — each with a feedback affordance so what lands
/// reshapes what she surfaces next.
struct KnowledgeCardsSection: View {
    let cards: [HomeContext.Card]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("TO CARRY TODAY")
                .font(.system(size: 10, design: .monospaced).weight(.semibold))
                .tracking(2.0)
                .foregroundStyle(Theme.inkSoft)
                .padding(.leading, 2)
            ForEach(cards) { card in
                KnowledgeCardView(card: card)
            }
        }
    }
}

struct KnowledgeCardView: View {
    @Environment(AppStore.self) private var store
    let card: HomeContext.Card
    /// v21: the feedback affordance hides until the card itself is tapped —
    /// the card is a thought first, a control second.
    @State private var revealed = false
    @State private var whyDraft = ""
    @State private var whyOpen = false
    @State private var whySent = false
    @FocusState private var whyFocused: Bool

    private var kicker: String {
        let base: String
        switch card.kind {
        case "thinker": base = "A MIND IN YOUR EARS"
        case "quote":   base = "FROM THE EPISODE"
        default:        base = "AN IDEA TO CARRY"
        }
        return card.badge.isEmpty ? base
            : base + " · " + card.badge.uppercased()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                Text(kicker)
                    .font(.system(size: 9, design: .monospaced).weight(.semibold))
                    .tracking(1.8)
                    .foregroundStyle(card.badge.isEmpty ? Theme.inkSoft : Theme.accent)
                Spacer()
                Text(card.source)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(Theme.inkSoft.opacity(0.7))
                // The dot that becomes her star (v26): hold this card on
                // the home screen — and tell her the topic matters.
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        store.togglePin(card: card)
                    }
                } label: {
                    InkPinMark(pinned: store.isPinned(card.id),
                               size: 22, seed: card.id.inkSeed)
                }
                .buttonStyle(.plain)
            }

            if card.kind == "thinker" {
                Button {
                    // v27: open the thinker right here, not in Knowledge.
                    store.showThinker(named: card.thinker)
                } label: {
                    HStack(spacing: 12) {
                        WikiPortrait(name: card.thinker, size: 54)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(card.title)
                                .font(.system(.headline, design: .serif))
                                .foregroundStyle(Theme.ink)
                            if !card.tagline.isEmpty {
                                Text(card.tagline)
                                    .font(.system(size: 12, design: .serif))
                                    .italic()
                                    .foregroundStyle(Theme.ink.opacity(0.65))
                                    .lineLimit(2)
                            }
                        }
                        Spacer()
                        InkChevron(pointing: .right, size: 12,
                                   color: Theme.inkSoft.opacity(0.7),
                                   seed: card.id.inkSeed)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else if card.kind == "quote" {
                Text("“" + card.body + "”")
                    .font(.system(size: 16, design: .serif))
                    .italic()
                    .lineSpacing(4)
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(card.title)
                    .font(.system(.headline, design: .serif))
                    .foregroundStyle(Theme.ink)
            }

            if card.kind != "quote", !card.body.isEmpty {
                Text(card.body)
                    .font(.system(.footnote, design: .serif))
                    .foregroundStyle(Theme.ink.opacity(0.8))
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if revealed {
                feedbackRow
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            } else {
                // A resting pen-tap: three faint dots where her line will
                // appear — tap the card and the affordance surfaces.
                HStack(spacing: 3) {
                    Spacer()
                    ForEach(0..<3, id: \.self) { _ in
                        Circle().fill(Theme.inkSoft.opacity(0.35))
                            .frame(width: 2.5, height: 2.5)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 14, radius: 20)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) { revealed.toggle() }
        }
    }

    /// relevant · great · not today — and, once judged, "why?" so Hector
    /// can tell her what made it land. The why re-posts the same verdict
    /// carrying the note. Hidden until the card is tapped (v21).
    @ViewBuilder private var feedbackRow: some View {
        InkUnderline(color: Theme.ink.opacity(0.3), seed: card.id.inkSeed)
            .frame(height: 4)
        if let verdict = store.cardVerdicts[card.id] {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    Text("NOTED · \(verdict == "skip" ? "NOT TODAY" : verdict.uppercased())")
                        .font(.system(size: 9, design: .monospaced).weight(.semibold))
                        .tracking(1.6)
                        .foregroundStyle(Theme.mint)
                    if !whySent, verdict != "skip" {
                        Button {
                            withAnimation { whyOpen.toggle() }
                            whyFocused = whyOpen
                        } label: {
                            Text("TELL HER WHY →")
                                .font(.system(size: 9, design: .monospaced).weight(.semibold))
                                .tracking(1.6)
                                .underline()
                                .foregroundStyle(Theme.accent)
                        }
                        .buttonStyle(.plain)
                    }
                    if whySent {
                        Text("· SHE HAS YOUR WHY")
                            .font(.system(size: 9, design: .monospaced))
                            .tracking(1.2)
                            .foregroundStyle(Theme.inkSoft)
                    }
                    Spacer()
                }
                if whyOpen, !whySent {
                    HStack(spacing: 8) {
                        TextField("why it lands…", text: $whyDraft, axis: .vertical)
                            .lineLimit(1...3)
                            .focused($whyFocused)
                            .font(.footnote)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.white.opacity(0.30), in: Capsule())
                        Button {
                            let note = whyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !note.isEmpty else { return }
                            store.giveCardFeedback(card, verdict: verdict, note: note)
                            withAnimation { whySent = true; whyOpen = false }
                        } label: {
                            InkSubmitArrow(size: 27, seed: card.id.inkSeed)
                        }
                        .disabled(whyDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
        } else {
            HStack(spacing: 16) {
                verdictButton("RELEVANT", verdict: "relevant", color: Theme.accent)
                verdictButton("GREAT", verdict: "great", color: Theme.accent)
                Spacer()
                verdictButton("NOT TODAY", verdict: "skip",
                              color: Theme.inkSoft.opacity(0.8))
            }
        }
    }

    private func verdictButton(_ label: String, verdict: String,
                               color: Color) -> some View {
        Button {
            withAnimation { store.giveCardFeedback(card, verdict: verdict) }
        } label: {
            Text(label)
                .font(.system(size: 9, design: .monospaced).weight(.semibold))
                .tracking(1.6)
                .underline()
                .foregroundStyle(color)
        }
        .buttonStyle(.plain)
    }
}

/// Behind the "Us" title: what Alicia thinks we're talking about today —
/// with THE ARC (the full timeline) one segment away.
struct UsSheet: View {
    @State private var segment = 0

    var body: some View {
        VStack(spacing: 0) {
            InkTabs(items: ["Today", "The Arc"], selection: $segment)
                .padding(.horizontal, 24)
                .padding(.top, 24)
            if segment == 0 {
                TodayContextSheet()
            } else {
                TimelineSheet()
            }
        }
        .presentationBackground(Theme.paper)
    }
}

/// The context drawn as an onion (v26): today at the heart, the trail
/// around it, the season as the outermost skin — three hand-pulled rings,
/// in to out, the way she actually holds the day.
struct ContextOnion: View {
    let home: HomeContext

    var body: some View {
        GeometryReader { geo in
            let c = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let u = min(geo.size.width, geo.size.height) / 2
            let rings: [CGFloat] = [u * 0.40, u * 0.68, u * 0.96]
            ZStack {
                Canvas { ctx, size in
                    var rand = InkRand((home.today?.label ?? "onion").inkSeed)
                    let center = CGPoint(x: size.width / 2, y: size.height / 2)
                    for (i, r) in rings.enumerated() {
                        // Each layer drawn twice — an ink pass and a
                        // sea-slate afterthought drifting wider.
                        let ring = InkPen.ring(
                            center: center, radius: r, rand: &rand,
                            sweep: 2 * .pi * rand.range(0.88, 0.99),
                            squashX: CGFloat(rand.range(0.97, 1.03)),
                            squashY: CGFloat(rand.range(0.96, 1.02)),
                            breathe: 2.2)
                        ctx.stroke(ring,
                                   with: .color(Theme.ink.opacity(0.42 - Double(i) * 0.09)),
                                   style: StrokeStyle(lineWidth: 1.15, lineCap: .round))
                        let echo = InkPen.ring(
                            center: center, radius: r + CGFloat(rand.range(1.5, 4)),
                            rand: &rand, sweep: 2 * .pi * rand.range(0.25, 0.5),
                            breathe: 2.6)
                        ctx.stroke(echo,
                                   with: .color(Theme.accent.opacity(0.30)),
                                   style: StrokeStyle(lineWidth: 0.8, lineCap: .round))
                    }
                }

                // The heart: today.
                if let today = home.today {
                    VStack(spacing: 3) {
                        Text(today.label)
                            .font(.system(size: 9, design: .monospaced).weight(.semibold))
                            .tracking(1.6)
                            .foregroundStyle(Theme.accent)
                        Text(today.title)
                            .font(.system(size: 13, design: .serif))
                            .italic()
                            .multilineTextAlignment(.center)
                            .foregroundStyle(Theme.ink)
                            .lineLimit(3)
                    }
                    .frame(width: rings[0] * 1.7)
                    .position(c)
                }

                // The middle skin: the trail, scattered around the ring.
                ForEach(Array(home.trail.prefix(4).enumerated()), id: \.element.id) { i, item in
                    let angles: [Double] = [-0.42, 0.35, 2.75, 3.55]
                    let a = angles[i % angles.count]
                    Text(item.label)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(Theme.inkSoft)
                        .position(x: c.x + CGFloat(cos(a)) * rings[1],
                                  y: c.y + CGFloat(sin(a)) * rings[1])
                }

                // The outermost skin: the season, resting on the rim.
                if let season = home.season {
                    VStack(spacing: 1) {
                        Text("SEASON \(season.season)")
                            .font(.system(size: 8, design: .monospaced).weight(.semibold))
                            .tracking(1.8)
                            .foregroundStyle(Theme.inkSoft)
                        Text(season.title)
                            .font(.system(size: 11, design: .serif))
                            .italic()
                            .foregroundStyle(Theme.ink.opacity(0.75))
                    }
                    .position(x: c.x, y: c.y - rings[2] + 2)
                    .background(alignment: .center) { Color.clear }
                }

                // Quiet layer names down the right, in to out.
                ForEach(Array(["today", "the days behind", "the season"].enumerated()),
                        id: \.offset) { i, name in
                    Text(name)
                        .font(.system(size: 8.5, design: .serif))
                        .italic()
                        .foregroundStyle(Theme.inkSoft.opacity(0.75))
                        .position(x: c.x + rings[i] * 0.72,
                                  y: c.y + rings[i] * 0.72)
                }
            }
        }
        .frame(height: 330)
    }
}

/// The context of today, readable: the sentence, the episode, the season
/// around it, the trail behind it, and what she's surfacing.
struct TodayContextSheet: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Text("WHAT WE'RE TALKING ABOUT TODAY")
                    .font(.system(size: 11, design: .monospaced).weight(.bold))
                    .tracking(3.0)
                    .foregroundStyle(Theme.inkSoft)
                    .padding(.top, 22)

                if let home = store.homeContext {
                    // The onion: the day's context as layers, in to out.
                    ContextOnion(home: home)

                    if !home.contextLine.isEmpty {
                        Text(home.contextLine)
                            .font(.system(.title3, design: .serif, weight: .semibold))
                            .multilineTextAlignment(.center)
                            .foregroundStyle(Theme.ink)
                    }
                    Theme.stroke.frame(width: 60, height: 1)

                    if let today = home.today, !today.about.isEmpty {
                        Text(today.about)
                            .font(.system(size: 15, design: .serif))
                            .lineSpacing(6)
                            .foregroundStyle(Theme.ink.opacity(0.9))
                    }

                    if let season = home.season {
                        contextKicker("THE SEASON AROUND IT")
                        VStack(spacing: 6) {
                            Text("Season \(season.season) — \(season.title)")
                                .font(.system(.headline, design: .serif))
                            if !season.movementNow.isEmpty {
                                Text(season.movementNow)
                                    .font(.system(size: 10, design: .monospaced))
                                    .tracking(1.4)
                                    .foregroundStyle(Theme.accent)
                            }
                            if !season.premise.isEmpty {
                                Text(season.premise)
                                    .font(.system(size: 13, design: .serif))
                                    .italic()
                                    .lineSpacing(4)
                                    .foregroundStyle(Theme.ink.opacity(0.7))
                            }
                        }
                        .multilineTextAlignment(.center)
                    }

                    if !home.trail.isEmpty {
                        contextKicker("THE TRAIL HERE")
                        VStack(spacing: 4) {
                            ForEach(home.trail) { item in
                                Text("\(item.label) · \(item.title)")
                                    .font(.system(size: 13, design: .serif))
                                    .foregroundStyle(Theme.ink.opacity(0.8))
                            }
                        }
                    }

                    if !home.cards.isEmpty {
                        contextKicker("SHE IS SURFACING")
                        VStack(spacing: 4) {
                            ForEach(home.cards) { card in
                                Text(card.kind == "quote" ? "the quote" : card.title)
                                    .font(.system(size: 13, design: .serif))
                                    .italic()
                                    .foregroundStyle(Theme.ink.opacity(0.8))
                            }
                        }
                    }
                } else {
                    ProgressView("Reading the day…")
                        .padding(.vertical, 40)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(24)
            .padding(.bottom, 40)
        }
    }

    private func contextKicker(_ label: String) -> some View {
        Text(label)
            .font(.system(size: 10, design: .monospaced).weight(.semibold))
            .tracking(2.0)
            .foregroundStyle(Theme.accent)
            .padding(.top, 10)
    }
}

/// The story of you two — every lived day since she began, milestones
/// full-size, ordinary days as ledger lines. Opens from the "Us" title.
struct TimelineSheet: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(spacing: 6) {
                    Text("THE ARC")
                        .font(.system(size: 11, design: .monospaced).weight(.bold))
                        .tracking(3.0)
                        .foregroundStyle(Theme.inkSoft)
                    Text("Every day since she began")
                        .font(.system(.title3, design: .serif, weight: .semibold))
                    if let last = store.timeline.last {
                        Text(last.date + " → today")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(Theme.inkSoft)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.bottom, 22)

                if store.timeline.isEmpty {
                    ProgressView("Walking back to day one…")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                }

                ForEach(store.timeline) { day in
                    HStack(alignment: .top, spacing: 12) {
                        // The spine (v26): her emblem where a voice led the
                        // day, and a line that trembles and sometimes curls
                        // — a pen wandering, not a ruler.
                        VStack(spacing: 3) {
                            if let arch = day.archetype, !arch.isEmpty,
                               Archetypes.get(arch) != nil {
                                ArchetypeEmblem(id: arch,
                                                size: day.milestone ? 21 : 14)
                            } else {
                                Circle()
                                    .fill(day.milestone ? Theme.accent
                                          : Theme.inkSoft.opacity(0.5))
                                    .frame(width: day.milestone ? 11 : 5,
                                           height: day.milestone ? 11 : 5)
                            }
                            InkSpineSegment(seed: day.date.inkSeed)
                                .frame(width: 14)
                                .frame(maxHeight: .infinity)
                        }
                        .frame(width: 22)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(day.date)
                                .font(.system(size: 9, design: .monospaced))
                                .tracking(1.2)
                                .foregroundStyle(Theme.inkSoft)
                            Text(day.headline.strippedEmojis)
                                .font(.system(size: day.milestone ? 20 : 14,
                                              weight: day.milestone ? .semibold : .regular,
                                              design: .serif))
                                .foregroundStyle(Theme.ink)
                            if day.milestone {
                                // Her line under the days that moved.
                                InkUnderline(color: Theme.accent.opacity(0.55),
                                             seed: day.date.inkSeed)
                                    .frame(width: 96, height: 5)
                            }
                            // v22: every day tells you what it was — what
                            // she learned about you, and the idea that was
                            // circulating — not just who was speaking.
                            ForEach((day.learned ?? []).prefix(2), id: \.self) { l in
                                HStack(alignment: .top, spacing: 6) {
                                    InkSpark(size: 9, seed: l.inkSeed)
                                        .padding(.top, 3)
                                    Text(l.strippedEmojis)
                                        .font(.system(size: 12, design: .serif))
                                        .foregroundStyle(Theme.ink.opacity(0.75))
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            if let thread = day.thread, !thread.isEmpty {
                                Text("the thread · " + thread.strippedEmojis)
                                    .font(.system(size: 11, design: .serif))
                                    .italic()
                                    .foregroundStyle(Theme.accent.opacity(0.85))
                                    .lineLimit(2)
                            }
                            if day.milestone {
                                ForEach(day.growth, id: \.self) { g in
                                    Text(g)
                                        .font(.system(size: 12, design: .serif))
                                        .italic()
                                        .foregroundStyle(Theme.accent)
                                }
                            }
                            if !day.what.isEmpty {
                                Text(day.what.joined(separator: " · "))
                                    .font(.system(size: 10.5, design: .serif))
                                    .foregroundStyle(Theme.inkSoft.opacity(0.85))
                            }
                        }
                        .padding(.bottom, day.milestone ? 26 : 18)
                        Spacer(minLength: 0)
                    }
                }
            }
            .padding(24)
            .padding(.bottom, 40)
        }
        .presentationBackground(Theme.paper)
        .task { await store.loadTimeline() }
    }
}

