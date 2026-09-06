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

    private var visibleRecording: Bool {
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--episode-day-preview") && ProcessInfo.processInfo.arguments.contains("--episode-microphone-on") { return true }
#endif
        return speech.isRecording
    }

    var body: some View {
        @Bindable var store = store
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text(store.walkEpisodeID).font(.system(size: 11, design: .monospaced)).tracking(1.5)
                Spacer()
                Button("CLOSE") { pause(); store.pauseEpisodeWalk(); store.showWalk = false }
                    .font(.system(size: 10, design: .monospaced)).tracking(1.2)
            }
            ListeningPresence(isRecording: visibleRecording, isStarting: starting || restarting)
            InkTitle(text: visibleRecording ? "I'm listening" : "Stay with the thought", size: 30)
            if !store.walkPrompt.isEmpty {
                Text(store.walkPrompt.strippedEmojis).font(.system(size: 21, design: .serif))
            }
            Text("Say what stayed with you, what you question, or where it meets your day.")
                .font(.subheadline).italic().foregroundStyle(Theme.inkSoft)
            TextEditor(text: $store.walkDraft)
                .font(.system(size: 20, design: .serif))
                .disabled(listening || store.pendingWalkSave != nil)
                .scrollContentBackground(.hidden)
                .accessibilityLabel("Your walk reflection")
            Text(reviewingWords ? "Check these words against your recording. Corrections stay separate from the original transcript." : speech.lastError ?? (status.isEmpty ? "Original audio is kept on this phone and synced to your Mac." : status))
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
                if listening { pause() } else { Task { await begin() } }
            }
            .font(.system(size: 11, design: .monospaced)).tracking(1.3)
            .frame(maxWidth: .infinity, minHeight: 44)
            .disabled(starting || store.pendingWalkSave != nil)
            Button(store.isSavingWalk ? "SAVING YOUR REFLECTION…" : store.pendingWalkSave != nil ? "RETRY SAVE" : reviewingWords ? "SAVE & REFLECT" : "FINISH & REFLECT") {
                let wasListening = listening
                pause()
                if wasListening && store.pendingWalkSave == nil { reviewingWords = true }
                else { Task { _ = await store.finishEpisodeWalk() } }
            }
            .buttonStyle(EpisodeButtonStyle())
            .disabled(store.isSavingWalk || (!listening && !store.voiceArchive.hasAudio(store.walkRecordingID)
                && store.walkDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
            .accessibilityIdentifier("episode.finishWalk")
        }
        .disabled(store.isSavingWalk)
        .padding(24)
        .background(Theme.paper)
        .sheet(isPresented: $showRecording) { VoiceRecordingsView(recordingID: store.walkRecordingID) }
        .task {
#if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--voice-evidence-preview") || ProcessInfo.processInfo.arguments.contains("--episode-day-preview") || ProcessInfo.processInfo.arguments.contains("--episode-continuity-preview") {
                status = visibleRecording ? "Preview of microphone-on UI. No audio is recorded or sent." : "Preview — recording is paused. No audio or words are sent."
                return
            }
#endif
            await begin()
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
        guard !listening, !starting, scenePhase == .active, store.showWalk else { return }
        startGeneration += 1
        reviewingWords = false
        let generation = startGeneration
        starting = true
        defer { if generation == startGeneration { starting = false } }
        guard await store.beginWalkRecording() else { return }
        guard canStart(generation) else { store.pauseEpisodeWalk(); return }
        let allowed = await speech.requestAuthorization()
        guard canStart(generation) else { store.pauseEpisodeWalk(); return }
        guard allowed else {
            status = "Microphone permission is off. You can write here, or enable it in Settings."
            return
        }
        base = store.walkDraft
        do {
            if store.walkRecordingID.isEmpty { store.walkRecordingID = UUID().uuidString }
            try store.startVoiceCapture(speech, id: store.walkRecordingID, walk: true)
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
