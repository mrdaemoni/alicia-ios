import SwiftUI

struct StudioView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        playlistHeader
                        ForEach(store.tracks) { track in
                            TrackRow(track: track,
                                     isCurrent: store.nowPlaying?.id == track.id,
                                     isPlaying: store.isPlaying && store.nowPlaying?.id == track.id)
                                .contentShape(Rectangle())
                                .onTapGesture { store.play(track) }
                        }
                    }
                    .padding(16)
                    .padding(.bottom, 92)   // room for the player bar
                }
                if store.nowPlaying != nil { PlayerBar() }
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
                Text("Made for Hector")
                    .font(.title2.weight(.bold))
                Text("By Alicia · \(store.tracks.count) pieces")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("Music she scored for you")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
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
