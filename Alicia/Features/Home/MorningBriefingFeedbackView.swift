import SwiftUI

/// Explicit assessment of this script; playback never supplies feedback.
struct MorningBriefingFeedbackView: View {
    @Environment(AppStore.self) private var store
    let briefing: MorningBriefing
    @State private var text = ""
    @State private var pending: BriefingFeedbackMutation?
    @State private var busy = false
    @State private var message = ""
    @FocusState private var writing: Bool
    private var key: String { "morning." + briefing.id + ".feedback" }

    var body: some View {
        InkDisclosure("How was this briefing?") {
            VStack(alignment: .leading, spacing: 10) {
                TextField("What should Alicia carry into tomorrow?", text: $text, axis: .vertical)
                    .lineLimit(2...8).inkField().focused($writing).disabled(busy || pending != nil)
                    .accessibilityIdentifier("morningBriefing.feedbackWords")
                if pending != nil {
                    Button("Retry feedback") { send(nil) }.buttonStyle(.inkSecondaryCompact)
                        .disabled(busy)
                } else {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 12) { choices }
                        VStack(alignment: .leading, spacing: 10) { choices }
                    }.disabled(busy || text.unicodeScalars.count > 4000)
                }
                if text.unicodeScalars.count > 4000 { InkNotice(text: "Please keep this under 4,000 characters. Your full draft stays here.") }
                if !message.isEmpty { InkNotice(text: message) }
            }
        }
        .task {
            let draft = store.collaboration.draft(key)
            text = draft?["text"] ?? briefing.feedback?.text ?? ""
            if let event = draft?["event_id"], let verdict = draft?["verdict"], let hash = draft?["script_sha256"] {
                pending = .init(id: briefing.id, event_id: event, verdict: verdict, text: text, script_sha256: hash)
                message = "Save unconfirmed. Retry keeps your exact feedback."
            }
        }
        .onChange(of: text) { _, _ in if pending == nil { store.collaboration.saveDraft(["text": text], name: key) } }
        .toolbar { ToolbarItemGroup(placement: .keyboard) {
            Spacer()
            Button("Done writing") { writing = false }
        } }
    }

    private var choices: some View {
        Group {
            WorkReviewChoice(title: "Useful", selected: briefing.feedback?.verdict == "useful") { send("useful") }
            WorkReviewChoice(title: "Missed what mattered", selected: briefing.feedback?.verdict == "missed") { send("missed") }
        }
    }

    private func send(_ verdict: String?) {
        guard !busy else { return }
        if let verdict {
            pending = .init(id: briefing.id, event_id: UUID().uuidString, verdict: verdict,
                            text: text, script_sha256: briefing.script_sha256)
        }
        guard let request = pending else { return }
        writing = false
        store.collaboration.saveDraft(request.body, name: key)
        busy = true
        Task {
            let result = await store.saveBriefingFeedback(request)
            busy = false
            if result?.ok == true {
                pending = nil; store.collaboration.clearDraft(key)
                message = "Saved for the next morning’s preparation."
            } else if let result, !result.ok {
                pending = nil; store.collaboration.saveDraft(["text": text], name: key)
                message = result.error ?? "Feedback was not saved. Refresh and retry."
            } else {
                message = "Save unconfirmed. Retry keeps your exact feedback."
            }
        }
    }
}
