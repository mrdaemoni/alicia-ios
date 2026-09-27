import SwiftUI

/// Shared review surface. The view never sends on arrival or adopts late text over an edit.
struct VoiceProcessingView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    let id: String
    /// "Check your Mac": where this view sits inside the recording page, the
    /// page passes its own check (archive + this recording's detail) so there
    /// is one check on the screen. Alone (the walk), it refreshes the archive.
    var check: (() async -> Void)? = nil
    @State private var draft = ""
    @State private var loaded = false
    @State private var locallyEdited = false
    @FocusState private var editing: Bool
    private var record: VoiceRecording? { store.voiceArchive.recording(id) }

    var body: some View {
        // v40: ink on paper, never a tinted system link. The actions carry
        // their own Ink styles (CL-20260926-ia-pass).
        content.foregroundStyle(Theme.ink).tint(Theme.ink)
    }

    @ViewBuilder private var content: some View {
        if let record, record.macProcessing == true {
            VStack(alignment: .leading, spacing: 20) {
                if record.deleted {
                    stageCard {
                        InkKicker(text: "Your voice → Mac → your review")
                        Text("Audio deleted. No new transcription will be requested.").font(InkType.body)
                        if let text = record.review?.text, !text.isEmpty {
                            InkKicker(text: "Retained review draft")
                            Text(text).font(InkType.body).textSelection(.enabled)
                        }
                        if check != nil { checkButton }
                        InkNotice(text: store.voiceArchive.lastError, kind: .error)
                    }
                } else if record.finalization == nil {
                    stageCard {
                        InkKicker(text: "Your voice → Mac → your review")
                        Text("This recording is paused. Finish it when you are ready for a Mac transcript.").font(InkType.body)
                        Button("FINISH & TRANSCRIBE ON MAC") { _ = store.finalizeVoice(id) }
                            .buttonStyle(.inkPrimary).accessibilityIdentifier("voice.finalize")
                        if check != nil { checkButton }
                        InkNotice(text: store.voiceArchive.lastError, kind: .error)
                    }
                } else {
                    stageCard {
                        InkKicker(text: "Your voice → Mac → your review")
                        Text(progressText(record)).font(InkType.subhead)
                            .accessibilityIdentifier("voice.stage")
                        Text(record.stage.detail).font(.callout).foregroundStyle(Theme.inkSoft)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(record.syncSummary).font(InkType.meta).foregroundStyle(Theme.inkSoft)
                        if record.transcription?.ready != true {
                            Text("Uploads resume while this app is open. Once all audio reaches your Mac, it can transcribe while the phone is away.")
                                .font(InkType.meta).foregroundStyle(Theme.inkSoft)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if let error = record.processingError ?? record.transcription?.error { InkNotice(text: error, kind: .error) }
                        if let error = record.submissionError { InkNotice(text: error, kind: .error) }
                        InkNotice(text: store.voiceArchive.lastError, kind: .error)
                        // Recovery belongs to the state it recovers: retry is
                        // the stronger action, checking is quiet.
                        if record.canReopenSubmission {
                            Button(record.submissionStatus?.state == "failed" ? "Edit & try again" : "Edit after rejection") {
                                store.voiceArchive.editRejectedSubmission(id)
                            }.buttonStyle(.inkSecondaryCompact)
                        }
                        if record.transcription?.canRetryExplicitly == true {
                            Button(record.pendingTranscriptionRetry == nil ? "Try again on your Mac" : "Try again · waiting to sync") {
                                store.retryVoiceTranscription(id)
                            }.buttonStyle(.inkSecondaryCompact)
                        }
                        checkButton
                    }
                    if let state = record.transcription, state.ready {
                        InkSection(kicker: "Mac transcription", trailing: {
                            if editing {
                                Button("Done editing") { editing = false }
                                    .buttonStyle(.inkQuiet)
                                    .accessibilityIdentifier("voice.doneEditing")
                            }
                        }) {
                            Text("Check the words against your original recording. Alicia receives them only when you choose Send.")
                                .font(InkType.meta).foregroundStyle(Theme.inkSoft)
                                .fixedSize(horizontal: false, vertical: true)
                            if record.review?.destination == "proactive" {
                                Text("Answering: " + (record.review?.proactiveExcerpt ?? "the original prompt").strippedEmojis)
                                    .font(.subheadline).italic()
                            } else if record.review?.destination == "walk", !record.context.question_presented.isEmpty {
                                Text("Reflection on: " + record.context.question_presented.strippedEmojis).font(.subheadline).italic()
                            }
                            TextEditor(text: Binding(get: { draft }, set: { value in
                                locallyEdited = true; draft = value; store.voiceArchive.editReview(id, text: value)
                            }))
                            .focused($editing)
                            .scrollContentBackground(.hidden)
                            .inkField(minHeight: 180)
                            .disabled(record.submission != nil || record.deleted)
                            .accessibilityLabel("Review Mac transcript").accessibilityIdentifier("voice.macDraft")
                            if draft.unicodeScalars.count > 60000 {
                                InkNotice(text: "Please shorten this to 60,000 characters before sending. Your full draft is kept.", kind: .error)
                            }
                            if loaded, draft != record.review?.text, record.submission == nil {
                                InkNotice(text: "These edits have not been saved locally yet. Send is paused.", kind: .info)
                                Button("Keep these edits on phone") { store.voiceArchive.editReview(id, text: draft) }
                                    .buttonStyle(.inkSecondary)
                            }
                            if record.submission == nil {
                                Button(record.review?.destination == "walk" ? "SEND THESE WORDS & REFLECT" : "SEND THESE WORDS") {
                                    editing = false
                                    Task { await store.sendReviewedVoice(id) }
                                }
                                .buttonStyle(.inkPrimary)
                                .disabled(!loaded || draft != record.review?.text || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || draft.unicodeScalars.count > 60000)
                                .accessibilityIdentifier("voice.sendReviewed")
                            }
                            InkDisclosure("Mac transcript and processing details") {
                                Text(state.draft?.text ?? "").textSelection(.enabled).font(.body)
                                Text([state.model, state.language].compactMap { $0 }.joined(separator: " · ")).font(.caption)
                                if let recorded = state.recorded_seconds, let processed = state.processed_seconds {
                                    Text(String(format: "%.1f of %.1f recorded seconds processed. Recognition can still miss words.", processed, recorded)).font(.caption)
                                }
                                if let provenance = state.draft?.provenance,
                                   let data = try? JSONEncoder().encode(provenance), let text = String(data: data, encoding: .utf8) {
                                    Text(text).font(.caption.monospaced()).textSelection(.enabled)
                                }
                            }
                        }
                    }
                    if let status = record.submissionStatus {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(submissionText(status)).font(.callout).accessibilityIdentifier("voice.sendStatus")
                            if status.state == "completed", let reply = status.text, !reply.isEmpty {
                                Text(reply.strippedEmojis).font(InkType.body).textSelection(.enabled)
                            }
                        }
                    } else if record.submission != nil {
                        Text("Checking the saved send receipt. Your exact words are kept here.").font(.callout)
                    }
                }
            }
            .onAppear { receiveDraft() }
            .onChange(of: record.review?.text) { _, _ in receiveDraft() }
            .task(id: scenePhase) {
                guard scenePhase == .active else { return }
                while !Task.isCancelled {
                    if needsProgress { await store.refreshVoiceArchive() }
                    do { try await Task.sleep(for: .seconds(4)) } catch { return }
                }
            }
        }
    }

    /// The recording's state and the actions that recover it, in one card.
    private func stageCard<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) { content() }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card(padding: 16, radius: 16)
    }

    /// The one check on this screen ("CHECK MAC / SYNC" and the page's "SYNC"
    /// were two looks for the same question).
    private var checkButton: some View {
        let busy = store.voiceArchive.processing || store.voiceArchive.syncing
        return Button(busy ? "Checking…" : "Check your Mac") {
            Task {
                if let check { await check() } else { await store.refreshVoiceArchive() }
            }
        }
        .buttonStyle(.inkQuiet)
        .disabled(busy)
    }

    private var needsProgress: Bool {
        guard let record, !record.deleted, record.finalization != nil, record.processingRejected != true,
              record.submissionRejected != true else { return false }
        if record.pendingTranscriptionRetry != nil { return true }
        if record.submission != nil { return !["completed", "failed", "outcome_unknown"].contains(record.submissionStatus?.state ?? "") }
        return !["ready", "failed", "cancelled"].contains(record.transcription?.state ?? "")
    }

    private func receiveDraft() {
        guard !locallyEdited else { return }
        draft = record?.review?.text ?? ""; loaded = true
    }
    /// One vocabulary, owned by `VoiceRecording.stage`. This used to answer a
    /// question about the Mac's transcription queue ("Queued on your Mac")
    /// instead of the question Hector was asking, which was where his words
    /// were and whether he had already sent them.
    private func progressText(_ record: VoiceRecording) -> String {
        if record.processingRejected == true { return "Your Mac could not accept this recording" }
        return record.stage.label
    }
    private func submissionText(_ status: VoiceSubmissionStatus) -> String {
        switch status.state {
        case "completed": return "Saved with Alicia. Your original recording stays available."
        case "failed": return "This send failed. Your exact words are kept; it has not been sent again."
        case "outcome_unknown": return "The Mac cannot confirm this send's outcome. Your words are kept; it will not be repeated automatically."
        default: return "Alicia is responding. Your send receipt is saved."
        }
    }
}
