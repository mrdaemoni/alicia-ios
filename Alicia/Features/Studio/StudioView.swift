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
                                Image(systemName: drawing ? "waveform" : "pencil.and.outline")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(Theme.ink)
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
    /// them line-by-line (headings → bold, bullets → dots, quotes → ❝).
    static func render(_ md: String) -> AttributedString {
        let cleaned = md
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                var l = String(line)
                if l.hasPrefix("#") {
                    let text = l.drop(while: { $0 == "#" || $0 == " " })
                    l = text.isEmpty ? "" : "**\(text)**"
                } else if l.hasPrefix("- ") {
                    l = "  •  " + l.dropFirst(2)
                } else if l.hasPrefix("> ") {
                    l = "❝ " + l.dropFirst(2).replacingOccurrences(of: "\"", with: "")
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
                            Text(track.title)
                                .font(.system(size: 22, weight: .semibold, design: .serif))
                                .foregroundStyle(Theme.ink)
                        }
                        Spacer()
                        Button { store.togglePlay() } label: {
                            Image(systemName: store.isPlaying && store.nowPlaying?.id == track.id
                                  ? "pause.circle.fill" : "play.circle.fill")
                                .font(.system(size: 40))
                                .foregroundStyle(Theme.ink)
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
                    Label("No shownotes for this one.", systemImage: "doc.questionmark")
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
        .navigationTitle(track.label ?? "Episode")
        .navigationBarTitleDisplayMode(.inline)
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
                    Image(systemName: "waveform")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(4)
                        .background(Theme.accent, in: Circle())
                        .offset(x: 5, y: 5)
                        .symbolEffect(.variableColor.iterative, isActive: true)
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(track.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(isCurrent ? Theme.accentSoft : .primary)
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
                        .overlay(Image(systemName: track.symbol).foregroundStyle(.white))
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
                        Image(systemName: "gobackward.15")
                    }
                    Button { store.togglePlay() } label: {
                        Image(systemName: store.isPlaying ? "pause.fill" : "play.fill")
                            .font(.title3)
                    }
                    Button { store.skip(15) } label: {
                        Image(systemName: "goforward.15")
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
