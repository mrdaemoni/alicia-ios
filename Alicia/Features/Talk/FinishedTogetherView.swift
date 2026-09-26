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
                VStack(alignment: .leading, spacing: 6) {
                    Text("FINISHED TOGETHER").font(.system(size: 10, design: .monospaced)).tracking(2)
                        .foregroundStyle(Theme.inkSoft)
                    Text("What we closed, and what it took").font(.system(size: 27, design: .serif))
                }
                if closures.isEmpty {
                    Text("Nothing finished yet. When you close a goal, on a walk or here, its whole record stays in this room.")
                        .font(.system(size: 16, design: .serif)).italic().foregroundStyle(Theme.inkSoft)
                }
                ForEach(closures) { item in
                    NavigationLink { FinishedGoalView(closureID: item.closure_id) } label: { row(item) }
                        .accessibilityIdentifier("finished.row." + item.closure_id)
                }
            }.padding(22)
        }
        .background(Theme.paper).foregroundStyle(Theme.ink)
        .navigationTitle("Finished together").navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar { ToolbarItem(placement: .topBarLeading) { InkBackButton() } }
        .navigationDestination(item: $opened) { FinishedGoalView(closureID: $0) }
        .task { if opened == nil, let id = openClosureID, !id.isEmpty { opened = id } }
        .buttonStyle(.plain)
    }

    private func row(_ item: GoalClosureSummary) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text((item.isReopened ? "REOPENED · " : "") + item.howClosed.uppercased() + " · " + goalDay(item.closed_at).uppercased())
                .font(.system(size: 10, design: .monospaced)).tracking(1.5).foregroundStyle(Theme.inkSoft)
            Text(item.title.strippedEmojis).font(.system(size: 22, design: .serif))
            if !item.words.isEmpty {
                Text("“" + item.words.strippedEmojis + "”").font(.system(size: 15, design: .serif)).italic().lineLimit(3)
            }
            Text(counts(item)).font(.caption).foregroundStyle(Theme.inkSoft)
            InkUnderline(seed: item.closure_id.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }).frame(height: 6).opacity(0.5)
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
    @State private var showArtifact = false
    @State private var showWhole = false
    @State private var confirmReopen = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                if let record { content(record) }
                else if failed {
                    Text("This record could not be opened. It is kept on your Mac.").font(.system(size: 15, design: .serif))
                        .foregroundStyle(Theme.rose)
                    Button("Try again") { Task { await load() } }.frame(minHeight: 44)
                } else {
                    Text("Opening…").font(.system(size: 15, design: .serif)).italic().foregroundStyle(Theme.inkSoft)
                }
            }.padding(22)
        }
        .background(Theme.paper).foregroundStyle(Theme.ink)
        .navigationTitle("Finished goal").navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar { ToolbarItem(placement: .topBarLeading) { InkBackButton() } }
        .buttonStyle(CollaborationButtonStyle())
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
            kicker(howClosed(r) + " · " + goalDay(r.closed_at))
            Text(d.goal.title.strippedEmojis).font(.system(size: 28, design: .serif))
            Text(d.goal.outcome.strippedEmojis).font(.system(size: 16, design: .serif))
            if let why = d.goal.why, !why.isEmpty {
                Text("Why it mattered · " + why.strippedEmojis).font(.callout).foregroundStyle(Theme.inkSoft)
            }
            Text(span(d)).font(.caption).foregroundStyle(Theme.inkSoft)
        }
        if !r.words.isEmpty {
            section("HOW YOU CLOSED IT") {
                Text("“" + r.words.strippedEmojis + "”").font(.system(size: 19, design: .serif)).italic()
                if let full = d.closing_input?.text, !full.isEmpty {
                    Button(showWhole ? "Fold the reflection away" : "The whole reflection") { showWhole.toggle() }
                    if showWhole {
                        Text(full.strippedEmojis).font(.system(size: 15, design: .serif)).textSelection(.enabled)
                    }
                }
            }
        }
        if let reflection = r.reflection {
            section("ALICIA'S READING") {
                Text(reflection.text.strippedEmojis).font(.system(size: 16, design: .serif))
                NaturalReviewButton(title: "Alicia's reading", text: reflection.text)
                Text("Her reading of the work, written when the goal closed. Not your words.").font(.caption).foregroundStyle(Theme.inkSoft)
            }
        }
        section("WHERE THE WORK LANDED") {
            Text(d.final_artifact.title.strippedEmojis).font(.system(size: 18, design: .serif))
            if !d.final_artifact.body.isEmpty {
                Button(showArtifact ? "Fold it away" : "Read the last version") { showArtifact.toggle() }
                if showArtifact {
                    Text(d.final_artifact.body.strippedEmojis).font(.system(size: 15, design: .serif)).textSelection(.enabled)
                    NaturalReviewButton(title: d.final_artifact.title, text: d.final_artifact.body)
                }
            }
            Text("Alicia's prepared work. Not proof you agreed with it.").font(.caption).foregroundStyle(Theme.inkSoft)
        }
        if !d.his_words.isEmpty {
            section("YOUR WORDS ALONG THE WAY") {
                ForEach(d.his_words) { words in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(goalDay(words.observed_at)).font(.system(size: 10, design: .monospaced)).tracking(1.5)
                            .foregroundStyle(Theme.inkSoft)
                        Text("“" + words.excerpt.strippedEmojis + "”").font(.system(size: 15, design: .serif)).italic()
                        if let recording = words.recording_id, !recording.isEmpty {
                            NavigationLink("Hear the original") { VoiceRecordingsView(recordingID: recording) }.font(.caption)
                        }
                    }
                }
            }
        }
        if !d.steps.isEmpty {
            section("THE STEPS OF THE WORK · \(d.steps.count)") {
                ForEach(d.steps) { step in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(goalDay(step.at) + (step.number.map { " · REVISION \($0)" } ?? ""))
                            .font(.system(size: 10, design: .monospaced)).tracking(1.5).foregroundStyle(Theme.inkSoft)
                        Text(step.title.strippedEmojis).font(.system(size: 15, design: .serif))
                    }
                }
            }
        }
        if !d.references.isEmpty {
            section("WHAT WE DREW ON") {
                ForEach(d.references) { ref in
                    Text(ref.title.strippedEmojis + (ref.uses > 1 ? "  ·  \(ref.uses)×" : "")).font(.system(size: 15, design: .serif))
                }
            }
        }
        let seeds = r.reflection?.next_goal_seeds ?? []
        if !d.open_questions.isEmpty || !seeds.isEmpty {
            section("LEFT OPEN · WHERE A NEXT GOAL COULD START") {
                ForEach(seeds, id: \.self) { seed in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(seed.strippedEmojis).font(.system(size: 16, design: .serif))
                        NavigationLink("Start a goal from this") { CollaborationEditor(kind: .goal(nil), suggestedTitle: seed) }
                            .font(.callout)
                    }
                }
                ForEach(d.open_questions) { q in
                    Text(q.question.strippedEmojis).font(.system(size: 14, design: .serif)).foregroundStyle(Theme.inkSoft)
                }
                if !seeds.isEmpty { Text("Her suggestions. A goal starts only when you write it.").font(.caption).foregroundStyle(Theme.inkSoft) }
            }
        }
        if (r.reopened_at ?? "").isEmpty {
            Button("Reopen this goal") { confirmReopen = true }.disabled(!store.collaboration.canEdit)
                .accessibilityIdentifier("finished.reopen")
        } else {
            Text("Reopened " + goalDay(r.reopened_at) + ". This record is kept as it was.").font(.caption)
        }
        if let notice = d.notice { Text(notice).font(.caption2).foregroundStyle(Theme.inkSoft) }
        CollaborationSaveStatus()
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
    private func kicker(_ text: String) -> some View {
        Text(text.uppercased()).font(.system(size: 10, design: .monospaced)).tracking(2).foregroundStyle(Theme.inkSoft)
    }
    private func section<Content: View>(_ title: String, @ViewBuilder _ body: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            kicker(title)
            body()
        }.frame(maxWidth: .infinity, alignment: .leading)
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
                Text("Close this goal").font(.system(size: 27, design: .serif))
                Text(goal.title.strippedEmojis).font(.system(size: 19, design: .serif))
                Text("Alicia keeps its whole record in Finished together: your words, the steps of the work and where it landed.")
                    .font(.callout)
                Text("Where did it land? (optional, in your words)").font(.headline)
                TextField("Where did it land?", text: $words, axis: .vertical).lineLimit(3...8)
                    .padding(12).background(Theme.ink.opacity(0.04))
                Button("Close it and keep the record") {
                    let change = CollaborationMutation(action: "close_goal", goal_id: goal.id,
                                                       text: words.trimmingCharacters(in: .whitespacesAndNewlines))
                    requestID = change.event_id
                    Task { await store.collaboration.submit(change) }
                }.disabled(!store.collaboration.canEdit || words.unicodeScalars.count > 2000)
                    .accessibilityIdentifier("collaboration.closeGoal.confirm")
                CollaborationSaveStatus()
            }.padding(22)
        }
        .background(Theme.paper).foregroundStyle(Theme.ink)
        .navigationTitle("Close goal").navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar { ToolbarItem(placement: .topBarLeading) { InkBackButton() } }
        .buttonStyle(CollaborationButtonStyle())
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
            VStack(alignment: .leading, spacing: 14) {
                ForEach(state.closure_proposals ?? []) { proposal in
                    VStack(alignment: .leading, spacing: 8) {
                        Text("DID YOU MEAN TO CLOSE THIS?").font(.system(size: 10, design: .monospaced)).tracking(2)
                            .foregroundStyle(Theme.inkSoft)
                        Text(proposal.titles.joined(separator: " · ").strippedEmojis).font(.system(size: 19, design: .serif))
                        Text("You said: “" + proposal.words.strippedEmojis + "”").font(.system(size: 15, design: .serif)).italic()
                        HStack(spacing: 16) {
                            Button("Yes, close it") { decide(proposal, "confirm") }
                                .accessibilityIdentifier("closure.proposal.confirm")
                            Button("Not yet") { decide(proposal, "dismiss") }
                                .accessibilityIdentifier("closure.proposal.dismiss")
                        }.disabled(!store.collaboration.canEdit).frame(minHeight: 44)
                    }
                }
                if let closed = state.closureAcknowledgement, let line = closed.acknowledgement {
                    Button { openFinished(closed.closure_id) } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(line.strippedEmojis).font(.system(size: 17, design: .serif))
                            Text("SEE WHAT WE BUILT").font(.system(size: 10, design: .monospaced)).tracking(2)
                        }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }.buttonStyle(.plain).accessibilityIdentifier("closure.acknowledgement")
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
