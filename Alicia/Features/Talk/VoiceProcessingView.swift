import SwiftUI

/// Shared review surface. The view never sends on arrival or adopts late text over an edit.
struct VoiceProcessingView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    let id: String
    @State private var draft = ""
    @State private var loaded = false
    @State private var locallyEdited = false
    @FocusState private var editing: Bool
    private var record: VoiceRecording? { store.voiceArchive.recording(id) }

    var body: some View {
        if let record, record.macProcessing == true {
            VStack(alignment: .leading, spacing: 16) {
                Text("YOUR VOICE → MAC → YOUR REVIEW").font(.system(size: 10, design: .monospaced)).tracking(0.7)
                if record.deleted {
                    Text("Audio deleted. No new transcription will be requested.").font(.callout)
                    if let text = record.review?.text, !text.isEmpty {
                        Text("Retained review draft").font(.caption)
                        Text(text).font(.body).textSelection(.enabled)
                    }
                } else if record.finalization == nil {
                    Text("This recording is paused. Finish it when you are ready for a Mac transcript.").font(.callout)
                    Button("FINISH & TRANSCRIBE ON MAC") { _ = store.finalizeVoice(id) }
                        .buttonStyle(EpisodeButtonStyle()).accessibilityIdentifier("voice.finalize")
                } else {
                    Text(progressText(record)).font(.system(size: 22, design: .serif))
                    Text(record.syncSummary).font(.caption).foregroundStyle(Theme.inkSoft)
                    if record.transcription?.ready != true {
                        Text("Uploads resume while this app is open. Once all audio reaches your Mac, it can transcribe while the phone is away.")
                            .font(.caption).foregroundStyle(Theme.inkSoft)
                    }
                    if let state = record.transcription, state.ready {
                        HStack {
                            Text("MAC TRANSCRIPTION").font(.system(size: 10, design: .monospaced)).tracking(1)
                            Spacer()
                            if editing {
                                Button("DONE EDITING") { editing = false }
                                    .font(.system(size: 10, design: .monospaced)).frame(minHeight: 44)
                                    .accessibilityIdentifier("voice.doneEditing")
                            }
                        }
                        Text("Check the words against your original recording. Alicia receives them only when you choose Send.")
                            .font(.caption).foregroundStyle(Theme.inkSoft)
                        if record.review?.destination == "proactive" {
                            Text("Answering: " + (record.review?.proactiveExcerpt ?? "the original prompt"))
                                .font(.subheadline).italic()
                        } else if record.review?.destination == "walk", !record.context.question_presented.isEmpty {
                            Text("Reflection on: " + record.context.question_presented).font(.subheadline).italic()
                        }
                        TextEditor(text: Binding(get: { draft }, set: { value in
                            locallyEdited = true; draft = value; store.voiceArchive.editReview(id, text: value)
                        }))
                        .font(.body).frame(minHeight: 180).focused($editing)
                        .scrollContentBackground(.hidden)
                        .overlay(Rectangle().stroke(Theme.inkSoft.opacity(0.25)))
                        .disabled(record.submission != nil || record.deleted)
                        .accessibilityLabel("Review Mac transcript").accessibilityIdentifier("voice.macDraft")
                        if draft.unicodeScalars.count > 60000 {
                            Text("Please shorten this to 60,000 characters before sending. Your full draft is kept.").font(.caption)
                        }
                        if loaded, draft != record.review?.text, record.submission == nil {
                            Button("KEEP THESE EDITS ON PHONE") { store.voiceArchive.editReview(id, text: draft) }
                                .frame(minHeight: 44)
                            Text("These edits have not been saved locally yet. Send is paused.").font(.caption)
                        }
                        if record.submission == nil {
                            Button(record.review?.destination == "walk" ? "SEND THESE WORDS & REFLECT" : "SEND THESE WORDS") {
                                editing = false
                                Task { await store.sendReviewedVoice(id) }
                            }
                            .buttonStyle(EpisodeButtonStyle())
                            .disabled(!loaded || draft != record.review?.text || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || draft.unicodeScalars.count > 60000)
                            .accessibilityIdentifier("voice.sendReviewed")
                        }
                        DisclosureGroup("Mac transcript and processing details") {
                            Text(state.draft?.text ?? "").textSelection(.enabled).font(.body)
                            Text([state.model, state.language].compactMap { $0 }.joined(separator: " · ")).font(.caption)
                            if let recorded = state.recorded_seconds, let processed = state.processed_seconds {
                                Text(String(format: "%.1f of %.1f recorded seconds processed. Recognition can still miss words.", processed, recorded)).font(.caption)
                            }
                            if let provenance = state.draft?.provenance,
                               let data = try? JSONEncoder().encode(provenance), let text = String(data: data, encoding: .utf8) {
                                Text(text).font(.caption.monospaced()).textSelection(.enabled)
                            }
                        }.font(.caption)
                    }
                    if let status = record.submissionStatus {
                        Text(submissionText(status)).font(.callout).accessibilityIdentifier("voice.sendStatus")
                        if status.state == "completed", let reply = status.text, !reply.isEmpty {
                            Text(reply).font(.body).textSelection(.enabled)
                        }
                    } else if record.submission != nil {
                        Text("Checking the saved send receipt. Your exact words are kept here.").font(.callout)
                    }
                    if record.canReopenSubmission {
                        Button(record.submissionStatus?.state == "failed" ? "EDIT & TRY AGAIN" : "EDIT AFTER REJECTION") { store.voiceArchive.editRejectedSubmission(id) }.frame(minHeight: 44)
                    }
                    if record.transcription?.canRetryExplicitly == true {
                        Button(record.pendingTranscriptionRetry == nil ? "RETRY MAC TRANSCRIPTION" : "RETRY WAITING TO SYNC") {
                            store.retryVoiceTranscription(id)
                        }.frame(minHeight: 44)
                    }
                    if let error = record.processingError ?? record.transcription?.error { Text(error).font(.caption) }
                    if let error = record.submissionError { Text(error).font(.caption) }
                    Button(store.voiceArchive.processing || store.voiceArchive.syncing ? "CHECKING…" : "CHECK MAC / SYNC") {
                        Task { await store.refreshVoiceArchive() }
                    }.frame(minHeight: 44).disabled(store.voiceArchive.processing || store.voiceArchive.syncing)
                }
                if !store.voiceArchive.lastError.isEmpty { Text(store.voiceArchive.lastError).font(.caption) }
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
    private func progressText(_ record: VoiceRecording) -> String {
        if record.submissionStatus?.state == "completed" { return "Your words reached Alicia" }
        if record.processingRejected == true { return "Your Mac could not accept this recording" }
        switch record.transcription?.state {
        case "ready": return "Your transcript is ready to review"
        case "transcribing": return "Your Mac is transcribing"
        case "queued": return "Queued on your Mac"
        case "waiting_for_audio": return "Waiting for the rest of your audio"
        case "failed": return "Transcription needs attention"
        case "cancelled": return "Transcription cancelled"
        default: return "Preparing your recording for your Mac"
        }
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
