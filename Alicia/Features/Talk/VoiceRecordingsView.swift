import SwiftUI
import AVFoundation

struct VoiceRecordingsView: View {
    @Environment(AppStore.self) private var store
    var recordingID: String? = nil
    @State private var path: [String] = []

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if let recordingID {
                    VoiceRecordingDetail(id: recordingID, pushed: false)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            // The introduction is about the page, not a row.
                            Text("Your original voice, the words captured from it, and the context around it.")
                                .font(.subheadline).italic().foregroundStyle(Theme.inkSoft)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.bottom, 16)
                            if store.voiceArchive.recordings.isEmpty {
                                InkNotice(text: "New walk recordings and dictated messages will appear here. Earlier audio cannot be recovered.", kind: .info)
                            }
                            ForEach(Array(store.voiceArchive.recordings.enumerated()), id: \.element.id) { index, record in
                                if index > 0 { InkRule(opacity: 0.6) }
                                Button { path.append(record.id) } label: { VoiceRecordingRow(record: record) }
                                    .buttonStyle(.inkLink)
                            }
                        }
                        .padding(22)
                    }
                    .navigationDestination(for: String.self) { VoiceRecordingDetail(id: $0, pushed: true) }
                    .inkSheetPage("Recordings")
                }
            }
            // v40: reviewing what he said is still being with her.
            .presenceBackground(.mind, store: store)
            .task { await store.refreshVoiceArchive() }
        }
        .tint(Theme.ink)
    }
}

/// One recording in the list: where it came from, where it is, and her chevron.
private struct VoiceRecordingRow: View {
    let record: VoiceRecording
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(record.context.episode_title.isEmpty ? "A spoken thought" : record.context.episode_title.strippedEmojis)
                    .font(.system(size: 20, design: .serif)).foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.leading)
                Text(voiceDateLabel(record.context) + " · " + (record.context.source == "ios_walk" ? "Walk" : "Dialogue"))
                    .font(InkType.meta).foregroundStyle(Theme.inkSoft)
                // The same vocabulary the detail screen and the composer band
                // use, so a reflection reads the same wherever he finds it.
                Text(record.stage.label)
                    .font(.system(size: 10, design: .monospaced)).tracking(0.8)
                    .foregroundStyle(record.stage.needsYou ? Theme.ink : Theme.inkSoft)
                    .accessibilityIdentifier("voice.listStage")
                Text(record.deleted ? "Audio deleted · words kept" : "\(Int(record.duration / 60))m \(Int(record.duration) % 60)s recorded")
                    .font(InkType.meta).foregroundStyle(Theme.inkSoft)
            }
            Spacer(minLength: 8)
            InkChevron(pointing: .right, size: 14, color: Theme.inkSoft, seed: record.id.inkSeed)
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
    }
}

func voiceDateLabel(_ context: VoiceContext) -> String {
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
    /// Pushed from the list (her BACK) or the root of the sheet (CLOSE).
    var pushed: Bool
    @State private var player: AVQueuePlayer?
    @State private var correction = ""
    /// Playback and correction each report next to their own control.
    @State private var playbackStatus = ""
    @State private var status = ""
    @State private var statusIsError = false
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

    /// The page's one check: the archive and this recording's detail. It was
    /// "SYNC" here and "CHECK MAC / SYNC" in the stage below — now one action.
    private func checkMac() async {
        await store.refreshVoiceArchive(); details = await store.voiceDetail(id)
    }

    private var record: VoiceRecording? { store.voiceArchive.recording(id) }

    var body: some View {
        page
            .presenceBackground(.mind, store: store)
            .scrollDismissesKeyboard(.interactively)
            .task { await store.refreshVoiceArchive(); details = await store.voiceDetail(id) }
            .onDisappear { stopPlayback() }
            .onChange(of: scenePhase) { _, phase in if phase != .active { stopPlayback() } }
            .confirmationDialog("Delete the original audio from this phone and your Mac? The transcript and context will remain.",
                                isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete original audio", role: .destructive) { Task { await store.deleteOriginalVoice(id) } }
            }
    }

    @ViewBuilder private var page: some View {
        if pushed { scroll.inkPushedPage("Original voice") } else { scroll.inkSheetPage("Original voice") }
    }

    private var scroll: some View {
        ScrollView {
            if let record {
                VStack(alignment: .leading, spacing: 26) {
                    header(record)
                    listen(record)
                    InkSection(kicker: "Where it is") { whereItIs(record) }
                    if !record.isPrivateBody, !record.deleted { VoiceEnrichmentView(recordingID: id) }
                    words(record)
                    if record.macProcessing != true || record.submissionStatus?.state == "completed" || record.transcripts.contains(where: { $0.kind == "submitted" }) {
                        correct(record)
                    }
                    versions(record)
                    if !record.deleted {
                        InkSection(kicker: "Original audio") {
                            Text("Deleting removes the audio from this phone and your Mac. Your words and context stay.")
                                .font(InkType.meta).foregroundStyle(Theme.inkSoft)
                            Button("DELETE AUDIO") { stopPlayback(); confirmDelete = true }
                                .buttonStyle(.inkDestructiveCompact)
                        }
                    }
                }
                .padding(24)
            } else {
                InkNotice(text: "This recording is not available on this phone yet.", kind: .info).padding(24)
            }
        }
    }

    // MARK: Header — what it is, when and where, as one meta block.

    @ViewBuilder private func header(_ record: VoiceRecording) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(record.context.episode_title.isEmpty ? "A spoken thought" : record.context.episode_title.strippedEmojis)
                .font(.system(size: 28, design: .serif))
                .fixedSize(horizontal: false, vertical: true)
            Text(voiceDateLabel(record.context)).font(.subheadline)
            Text(record.context.timezone + " · " + (record.context.source == "ios_walk" ? "Recorded in Walk" : "Dictated in Dialogue"))
                .font(InkType.meta).foregroundStyle(Theme.inkSoft)
            if !record.context.episode_id.isEmpty {
                Text(record.context.episode_id + " · " + (record.context.episode_basis == "selected" ? "chosen episode" : "episode context"))
                    .font(InkType.meta).foregroundStyle(Theme.inkSoft)
            }
            if let season = record.context.season {
                HStack(spacing: 12) {
                    if let previous = record.context.previous_season { Text("Season \(previous)") }
                    Text("Season \(season)").bold()
                    if let next = record.context.next_season { Text("Season \(next)") }
                }.font(InkType.meta).foregroundStyle(Theme.inkSoft)
                Text("Neighboring seasons in the available catalog.").font(InkType.meta).foregroundStyle(Theme.inkSoft)
            }
        }
        if !record.context.question_presented.isEmpty {
            Text(record.context.question_presented.strippedEmojis).font(.system(size: 20, design: .serif)).italic()
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: The page's primary — listen to the original.

    @ViewBuilder private func listen(_ record: VoiceRecording) -> some View {
        if record.deleted {
            InkNotice(text: record.deletionUploaded == true ? "Original audio deleted. Your text and context remain." : "Audio deleted on this phone. Deletion on the Mac is pending; tap Check your Mac.",
                      kind: .info)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Button(loading ? "OPENING ORIGINAL…" : player == nil ? "LISTEN TO ORIGINAL" : "STOP PLAYBACK") {
                    editing = false
                    if let player { player.pause(); self.player = nil }
                    else {
                        loading = true
                        playbackStatus = ""
                        let generation = UUID(); playbackGeneration = generation
                        Task {
                            let files = await store.playOriginalVoice(id)
                            guard playbackGeneration == generation, scenePhase == .active else { return }
                            loading = false
                            guard store.voiceArchive.recording(id)?.deleted == false else { return }
                            if files.isEmpty { playbackStatus = "No playable audio is available yet."; return }
                            do {
                                try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
                                try AVAudioSession.sharedInstance().setActive(true)
                                player = AVQueuePlayer(items: files.map { AVPlayerItem(url: $0) })
                                player?.play()
                            } catch { playbackStatus = "Audio playback could not start." }
                        }
                    }
                }
                .buttonStyle(.inkPrimary)
                .disabled(loading || record.segments.isEmpty)
                .accessibilityIdentifier("voice.playOriginal")
                Text("\(Int(record.duration / 60))m \(Int(record.duration) % 60)s of original audio · \(record.segments.reduce(0) { $0 + $1.bytes } / 1_000_000) MB")
                    .font(InkType.meta).foregroundStyle(Theme.inkSoft)
                InkNotice(text: playbackStatus, kind: .error)
            }
        }
    }

    // MARK: Where it is — the stage and the actions that recover it, in one card.

    @ViewBuilder private func whereItIs(_ record: VoiceRecording) -> some View {
        InkNotice(text: record.error ?? "", kind: .error)
        if !record.isPrivateBody, record.macProcessing == true {
            // The stage card, its retry and the page's one check live here;
            // it also prints the archive's error once.
            VoiceProcessingView(id: id, check: { await checkMac() }).id(id)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Text(record.isPrivateBody ? "Private audio stays on this phone; no cloud transcription or enrichment." : record.segments.isEmpty ? "No audio segment has finalized yet." :
                    record.segments.allSatisfy { $0.uploaded == true } ? "Audio synced to your Mac." : "Original audio is kept on this phone. Some audio is waiting to sync.")
                    .font(.callout).foregroundStyle(Theme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                if !record.isPrivateBody {
                    Button(store.voiceArchive.syncing ? "Checking…" : "Check your Mac") { Task { await checkMac() } }
                        .buttonStyle(.inkQuiet)
                        .disabled(store.voiceArchive.syncing)
                }
                InkNotice(text: store.voiceArchive.lastError, kind: .error)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card(padding: 16, radius: 16)
        }
    }

    // MARK: His words as captured.

    @ViewBuilder private func words(_ record: VoiceRecording) -> some View {
        InkSection(kicker: "Your words") {
            if !record.latestWords.isEmpty {
                Text(record.latestWords).font(.system(size: 20, design: .serif)).textSelection(.enabled)
            }
            InkDisclosure("Original on-device transcript") {
                let original = record.orderedTranscripts.filter { $0.kind == "on_device" }
                if original.isEmpty { Text("No live transcript was captured. The recording is the source.").font(.callout) }
                ForEach(original) { version in Text(version.text).font(.callout).frame(maxWidth: .infinity, alignment: .leading) }
            }
        }
    }

    @ViewBuilder private func correct(_ record: VoiceRecording) -> some View {
        InkSection(kicker: "Correct the transcript") {
            Text("Replay your voice, then write what the transcript missed. Saving adds a correction; the original stays visible.")
                .font(InkType.meta).foregroundStyle(Theme.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
            TextEditor(text: $correction)
                .focused($editing)
                .scrollContentBackground(.hidden)
                .inkField(minHeight: 120)
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
                        status = "Correction kept. Sync status shows whether it reached Alicia."; statusIsError = false
                    } else { status = "Correction could not be saved. Your text is still here."; statusIsError = true }
                }
            }
            .buttonStyle(.inkSecondary)
            .disabled(savingCorrection || correction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || correction.count > 60000)
            InkNotice(text: status, kind: statusIsError ? .error : .success)
        }
    }

    // MARK: Versions and links — each opens here.

    @ViewBuilder private func versions(_ record: VoiceRecording) -> some View {
        let later = record.orderedTranscripts.filter { $0.kind != "on_device" }
        let hasCorrection = record.orderedTranscripts.contains(where: { $0.kind == "correction" })
        let nearby = details?.nearby_messages ?? []
        if hasCorrection || !later.isEmpty || !record.links.isEmpty || !nearby.isEmpty {
            InkSection(kicker: "Versions and links", spacing: 4) {
                if hasCorrection {
                    InkNotice(text: record.correction_state == "linked_to_episode" ? "Your correction is linked to the episode reflection." : "Correction retained. Awaiting its message link or episode refresh; Check your Mac to retry.",
                              kind: .info)
                        .padding(.bottom, 6)
                }
                ForEach(later) { version in
                    InkDisclosure(version.kind == "correction" ? "Your correction" : "Words you submitted") {
                        Text(version.text).font(.body).textSelection(.enabled)
                    }
                }
                ForEach(Array(record.links.enumerated()), id: \.offset) { _, link in
                    InkDisclosure(link.kind == "walk" ? "Linked walk reflection" : "Linked Dialogue message") {
                        Text(link.text.strippedEmojis).font(.body).textSelection(.enabled)
                    }
                }
                if !nearby.isEmpty {
                    InkDisclosure("Messages near this recording") {
                        Text("Within two hours. Proximity is a time reference; you decide what connects.")
                            .font(InkType.meta).foregroundStyle(Theme.inkSoft)
                        ForEach(nearby) { message in
                            VStack(alignment: .leading) {
                                Text(message.role == "user" ? "You" : "Alicia").font(.caption).bold()
                                Text(message.role == "user" ? message.content : message.content.strippedEmojis).font(.body)
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 6)
                        }
                    }
                }
            }
        }
    }
}
