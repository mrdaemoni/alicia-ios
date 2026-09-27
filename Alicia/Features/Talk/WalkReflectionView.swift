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
                    InkKicker(text: record.context.episode_id)
                    Spacer()
                    InkCloseButton { pause(); store.showWalk = false }
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if !store.walkDraft.isEmpty {
                            InkDisclosure("Earlier typed words · kept separately") {
                                Text(store.walkDraft).textSelection(.enabled)
                            }
                        }
                        // The stage card and SEND, the one primary here.
                        VoiceProcessingView(id: record.id).id(record.id)
                    }
                }
                Button { showRecording = true } label: { InkLinkLabel(title: "Original recording", small: true) }
                    .buttonStyle(.inkLink)
                HStack(spacing: 16) {
                    Button("Record another thought") {
                        store.walkRecordingID = UUID().uuidString
                        Task { await begin() }
                    }.buttonStyle(.inkQuiet)
                    Spacer(minLength: 0)
                    if record.submissionStatus?.state == "completed" {
                        Button("DONE") { store.showWalk = false; store.selectedSection = .mind }
                            .buttonStyle(.inkSecondaryCompact)
                    }
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
                InkKicker(text: subjectKicker)
                Spacer()
                InkCloseButton { pause(); store.pauseEpisodeWalk(); store.showWalk = false }
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
                    InkDisclosure("Earlier typed words · kept separately") {
                        Text(store.walkDraft).textSelection(.enabled)
                    }
                }
                Spacer(minLength: 16)
            } else {
            TextEditor(text: $store.walkDraft)
                .font(.system(size: 20, design: .serif))
                .disabled(listening || store.pendingWalkSave != nil)
                .scrollContentBackground(.hidden)
                .inkField()
                .accessibilityLabel("Your walk reflection")
            }
            Text(reviewingWords ? (speech.transcriptNeedsReview ? "Live text was interrupted. These words may be incomplete. Review the audio, edit the words, or save just the recording." : "Check these words before sending. Your original recording is kept separately.") : speech.lastError ?? (status.isEmpty ? "Original audio is kept on this phone and synced to your Mac." : status))
                .font(.caption)
                .foregroundStyle(!reviewingWords && speech.lastError != nil ? Theme.rose : Theme.inkSoft)
            Text("Audio stays until you delete it.").font(.caption).foregroundStyle(Theme.inkSoft)
            if store.voiceArchive.hasAudio(store.walkRecordingID) {
                Button { pause(); showRecording = true } label: { InkLinkLabel(title: "Original recording", small: true) }
                    .buttonStyle(.inkLink)
            }
            EpisodeErrorLine()
            Button(listening ? "PAUSE LISTENING" : "KEEP TALKING") {
                if listening { Task { await finishListening() } } else { Task { await begin() } }
            }
            .buttonStyle(.inkSecondary)
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
            .buttonStyle(.inkPrimary)
            .disabled(store.isSavingWalk || speech.isFinishing || (!listening && !store.voiceArchive.hasAudio(store.walkRecordingID)
                && store.walkDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
            .accessibilityIdentifier("episode.finishWalk")
            if !listening, store.pendingWalkSave == nil, store.voiceArchive.hasAudio(store.walkRecordingID), store.voiceArchive.recording(store.walkRecordingID)?.macProcessing != true {
                Button("Save audio only") { Task { await save(audioOnly: true) } }
                    .buttonStyle(.inkQuiet)
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
            if store.voiceArchive.recording(store.walkRecordingID)?.finalization == nil { await begin() }
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
        store.voiceArchive.recording(store.walkRecordingID)?.macProcessing == true
            || store.voiceArchive.recording(store.walkRecordingID) == nil
    }

    private var episodeListening: some View {
        ListeningStage(
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
            noteIsError: speech.lastError != nil,
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
                .buttonStyle(.inkSecondary)
                .disabled(starting || speech.isFinishing || store.pendingWalkSave != nil)
                Button(store.isSavingWalk ? "SAVING…" : store.pendingWalkSave != nil ? "RETRY SAVE" : "FINISH & REVIEW") {
                    let wasListening = listening
                    Task {
                        if wasListening { await finishListening() }
                        guard store.showWalk else { return }
                        _ = store.finalizeVoice(store.walkRecordingID, speech: speech)
                    }
                }
                .buttonStyle(.inkPrimary)
                .disabled(store.isSavingWalk || speech.isFinishing
                          || (!listening && !store.voiceArchive.hasAudio(store.walkRecordingID)))
                .accessibilityIdentifier("episode.finishWalk")
            }
            if store.voiceArchive.hasAudio(store.walkRecordingID), !listening {
                Button { pause(); showRecording = true } label: { InkLinkLabel(title: "Original recording", small: true) }
                    .buttonStyle(.inkLink)
            }
        }
        .disabled(store.isSavingWalk)
    }

    private var savedView: some View {
        VStack(alignment: .leading, spacing: 24) {
            InkKicker(text: "Saved")
            InkTitle(text: savedAudioOnly ? "Your recording is kept" : "Your reflection is saved", size: 30)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(savedAudioOnly ? "Your recording is kept" : "Your reflection is saved")
            Text(savedAudioOnly ? "The audio is kept for review. No transcript was sent as your reflection." : "Your words reached Alicia. The original recording stays available for review.")
                .font(.system(size: 20, design: .serif))
            if let recording = store.voiceArchive.recording(savedRecordingID) {
                Text(recording.syncSummary).font(.callout).foregroundStyle(Theme.inkSoft)
                    .accessibilityIdentifier("walk.audioSaveStatus")
            }
            InkNotice(text: store.voiceArchive.lastError, kind: .error)
            Button { showRecording = true } label: { InkLinkLabel(title: "Original recording", small: true) }
                .buttonStyle(.inkLink)
            Button("DONE") { store.showWalk = false; if !savedAudioOnly { store.selectedSection = .mind } }
                .buttonStyle(.inkPrimary)
        }
    }

    private func save(audioOnly: Bool) async {
        let recordingID = store.walkRecordingID
        let onlyAudio = audioOnly || (store.pendingWalkSave == nil && store.walkDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        if await store.finishEpisodeWalk(closeOnSuccess: false, audioOnly: audioOnly) {
            savedRecordingID = recordingID; savedAudioOnly = onlyAudio; didSave = true
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
            if store.walkRecordingID.isEmpty || store.voiceArchive.recording(store.walkRecordingID)?.deleted == true
                || (store.voiceArchive.recording(store.walkRecordingID) != nil && store.voiceArchive.recording(store.walkRecordingID)?.macProcessing != true) {
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
        sealIfWorthSending()
    }

    /// Leaving a walk finishes it.
    ///
    /// Until now, closing without pressing FINISH left the recording
    /// unfinalized — so the Mac never transcribed it, and the auto-send it
    /// feeds never saw it. A walk he simply walked away from was a walk that
    /// silently never happened. Hector's instruction was "just send it", and
    /// that has to include the case where he does not press anything.
    ///
    /// Only for real audio: twenty seconds is well under his shortest real
    /// walk and well over a misfire, and sealing a one-second press would
    /// queue the Mac to transcribe silence.
    private func sealIfWorthSending() {
        let id = store.walkRecordingID
        guard !id.isEmpty,
              let record = store.voiceArchive.recording(id),
              !record.deleted,
              record.finalization == nil,
              record.duration >= 20 else { return }
        _ = store.finalizeVoice(id, speech: speech)
    }
}
