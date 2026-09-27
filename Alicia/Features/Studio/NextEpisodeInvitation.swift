import SwiftUI

/// The episode that comes after the last one he played: one card that owns
/// its title and the one thing to do with it — play it.
struct NextEpisodeInvitation: View {
    @Environment(AppStore.self) private var store
    var body: some View {
        if let track = store.nextEpisodeTrack {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    InkKicker(text: "Next episode")
                    Text(track.title.strippedEmojis).font(.system(size: 19, design: .serif))
                        .fixedSize(horizontal: false, vertical: true)
                    if let label = track.label { Text(label).font(InkType.meta).foregroundStyle(Theme.inkSoft) }
                }
                Button { store.playFromHome(track) } label: {
                    HStack(spacing: 10) {
                        InkPlayPause(playing: false, size: 18, color: Theme.ink, seed: track.title.inkSeed)
                            .frame(width: 18, height: 18)
                            .accessibilityHidden(true)
                        Text("Listen")
                    }
                }
                .buttonStyle(.inkSecondaryCompact)
                .accessibilityLabel("Listen to next episode: \(track.title)")
                .accessibilityIdentifier("episode.next.listen")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card(padding: 16, radius: 16)
        }
    }
}
