import SwiftUI

struct NextEpisodeInvitation: View {
    @Environment(AppStore.self) private var store
    var body: some View {
        if let track = store.nextEpisodeTrack {
            HStack(alignment: .center, spacing: 18) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("NEXT EPISODE").font(.caption2.monospaced()).tracking(1.5).foregroundStyle(Theme.inkSoft)
                    Text(track.title.strippedEmojis).font(.system(size: 19, design: .serif))
                    if let label = track.label { Text(label).font(.caption).foregroundStyle(Theme.inkSoft) }
                }
                Spacer(minLength: 0)
                Button("Listen") { store.playFromHome(track) }
                    .font(.callout).frame(minWidth: 60, minHeight: 44)
                    .accessibilityLabel("Listen to next episode: \(track.title)")
                    .accessibilityIdentifier("episode.next.listen")
            }.padding(.vertical, 14)
                .overlay(alignment: .bottom) { Theme.stroke.frame(height: 0.7) }
        }
    }
}
