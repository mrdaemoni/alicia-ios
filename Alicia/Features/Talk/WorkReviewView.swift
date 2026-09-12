import SwiftUI

/// One visual vocabulary for reacting to work, replying to it, and returning to it.
struct WorkReviewChoice: View {
    let title: String
    var selected = false
    var compact = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(.system(.subheadline, design: .serif))
                .lineLimit(compact ? 1 : nil)
                .frame(maxWidth: compact ? 160 : nil)
                .padding(.horizontal, 12).frame(minHeight: 44)
                .foregroundStyle(selected ? Theme.paper : Theme.ink)
                .background(selected ? Theme.ink : Theme.paper, in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(Theme.ink.opacity(selected ? 1 : 0.25), lineWidth: 0.7))
        }.buttonStyle(.plain)
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct WorkReviewMeter: View {
    let progress: WorkReviewProgress
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(progress.remaining == 0 ? "Review complete" : "\(progress.remaining) pieces need your review")
                .font(.headline).accessibilityIdentifier("workReview.remaining")
            ProgressView(value: Double(min(progress.reviewed, progress.total)), total: Double(max(1, progress.total)))
                .tint(Theme.ink).accessibilityLabel("Prepared work reviewed")
                .accessibilityValue("\(progress.reviewed) of \(progress.total)")
            Text("\(progress.reviewed) of \(progress.total) reviewed" + (progress.questions > 0 ? " · \(progress.answered) of \(progress.questions) questions answered" : ""))
                .font(.caption).foregroundStyle(Theme.inkSoft)
        }.padding(.vertical, 8)
    }
}

struct GoalWorkProgress: View {
    let goal: CollaborationState.Goal
    let state: CollaborationState
    private var results: [CollaborationState.Result] {
        let agreements = Set(state.agreements.filter { $0.goal_id == goal.id }.map(\.id))
        return state.results.filter { $0.goal_id == goal.id || agreements.contains($0.agreement_id) }
    }
    var body: some View {
        let progress = results.compactMap(\.review_progress)
        let agreements = state.agreements.filter { $0.goal_id == goal.id && $0.status != "cancelled" }
        let complete = agreements.filter { $0.status == "completed" }.count
        VStack(alignment: .leading, spacing: 8) {
            if !progress.isEmpty {
                WorkReviewMeter(progress: .init(total: progress.reduce(0) { $0 + $1.total },
                    reviewed: progress.reduce(0) { $0 + $1.reviewed },
                    questions: progress.reduce(0) { $0 + $1.questions },
                    answered: progress.reduce(0) { $0 + $1.answered }))
            }
            Text(goal.status == "completed" ? "Goal completed · marked by you" : goal.status == "paused" ? "Goal paused" : "Goal in progress")
                .font(.caption.monospaced()).accessibilityIdentifier("workReview.goalStatus")
            Text(agreements.isEmpty ? "No agreed steps yet. You decide what finishing looks like."
                 : "\(complete) of \(agreements.count) agreed steps completed · based on your outcome reports")
                .font(.caption).foregroundStyle(Theme.inkSoft)
        }
    }
}

struct CollaborationResultView: View {
    @Environment(AppStore.self) private var store
    let result: CollaborationState.Result
    var sectionID: String? = nil
    private var current: CollaborationState.Result? {
        store.collaboration.state?.results.first { $0.id == result.id }
    }
    var body: some View {
        ScrollViewReader { scroll in
            ScrollView {
                WorkReviewContent(result: current ?? result, available: current != nil,
                                  requestedSectionID: sectionID, jump: { scroll.scrollTo($0, anchor: .top) })
                    .padding(22)
            }
            .task { if let sectionID { scroll.scrollTo(sectionID, anchor: .top) } }
        }.background(Theme.paper).foregroundStyle(Theme.ink)
            .navigationTitle("Prepared work").navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
    }
}

struct WorkReviewContent: View {
    @Environment(AppStore.self) private var store
    let result: CollaborationState.Result
    var available = true
    var requestedSectionID: String? = nil
    var jump: ((String) -> Void)? = nil
    @State private var showHidden = false
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text(result.title).font(.title2)
            Text(result.status == "blocked" ? "Blocked · your input may help" : "Prepared by Alicia · awaiting your review")
                .font(.caption).foregroundStyle(Theme.inkSoft)
            if let goal = store.collaboration.state?.goal(for: result) {
                Text("FOR · " + goal.title).font(.caption.monospaced())
            }
            if !available {
                Text("This passage is unavailable in the current work. Its original text and your draft stay here. Return to Together to refresh the goal.")
                    .font(.callout).foregroundStyle(Theme.rose)
            }
            if let progress = result.review_progress { WorkReviewMeter(progress: progress) }
            if let jump, let sections = result.review_sections, sections.filter({ $0.kind == "question" }).count > 1 {
                Menu("Jump to a question") {
                    ForEach(sections.filter { $0.kind == "question" && !$0.review.hidden }) { section in
                        Button(section.title) { jump(section.id) }
                    }
                }.frame(minHeight: 44)
            }
            Text("Mark what matters, or answer in your own words.")
                .font(.callout).foregroundStyle(Theme.inkSoft)
            NaturalReviewButton(title: result.title, text: result.body)
            CollaborationSaveStatus()
            if let sections = result.review_sections, !sections.isEmpty {
                ForEach(sections.filter { !$0.review.hidden }) { section in
                    WorkReviewCard(result: result, section: section, available: available).id(section.id)
                }
                let hidden = sections.filter { $0.review.hidden }
                if !hidden.isEmpty {
                    DisclosureGroup("Set aside · \(hidden.count)", isExpanded: $showHidden) {
                        ForEach(hidden) { section in
                            WorkReviewCard(result: result, section: section, available: available).id(section.id)
                        }
                    }
                }
            } else {
                Text(result.body).textSelection(.enabled)
                Text("Section review is unavailable for this version. Refresh Together to check for an update.")
                    .font(.caption).foregroundStyle(Theme.inkSoft)
            }
            if !result.evidence.isEmpty {
                Divider()
                Text("What this draws on").font(.title3)
                ForEach(result.evidence) { evidence in
                    NavigationLink(evidence.title) { CollaborationEvidenceView(evidence: evidence, resultID: result.id) }
                        .frame(minHeight: 44)
                }
            }
        }.task {
            if let requestedSectionID, result.review_sections?.first(where: { $0.id == requestedSectionID })?.review.hidden == true {
                showHidden = true
            }
        }
    }
}

private struct WorkReviewCard: View {
    @Environment(AppStore.self) private var store
    let result: CollaborationState.Result
    let section: WorkReviewSection
    let available: Bool
    @State private var editor: String?
    @State private var lastRequestID = ""
    private var shared: CollaborationStore { store.collaboration }
    private var goal: CollaborationState.Goal? { shared.state?.goal(for: result) }
    private var key: String { "work." + result.id + "." + section.id }
    private var canEdit: Bool { available && shared.canEdit }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(section.kind == "question" ? "A QUESTION FOR YOU" : "A PIECE TO CONSIDER")
                    .font(.caption.monospaced()).foregroundStyle(Theme.inkSoft)
                Spacer(minLength: 8)
                if section.review.salient { Text("Important").font(.caption).italic() }
            }
            Text(section.text.trimmingCharacters(in: .whitespacesAndNewlines))
                .font(.system(.body, design: .serif)).textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            if !section.review.edited_text.isEmpty {
                savedWords("Your edit", text: section.review.edited_text)
            }
            if !section.review.answer.isEmpty { savedWords("Your answer", text: section.review.answer) }
            if !section.review.comment.isEmpty { savedWords("Your note", text: section.review.comment) }
            if section.review.hidden {
                WorkReviewChoice(title: "Restore this piece") { send("restore") }.disabled(!canEdit)
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 7) { choices }
                    VStack(alignment: .leading, spacing: 7) { choices }
                }.disabled(!canEdit || editor != nil)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 16) { writingActions }
                    VStack(alignment: .leading, spacing: 5) { writingActions }
                }.disabled(!canEdit || editor != nil)
                if let editor {
                    WorkReviewEditor(resultID: result.id, section: section, mode: editor,
                        draftKey: key + "." + editor, available: available) { self.editor = nil }
                        .id(key + "." + editor)
                }
                if goal != nil {
                    Button("Discuss this in Dialogue") { discuss() }
                        .font(.callout).underline().frame(minHeight: 44)
                        .disabled(!available || editor != nil || !shared.canEdit)
                        .accessibilityIdentifier("workReview.discuss." + section.id)
                }
            }
            if lastRequestID == shared.lastConfirmedID, !lastRequestID.isEmpty {
                Text("Saved for Alicia's next revision.").font(.caption).accessibilityIdentifier("workReview.saved." + section.id)
            }
        }
        .padding(16)
        .background(Theme.ink.opacity(0.025), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.stroke, lineWidth: 0.7))
        .buttonStyle(.plain)
        .task { if editor == nil { editor = ["answer", "edit", "comment"].first { shared.draft(key + "." + $0) != nil } } }
    }
    @ViewBuilder private var choices: some View {
        WorkReviewChoice(title: "Agree", selected: section.review.stance == "agree") {
            send(section.review.stance == "agree" ? "clear_stance" : "agree")
        }.accessibilityIdentifier("workReview.agree." + section.id)
        WorkReviewChoice(title: "Disagree", selected: section.review.stance == "disagree") {
            send(section.review.stance == "disagree" ? "clear_stance" : "disagree")
        }.accessibilityIdentifier("workReview.disagree." + section.id)
        WorkReviewChoice(title: "Important", selected: section.review.salient) {
            send(section.review.salient ? "unsalient" : "salient")
        }.accessibilityIdentifier("workReview.salient." + section.id)
    }
    @ViewBuilder private var writingActions: some View {
        Button(section.review.answer.isEmpty ? "Answer this" : "Edit my answer") { editor = "answer" }
            .accessibilityIdentifier("workReview.answer." + section.id)
        Button("Edit this") { editor = "edit" }.accessibilityIdentifier("workReview.edit." + section.id)
        Menu {
            Button("Add a note") { editor = "comment" }
            Button("Set aside") { send("hide") }
            if section.review.stance != "unreviewed" { Button("Clear agreement") { send("clear_stance") } }
            Button("Read this aloud") {
                store.readAloud(Readable(title: section.title, body: section.text, kind: "collaboration_review"))
            }
        } label: { Text("More").frame(minHeight: 44) }
            .accessibilityIdentifier("workReview.more." + section.id)
    }
    private func savedWords(_ label: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.caption.monospaced())
            Text(text).textSelection(.enabled)
        }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.paper, in: RoundedRectangle(cornerRadius: 8))
    }
    private func send(_ verdict: String) {
        guard canEdit else { return }
        let mutation = section.mutation(resultID: result.id, verdict: verdict)
        lastRequestID = mutation.event_id
        Task { await shared.submit(mutation) }
    }
    private func discuss() {
        guard let goal else { return }
        store.cancelAnswering()
        shared.dialogueContext = .init(goal_id: goal.id, result_id: result.id, section_id: section.id,
            content_hash: section.content_hash, goalTitle: goal.title, sectionTitle: section.title, quote: section.text)
        shared.route = nil
        store.selectedSection = .dialogue
    }
}

/// In-place writing avoids the nested-sheet keyboard jump. The frozen review
/// revision and durable draft never change merely because a refresh arrived.
private struct WorkReviewEditor: View {
    @Environment(AppStore.self) private var store
    let resultID: String
    let section: WorkReviewSection
    let mode, draftKey: String
    let available: Bool
    let close: () -> Void
    @State private var text = ""
    @State private var revision = 0
    @State private var requestID = ""
    @State private var seeded = false
    @FocusState private var writing: Bool
    private var shared: CollaborationStore { store.collaboration }
    private var label: String { mode == "edit" ? "Your version" : mode == "answer" ? "Your answer" : "Your note" }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(label).font(.headline)
            Text(mode == "edit" ? "The original stays above. Your version is saved separately." : "Saved with the exact passage above, for this goal.")
                .font(.caption).foregroundStyle(Theme.inkSoft)
            TextField(label, text: $text, axis: .vertical).lineLimit(4...16)
                .focused($writing).padding(12).background(Theme.paper, in: RoundedRectangle(cornerRadius: 8))
                .disabled(!available || !shared.canEdit)
                .accessibilityIdentifier("workReview.editor." + section.id)
            if text.unicodeScalars.count > 8000 { Text("Please keep this under 8,000 characters. Your full draft is retained.").font(.caption) }
            HStack(spacing: 18) {
                WorkReviewChoice(title: "Save " + label.lowercased()) { save() }
                    .disabled(!available || !shared.canEdit || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || text.unicodeScalars.count > 8000)
                    .accessibilityIdentifier("workReview.save." + section.id)
                Button("Keep draft") { writing = false; persist(); close() }.frame(minHeight: 44)
            }
            CollaborationSaveStatus()
            if section.review.revision != revision {
                Text("This piece has newer feedback. Your words remain unchanged.").font(.caption)
                Button("Use current review version") { revision = section.review.revision; requestID = ""; persist() }
                    .frame(minHeight: 44).disabled(!shared.canEdit)
            }
        }.padding(.vertical, 6)
            .task {
                guard !seeded else { return }
                let draft = shared.draft(draftKey)
                revision = Int(draft?["revision"] ?? "") ?? section.review.revision
                requestID = draft?["request_id"] ?? ""
                if draft?["mode"] == mode { text = draft?["text"] ?? "" }
                else { text = mode == "edit" ? (section.review.edited_text.isEmpty ? section.text : section.review.edited_text) : mode == "answer" ? section.review.answer : section.review.comment }
                seeded = true; persist()
            }
            .onChange(of: text) { _, _ in persist() }
            .onDisappear { if seeded { persist() } }
            .onChange(of: shared.lastConfirmedID) { _, id in
                if !requestID.isEmpty, requestID == id { shared.clearDraft(draftKey); writing = false; close() }
            }
            .toolbar { ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("OK") { writing = false }.font(.callout).accessibilityLabel("Done writing")
            } }
    }
    private func persist() {
        guard seeded else { return }
        shared.saveDraft(["mode": mode, "text": text, "revision": String(revision), "request_id": requestID], name: draftKey)
    }
    private func save() {
        writing = false
        let mutation = section.mutation(resultID: resultID, verdict: mode, text: text, revision: revision)
        requestID = mutation.event_id; persist()
        Task { await shared.submit(mutation, draftName: draftKey) }
    }
}
