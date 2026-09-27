import SwiftUI

/// Finished together: every goal he closed, and what it took.
///
/// Hector, 2026-09-26: "once they are closed, wrap them up in a way that shows
/// the work we did together. So in the future if I want to go back to the
/// cleared goals and the data and steps we did…" The record is frozen by the
/// backend at the moment a goal closes (goal_closure.py); this room only reads it.
struct FinishedTogetherRoom: View {
    @Environment(AppStore.self) private var store
    var openClosureID: String? = nil
    @State private var opened: String?

    var body: some View {
        let closures = store.collaboration.state?.closures ?? []
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("What we closed, and what it took").font(InkType.subhead)
                if closures.isEmpty {
                    InkNotice(text: "Nothing finished yet. When you close a goal, on a walk or here, its whole record stays in this room.")
                }
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(closures.enumerated()), id: \.element.id) { index, item in
                        if index > 0 { InkRule(opacity: 0.6) }
                        NavigationLink { FinishedGoalView(closureID: item.closure_id) } label: { row(item) }
                            .buttonStyle(.inkLink)
                            .accessibilityIdentifier("finished.row." + item.closure_id)
                    }
                }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(22)
        }
        .background(Theme.paper).foregroundStyle(Theme.ink).tint(Theme.ink)
        .inkPushedPage("Finished together")
        .navigationDestination(item: $opened) { FinishedGoalView(closureID: $0) }
        .task { if opened == nil, let id = openClosureID, !id.isEmpty { opened = id } }
    }

    private func row(_ item: GoalClosureSummary) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            InkKicker(text: (item.isReopened ? "Reopened · " : "") + item.howClosed + " · " + goalDay(item.closed_at))
            InkLinkLabel(title: item.title, detail: counts(item))
            if !item.words.isEmpty {
                Text("“" + item.words.strippedEmojis + "”").font(InkType.linkSmall).italic().lineLimit(3)
                    .foregroundStyle(Theme.inkSoft).multilineTextAlignment(.leading)
            }
        }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
    }

    private func counts(_ item: GoalClosureSummary) -> String {
        var parts: [String] = []
        if let start = item.created_at, !start.isEmpty { parts.append(goalDay(start) + " → " + goalDay(item.closed_at)) }
        if let n = item.revisions, n > 0 { parts.append("\(n) revisions of her work") }
        if let n = item.his_words, n > 0 { parts.append("\(n) of your passages") }
        return parts.joined(separator: " · ")
    }
}

/// One finished goal: the goal as he stated it, where it landed, his words along
/// the way, the steps of her work, what was left open, and a way back in.
struct FinishedGoalView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let closureID: String
    @State private var record: GoalClosureRecord?
    @State private var failed = false
    @State private var confirmReopen = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                if let record { content(record) }
                else if failed {
                    InkNotice(text: "This record could not be opened. It is kept on your Mac.", kind: .error)
                    Button("Try again") { Task { await load() } }.buttonStyle(.inkQuiet)
                } else {
                    InkNotice(text: "Opening…")
                }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(22)
        }
        .background(Theme.paper).foregroundStyle(Theme.ink).tint(Theme.ink)
        .inkPushedPage("Finished goal")
        .task { if record == nil { await load() } }
        .confirmationDialog("Reopen this goal?", isPresented: $confirmReopen, titleVisibility: .visible) {
            Button("Reopen and keep working") { reopen() }
            Button("Keep it finished", role: .cancel) {}
        } message: { Text("Its record stays here, marked reopened.") }
    }

    private func load() async {
        failed = false
        record = await store.collaboration.goalClosure(closureID)
        failed = record == nil
    }

    @ViewBuilder private func content(_ r: GoalClosureRecord) -> some View {
        let d = r.dossier
        VStack(alignment: .leading, spacing: 8) {
            InkKicker(text: howClosed(r) + " · " + goalDay(r.closed_at))
            Text(d.goal.title.strippedEmojis).font(.system(size: 28, design: .serif))
            Text(d.goal.outcome.strippedEmojis).font(InkType.body)
            if let why = d.goal.why, !why.isEmpty {
                Text("Why it mattered · " + why.strippedEmojis).font(.callout).foregroundStyle(Theme.inkSoft)
            }
            Text(span(d)).font(InkType.meta).foregroundStyle(Theme.inkSoft)
        }
        if !r.words.isEmpty {
            InkSection(kicker: "How you closed it") {
                Text("“" + r.words.strippedEmojis + "”").font(.system(size: 19, design: .serif)).italic()
                if let full = d.closing_input?.text, !full.isEmpty {
                    InkDisclosure("The whole reflection") {
                        Text(full.strippedEmojis).font(InkType.linkSmall).textSelection(.enabled)
                    }
                }
            }
        }
        if let reflection = r.reflection {
            InkSection(kicker: "Alicia's reading") {
                Text(reflection.text.strippedEmojis).font(InkType.body)
                NaturalReviewButton(title: "Alicia's reading", text: reflection.text)
                Text("Her reading of the work, written when the goal closed. Not your words.").font(InkType.meta).foregroundStyle(Theme.inkSoft)
            }
        }
        InkSection(kicker: "Where the work landed") {
            Text(d.final_artifact.title.strippedEmojis).font(.system(size: 18, design: .serif))
            if !d.final_artifact.body.isEmpty {
                InkDisclosure("Read the last version") {
                    Text(d.final_artifact.body.strippedEmojis).font(InkType.linkSmall).textSelection(.enabled)
                    NaturalReviewButton(title: d.final_artifact.title, text: d.final_artifact.body)
                }
            }
            Text("Alicia's prepared work. Not proof you agreed with it.").font(InkType.meta).foregroundStyle(Theme.inkSoft)
        }
        if !d.his_words.isEmpty {
            InkSection(kicker: "Your words along the way") {
                ForEach(Array(d.his_words.enumerated()), id: \.element.id) { index, words in
                    if index > 0 { InkRule(opacity: 0.6) }
                    VStack(alignment: .leading, spacing: 4) {
                        InkKicker(text: goalDay(words.observed_at))
                        Text("“" + words.excerpt.strippedEmojis + "”").font(InkType.linkSmall).italic()
                        if let recording = words.recording_id, !recording.isEmpty {
                            NavigationLink { VoiceRecordingDetail(id: recording, pushed: true) } label: {
                                InkLinkLabel(title: "Hear the original", small: true)
                            }.buttonStyle(.inkLink)
                        }
                    }
                }
            }
        }
        if !d.steps.isEmpty {
            InkSection(kicker: "The steps of the work · \(d.steps.count)") {
                ForEach(Array(d.steps.enumerated()), id: \.element.id) { index, step in
                    if index > 0 { InkRule(opacity: 0.6) }
                    VStack(alignment: .leading, spacing: 3) {
                        InkKicker(text: goalDay(step.at) + (step.number.map { " · revision \($0)" } ?? ""))
                        Text(step.title.strippedEmojis).font(InkType.linkSmall)
                    }
                }
            }
        }
        if !d.references.isEmpty {
            InkSection(kicker: "What we drew on") {
                ForEach(Array(d.references.enumerated()), id: \.element.id) { index, ref in
                    if index > 0 { InkRule(opacity: 0.6) }
                    Text(ref.title.strippedEmojis + (ref.uses > 1 ? "  ·  \(ref.uses)×" : "")).font(InkType.linkSmall)
                }
            }
        }
        let seeds = r.reflection?.next_goal_seeds ?? []
        if !d.open_questions.isEmpty || !seeds.isEmpty {
            InkSection(kicker: "Left open · where a next goal could start") {
                ForEach(seeds, id: \.self) { seed in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(seed.strippedEmojis).font(InkType.body)
                        NavigationLink { CollaborationEditor(kind: .goal(nil), suggestedTitle: seed) } label: {
                            InkLinkLabel(title: "Start a goal from this", small: true)
                        }.buttonStyle(.inkLink)
                    }
                }
                ForEach(d.open_questions) { q in
                    Text(q.question.strippedEmojis).font(.system(size: 14, design: .serif)).foregroundStyle(Theme.inkSoft)
                }
                if !seeds.isEmpty { Text("Her suggestions. A goal starts only when you write it.").font(InkType.meta).foregroundStyle(Theme.inkSoft) }
            }
        }
        VStack(alignment: .leading, spacing: 10) {
            InkRule()
            if (r.reopened_at ?? "").isEmpty {
                Button("Reopen this goal") { confirmReopen = true }
                    .buttonStyle(.inkSecondary)
                    .disabled(!store.collaboration.canEdit)
                    .accessibilityIdentifier("finished.reopen")
            } else {
                InkNotice(text: "Reopened " + goalDay(r.reopened_at) + ". This record is kept as it was.")
            }
            if let notice = d.notice { Text(notice).font(.caption2).foregroundStyle(Theme.inkSoft) }
            CollaborationSaveStatus()
        }
    }

    private func reopen() {
        Task {
            if await store.collaboration.submit(CollaborationMutation(action: "reopen_goal", closure_id: closureID)) {
                await load()
            }
        }
    }

    private func howClosed(_ r: GoalClosureRecord) -> String {
        r.by == "walk" ? "CLOSED ON YOUR WALK" : r.by == "chat" ? "CLOSED IN CONVERSATION" : "CLOSED IN THE APP"
    }
    private func span(_ d: GoalClosureRecord.Dossier) -> String {
        var parts = [goalDay(d.goal.created_at) + " → " + goalDay(record?.closed_at)]
        parts.append("\(d.stats.revisions) revisions")
        parts.append("\(d.stats.his_words) of your passages")
        if d.stats.connections > 0 { parts.append("\(d.stats.connections) connections") }
        return parts.joined(separator: " · ")
    }
}

/// Close a goal from the app, optionally in his own words.
struct CloseGoalView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let goal: CollaborationState.Goal
    @State private var words = ""
    @State private var requestID = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(goal.title.strippedEmojis).font(InkType.subhead)
                Text("Alicia keeps its whole record in Finished together: your words, the steps of the work and where it landed.")
                    .font(.callout).foregroundStyle(Theme.inkSoft)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Where did it land? (optional, in your words)").font(InkType.linkSmall.weight(.semibold))
                    TextField("Where did it land?", text: $words, axis: .vertical).lineLimit(3...8)
                        .inkField()
                    if words.unicodeScalars.count > 2000 {
                        InkNotice(text: "Keep this under 2,000 characters. Your words are retained.", kind: .error)
                    }
                }
                Button("Close it and keep the record") {
                    let change = CollaborationMutation(action: "close_goal", goal_id: goal.id,
                                                       text: words.trimmingCharacters(in: .whitespacesAndNewlines))
                    requestID = change.event_id
                    Task { await store.collaboration.submit(change) }
                }
                .buttonStyle(.inkPrimary)
                .disabled(!store.collaboration.canEdit || words.unicodeScalars.count > 2000)
                .accessibilityIdentifier("collaboration.closeGoal.confirm")
                CollaborationSaveStatus()
            }.frame(maxWidth: .infinity, alignment: .leading).padding(22)
        }
        .background(Theme.paper).foregroundStyle(Theme.ink).tint(Theme.ink)
        .inkPushedPage("Close this goal")
        .onChange(of: store.collaboration.lastConfirmedID) { _, id in if id == requestID { dismiss() } }
    }
}

/// What she says after a close, and any "did you mean to close?" question.
/// Shown on Us and Alicia (CollaborationSummary) and at the top of Together.
struct GoalClosureNotices: View {
    @Environment(AppStore.self) private var store
    /// Called to open Finished together from wherever this is mounted.
    var openFinished: (String?) -> Void

    var body: some View {
        if let state = store.collaboration.state {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(state.closure_proposals ?? []) { proposal in
                    // A question for him: its own card, with the two answers as actions.
                    VStack(alignment: .leading, spacing: 10) {
                        InkKicker(text: "Did you mean to close this?")
                        Text(proposal.titles.joined(separator: " · ").strippedEmojis).font(InkType.subhead)
                        Text("You said: “" + proposal.words.strippedEmojis + "”").font(.system(size: 15, design: .serif)).italic()
                            .foregroundStyle(Theme.inkSoft)
                        HStack(spacing: 10) {
                            Button("Yes, close it") { decide(proposal, "confirm") }
                                .buttonStyle(.inkSecondaryCompact)
                                .accessibilityIdentifier("closure.proposal.confirm")
                            Button("Not yet") { decide(proposal, "dismiss") }
                                .buttonStyle(.inkQuiet)
                                .accessibilityIdentifier("closure.proposal.dismiss")
                        }.disabled(!store.collaboration.canEdit)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card(padding: 16, radius: 16)
                }
                if let closed = state.closureAcknowledgement, let line = closed.acknowledgement {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(line.strippedEmojis).font(.system(size: 16, design: .serif))
                        Button { openFinished(closed.closure_id) } label: { InkLinkLabel(title: "See what we built", small: true) }
                            .buttonStyle(.inkLink)
                            .accessibilityIdentifier("closure.acknowledgement")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card(padding: 16, radius: 16)
                }
            }
        }
    }

    private func decide(_ proposal: GoalClosureProposal, _ verdict: String) {
        Task {
            await store.collaboration.submit(CollaborationMutation(action: "closure_decision", verdict: verdict,
                                                                   proposal_id: proposal.proposal_id))
        }
    }
}
