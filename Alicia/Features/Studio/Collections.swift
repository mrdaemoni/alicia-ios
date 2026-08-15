import SwiftUI

/// One run of the podcast, as Studio shelves it: a numbered season, or a
/// named run like "Nights" that has no number at all.
struct PodcastCollection: Identifiable, Hashable {
    var id: String              // "S13" | "NIGHTS"
    var title: String           // "Season 13" | "Nights"
    var tracks: [Track]

    var duration: TimeInterval { tracks.reduce(0) { $0 + $1.duration } }
    /// A named run has no season number — that's what made it invisible.
    var isNamedRun: Bool { !(id.first == "S" && id.dropFirst().allSatisfy(\.isNumber)) }
}

/// A season on the shelf. Same shape as a playlist row so Studio reads as
/// one list of things to listen to, not two different kinds of object.
struct CollectionRow: View {
    let collection: PodcastCollection

    var body: some View {
        HStack(spacing: 14) {
            Image(artTile(for: collection.tracks.first ?? Track(
                title: collection.title, mood: "", duration: 0, symbol: "")))
                .resizable()
                .scaledToFill()
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Theme.stroke))
            VStack(alignment: .leading, spacing: 3) {
                InkTitle(text: collection.title, size: 16, weight: .semibold)
                Text("\(collection.tracks.count) episodes · "
                     + "\(Int((collection.duration / 60).rounded())) min")
                    .font(.caption)
                    .foregroundStyle(Theme.inkSoft)
            }
            Spacer()
            if collection.isNamedRun {
                // The specials earn a mark: they're the newest thing she made.
                InkSpark(size: 11, color: Theme.accent, seed: collection.id.inkSeed)
            }
            InkChevron(pointing: .right, size: 14)
        }
        .padding(10)
        .contentShape(Rectangle())
    }
}

/// A season opened: its episodes, playable and queueable.
struct CollectionDetailView: View {
    @Environment(AppStore.self) private var store
    let collection: PodcastCollection

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 14) {
                    Image(artTile(for: collection.tracks.first ?? Track(
                        title: collection.title, mood: "", duration: 0, symbol: "")))
                        .resizable().scaledToFill()
                        .frame(width: 96, height: 96)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(Theme.stroke))
                    VStack(alignment: .leading, spacing: 5) {
                        InkTitle(text: collection.title, size: 21, weight: .semibold)
                        Text(collection.tracks.first?.series ?? "")
                            .font(.subheadline)
                            .foregroundStyle(Theme.inkSoft)
                        Text("\(collection.tracks.count) episodes · "
                             + "\(Int((collection.duration / 60).rounded())) min")
                            .font(.caption)
                            .foregroundStyle(Theme.inkSoft)
                    }
                    Spacer()
                }
                .padding(.horizontal, 2)

                ForEach(collection.tracks) { track in
                    VStack(spacing: 0) {
                        NavigationLink(value: track) {
                            TrackRow(track: track,
                                     isCurrent: store.nowPlaying?.id == track.id,
                                     isPlaying: store.isPlaying
                                        && store.nowPlaying?.id == track.id)
                        }
                        .buttonStyle(.plain)
                        // Episodes queue exactly like syntheses do — the
                        // audio already exists, so it plays the instant it
                        // lands in a playlist.
                        HStack {
                            Spacer()
                            AddEpisodeToPlaylistLine(track: track)
                        }
                        .padding(.trailing, 10)
                        .padding(.bottom, 6)
                    }
                }
            }
            .padding(16)
            .padding(.bottom, 90)
        }
        .sectionBackground()
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { InkBackButton() }
            ToolbarItem(placement: .principal) {
                InkTitleLine(text: collection.title, size: 16)
            }
        }
    }
}

/// "Listen later" for a podcast episode. Same affordance and same queue as a
/// synthesis — the only difference is that the audio is already rendered.
struct AddEpisodeToPlaylistLine: View {
    @Environment(AppStore.self) private var store
    let track: Track
    @State private var picking = false

    private var queued: Bool {
        !store.playlistsHolding(track.playlistItemID).isEmpty
    }

    var body: some View {
        Button { picking = true } label: {
            VStack(spacing: 2) {
                Text(queued ? "QUEUED" : "LISTEN LATER")
                    .font(.system(size: 9, design: .monospaced).weight(.bold))
                    .tracking(1.4)
                    .foregroundStyle(queued ? Theme.mint : Theme.inkSoft)
                InkUnderline(color: queued ? Theme.mint : Theme.inkSoft,
                             seed: track.title.inkSeed, lineWidth: 1.0)
                    .frame(width: queued ? 42 : 66, height: 4)
            }
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $picking) {
            AddEpisodeSheet(track: track)
        }
    }
}

/// Playlist picker for an episode. Deliberately the same shape as
/// `AddToPlaylistSheet` so queueing feels identical whatever you're queueing.
struct AddEpisodeSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let track: Track

    @State private var newName = ""
    @State private var working = false

    private var holding: Set<String> {
        store.playlistsHolding(track.playlistItemID)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(track.title.strippedEmojis)
                        .font(.system(.headline, design: .serif))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(track.mood)
                        .font(.caption)
                        .foregroundStyle(Theme.inkSoft)

                    Text("ADD TO")
                        .font(.system(size: 9, design: .monospaced).weight(.semibold))
                        .tracking(1.8)
                        .foregroundStyle(Theme.inkSoft)

                    if store.playlists.isEmpty {
                        Text("No playlists yet — name one below and this episode becomes its first piece.")
                            .font(.system(size: 14, design: .serif)).italic()
                            .foregroundStyle(Theme.inkSoft)
                    }

                    ForEach(store.playlists) { playlist in
                        Button { toggle(playlist) } label: {
                            HStack(spacing: 12) {
                                InkPinMark(pinned: holding.contains(playlist.id),
                                           size: 20, seed: playlist.id.inkSeed)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(playlist.name)
                                        .font(.system(size: 15, design: .serif))
                                        .foregroundStyle(Theme.ink)
                                    Text("\(playlist.items.count) pieces · "
                                         + "\(Int((playlist.duration / 60).rounded())) min")
                                        .font(.caption2)
                                        .foregroundStyle(Theme.inkSoft)
                                }
                                Spacer()
                            }
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(working)
                    }

                    Theme.stroke.frame(height: 0.7).padding(.vertical, 4)
                    Text("OR START A NEW ONE")
                        .font(.system(size: 9, design: .monospaced).weight(.semibold))
                        .tracking(1.8)
                        .foregroundStyle(Theme.inkSoft)
                    HStack(spacing: 10) {
                        TextField("Name it — Drive, Walk, Sunday…", text: $newName)
                            .font(.system(size: 15, design: .serif))
                            .textFieldStyle(.plain)
                            .submitLabel(.done)
                            .onSubmit { create() }
                        Button(action: create) { InkSubmitArrow(size: 24) }
                            .buttonStyle(.plain)
                            .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty
                                      || working)
                    }
                    Theme.stroke.frame(height: 0.7)
                }
                .padding(24)
            }
            .sectionBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    InkTitleLine(text: "Listen later", size: 16)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Theme.accent)
                }
            }
        }
        .presentationBackground(Theme.paper)
        .presentationDetents([.medium, .large])
        .task { await store.loadPlaylists() }
    }

    private func toggle(_ playlist: Playlist) {
        working = true
        Task {
            if holding.contains(playlist.id) {
                await store.removeFromPlaylist(playlist.id,
                                               itemID: track.playlistItemID)
            } else {
                await store.addEpisodeToPlaylist(playlist.id, track: track)
            }
            working = false
        }
    }

    private func create() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        working = true
        Task {
            await store.createPlaylist(named: name)
            if let made = store.playlists.first(where: { $0.name == name }) {
                await store.addEpisodeToPlaylist(made.id, track: track)
            }
            newName = ""
            working = false
        }
    }
}
