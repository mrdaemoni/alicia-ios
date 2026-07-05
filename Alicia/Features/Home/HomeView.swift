import SwiftUI

/// Us — the landing page. Hector's `memories` drawing (the figure before
/// the sea) washes down from the top of the page; beneath it: her greeting,
/// the latest thing she said, what her day held, and a quiet status strip.
struct HomeView: View {
    @Environment(AppStore.self) private var store

    /// Her line, when the backend has one — grounded in what you two are
    /// actually talking about. Time-of-day only as the offline fallback.
    private var greeting: String {
        if let live = store.greeting, !live.isEmpty { return live }
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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    SectionHeader(title: "Us",
                                  kicker: Date.now.formatted(date: .complete, time: .omitted))
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

                    if !store.suggestedTracks.isEmpty {
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
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(greeting)
                .font(.system(.largeTitle, design: .serif, weight: .semibold))
                .foregroundStyle(Theme.ink)
            if let season = seasonThought {
                Text(season.body)
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
            Image(systemName: store.isPlaying ? "waveform" : "pause.fill")
                .symbolEffect(.variableColor.iterative, isActive: store.isPlaying)
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(Theme.ink, in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(track.title).font(.footnote.weight(.semibold)).lineLimit(1)
                Text(track.mood).font(.caption2).foregroundStyle(Theme.inkSoft).lineLimit(1)
            }
            Spacer()
            Button { store.togglePlay() } label: {
                Image(systemName: store.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.title2)
                    .foregroundStyle(Theme.accentSoft)
            }
        }
        .card(padding: 10, radius: 18)
    }

    private func card(icon: String, title: String, body text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
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
                    Label("Status", systemImage: "waveform.path.ecg")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.accentSoft)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(Theme.inkSoft.opacity(0.75))
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
                    markdown: proactive.text.strippedLeadingEmoji,
                    options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
                 ?? AttributedString(proactive.text.strippedLeadingEmoji))
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
                        Image(systemName: "arrow.up")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 32, height: 32)
                            .background(Theme.ink, in: Circle())
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
                Text(featured.title)
                    .font(.system(.title3, design: .serif, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Text(featured.excerpt)
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
        featured.body.components(separatedBy: "\n\n").compactMap { raw in
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

/// Minimal wrap layout for the chips.
struct FlexWrap: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 320
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for sub in subviews {
            let s = sub.sizeThatFits(.unspecified)
            if x + s.width > width { x = 0; y += rowH + spacing; rowH = 0 }
            x += s.width + spacing
            rowH = max(rowH, s.height)
        }
        return CGSize(width: width, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for sub in subviews {
            let s = sub.sizeThatFits(.unspecified)
            if x + s.width > bounds.maxX { x = bounds.minX; y += rowH + spacing; rowH = 0 }
            sub.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += s.width + spacing
            rowH = max(rowH, s.height)
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
            Text("“" + quote.text + "”")
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
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(Theme.inkSoft)
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
                        Image(systemName: "play.circle")
                            .font(.title3)
                            .foregroundStyle(Theme.accent)
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
            Text("IN YOUR EARS TODAY")
                .font(.system(size: 10, design: .monospaced).weight(.semibold))
                .tracking(2.0)
                .foregroundStyle(Theme.inkSoft)
            HStack(spacing: 14) {
                ForEach(thinkers) { t in
                    Button {
                        store.pendingThinker = t.name
                        store.selectedSection = .knowledge
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

