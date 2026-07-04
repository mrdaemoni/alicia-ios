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

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
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
                    .padding(16)
                    .padding(.bottom, 92)   // room for the player bar
                }
                if store.nowPlaying != nil { PlayerBar() }
            }
            .navigationDestination(for: Track.self) { track in
                EpisodeDetailView(track: track)
            }
            .refreshable { await store.load() }
            .sectionBackground()
            .navigationTitle("Studio")
        }
    }

    private var playlistHeader: some View {
        HStack(spacing: 16) {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Theme.accentGradient)
                .frame(width: 96, height: 96)
                .overlay(
                    Image(systemName: "waveform")
                        .font(.system(size: 36, weight: .semibold))
                        .foregroundStyle(.white)
                )
            VStack(alignment: .leading, spacing: 4) {
                Text("Memories of My Future Self")
                    .font(.title2.weight(.bold))
                Text("By Alicia · \(store.tracks.count) episodes")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("The podcast she makes for you")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
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
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 14) {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Theme.accentGradient)
                        .frame(width: 72, height: 72)
                        .overlay(
                            Image(systemName: store.isPlaying && store.nowPlaying?.id == track.id
                                  ? "waveform" : "play.fill")
                                .font(.title2)
                                .foregroundStyle(.white)
                                .symbolEffect(.variableColor.iterative,
                                              isActive: store.isPlaying && store.nowPlaying?.id == track.id)
                        )
                        .onTapGesture { store.togglePlay() }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(track.title).font(.title3.weight(.bold))
                        Text(track.mood).font(.caption).foregroundStyle(.secondary)
                        Text(track.duration.asClock)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                }
                .card(padding: 12, radius: 20)

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
                        .foregroundStyle(.secondary)
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

struct TrackRow: View {
    let track: Track
    let isCurrent: Bool
    let isPlaying: Bool

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isCurrent ? AnyShapeStyle(Theme.accentGradient) : AnyShapeStyle(Theme.card))
                    .frame(width: 52, height: 52)
                Image(systemName: isPlaying ? "waveform" : track.symbol)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(isCurrent ? .white : .secondary)
                    .symbolEffect(.variableColor.iterative, isActive: isPlaying)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(track.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(isCurrent ? Theme.accentSoft : .primary)
                Text(track.mood)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(track.duration.asClock)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(isCurrent ? Theme.card : .clear, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// Persistent now-playing bar, like Spotify's mini-player.
struct PlayerBar: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        guard let track = store.nowPlaying else { return AnyView(EmptyView()) }
        return AnyView(
            VStack(spacing: 8) {
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Theme.accentGradient)
                        .frame(width: 40, height: 40)
                        .overlay(Image(systemName: track.symbol).foregroundStyle(.white))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(track.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                        Text(track.mood).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    Button { store.previous() } label: {
                        Image(systemName: "backward.fill")
                    }
                    Button { store.togglePlay() } label: {
                        Image(systemName: store.isPlaying ? "pause.fill" : "play.fill")
                            .font(.title3)
                    }
                    Button { store.next() } label: {
                        Image(systemName: "forward.fill")
                    }
                }
                .foregroundStyle(.primary)

                ProgressView(value: store.progress)
                    .tint(Theme.accentSoft)
                    .scaleEffect(x: 1, y: 0.6, anchor: .center)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Theme.stroke))
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
