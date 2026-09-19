import SwiftUI
import UIKit

/// A dedicated, recoverable thinking-aloud surface. No model interrupts the walk.
struct WalkReflectionView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @State private var speech = SpeechTranscriber()
    @State private var base = ""
    @State private var listening = false
    @State private var status = ""
    @State private var restarting = false
    @State private var automaticRestarts = 0
    @State private var startGeneration = 0
    @State private var starting = false
    @State private var reviewingWords = false
    @State private var previousIdleTimerDisabled: Bool?
    @State private var showRecording = false
    @State private var savedRecordingID = ""
    @State private var savedAudioOnly = false
    @State private var didSave = false
    @State private var savedPrivate = false

    private var visibleRecording: Bool {
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--episode-day-preview") && ProcessInfo.processInfo.arguments.contains("--episode-microphone-on") { return true }
#endif
        return speech.isRecording && !speech.isFinishing
    }

    var body: some View {
        @Bindable var store = store
        // The listening room owns the whole screen. The padding and paper
        // ground below belong to the *other* phases — applied to the outer
        // container they stopped her field 24 points short of every edge, and
        // the room read as a card on a page rather than the page itself.
        Group {
        VStack(alignment: .leading, spacing: 20) {
            if let record = store.voiceArchive.recording(store.walkRecordingID), record.finalization != nil {
                HStack {
                    Text(record.context.episode_id).font(.system(size: 11, design: .monospaced))
                    Spacer()
                    Button("CLOSE") { pause(); store.showWalk = false }.frame(minHeight: 44)
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if !store.walkDraft.isEmpty {
                            DisclosureGroup("Earlier typed words · kept separately") {
                                Text(store.walkDraft).textSelection(.enabled)
                            }.font(.caption)
                        }
                        VoiceProcessingView(id: record.id).id(record.id)
                    }
                }
                Button("RECORD ANOTHER THOUGHT") {
                    store.walkRecordingID = UUID().uuidString
                    Task { await begin() }
                }.font(.system(size: 10, design: .monospaced)).frame(minHeight: 44)
                Button("REVIEW ORIGINAL AUDIO") { showRecording = true }.frame(minHeight: 44)
                if record.submissionStatus?.state == "completed" {
                    Button("DONE") { store.showWalk = false; store.selectedSection = .mind }.buttonStyle(EpisodeButtonStyle())
                }
            } else if didSave {
                savedView
            } else if macMode {
                // v39: "talk about this episode" opens the same full-screen
                // room the composer's TALK does. Hector could not tell from a
                // 90-point strip whether the microphone was taking his words,
                // so the words are now the page: her particles behind, his own
                // sentences large in front, and nothing else competing.
                episodeListening
            } else {
            HStack {
                Text(subjectKicker).font(.system(size: 11, design: .monospaced)).tracking(1.5)
                Spacer()
                Button("CLOSE") { pause(); store.pauseEpisodeWalk(); store.showWalk = false }
                    .font(.system(size: 10, design: .monospaced)).tracking(1.2)
            }
            ListeningPresence(isRecording: visibleRecording, isStarting: starting || restarting,
                seconds: speech.recordedSeconds, level: speech.inputLevel,
                microphoneName: speech.microphoneName, liveTextAvailable: speech.liveTextAvailable, transcribesOnMac: true, voice: TabPresence.voice(for: store.composerSection))
            InkTitle(text: speech.isFinishing ? "Keeping your last words" : visibleRecording ? "I'm listening" : "Stay with the thought", size: 30)
            if !store.walkPrompt.isEmpty {
                Text(store.walkPrompt.strippedEmojis).font(.system(size: 21, design: .serif))
            }
            Text("Say what stayed with you, what you question, or where it meets your day.")
                .font(.subheadline).italic().foregroundStyle(Theme.inkSoft)
            if store.voiceArchive.recording(store.walkRecordingID)?.macProcessing == true {
                Text("Finish to get a Mac transcript. Review it before sending.")
                    .font(.body).foregroundStyle(Theme.inkSoft).fixedSize(horizontal: false, vertical: true)
                if !store.walkDraft.isEmpty {
                    DisclosureGroup("Earlier typed words · kept separately") {
                        Text(store.walkDraft).textSelection(.enabled)
                    }.font(.caption)
                }
                Spacer(minLength: 16)
            } else {
            TextEditor(text: $store.walkDraft)
                .font(.system(size: 20, design: .serif))
                .disabled(listening || store.pendingWalkSave != nil)
                .scrollContentBackground(.hidden)
                .accessibilityLabel("Your walk reflection")
            }
            Text(reviewingWords ? (speech.transcriptNeedsReview ? "Live text was interrupted. These words may be incomplete. Review the audio, edit the words, or save just the recording." : "Check these words before sending. Your original recording is kept separately.") : speech.lastError ?? (status.isEmpty ? "Original audio is kept on this phone and synced to your Mac." : status))
                .font(.caption).foregroundStyle(Theme.inkSoft)
            HStack {
                Text("Audio stays until you delete it.").font(.caption).foregroundStyle(Theme.inkSoft)
                Spacer()
                if store.voiceArchive.hasAudio(store.walkRecordingID) {
                    Button("REVIEW AUDIO") { pause(); showRecording = true }
                        .font(.system(size: 10, design: .monospaced)).frame(minHeight: 44)
                }
            }
            EpisodeErrorLine()
            Button(listening ? "PAUSE LISTENING" : "KEEP TALKING") {
                if listening { Task { await finishListening() } } else { Task { await begin() } }
            }
            .font(.system(size: 11, design: .monospaced)).tracking(1.3)
            .frame(maxWidth: .infinity, minHeight: 44)
            .disabled(starting || speech.isFinishing || store.pendingWalkSave != nil)
            Button(store.isSavingWalk ? "SAVING YOUR REFLECTION…" : store.pendingWalkSave != nil ? "RETRY SAVE" : reviewingWords ? "SEND THESE WORDS & REFLECT" : "FINISH & REVIEW") {
                let wasListening = listening
                Task {
                    if wasListening { await finishListening() }
                    guard store.showWalk else { return }
                    if store.voiceArchive.recording(store.walkRecordingID)?.macProcessing == true {
                        _ = store.finalizeVoice(store.walkRecordingID, speech: speech)
                    } else if wasListening && store.pendingWalkSave == nil { reviewingWords = true }
                    else { await save(audioOnly: false) }
                }
            }
            .buttonStyle(EpisodeButtonStyle())
            .disabled(store.isSavingWalk || speech.isFinishing || (!listening && !store.voiceArchive.hasAudio(store.walkRecordingID)
                && store.walkDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
            .accessibilityIdentifier("episode.finishWalk")
            if !listening, store.pendingWalkSave == nil, store.voiceArchive.hasAudio(store.walkRecordingID), store.voiceArchive.recording(store.walkRecordingID)?.macProcessing != true {
                Button("SAVE AUDIO ONLY") { Task { await save(audioOnly: true) } }
                    .font(.system(size: 11, design: .monospaced)).frame(minHeight: 44)
                    .accessibilityIdentifier("walk.saveAudioOnly")
            }
            }
        }
        .disabled(store.isSavingWalk)
        .padding(listeningPhase ? 0 : 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity,
               alignment: listeningPhase ? .center : .topLeading)
        .background(listeningPhase ? Color.clear : Theme.paper)
        }
        // No ignoresSafeArea here: ListeningStage's own backdrop, tint, field
        // and grain each ignore it already, so the ROOM reaches every edge
        // while the clock, the CLOSE button and the controls stay inside the
        // safe area where they can be read and tapped.
        .sheet(isPresented: $showRecording) { VoiceRecordingsView(recordingID: didSave ? savedRecordingID : store.walkRecordingID) }
        .task {
#if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--voice-evidence-preview") || ProcessInfo.processInfo.arguments.contains("--episode-day-preview") || ProcessInfo.processInfo.arguments.contains("--episode-continuity-preview") {
                listening = visibleRecording
                status = visibleRecording ? "Preview of microphone-on UI. No audio is recorded or sent." : "Preview — recording is paused. No audio or words are sent."
                return
            }
#endif
            // A private Body walk with kept words and audio re-opens in its
            // editable review — never auto-restarting the mic over his words.
            if privateBodyWalk,
               store.voiceArchive.hasAudio(store.walkRecordingID),
               !store.walkDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                reviewingWords = true
            } else if store.voiceArchive.recording(store.walkRecordingID)?.finalization == nil {
                await begin()
            }
        }
        .onAppear { keepScreenAwake() }
        .onDisappear { pause(); restoreScreenSleep() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                keepScreenAwake()
            } else {
                restoreScreenSleep()
                pause()
                status = "Listening paused. Your words are kept here; tap Keep talking to continue."
            }
        }
        .onChange(of: speech.transcript) { _, text in
            if listening { store.walkDraft = base + (base.isEmpty || text.isEmpty ? "" : "\n\n") + text }
        }
        .onChange(of: speech.isRecording) { was, now in
            guard was, !now, listening else { return }
            if !speech.transcript.isEmpty {
                store.walkDraft = base + (base.isEmpty ? "" : "\n\n") + speech.transcript
            }
            base = store.walkDraft
            listening = false
            status = speech.lastError ?? "Recording paused. Your captured audio is kept."
        }
    }

    /// True for every recording made since Mac transcription landed: the
    /// phone keeps the original audio and the Mac writes the transcript he
    /// reviews. The legacy typed path below is kept for older recordings.
    private var macMode: Bool {
        let record = store.voiceArchive.recording(store.walkRecordingID)
        return record?.macProcessing == true || record == nil || record?.isPrivateBody == true
    }

    /// A no-episode walk started from the Body section. Its words stay in the
    /// private Body lane: no Mac transcript, no cloud upload, reviewed then sent
    /// only through `sendPrivateBodyWalk`.
    private var privateBodyWalk: Bool {
        if let record = store.voiceArchive.recording(store.walkRecordingID) { return record.isPrivateBody }
        return store.walkEpisodeID.isEmpty && store.walkSurface == "body"
    }

    /// The private Body walk is in its editable review phase (stopped, not
    /// recording), so the room shows a correctable field instead of read-only text.
    private var privateReviewing: Bool { privateBodyWalk && reviewingWords && !visibleRecording }

    private var episodeListening: some View {
        @Bindable var store = store
        return ListeningStage(
            voice: .forSurface(store.walkSurface.isEmpty ? "alicia" : store.walkSurface),
            isRecording: visibleRecording,
            isStarting: starting || restarting,
            level: speech.inputLevel,
            kicker: subjectKicker,
            seconds: speech.recordedSeconds,
            words: spokenWords,
            placeholder: speech.isFinishing ? "Keeping your last words…"
                : visibleRecording ? (store.walkPrompt.isEmpty
                    ? "Say what stayed with you, what you question, or where it meets your day."
                    : store.walkPrompt.strippedEmojis)
                : "Stay with the thought. Tap Keep talking when you're ready.",
            note: listeningNote,
            // The private review is an editable field: on-device corrections or
            // typing when live text was off, with the visible 4000-char limit.
            editableWords: privateReviewing ? $store.walkDraft : nil,
            characterLimit: privateReviewing ? 4000 : nil,
            close: { pause(); store.pauseEpisodeWalk(); store.showWalk = false },
            controls: { episodeControls }
        )
    }

    /// Live recognition while he speaks, then the audio's own record once the
    /// recognizer stops. The Mac transcript he reviews later is still the
    /// authority; this is only so he can watch it landing.
    private var spokenWords: String {
        let live = speech.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        if !live.isEmpty { return live }
        return store.walkDraft
    }

    /// What this walk is about, in his words: the episode when one is playing,
    /// otherwise the section he started it from.
    private var subjectKicker: String {
        if !store.walkEpisodeID.isEmpty { return "WALKING WITH · " + store.walkEpisodeID }
        let title = SurfaceContext(section: store.walkSurface, captured_at: "").title
        return store.walkSurface.isEmpty ? "WALKING WITH ALICIA"
                                         : "WALKING FROM · " + title.uppercased()
    }

    /// True exactly when `episodeListening` is what is on screen.
    private var listeningPhase: Bool {
        if didSave { return false }
        if let record = store.voiceArchive.recording(store.walkRecordingID), record.finalization != nil { return false }
        return macMode
    }

    private var listeningNote: String {
        if let error = speech.lastError { return error }
        // Private Body guidance takes precedence over generic recorder status, so
        // the private/review promise stays visible after begin and pause too. A
        // real error above still wins; a paused status is folded in below.
        if privateBodyWalk {
            if reviewingWords {
                return "Review and edit these words — correct anything, or type if live text was off. They go only to your private Body lane; the original recording never leaves this phone."
            }
            if visibleRecording, !speech.liveTextAvailable {
                return "Live transcription is unavailable, so nothing appears here — the audio is recording on this phone and stays private."
            }
            let privateLine = "Your original recording stays on this phone. Nothing is sent to your Mac; your reviewed words go only to your private Body lane."
            return status.isEmpty ? privateLine : status + " " + privateLine
        }
        if !status.isEmpty { return status }
        if visibleRecording, !speech.liveTextAvailable {
            return "Live text is off, so nothing appears here — the audio is still recording and your Mac writes the transcript."
        }
        return "Original audio is kept on this phone. Your Mac writes the transcript, and you review it before it is sent."
    }

    @ViewBuilder private var episodeControls: some View {
        VStack(spacing: 10) {
            EpisodeErrorLine()
            HStack(spacing: 12) {
                Button(listening ? "PAUSE" : "KEEP TALKING") {
                    if listening { Task { await finishListening() } } else { Task { await begin() } }
                }
                .font(.system(size: 10, design: .monospaced)).tracking(1.2)
                .foregroundStyle(Theme.inkSoft)
                .frame(maxWidth: .infinity, minHeight: 52)
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.stroke, lineWidth: 0.9))
                .disabled(starting || speech.isFinishing || store.pendingWalkSave != nil)
                Button(store.isSavingWalk ? "SAVING…" : store.pendingWalkSave != nil ? "RETRY SAVE"
                        : privateBodyWalk ? (reviewingWords ? "SEND PRIVATELY" : "FINISH & REVIEW") : "FINISH & REVIEW") {
                    let wasListening = listening
                    Task {
                        if wasListening { await finishListening() }
                        guard store.showWalk else { return }
                        if privateBodyWalk {
                            // Explicit review first, then the private send. Nothing
                            // leaves the phone until he taps SEND PRIVATELY.
                            if reviewingWords { await savePrivateBody() }
                            else { reviewingWords = true }
                        } else {
                            _ = store.finalizeVoice(store.walkRecordingID, speech: speech)
                        }
                    }
                }
                .font(.system(size: 11, design: .monospaced).weight(.semibold)).tracking(1.2)
                .foregroundStyle(Theme.paper)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(Theme.ink, in: RoundedRectangle(cornerRadius: 14))
                .disabled(store.isSavingWalk || speech.isFinishing
                          || (!listening && !store.voiceArchive.hasAudio(store.walkRecordingID))
                          || (privateReviewing && store.walkDraft.trimmingCharacters(in: .whitespacesAndNewlines).count > 4000))
                .accessibilityIdentifier("episode.finishWalk")
            }
            if store.voiceArchive.hasAudio(store.walkRecordingID), !listening {
                Button("REVIEW ORIGINAL AUDIO") { pause(); showRecording = true }
                    .font(.system(size: 9, design: .monospaced)).tracking(1)
                    .foregroundStyle(Theme.inkSoft).frame(minHeight: 32)
            }
        }
        .buttonStyle(.plain)
        .disabled(store.isSavingWalk)
    }

    private var savedView: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("SAVED").font(.system(size: 11, design: .monospaced)).tracking(1.5)
            InkTitle(text: savedAudioOnly ? "Your recording is kept" : "Your reflection is saved", size: 30)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(savedAudioOnly ? "Your recording is kept" : "Your reflection is saved")
            Text(savedAudioOnly ? "The audio is kept for review. No transcript was sent as your reflection."
                 : savedPrivate ? "Your question was answered privately in your Body lane — it isn't added to a saved conversation. The original recording stays on this phone for your review."
                 : "Your words reached Alicia. The original recording stays available for review.")
                .font(.system(size: 20, design: .serif))
            if let recording = store.voiceArchive.recording(savedRecordingID) {
                Text(recording.syncSummary).font(.callout).foregroundStyle(Theme.inkSoft)
                    .accessibilityIdentifier("walk.audioSaveStatus")
            }
            if !store.voiceArchive.lastError.isEmpty { Text(store.voiceArchive.lastError).font(.caption).foregroundStyle(Theme.inkSoft) }
            Button("REVIEW RECORDING") { showRecording = true }
                .font(.system(size: 11, design: .monospaced)).frame(minHeight: 44)
            Button("DONE") { store.showWalk = false; if savedPrivate { store.selectedSection = .body } else if !savedAudioOnly { store.selectedSection = .mind } }
                .buttonStyle(EpisodeButtonStyle())
        }
    }

    private func save(audioOnly: Bool) async {
        let recordingID = store.walkRecordingID
        let onlyAudio = audioOnly || (store.pendingWalkSave == nil && store.walkDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        if await store.finishEpisodeWalk(closeOnSuccess: false, audioOnly: audioOnly) {
            savedRecordingID = recordingID; savedAudioOnly = onlyAudio; didSave = true
        }
    }

    /// Private Body walk send. Reviewed words go only to the private Body lane;
    /// with no words, the original recording simply stays kept on this phone.
    /// The saved screen only appears when the request actually succeeded.
    private func savePrivateBody() async {
        let words = store.walkDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if words.isEmpty { await save(audioOnly: true); return }
        let recordingID = store.walkRecordingID
        if await store.sendPrivateBodyWalk(recordingID, text: words) {
            savedRecordingID = recordingID; savedAudioOnly = false; savedPrivate = true; didSave = true
        }
    }

    private func finishListening() async {
        let generation = startGeneration
        let previousWords = base
        await speech.finishAndStop()
        guard generation == startGeneration, store.showWalk else { return }
        // Use the final recognition snapshot, including the last submitted buffers.
        if !speech.transcript.isEmpty { store.walkDraft = previousWords + (previousWords.isEmpty ? "" : "\n\n") + speech.transcript }
        listening = false
        pause()
    }

    private func keepScreenAwake() {
        guard scenePhase == .active, store.showWalk else { return }
        if previousIdleTimerDisabled == nil {
            previousIdleTimerDisabled = UIApplication.shared.isIdleTimerDisabled
        }
        UIApplication.shared.isIdleTimerDisabled = true
    }

    private func restoreScreenSleep() {
        guard let previous = previousIdleTimerDisabled else { return }
        UIApplication.shared.isIdleTimerDisabled = previous
        previousIdleTimerDisabled = nil
    }

    private func begin() async {
        guard !listening, !starting, scenePhase == .active, store.showWalk, store.voiceArchive.recording(store.walkRecordingID)?.finalization == nil else { return }
        startGeneration += 1
        reviewingWords = false
        let generation = startGeneration
        starting = true
        defer { if generation == startGeneration { starting = false } }
        guard await store.beginWalkRecording() else { return }
        guard canStart(generation) else { store.pauseEpisodeWalk(); return }
        // Speech authorization first so the words can be read while he talks;
        // microphone alone still records, and `listeningNote` says as much.
        var allowed = await speech.requestAuthorization()
        if !allowed { allowed = await speech.requestMicrophoneAuthorization() }
        guard canStart(generation) else { store.pauseEpisodeWalk(); return }
        guard allowed else {
            status = "Microphone permission is off. You can write here, or enable it in Settings."
            return
        }
        base = store.walkDraft
        do {
            // A resume keeps the paused recording — a private Body original or a
            // Mac walk must never be forked or discarded by tapping Keep talking.
            if store.voiceArchive.shouldStartFreshRecording(store.walkRecordingID) {
                store.walkRecordingID = UUID().uuidString
            }
            try store.startVoiceCapture(speech, id: store.walkRecordingID, walk: true, liveText: true)
            listening = true
            automaticRestarts = 0
            status = "Recording the original audio. Take your time."
        } catch {
            status = "The microphone couldn't start. Your words are kept; you can write or try again."
        }
    }

    private func canStart(_ generation: Int) -> Bool {
        generation == startGeneration && !Task.isCancelled && scenePhase == .active && store.showWalk
    }

    private func pause() {
        startGeneration += 1
        starting = false
        if listening, !speech.transcript.isEmpty {
            store.walkDraft = base + (base.isEmpty ? "" : "\n\n") + speech.transcript
        }
        listening = false
        speech.stop()
        base = store.walkDraft
    }
}
