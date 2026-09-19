import SwiftUI

/// The microphone, at the size of the thing it is doing.
///
/// Hector's build-18 note: *"when I open the mic, I want it to be more
/// prominent … the whole microphone should take the entire screen. I can see
/// that word's big, so I can see as I'm talking if it's actually taking it
/// well. It should be in the background using the same animation that Alicia
/// has in the home screen … these moving particles."*
///
/// So: her particle body fills the page, full bleed, in the voice of the
/// section he opened this from; his own words are set large over it as they
/// arrive; and the only two things he can do are stop and keep going. The
/// point of the big type is verification — he is reading back what the
/// microphone actually heard while he is still speaking, not discovering
/// afterwards that it took nothing.
///
/// This is the surface for a remark about the section he is on. An episode
/// reflection keeps its own lifecycle in `WalkReflectionView`, which presents
/// the same room through `ListeningStage` and then makes him review the Mac's
/// transcript before anything is sent.
struct ListeningRoom: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var speech = SpeechTranscriber()
    @State private var starting = false
    @State private var generation = 0
    @State private var capture: SurfaceContext?
    @State private var recordingID = ""
    @State private var status = ""
    @State private var review: String?

    private var section: SurfaceContext { capture ?? store.surfaceContext() }
    private var privateBody: Bool { section.section == "body" }
    private var recording: Bool { speech.isRecording || speech.isFinishing }

    var body: some View {
        ListeningStage(
            voice: .forSurface(section.section),
            isRecording: speech.isRecording && !speech.isFinishing,
            isStarting: starting,
            level: speech.inputLevel,
            kicker: "TALKING TO ALICIA · " + section.title.uppercased(),
            seconds: speech.recordedSeconds,
            words: speech.transcript,
            placeholder: placeholder,
            note: note,
            close: { end(save: true) },
            controls: { controls }
        )
        .task { await begin() }
        .onChange(of: scenePhase) { _, phase in
            // Backgrounding keeps the audio that exists and stops asking for
            // more; it never discards what he already said.
            if phase != .active, speech.isRecording { Task { await pause() } }
        }
        .sheet(item: Binding(get: { review.map(ReviewTarget.init(id:)) },
                             set: { review = $0?.id })) { target in
            VoiceRecordingsView(recordingID: target.id)
        }
    }

    private struct ReviewTarget: Identifiable { let id: String }

    private var placeholder: String {
        if starting { return "Opening the microphone…" }
        if speech.isFinishing { return "Keeping your last words…" }
        if recording { return "Listening. Say it however it comes." }
        return "The microphone is paused."
    }

    private var note: String {
        if let error = speech.lastError { return error }
        if !status.isEmpty { return status }
        if recording, !speech.liveTextAvailable {
            return "Live text is off, so nothing appears here — but the audio is recording, and your Mac writes the transcript."
        }
        if privateBody { return "Private. The audio and the words stay on this phone." }
        return "Your original recording is kept. Your Mac writes the transcript, so these words are a preview."
    }

    @ViewBuilder private var controls: some View {
        HStack(spacing: 14) {
            Button { Task { await discardAndClose() } } label: {
                Text("CANCEL")
                    .font(.system(size: 10, design: .monospaced)).tracking(1.2)
                    .foregroundStyle(Theme.inkSoft)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.stroke, lineWidth: 0.9))
            }
            .accessibilityIdentifier("listening.cancel")
            Button { Task { await finish() } } label: {
                Text(speech.isFinishing ? "KEEPING…" : recording ? "FINISH" : "KEEP TALKING")
                    .font(.system(size: 11, design: .monospaced).weight(.semibold)).tracking(1.2)
                    .foregroundStyle(Theme.paper)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(Theme.ink, in: RoundedRectangle(cornerRadius: 14))
            }
            .disabled(speech.isFinishing || starting)
            .accessibilityIdentifier("listening.finish")
        }
        .buttonStyle(.plain)
    }

    private func begin() async {
        guard !recording, !starting else { return }
        let context = store.surfaceContext()
        store.prepareForRecording()
        let stamp = generation + 1; generation = stamp; starting = true
        defer { if generation == stamp { starting = false } }
        // Full authorization, not microphone-only: this screen exists so he
        // can read the words as they land, and that needs the on-device
        // recognizer. If he declines speech recognition the audio is still
        // recorded and the Mac still transcribes it — `note` says so plainly
        // rather than leaving a big empty page that looks like a dead mic.
        var granted = await speech.requestAuthorization()
        if !granted { granted = await speech.requestMicrophoneAuthorization() }
        guard granted else {
            status = "Microphone permission is off. Nothing was recorded."
            return
        }
        guard generation == stamp, scenePhase == .active else { return }
        let id = UUID().uuidString
        do {
            try store.startVoiceCapture(speech, id: id, walk: false, surface: context, liveText: true)
            recordingID = id
            capture = context
            status = ""
            UserDefaults.standard.set(id, forKey: "alicia.surfaceRecording." + context.section)
        } catch {
            capture = nil
            status = "The microphone could not start."
        }
    }

    private func pause() async {
        guard speech.isRecording else { return }
        speech.stop()
        complete(showTranscript: false)
    }

    private func finish() async {
        if recording {
            await speech.finishAndStop()
            complete(showTranscript: true)
        } else {
            await begin()
        }
    }

    /// Leaving keeps what exists. This is the same promise the walk makes:
    /// nothing he said is thrown away because he closed a screen.
    private func end(save: Bool) {
        if speech.isRecording { speech.stop(); complete(showTranscript: false) }
        dismiss()
    }

    private func discardAndClose() async {
        if speech.isRecording { speech.stop() }
        let id = recordingID
        recordingID = ""; capture = nil
        if !id.isEmpty { await store.deleteOriginalVoice(id) }
        dismiss()
    }

    private func complete(showTranscript: Bool) {
        guard let original = capture, !recordingID.isEmpty else { return }
        let id = recordingID
        if original.section == "body" {
            // Body never leaves the phone on its own: the words become a draft
            // he can read and edit, and only Send moves them.
            let words = speech.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            if !words.isEmpty {
                let existing = store.composerDrafts.text(for: "body")
                store.composerDrafts.set(existing.isEmpty ? words : existing + "\n\n" + words, for: "body")
                UserDefaults.standard.set(id, forKey: "alicia.bodyDraftRecordingID")
            }
            status = "Kept on this phone. Read it before you send it."
            if showTranscript { dismiss(); store.openConversation() }
        } else if store.finalizeVoice(id, speech: speech) {
            status = "Original saved · your Mac is writing the transcript."
            if showTranscript { review = id }
        } else {
            status = "Original saved on this phone. Finish it from Recordings to transcribe."
        }
        capture = nil
        recordingID = ""
    }
}

/// The room itself: her body behind, his words in front, the controls at the
/// bottom. Split out so `WalkReflectionView` presents an episode reflection in
/// exactly the same space rather than a second, smaller idea of listening.
struct ListeningStage<Controls: View>: View {
    var voice: AliciaPresence.Voice
    var isRecording: Bool
    var isStarting: Bool
    var level: Double
    var kicker: String
    var seconds: Double
    var words: String
    var placeholder: String
    var note: String
    var close: () -> Void
    @ViewBuilder var controls: () -> Controls

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Loud speech gathers her; silence lets her rest. Clamped because a NaN
    /// from the audio tap must never reach the drawing.
    private var attention: Double {
        guard isRecording else { return 0.42 }
        let clean = level.isFinite ? min(1, max(0, level)) : 0
        return 0.58 + 0.34 * clean
    }

    private var elapsed: String {
        let whole = Int(max(0, seconds))
        return String(format: "%d:%02d", whole / 60, whole % 60)
    }

    var body: some View {
        ZStack {
            Theme.backdrop.ignoresSafeArea()
            AliciaPresence(voice: voice,
                           state: isRecording ? .listening : isStarting ? .thinking : .resting,
                           attention: attention,
                           isActive: isRecording && scenePhase == .active)
                .opacity(0.5)
                .ignoresSafeArea()
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                head
                transcript
                Text(note)
                    .font(.caption).foregroundStyle(Theme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 24).padding(.bottom, 12)
                controls()
                    .padding(.horizontal, 24)
                    .padding(.bottom, 28)
            }
        }
        .foregroundStyle(Theme.ink)
        .fontDesign(.serif)
    }

    private var head: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text(kicker)
                    .font(.system(size: 9, design: .monospaced)).tracking(1.2)
                    .foregroundStyle(Theme.inkSoft)
                    .lineLimit(1)
                HStack(spacing: 10) {
                    // A drawn mark, not a level meter: it says "on" at a glance
                    // from across the room, which six tiny bars never did.
                    Circle()
                        .fill(isRecording ? Theme.rose : Theme.inkSoft.opacity(0.35))
                        .frame(width: 9, height: 9)
                        .opacity(isRecording && !reduceMotion ? 0.55 + 0.45 * attention : 1)
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: attention)
                    Text(elapsed)
                        .font(.system(size: 15, design: .monospaced)).monospacedDigit()
                        .foregroundStyle(Theme.inkSoft)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(isRecording
                    ? "Microphone on, \(Int(seconds)) seconds recorded"
                    : "Microphone paused, \(Int(seconds)) seconds recorded")
                .accessibilityIdentifier("walk.microphoneState")
            }
            Spacer()
            Button(action: close) {
                Text("CLOSE")
                    .font(.system(size: 10, design: .monospaced)).tracking(1.2)
                    .foregroundStyle(Theme.inkSoft)
                    .frame(minWidth: 56, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("listening.close")
        }
        .padding(.horizontal, 24).padding(.top, 18)
    }

    /// His own words, as large as they can be and still hold a paragraph, and
    /// pinned to the bottom so the newest line is where his eye already is.
    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Spacer(minLength: 0)
                    Text(words.isEmpty ? placeholder : words)
                        .font(.system(size: words.count > 420 ? 24 : words.count > 160 ? 30 : 38,
                                      design: .serif))
                        .foregroundStyle(words.isEmpty ? Theme.inkSoft : Theme.ink)
                        .lineSpacing(4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .animation(.easeOut(duration: 0.18), value: words.count > 160)
                        .id("words")
                        .accessibilityIdentifier("listening.transcript")
                }
                .frame(maxWidth: .infinity, minHeight: 320, alignment: .bottomLeading)
                .padding(.horizontal, 24).padding(.vertical, 18)
            }
            .onChange(of: words) { _, _ in
                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("words", anchor: .bottom) }
            }
        }
    }
}

extension AliciaPresence.Voice {
    /// Which of her six bodies belongs to a surface. The same mapping the tabs
    /// use, so the particles behind a reflection are continuous with the page
    /// he just left rather than a generic animation.
    static func forSurface(_ section: String) -> AliciaPresence.Voice {
        switch section {
        case "mind": .ariadne
        case "body", "dialogue": .psyche
        case "alicia": .beatrice
        case "studio": .muse
        default: .musubi
        }
    }
}
