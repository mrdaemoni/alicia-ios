import SwiftUI

/// One stable input owner above the tab bar. Section changes never reparent the microphone.
struct ConversationComposer: View {
    @Environment(AppStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @State private var speech = SpeechTranscriber()
    @State private var starting = false
    @State private var generation = 0
    @State private var capture: SurfaceContext?
    @State private var activeRecordingID = ""
    @State private var status = ""
    @State private var reviewID: String?
    @State private var showReview = false
    @FocusState private var focused: Bool
    private var section: SurfaceContext { store.surfaceContext() }
    private var draft: Binding<String> {
        Binding(get: { store.composerDrafts.text(for: section.section) },
                set: { value in
                    store.composerDrafts.set(value, for: section.section)
                    if section.section == "body", value.isEmpty { UserDefaults.standard.removeObject(forKey: "alicia.bodyDraftRecordingID") }
                })
    }
    private var privateBody: Bool { section.section == "body" }
    private var busy: Bool { privateBody ? store.privateBodySending : store.isStreaming }
    private var previewListening: Bool {
#if DEBUG
        return ProcessInfo.processInfo.arguments.contains("--composer-listening-preview") && store.isMock
#else
        return false
#endif
    }
    private var recording: Bool { speech.isRecording || speech.isFinishing }
    private var latestReply: Message? {
        (privateBody ? store.privateBodyMessages : store.messages).last(where: { $0.sender == .alicia && !$0.text.isEmpty })
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("ABOUT · " + (capture?.title ?? section.title).uppercased())
                    .font(.system(size: 10, design: .monospaced)).tracking(0.6)
                    .accessibilityIdentifier("composer.context")
                Spacer()
                Button("CONVERSATION") { focused = false; pauseCapture(); store.selectedSection = .dialogue }
                    .font(.system(size: 9, design: .monospaced)).frame(minHeight: 32)
                    .accessibilityIdentifier("dialogue.open")
            }
            if !privateBody, let work = store.collaboration.dialogueContext {
                HStack {
                    Text("Passage · " + work.sectionTitle).font(.caption).lineLimit(1)
                    Spacer()
                    Button("Clear") { store.collaboration.dialogueContext = nil }.font(.caption)
                }.accessibilityIdentifier("workReview.dialogueContext")
            }
            if !privateBody, store.answeringAskID != nil {
                HStack {
                    Text("Replying to · " + store.answeringAskExcerpt).font(.caption).lineLimit(1)
                    Spacer(); Button("Cancel") { store.cancelAnswering() }.font(.caption)
                }
            }
            if recording || starting || previewListening {
                ListeningPresence(isRecording: (speech.isRecording && !speech.isFinishing) || previewListening, isStarting: starting,
                    seconds: speech.recordedSeconds, level: speech.inputLevel,
                    microphoneName: speech.microphoneName, liveTextAvailable: speech.liveTextAvailable,
                    transcribesOnMac: capture?.section != "body", voice: listeningVoice)
                    .frame(maxWidth: .infinity).padding(.vertical, 5)
            } else if let latestReply, store.selectedSection != .dialogue, !focused {
                Button { store.selectedSection = .dialogue } label: {
                    Text(latestReply.text).font(.system(size: 14, design: .serif)).lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }.accessibilityIdentifier("composer.lastReply")
            }
            HStack(spacing: 8) {
                TextField("Talk or type to Alicia…", text: draft, axis: .vertical)
                    .lineLimit(1...4).font(.system(size: 16, design: .serif))
                    .focused($focused).disabled(recording || starting)
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .background(Theme.ink.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityIdentifier("dialogue.composer")
                Button { toggleRecording() } label: {
                    Text(recording ? "FINISH" : starting ? "CANCEL" : "TALK")
                        .font(.system(size: 10, design: .monospaced).weight(.semibold))
                        .frame(minWidth: 46, minHeight: 44)
                }.disabled(speech.isFinishing || (!privateBody && store.collaboration.dialogueContext != nil))
                    .accessibilityLabel(recording ? "Finish recording" : "Talk to Alicia")
                    .accessibilityIdentifier("composer.microphone")
                Button { send() } label: {
                    InkSubmitArrow(size: 27, color: Theme.ink, seed: 23).frame(width: 44, height: 44)
                }.disabled(busy || recording || starting || draft.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.episodeChoiceSyncing)
                    .accessibilityLabel("Send message").accessibilityIdentifier("composer.send")
            }
            if busy { Text(privateBody ? "Thinking privately on your Mac…" : "Alicia is thinking…").font(.caption) }
            if let error = store.composerDrafts.error ?? speech.lastError {
                Text(error).font(.caption).fixedSize(horizontal: false, vertical: true)
            } else if !status.isEmpty { Text(status).font(.caption).fixedSize(horizontal: false, vertical: true) }
            if let record = selectedRecording, !recording, !starting {
                Button(record.isPrivateBody ? "REVIEW PRIVATE ORIGINAL" : record.finalization == nil ? "FINISH & TRANSCRIBE SAVED AUDIO" : "REVIEW RECORDING & MAC TRANSCRIPT") {
                    focused = false; reviewID = record.id
                    if !record.isPrivateBody { _ = store.finalizeVoice(record.id) }
                    showReview = true
                }.font(.system(size: 9, design: .monospaced)).frame(minHeight: 30)
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 8)
        .foregroundStyle(Theme.ink).background(Theme.paper)
        .overlay(alignment: .top) { Rectangle().fill(Theme.stroke).frame(height: 0.7) }
        .buttonStyle(.plain)
        .onChange(of: focused) { _, value in store.composerFocused = value }
        .onChange(of: store.selectedSection) { _, value in
            focused = false; pauseCapture(); status = ""
            if value != .dialogue { store.cancelAnswering(); store.collaboration.dialogueContext = nil }
        }
        .onChange(of: scenePhase) { _, phase in if phase != .active { pauseCapture() } }
        .onChange(of: store.showWalk) { _, shown in if shown { pauseCapture(); focused = false } }
        .onDisappear { pauseCapture(); store.composerFocused = false }
        .sheet(isPresented: $showReview) { VoiceRecordingsView(recordingID: reviewID) }
    }
    private var selectedRecording: VoiceRecording? {
        store.voiceArchive.recording(UserDefaults.standard.string(forKey: "alicia.surfaceRecording." + section.section) ?? "")
    }
    private var listeningVoice: AliciaPresence.Voice {
        switch capture?.section ?? section.section {
        case "mind": .ariadne
        case "body", "dialogue": .psyche
        case "alicia": .beatrice
        case "studio": .muse
        default: .musubi
        }
    }
    private func send() {
        let text = draft.wrappedValue
        let context = section
        guard !busy, !recording, !starting, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if privateBody { store.sendPrivateBody(text, recordingID: UserDefaults.standard.string(forKey: "alicia.bodyDraftRecordingID") ?? "") }
        else { store.send(text, surfaceContext: context) }
        draft.wrappedValue = ""; focused = false; status = ""
    }
    private func toggleRecording() {
        if starting { generation += 1; starting = false; capture = nil; return }
        if speech.isRecording {
            Task { await finishCapture(showTranscript: true) }
            return
        }
        focused = false; store.prepareForRecording()
        let context = section; let stamp = generation + 1; generation = stamp; starting = true
        Task {
            defer { if generation == stamp { starting = false } }
            let granted = context.section == "body" ? await speech.requestAuthorization() : await speech.requestMicrophoneAuthorization()
            guard granted else { status = "Microphone permission is off. Your typed draft is kept."; return }
            guard generation == stamp, scenePhase == .active, section.section == context.section, !store.showWalk else { return }
            let id = UUID().uuidString
            do {
                try store.startVoiceCapture(speech, id: id, walk: false, surface: context)
                activeRecordingID = id; capture = context; status = ""
                UserDefaults.standard.set(id, forKey: "alicia.surfaceRecording." + context.section)
            } catch { capture = nil; status = "The microphone could not start. Your draft is kept." }
        }
    }
    private func pauseCapture() {
        generation += 1; starting = false
        guard speech.isRecording else { return }
        speech.stop()
        completeCapture(showTranscript: false)
    }
    private func finishCapture(showTranscript: Bool) async {
        await speech.finishAndStop()
        completeCapture(showTranscript: showTranscript)
    }
    private func completeCapture(showTranscript: Bool) {
        guard let original = capture, !activeRecordingID.isEmpty else { return }
        let id = activeRecordingID
        if original.section == "body" {
            let words = speech.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            if !words.isEmpty {
                let existing = store.composerDrafts.text(for: "body")
                store.composerDrafts.set(existing.isEmpty ? words : existing + "\n\n" + words, for: "body")
                UserDefaults.standard.set(id, forKey: "alicia.bodyDraftRecordingID")
            }
            status = "Private original saved on this phone. Review the detected words before Send."
        } else {
            if store.finalizeVoice(id, speech: speech) {
                status = "Original saved · your Mac is preparing the transcript."
                if showTranscript { reviewID = id; showReview = true }
            } else { status = "Original saved on this phone. Finish the saved recording to transcribe." }
        }
        capture = nil; activeRecordingID = ""
    }
}
