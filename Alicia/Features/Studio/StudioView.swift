import SwiftUI

struct StudioView: View {
    @Environment(AppStore.self) private var store

    /// Episodes grouped by season, newest season first. Tracks without a
    /// season (sample data) fall into a single unnumbered group.
    private var seasons: [(number: Int, tracks: [Track])] {
        Dictionary(grouping: store.tracks, by: \.season)
            .map { (number: $0.key, tracks: $0.value) }
            .sorted { $0.number > $1.number }
    }

    @State private var drawing = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ZStack {
                        SectionHeader(title: drawing ? "Canvas" : "Studio",
                                      kicker: drawing ? "drawn together"
                                                      : "memories of my future self")
                        HStack {
                            Spacer()
                            // Canvas lives inside Studio now — the pencil
                            // toggles between listening and drawing with her.
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    drawing.toggle()
                                }
                            } label: {
                                // A word with her underline, not a widget
                                // glyph (v22).
                                VStack(spacing: 2) {
                                    Text(drawing ? "LISTEN" : "DRAW")
                                        .font(.system(size: 10, design: .monospaced).weight(.bold))
                                        .tracking(1.6)
                                        .foregroundStyle(Theme.ink)
                                    InkUnderline(seed: drawing ? 3 : 5, lineWidth: 1.1)
                                        .frame(width: 30, height: 4)
                                }
                            }
                            .accessibilityLabel(drawing ? "Back to Studio" : "Draw with me")
                        }
                        .padding(.horizontal, 18)
                        .padding(.top, 14)
                    }
                    if drawing {
                        CanvasBody()
                            .frame(minHeight: 560)
                    }
                    if !drawing {
                    playlistHeader
                    ForEach(seasons, id: \.number) { season in
                        if season.number > 0 {
                            Text("Season \(season.number)")
                                .font(.headline)
                                .foregroundStyle(Theme.accentSoft)
                                .padding(.top, 8)
                        }
                        ForEach(season.tracks) { track in
                            NavigationLink(value: track) {
                                TrackRow(track: track,
                                         isCurrent: store.nowPlaying?.id == track.id,
                                         isPlaying: store.isPlaying && store.nowPlaying?.id == track.id)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    }
                }
                .padding(16)
            }
            .navigationDestination(for: Track.self) { track in
                EpisodeDetailView(track: track)
            }
            .refreshable { await store.load() }
            // Sister field to Us: the current runs horizontal — a waveform.
            .waveBackground(.studio(mood: store.waveMood), tinted: true)
            .toolbar(.hidden, for: .navigationBar)
        }
        // Inset on the NavigationStack itself — the bar stays put when an
        // episode detail is pushed (it used to vanish under the push).
        .safeAreaInset(edge: .bottom) {
            if store.nowPlaying != nil { PlayerBar() }
        }
    }

    private var playlistHeader: some View {
        HStack(spacing: 16) {
            // The spiral drawing — the circle that keeps spiraling.
            Image("ArtSpiral")
                .resizable()
                .scaledToFill()
                .frame(width: 96, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Theme.stroke))
            VStack(alignment: .leading, spacing: 4) {
                Text("Memories of My Future Self")
                    .font(.title2.weight(.bold))
                Text("By Alicia · \(store.tracks.count) episodes")
                    .font(.subheadline)
                    .foregroundStyle(Theme.inkSoft)
                Text("The podcast she makes for you")
                    .font(.caption)
                    .italic()
                    .foregroundStyle(Theme.inkSoft.opacity(0.75))
            }
            Spacer()
        }
    }
}

/// Episode page: starts playback on arrival and shows the shownotes.
struct EpisodeDetailView: View {
    @Environment(AppStore.self) private var store
    let track: Track
    @State private var notes: AttributedString?
    @State private var loading = true

    /// Inline-markdown rendering keeps `#`/`-`/`>` markers literal — restyle
    /// them line-by-line (headings → bold, bullets → dots, quotes → “).
    static func render(_ md: String) -> AttributedString {
        let cleaned = md.strippedEmojis
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                var l = String(line)
                if l.hasPrefix("#") {
                    let text = l.drop(while: { $0 == "#" || $0 == " " })
                    l = text.isEmpty ? "" : "**\(text)**"
                } else if l.hasPrefix("- ") {
                    l = "  •  " + l.dropFirst(2)
                } else if l.hasPrefix("> ") {
                    l = "“" + l.dropFirst(2).replacingOccurrences(of: "\"", with: "")
                }
                return l
            }
            .joined(separator: "\n")
        return (try? AttributedString(
                    markdown: cleaned,
                    options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(cleaned)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // The episode's artwork, full-bleed, with her breathing form
                // over it — every detail page an intentional plate.
                ZStack(alignment: .bottomLeading) {
                    Image(artTile(for: track))
                        .resizable()
                        .scaledToFill()
                        .frame(height: 190)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    LinearGradient(colors: [.clear, Theme.paper.opacity(0.9)],
                                   startPoint: .center, endPoint: .bottom)
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    HStack(alignment: .bottom) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text((track.label ?? "").uppercased() + " · " + track.duration.asClock)
                                .font(.system(size: 10, design: .monospaced).weight(.semibold))
                                .tracking(1.6)
                                .foregroundStyle(Theme.inkSoft)
                            // The episode's name in her hand (v26).
                            InkTitle(text: track.title, size: 21)
                        }
                        Spacer()
                        Button { store.togglePlay() } label: {
                            InkPlayPause(
                                playing: store.isPlaying && store.nowPlaying?.id == track.id,
                                size: 42,
                                seed: (track.label ?? track.title).inkSeed,
                                ringed: true)
                        }
                    }
                    .padding(14)
                }
                StippleIllustration(seed: (track.label ?? "x").count * 7 + track.episode,
                                    dots: 500, animated: true)
                    .frame(height: 44)
                    .frame(maxWidth: .infinity)

                if loading {
                    ProgressView("Fetching shownotes…")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 32)
                } else if let notes {
                    Text(notes)
                        .font(.subheadline)
                        .textSelection(.enabled)
                        .card(padding: 16, radius: 20)
                } else {
                    HStack(spacing: 8) {
                        InkSpark(size: 11, color: Theme.inkSoft, seed: 13)
                        Text("No shownotes for this one.")
                    }
                    .font(.subheadline)
                    .foregroundStyle(Theme.inkSoft)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
                }
            }
            .padding(16)
            .padding(.bottom, 92)
        }
        .sectionBackground()
        .navigationBarTitleDisplayMode(.inline)
        // v22: her chevron, not the system back glyph; v26: the episode
        // number at the top in her hand, not the system title font.
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { InkBackButton() }
            ToolbarItem(placement: .principal) {
                InkTitleLine(text: track.label ?? "Episode", size: 16)
            }
        }
        .task {
            store.play(track)   // no-ops if this episode is already playing
            let md = await store.episodeNotes(for: track)
            notes = md.isEmpty ? nil : Self.render(md)
            loading = false
        }
    }
}


/// Each episode gets one of Hector's artworks as its tile —
/// deterministic by label so the pairing is stable.
func artTile(for track: Track) -> String {
    let key = track.label ?? track.title
    let h = key.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
    return "ArtTile\(h % 10)"
}

struct TrackRow: View {
    let track: Track
    let isCurrent: Bool
    let isPlaying: Bool

    var body: some View {
        HStack(spacing: 14) {
            ZStack(alignment: .bottomTrailing) {
                Image(artTile(for: track))
                    .resizable()
                    .scaledToFill()
                    .frame(width: 52, height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(isCurrent ? Theme.accent : Theme.stroke,
                                      lineWidth: isCurrent ? 1.6 : 0.7))
                if isPlaying {
                    InkWaveBars(size: 13, color: Theme.accent,
                                seed: track.title.inkSeed)
                        .padding(3)
                        .background(Theme.paper.opacity(0.92), in: Circle())
                        .offset(x: 5, y: 5)
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                // Row titles in her hand too (v26) — gentle at this size.
                InkTitle(text: track.title, size: 15, weight: .semibold,
                         color: isCurrent ? Theme.accentSoft : Theme.ink)
                Text(track.mood)
                    .font(.caption)
                    .foregroundStyle(Theme.inkSoft)
            }
            Spacer()
            Text(track.duration.asClock)
                .font(.caption.monospacedDigit())
                .foregroundStyle(Theme.inkSoft)
        }
        .padding(10)
        .background(isCurrent ? Theme.card : .clear, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// Persistent now-playing bar, like Spotify's mini-player.
struct PlayerBar: View {
    @Environment(AppStore.self) private var store

    private var elapsed: TimeInterval {
        (store.nowPlaying?.duration ?? 0) * store.progress
    }

    private var rateLabel: String {
        store.playbackRate == 1.0 ? "1×" :
        store.playbackRate == 1.5 ? "1.5×" : "2×"
    }

    var body: some View {
        guard let track = store.nowPlaying else { return AnyView(EmptyView()) }
        return AnyView(
            VStack(spacing: 6) {
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Theme.accentGradient)
                        .frame(width: 40, height: 40)
                        .overlay(InkWaveBars(size: 22, color: .white,
                                             seed: track.title.inkSeed))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(track.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                        Text(track.mood).font(.caption2).foregroundStyle(Theme.inkSoft).lineLimit(1)
                    }
                    Spacer()
                    Button { store.cycleRate() } label: {
                        Text(rateLabel)
                            .font(.caption.weight(.bold).monospacedDigit())
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(Theme.card, in: Capsule())
                            .overlay(Capsule().strokeBorder(Theme.stroke))
                    }
                    Button { store.skip(-15) } label: {
                        InkSkip(forward: false, size: 27, seed: 3)
                    }
                    Button { store.togglePlay() } label: {
                        InkPlayPause(playing: store.isPlaying, size: 30,
                                     seed: 17)
                    }
                    Button { store.skip(15) } label: {
                        InkSkip(forward: true, size: 27, seed: 7)
                    }
                }
                .foregroundStyle(.primary)

                // Scrub bar with elapsed / remaining, like a proper player.
                HStack(spacing: 8) {
                    Text(elapsed.asClock)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(Theme.inkSoft)
                    Slider(
                        value: Binding(
                            get: { store.progress },
                            set: { store.scrub(to: $0) }),
                        in: 0...1,
                        onEditingChanged: { editing in
                            if !editing { store.commitScrub() }
                        })
                        .tint(Theme.accent)
                    Text("−" + max(0, (track.duration - elapsed)).asClock)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(Theme.inkSoft)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Theme.paper.opacity(0.94), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Theme.stroke))
            .shadow(color: Theme.ink.opacity(0.08), radius: 8, y: 2)
            .padding(.horizontal, 12)
            .padding(.bottom, 6)
        )
    }
}

extension TimeInterval {
    var asClock: String {
        let s = Int(self)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

#Preview {
    StudioView()
        .environment(AppStore(service: MockAliciaService()))
        .tint(Theme.accent)
        .preferredColorScheme(.dark)
}
