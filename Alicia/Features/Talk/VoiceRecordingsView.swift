import SwiftUI
import AVFoundation

struct VoiceRecordingsView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var recordingID: String? = nil

    var body: some View {
        NavigationStack {
            Group {
                if let recordingID {
                    VoiceRecordingDetail(id: recordingID)
                } else {
                    List {
                        Text("Your original voice, the words captured from it, and the context around it.")
                            .font(.subheadline).foregroundStyle(Theme.inkSoft)
                        if store.voiceArchive.recordings.isEmpty {
                            Text("New walk recordings and dictated messages will appear here. Earlier audio cannot be recovered.")
                                .font(.subheadline)
                        }
                        ForEach(store.voiceArchive.recordings) { record in
                            NavigationLink(value: record.id) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(record.context.episode_title.isEmpty ? "A spoken thought" : record.context.episode_title)
                                        .font(.system(size: 20, design: .serif))
                                    Text(voiceDateLabel(record.context) + " · " + (record.context.source == "ios_walk" ? "Walk" : "Dialogue"))
                                        .font(.caption).foregroundStyle(Theme.inkSoft)
                                    Text(record.deleted ? "Audio deleted · words kept" : "\(Int(record.duration / 60))m \(Int(record.duration) % 60)s recorded")
                                        .font(.caption)
                                }.padding(.vertical, 8)
                            }
                        }
                    }
                    .scrollContentBackground(.hidden)
                    .navigationDestination(for: String.self) { VoiceRecordingDetail(id: $0) }
                    .navigationTitle("Recordings")
                }
            }
            .background(Theme.paper)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("CLOSE") { dismiss() }.font(.system(size: 10, design: .monospaced))
                }
            }
            .task { await store.refreshVoiceArchive() }
        }
        .tint(Theme.ink)
    }
}

private func voiceDateLabel(_ context: VoiceContext) -> String {
    let parser = ISO8601DateFormatter()
    parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    guard let date = parser.date(from: context.started_at) else { return context.started_at }
    let formatter = DateFormatter()
    formatter.timeZone = TimeZone(identifier: context.timezone)
    formatter.dateFormat = "EEEE, MMM d · h:mm a"
    return formatter.string(from: date)
}

private struct VoiceRecordingDetail: View {
    @Environment(AppStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    var id: String
    @State private var player: AVQueuePlayer?
    @State private var correction = ""
    @State private var status = ""
    @State private var loading = false
    @State private var playbackGeneration = UUID()
    @State private var savingCorrection = false
    @State private var confirmDelete = false
    @State private var details: VoiceEvidencePayload?
    @FocusState private var editing: Bool

    private func stopPlayback() {
        playbackGeneration = UUID(); loading = false
        player?.pause(); player = nil
    }

    private var record: VoiceRecording? { store.voiceArchive.recording(id) }

    var body: some View {
        ScrollView {
            if let record {
                VStack(alignment: .leading, spacing: 22) {
                    Text(record.context.episode_title.isEmpty ? "A spoken thought" : record.context.episode_title)
                        .font(.system(size: 28, design: .serif))
                    Text(voiceDateLabel(record.context)).font(.subheadline)
                    Text(record.context.timezone + " · " + (record.context.source == "ios_walk" ? "Recorded in Walk" : "Dictated in Dialogue"))
                        .font(.caption).foregroundStyle(Theme.inkSoft)
                    if !record.context.episode_id.isEmpty {
                        Text(record.context.episode_id + " · " + (record.context.episode_basis == "selected" ? "chosen episode" : "episode context"))
                            .font(.system(size: 11, design: .monospaced))
                    }
                    if let season = record.context.season {
                        HStack(spacing: 12) {
                            if let previous = record.context.previous_season { Text("Season \(previous)") }
                            Text("Season \(season)").bold()
                            if let next = record.context.next_season { Text("Season \(next)") }
                        }.font(.caption)
                        Text("Neighboring seasons in the available catalog.").font(.caption).foregroundStyle(Theme.inkSoft)
                    }
                    if !record.context.question_presented.isEmpty {
                        Text(record.context.question_presented).font(.system(size: 20, design: .serif)).italic()
                    }
                    if record.deleted {
                        Text(record.deletionUploaded == true ? "Original audio deleted. Your text and context remain." : "Audio deleted on this phone. Deletion on the Mac is pending; tap Sync.")
                            .font(.subheadline)
                    } else {
                        Button(loading ? "OPENING ORIGINAL…" : player == nil ? "LISTEN TO ORIGINAL" : "STOP PLAYBACK") {
                            editing = false
                            if let player { player.pause(); self.player = nil }
                            else {
                                loading = true
                                let generation = UUID(); playbackGeneration = generation
                                Task {
                                    let files = await store.playOriginalVoice(id)
                                    guard playbackGeneration == generation, scenePhase == .active else { return }
                                    loading = false
                                    guard store.voiceArchive.recording(id)?.deleted == false else { return }
                                    if files.isEmpty { status = "No playable audio is available yet."; return }
                                    do {
                                        try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
                                        try AVAudioSession.sharedInstance().setActive(true)
                                        player = AVQueuePlayer(items: files.map { AVPlayerItem(url: $0) })
                                        player?.play()
                                    } catch { status = "Audio playback could not start." }
                                }
                            }
                        }
                        .buttonStyle(EpisodeButtonStyle())
                        .disabled(loading || record.segments.isEmpty)
                        .accessibilityIdentifier("voice.playOriginal")
                        Text("\(Int(record.duration / 60))m \(Int(record.duration) % 60)s of original audio · \(record.segments.reduce(0) { $0 + $1.bytes } / 1_000_000) MB")
                            .font(.caption)
                        Text(record.segments.isEmpty ? "No audio segment has finalized yet." :
                            record.segments.allSatisfy { $0.uploaded == true } ? "Audio synced to your Mac." : "Original audio is kept on this phone. Some audio is waiting to sync.")
                            .font(.caption).foregroundStyle(Theme.inkSoft)
                    }
                    HStack {
                        Button(store.voiceArchive.syncing ? "SYNCING…" : "SYNC") {
                            Task { await store.refreshVoiceArchive(); details = await store.voiceDetail(id) }
                        }.disabled(store.voiceArchive.syncing)
                        Spacer()
                        if !record.deleted {
                            Button("DELETE AUDIO") { stopPlayback(); confirmDelete = true }
                        }
                    }
                    .font(.system(size: 10, design: .monospaced)).frame(minHeight: 44)

                    DisclosureGroup("Original on-device transcript") {
                        let original = record.orderedTranscripts.filter { $0.kind == "on_device" }
                        if original.isEmpty { Text("No live transcript was captured. The recording is the source.") }
                        ForEach(original) { version in Text(version.text).frame(maxWidth: .infinity, alignment: .leading) }
                    }.font(.subheadline)
                    if !record.latestWords.isEmpty {
                        Text("LATEST WORDS").font(.system(size: 10, design: .monospaced)).tracking(1)
                        Text(record.latestWords).font(.system(size: 20, design: .serif)).textSelection(.enabled)
                    }
                    Text("Correct the transcript").font(.system(size: 21, design: .serif))
                    Text("Replay your voice, then write what the transcript missed. Saving adds a correction; the original stays visible.")
                        .font(.caption).foregroundStyle(Theme.inkSoft)
                    TextEditor(text: $correction)
                        .font(.body).frame(minHeight: 120).focused($editing)
                        .scrollContentBackground(.hidden)
                        .overlay(Rectangle().stroke(Theme.inkSoft.opacity(0.25)))
                        .accessibilityLabel("Corrected transcript")
                    Button("SAVE CORRECTION") {
                        let text = correction.trimmingCharacters(in: .whitespacesAndNewlines)
                        editing = false
                        savingCorrection = true
                        Task {
                            let saved = await store.correctVoice(id, text: text)
                            savingCorrection = false
                            if saved {
                                if correction.trimmingCharacters(in: .whitespacesAndNewlines) == text { correction = "" }
                                status = "Correction kept. Sync status shows whether it reached Alicia."
                            } else { status = "Correction could not be saved. Your text is still here." }
                        }
                    }
                    .font(.system(size: 11, design: .monospaced)).frame(minHeight: 44)
                    .disabled(savingCorrection || correction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || correction.count > 60000)
                    if record.orderedTranscripts.contains(where: { $0.kind == "correction" }) {
                        Text(record.correction_state == "linked_to_episode" ? "Your correction is linked to the episode reflection." : "Correction retained. Awaiting its message link or episode refresh; tap Sync to retry.")
                            .font(.caption).foregroundStyle(Theme.inkSoft)
                    }
                    ForEach(record.orderedTranscripts.filter { $0.kind != "on_device" }) { version in
                        DisclosureGroup(version.kind == "correction" ? "Your correction" : "Words you submitted") {
                            Text(version.text).font(.body).textSelection(.enabled)
                        }.font(.caption)
                    }
                    ForEach(Array(record.links.enumerated()), id: \.offset) { _, link in
                        DisclosureGroup(link.kind == "walk" ? "Linked walk reflection" : "Linked Dialogue message") {
                            Text(link.text).font(.body).textSelection(.enabled)
                        }.font(.caption)
                    }
                    if let messages = details?.nearby_messages, !messages.isEmpty {
                        DisclosureGroup("Messages near this recording") {
                            Text("Within two hours. Proximity is a time reference; you decide what connects.")
                                .font(.caption).foregroundStyle(Theme.inkSoft)
                            ForEach(messages) { message in
                                VStack(alignment: .leading) {
                                    Text(message.role == "user" ? "You" : "Alicia").font(.caption).bold()
                                    Text(message.content).font(.body)
                                }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 6)
                            }
                        }.font(.subheadline)
                    }
                    if !status.isEmpty { Text(status).font(.caption) }
                    if let error = record.error { Text(error).font(.caption) }
                    if !store.voiceArchive.lastError.isEmpty { Text(store.voiceArchive.lastError).font(.caption) }
                }
                .padding(24)
            } else {
                Text("This recording is not available on this phone yet.").padding()
            }
        }
        .background(Theme.paper)
        .navigationTitle("Original voice").navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .task { await store.refreshVoiceArchive(); details = await store.voiceDetail(id) }
        .onDisappear { stopPlayback() }
        .onChange(of: scenePhase) { _, phase in if phase != .active { stopPlayback() } }
        .confirmationDialog("Delete the original audio from this phone and your Mac? The transcript and context will remain.",
                            isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete original audio", role: .destructive) { Task { await store.deleteOriginalVoice(id) } }
        }
    }
}
