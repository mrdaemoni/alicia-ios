import SwiftUI

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

    var body: some View {
        @Bindable var store = store
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text(store.walkEpisodeID).font(.system(size: 11, design: .monospaced)).tracking(1.5)
                Spacer()
                Button("CLOSE") { pause(); store.pauseEpisodeWalk(); store.showWalk = false }
                    .font(.system(size: 10, design: .monospaced)).tracking(1.2)
            }
            InkTitle(text: listening ? "I'm listening" : "Stay with the thought", size: 34)
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
            Text(status.isEmpty ? "Your words stay on this phone until you finish." : status)
                .font(.caption).foregroundStyle(Theme.inkSoft)
            EpisodeErrorLine()
            Button(listening ? "PAUSE LISTENING" : "KEEP TALKING") {
                if listening { pause() } else { Task { await begin() } }
            }
            .font(.system(size: 11, design: .monospaced)).tracking(1.3)
            .frame(maxWidth: .infinity, minHeight: 44)
            .disabled(starting || store.pendingWalkSave != nil)
            Button(store.isSavingWalk ? "SAVING YOUR REFLECTION…" : store.pendingWalkSave != nil ? "RETRY SAVE" : "FINISH & REFLECT") {
                pause()
                Task { _ = await store.finishEpisodeWalk() }
            }
            .buttonStyle(EpisodeButtonStyle())
            .disabled(store.isSavingWalk || store.walkDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityIdentifier("episode.finishWalk")
        }
        .disabled(store.isSavingWalk)
        .padding(24)
        .background(Theme.paper)
        .task {
#if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--episode-day-preview") {
                status = "Preview — recording is paused. No audio or words are sent."
                return
            }
#endif
            await begin()
        }
        .onDisappear { pause() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                pause()
                status = "Listening paused. Your words are kept here; tap Keep talking to continue."
            }
        }
        .onChange(of: speech.transcript) { _, text in
            if listening { store.walkDraft = base + (base.isEmpty || text.isEmpty ? "" : "\n\n") + text }
        }
        .onChange(of: speech.isRecording) { was, now in
            guard was, !now, listening, !restarting else { return }
            if !speech.transcript.isEmpty {
                store.walkDraft = base + (base.isEmpty ? "" : "\n\n") + speech.transcript
            }
            base = store.walkDraft
            speech.transcript = ""
            restarting = true
            if speech.lastError != nil { automaticRestarts += 1 } else { automaticRestarts = 0 }
            let generation = startGeneration
            Task {
                try? await Task.sleep(for: .milliseconds(400))
                if listening && automaticRestarts <= 3 && generation == startGeneration && scenePhase == .active && store.showWalk {
                    do { try speech.start() }
                    catch { listening = false; status = "Listening paused. Your words are kept. Tap Keep talking." }
                } else {
                    listening = false
                    status = "Listening paused. Your words are kept. Tap Keep talking."
                }
                restarting = false
            }
        }
    }

    private func begin() async {
        guard !listening, !starting, scenePhase == .active, store.showWalk else { return }
        startGeneration += 1
        let generation = startGeneration
        starting = true
        defer { if generation == startGeneration { starting = false } }
        guard await store.beginWalkRecording() else { return }
        guard canStart(generation) else { store.pauseEpisodeWalk(); return }
        let allowed = await speech.requestAuthorization()
        guard canStart(generation) else { store.pauseEpisodeWalk(); return }
        guard allowed else {
            status = "Microphone or speech permission is off. You can write here, or enable it in Settings."
            return
        }
        base = store.walkDraft
        do {
            try speech.start()
            listening = true
            automaticRestarts = 0
            status = "Listening. Take your time."
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
