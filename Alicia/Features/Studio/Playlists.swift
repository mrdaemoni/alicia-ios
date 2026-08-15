import SwiftUI

/// A playlist on Studio's shelf — a queue Hector built to listen to whole.
struct PlaylistRow: View {
    let playlist: Playlist

    private var subtitle: String {
        let pieces = playlist.items.count == 1 ? "1 piece" : "\(playlist.items.count) pieces"
        let mins = Int((playlist.duration / 60).rounded())
        // Length is the thing he's choosing on — "is this the drive or the walk".
        let length = mins > 0 ? " · \(mins) min" : ""
        // Say plainly when part of it can't play yet rather than letting him
        // find out at a red light.
        let pending = playlist.items.count - playlist.ready
        let warming = pending > 0 ? " · \(pending) still warming" : ""
        return pieces + length + warming
    }

    var body: some View {
        HStack(spacing: 14) {
            // A stack of leaves, drawn — not a stock artwork tile.
            StippleIllustration(seed: playlist.name.inkSeed, dots: 260,
                                animated: false)
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Theme.stroke))
            VStack(alignment: .leading, spacing: 3) {
                InkTitle(text: playlist.name, size: 16, weight: .semibold)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(Theme.inkSoft)
            }
            Spacer()
            InkChevron(pointing: .right, size: 14)
        }
        .padding(10)
        .contentShape(Rectangle())
    }
}

/// One queue, opened: play it whole, re-sequence it, let pieces go.
struct PlaylistDetailView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let playlistID: String

    @State private var renaming = false
    @State private var draftName = ""
    @State private var confirmingDelete = false
    @State private var editing = false
    /// The piece being read along with — tapping a row plays it and opens it.
    @State private var opened: Playlist.Item?

    /// Always read through the store so a mutation's refreshed shelf shows
    /// up here without a local copy to reconcile.
    private var playlist: Playlist? {
        store.playlists.first { $0.id == playlistID }
    }

    var body: some View {
        Group {
            if let playlist {
                content(playlist)
            } else {
                // Deleted from under us (or from another device).
                VStack(spacing: 8) {
                    InkSpark(size: 14, color: Theme.inkSoft, seed: 3)
                    Text("This playlist is gone.")
                        .font(.system(size: 15, design: .serif)).italic()
                        .foregroundStyle(Theme.inkSoft)
                }
                .frame(maxWidth: .infinity, minHeight: 320)
            }
        }
        .sectionBackground()
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { InkBackButton() }
            ToolbarItem(placement: .principal) {
                InkTitleLine(text: playlist?.name ?? "Playlist", size: 16)
            }
        }
        .task { await store.loadPlaylists() }
    }

    @ViewBuilder
    private func content(_ playlist: Playlist) -> some View {
        List {
            Section {
                header(playlist)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            Section {
                ForEach(Array(playlist.items.enumerated()), id: \.element.id) { i, item in
                    PlaylistItemRow(item: item, index: i, playlist: playlist)
                        .listRowBackground(Color.clear)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            // Start it playing AND open it, so he can read
                            // along with her rather than staring at a list.
                            store.playPlaylist(playlist, from: i)
                            opened = item
                        }
                }
                .onMove { from, to in
                    var ids = playlist.items.map(\.id)
                    ids.move(fromOffsets: from, toOffset: to)
                    Task { await store.reorderPlaylist(playlist.id, order: ids) }
                }
                .onDelete { offsets in
                    let ids = offsets.map { playlist.items[$0].id }
                    Task {
                        for id in ids {
                            await store.removeFromPlaylist(playlist.id, itemID: id)
                        }
                    }
                }
            } header: {
                Text("IN ORDER")
                    .font(.system(size: 9, design: .monospaced).weight(.semibold))
                    .tracking(1.8)
                    .foregroundStyle(Theme.inkSoft)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.editMode, .constant(editing ? .active : .inactive))
        // Read along while she reads aloud. Episodes have no text to show,
        // so only the written pieces open.
        .sheet(item: $opened) { item in
            if item.kind == "episode" {
                EpisodeNotesSheet(title: item.title, label: item.source)
            } else {
                SynthesisReader(featured: FeaturedSynthesis(
                    title: item.title,
                    excerpt: String(item.body.prefix(220)),
                    body: item.body,
                    date: item.source,
                    speechChunks: item.speechChunks,
                    speechDuration: item.duration))
            }
        }
        .alert("Name this playlist", isPresented: $renaming) {
            TextField("Name", text: $draftName)
            Button("Save") {
                let name = draftName
                Task { await store.renamePlaylist(playlist.id, to: name) }
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Delete \"\(playlist.name)\"?", isPresented: $confirmingDelete) {
            Button("Delete", role: .destructive) {
                Task {
                    await store.deletePlaylist(playlist.id)
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The syntheses stay on the shelf — only the queue goes.")
        }
    }

    private func header(_ playlist: Playlist) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                StippleIllustration(seed: playlist.name.inkSeed, dots: 520,
                                    animated: true)
                    .frame(width: 96, height: 96)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Theme.stroke))
                VStack(alignment: .leading, spacing: 5) {
                    InkTitle(text: playlist.name, size: 21, weight: .semibold)
                    Text("\(playlist.items.count) pieces · "
                         + "\(Int((playlist.duration / 60).rounded())) min")
                        .font(.subheadline)
                        .foregroundStyle(Theme.inkSoft)
                    if !playlist.isFullyReady {
                        Text("\(playlist.items.count - playlist.ready) still in her voice")
                            .font(.caption)
                            .italic()
                            .foregroundStyle(Theme.inkSoft.opacity(0.8))
                    }
                }
                Spacer()
            }

            HStack(spacing: 18) {
                Button { store.playPlaylist(playlist) } label: {
                    HStack(spacing: 8) {
                        InkPlayPause(playing: false, size: 30, seed: playlist.id.inkSeed,
                                     ringed: true)
                        VStack(spacing: 2) {
                            Text("PLAY ALL")
                                .font(.system(size: 11, design: .monospaced).weight(.bold))
                                .tracking(1.6)
                                .foregroundStyle(Theme.accent)
                            InkUnderline(color: Theme.accent, seed: 5, lineWidth: 1.2)
                                .frame(width: 52, height: 4)
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(playlist.items.isEmpty)
                Spacer()
                wordButton(editing ? "DONE" : "REORDER") {
                    withAnimation { editing.toggle() }
                }
                wordButton("RENAME") {
                    draftName = playlist.name
                    renaming = true
                }
                wordButton("DELETE") { confirmingDelete = true }
            }
        }
        .padding(.vertical, 6)
    }

    private func wordButton(_ word: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(word)
                .font(.system(size: 9, design: .monospaced).weight(.bold))
                .tracking(1.4)
                .underline()
                .foregroundStyle(Theme.inkSoft)
        }
        .buttonStyle(.plain)
    }
}

private struct PlaylistItemRow: View {
    @Environment(AppStore.self) private var store
    let item: Playlist.Item
    let index: Int
    let playlist: Playlist

    private var isCurrent: Bool {
        store.reader.playlistName == playlist.name
            && store.reader.queuePosition == index
            && store.reader.isActive
    }

    var body: some View {
        HStack(spacing: 12) {
            if isCurrent, store.reader.isSpeaking {
                InkWaveBars(size: 14, color: Theme.accent, seed: item.id.inkSeed)
                    .frame(width: 20)
            } else {
                Text("\(index + 1)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Theme.inkSoft)
                    .frame(width: 20)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title.strippedEmojis)
                    .font(.system(size: 14, design: .serif).weight(isCurrent ? .semibold : .regular))
                    .foregroundStyle(isCurrent ? Theme.accentSoft : Theme.ink)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    if item.duration > 0 {
                        Text(item.duration.asClock)
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(Theme.inkSoft)
                    }
                    if !item.isReady {
                        // Honest about what can't play yet.
                        Text("WARMING")
                            .font(.system(size: 8, design: .monospaced).weight(.semibold))
                            .tracking(1.2)
                            .foregroundStyle(Theme.amber)
                    }
                }
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

/// Shownotes for a queued episode — the read-along for something that has
/// no body text of its own.
struct EpisodeNotesSheet: View {
    @Environment(AppStore.self) private var store
    let title: String
    let label: String
    @State private var notes: AttributedString?
    @State private var loading = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                InkTitle(text: title, size: 21, weight: .semibold)
                Theme.stroke.frame(height: 0.7)
                if loading {
                    ProgressView("Fetching shownotes…")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                } else if let notes {
                    Text(notes)
                        .font(.system(size: 15, design: .serif))
                        .lineSpacing(5)
                        .textSelection(.enabled)
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
            .padding(24)
            .padding(.bottom, 40)
        }
        .presentationBackground(Theme.paper)
        .task {
            // A queued episode keeps its label in `source`; that's all the
            // shownotes lookup needs.
            let md = await store.episodeNotes(
                for: Track(title: title, mood: "", duration: 0, symbol: "",
                           label: label))
            notes = md.isEmpty ? nil : EpisodeDetailView.render(md)
            loading = false
        }
    }
}

/// "Add to a playlist" — pick an existing queue or start a new one.
struct AddToPlaylistSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let synthesis: FeaturedSynthesis

    @State private var newName = ""
    @State private var working = false

    private var holding: Set<String> { store.playlistsHolding(synthesis.pinID) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(synthesis.title.strippedEmojis)
                        .font(.system(.headline, design: .serif))
                        .fixedSize(horizontal: false, vertical: true)

                    Text("ADD TO")
                        .font(.system(size: 9, design: .monospaced).weight(.semibold))
                        .tracking(1.8)
                        .foregroundStyle(Theme.inkSoft)

                    if store.playlists.isEmpty {
                        Text("No playlists yet — name one below and this becomes its first piece.")
                            .font(.system(size: 14, design: .serif)).italic()
                            .foregroundStyle(Theme.inkSoft)
                    }

                    ForEach(store.playlists) { playlist in
                        Button {
                            toggle(playlist)
                        } label: {
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
                        Button(action: create) {
                            InkSubmitArrow(size: 24)
                        }
                        .buttonStyle(.plain)
                        .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty
                                  || working)
                    }
                    .padding(.bottom, 6)
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
                await store.removeFromPlaylist(playlist.id, itemID: synthesis.pinID)
            } else {
                await store.addToPlaylist(playlist.id, synthesis: synthesis)
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
            // Newest first, so the one just made is the head of the shelf —
            // add straight into it rather than making him tap again.
            if let made = store.playlists.first(where: { $0.name == name }) {
                await store.addToPlaylist(made.id, synthesis: synthesis)
            }
            newName = ""
            working = false
        }
    }
}

/// The affordance itself — a word, on any synthesis.
struct AddToPlaylistLine: View {
    @Environment(AppStore.self) private var store
    let synthesis: FeaturedSynthesis
    @State private var picking = false

    private var queued: Bool { !store.playlistsHolding(synthesis.pinID).isEmpty }

    var body: some View {
        Button { picking = true } label: {
            VStack(spacing: 2) {
                Text(queued ? "QUEUED" : "LISTEN LATER")
                    .font(.system(size: 10, design: .monospaced).weight(.bold))
                    .tracking(1.5)
                    .foregroundStyle(queued ? Theme.mint : Theme.inkSoft)
                InkUnderline(color: queued ? Theme.mint : Theme.inkSoft,
                             seed: synthesis.title.inkSeed, lineWidth: 1.0)
                    .frame(width: queued ? 46 : 72, height: 4)
            }
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $picking) {
            AddToPlaylistSheet(synthesis: synthesis)
        }
    }
}
