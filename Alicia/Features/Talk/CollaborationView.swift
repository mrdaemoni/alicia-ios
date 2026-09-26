import SwiftUI

/// Our shared focus, as it appears on Us and Alicia. The parent owns the
/// section kicker (InkSection); this is its content: her notices, the active
/// goals as rows that open Together, and the ways in.
struct CollaborationSummary: View {
    @Environment(AppStore.self) private var store
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GoalClosureNotices { id in
                store.collaboration.route = CollaborationRoute(finishedClosureID: id ?? "")
            }
            if let state = store.collaboration.state {
                if state.activeGoals.isEmpty {
                    Text(state.finishedGoals.isEmpty ? "What would you like us to work toward?"
                         : "Ready for a next goal. What would you like us to work toward now?")
                        .font(InkType.subhead)
                } else {
                    ForEach(Array(state.activeGoals.prefix(3).enumerated()), id: \.element.id) { index, goal in
                        if index > 0 { InkRule(opacity: 0.6) }
                        Button { store.collaboration.route = CollaborationRoute(goalID: goal.id) } label: {
                            InkLinkLabel(title: goal.title, detail: goal.outcome)
                        }
                        .buttonStyle(.inkLink)
                        .accessibilityIdentifier("collaboration.summaryGoal." + goal.id)
                    }
                }
                if let connection = state.connections.first(where: { c in c.status == "proposed" && state.activeGoals.contains { $0.id == c.goal_id } }) {
                    Text("Alicia proposes · " + connection.title.strippedEmojis)
                        .font(.subheadline).italic().foregroundStyle(Theme.inkSoft).lineLimit(2)
                } else if let agreement = state.agreements.first(where: { $0.status == "active" }) {
                    Text("Agreed · " + agreement.action.strippedEmojis).font(.subheadline).foregroundStyle(Theme.inkSoft).lineLimit(2)
                }
                if state.pending { InkNotice(text: "Revisiting the evidence…") }
            }
            InkRule(opacity: 0.6).padding(.top, 4)
            Button { store.collaboration.route = CollaborationRoute() } label: {
                InkLinkLabel(title: "Open Together",
                             detail: "Goals, connections, agreements" + (store.collaboration.state?.finishedGoals.isEmpty == false ? " and what we finished" : ""))
            }
            .buttonStyle(.inkLink)
            .accessibilityIdentifier("collaboration.open")
            Button("Add a goal") { store.collaboration.route = CollaborationRoute(newGoal: true) }
                .buttonStyle(.inkSecondaryCompact)
                .accessibilityIdentifier("collaboration.addGoal")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Together: the shared focus in full. It is a sheet root (from the summary,
/// a notification or a voice note) or pushed from Context enrichment; `pushed`
/// picks the chrome, and closing either way is the same `dismiss()`.
struct CollaborationView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var target = CollaborationRoute()
    var pushed = false
    @State private var viewed = false
    @State private var openTarget = false
    @State private var openNewGoal = false
    @State private var openedGoalEditor = false
    @State private var openFinished = false
    @State private var finishedTarget: String?
    @State private var selectedGoalID = ""
    @State private var targetResult: CollaborationState.Result?
    @State private var signal = ""
    @State private var signalRequestID = ""
    @FocusState private var writing: Bool
    private var shared: CollaborationStore { store.collaboration }

    var body: some View {
        ScrollViewReader { scroll in
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if let state = shared.state {
                        if !target.candidateID.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                InkNotice(text: "Returning to the exact idea you opened.")
                                if let candidate = state.followup, candidate.id == target.candidateID {
                                    Text(candidate.reason).font(.callout)
                                }
                            }
                        }
                        GoalClosureNotices { id in finishedTarget = id; openFinished = true }
                        if state.pending { InkNotice(text: "Alicia is revisiting the evidence. Prepared work will appear here.") }
                        if !state.error.isEmpty { InkNotice(text: state.error, kind: .error) }
                        goalsSection(state)
                        if !(state.closures ?? []).isEmpty {
                            InkSection(kicker: "Finished together · \(state.finishedGoals.count)") {
                                NavigationLink { FinishedTogetherRoom() } label: {
                                    InkLinkLabel(title: "What we closed, and what it took",
                                                 detail: state.finishedGoals.prefix(3).map { $0.title.strippedEmojis }.joined(separator: " · "))
                                }
                                .buttonStyle(.inkLink)
                                .accessibilityIdentifier("collaboration.finished")
                            }
                        }
                        if !state.connections.isEmpty {
                            InkSection(kicker: "Connections to consider", spacing: 4) {
                                let rows = state.connections.filter { (selectedGoalID.isEmpty || $0.goal_id == selectedGoalID) && ($0.status != "dismissed" || $0.id == target.connectionID) }
                                ForEach(Array(rows.enumerated()), id: \.element.id) { index, connection in
                                    if index > 0 { InkRule(opacity: 0.6) }
                                    NavigationLink { CollaborationConnectionView(id: connection.id) } label: {
                                        VStack(alignment: .leading, spacing: 2) {
                                            InkLinkLabel(title: connection.title,
                                                         detail: connection.status == "used" ? "In use · no commitment implied" : connection.status == "dismissed" ? "Dismissed" : "Alicia proposes · inspect and decide")
                                            Text(connection.why_now.strippedEmojis).font(.callout).foregroundStyle(Theme.inkSoft)
                                                .lineLimit(3).multilineTextAlignment(.leading)
                                                .padding(.bottom, 8)
                                        }
                                    }
                                    .buttonStyle(.inkLink)
                                    .id(connection.id).accessibilityIdentifier("collaboration.connection." + connection.id)
                                }
                            }
                        }
                        if !state.agreements.isEmpty {
                            InkSection(kicker: "What we agreed", spacing: 4) {
                                let rows = state.agreements.filter { selectedGoalID.isEmpty || $0.goal_id == selectedGoalID }
                                ForEach(Array(rows.enumerated()), id: \.element.id) { index, agreement in
                                    if index > 0 { InkRule(opacity: 0.6) }
                                    NavigationLink { CollaborationAgreementView(id: agreement.id) } label: {
                                        VStack(alignment: .leading, spacing: 2) {
                                            InkLinkLabel(title: agreement.action, detail: agreement.owner.capitalized + " · " + agreement.status)
                                            if !agreement.outcome.isEmpty {
                                                Text(agreement.outcome.strippedEmojis).font(.callout).foregroundStyle(Theme.inkSoft)
                                                    .lineLimit(2).multilineTextAlignment(.leading)
                                                    .padding(.bottom, 8)
                                            }
                                        }
                                    }
                                    .buttonStyle(.inkLink)
                                    .id(agreement.id).accessibilityIdentifier("collaboration.agreement." + agreement.id)
                                }
                            }
                        }
                        InkSection(kicker: "Context and returns", spacing: 4) {
                            InkDisclosure("Your context right now") { contextNow(state) }
                            InkRule(opacity: 0.6)
                            InkDisclosure("When Alicia returns") { returns(state) }
                        }
                    } else {
                        InkNotice(text: "Connect to Alicia to see the shared focus. Your saved drafts remain here.")
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        InkRule()
                        CollaborationSaveStatus()
                        HStack(spacing: 24) {
                            if shared.state != nil {
                                Button("Revisit the evidence") { Task { await shared.submit(CollaborationMutation(action: "refresh")) } }
                                    .buttonStyle(.inkQuiet)
                                    .disabled(!shared.canEdit)
                            }
                            Button("Refresh shared focus") { Task { await shared.load() } }
                                .buttonStyle(.inkQuiet)
                        }
                    }
                }.padding(22)
            }
            .task {
                if !viewed { selectedGoalID = target.goalID }
                signal = shared.draft("signal")?["text"] ?? ""
                signalRequestID = shared.draft("signal")?["request_id"] ?? ""
                await shared.load()
                if targetResult == nil { targetResult = shared.state?.results.first { $0.id == target.resultID } }
                if let id = target.finishedClosureID, !openedGoalEditor {
                    openedGoalEditor = true
                    finishedTarget = id.isEmpty ? nil : id
                    openFinished = true
                }
                if target.newGoal == true, !openedGoalEditor {
                    openedGoalEditor = true
                    openNewGoal = true
                }
                let id = !target.agreementID.isEmpty ? target.agreementID : !target.connectionID.isEmpty ? target.connectionID : target.goalID
                if !id.isEmpty { scroll.scrollTo(id, anchor: .top) }
                if !viewed {
                    if target.resultID != nil || shared.state?.agreements.contains(where: { $0.id == target.agreementID }) == true || shared.state?.connections.contains(where: { $0.id == target.connectionID }) == true { openTarget = true }
                    else { await shared.viewed(target); viewed = true }
                }
            }
        }
        .onChange(of: signal) { _, text in shared.saveDraft(["text": text,"request_id": signalRequestID], name: "signal") }
        .onChange(of: shared.lastConfirmedID) { _, id in
            if id == signalRequestID { signal = ""; signalRequestID = ""; shared.clearDraft("signal") }
        }
        .background(Theme.paper).foregroundStyle(Theme.ink).tint(Theme.ink)
        .modifier(TogetherChrome(pushed: pushed, close: { dismiss() }))
        .navigationDestination(isPresented: $openNewGoal) { CollaborationEditor(kind: .goal(nil)) }
        .navigationDestination(isPresented: $openFinished) { FinishedTogetherRoom(openClosureID: finishedTarget) }
        .navigationDestination(isPresented: $openTarget) {
            Group {
                if let result = targetResult {
                    CollaborationResultView(result: result, sectionID: target.sectionID)
                }
                else if target.resultID != nil {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            Text("Your original passage").font(InkType.subhead)
                            InkNotice(text: "This passage is unavailable in the current work. Return to Together to refresh the goal. Your conversation still refers to the original below.")
                            if let original = target.originalQuote {
                                Text(original).font(InkType.body).textSelection(.enabled)
                                NaturalReviewButton(title: "The original passage", text: original)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(22)
                    }.background(Theme.paper).foregroundStyle(Theme.ink).inkPushedPage("Original context")
                }
                else if !target.agreementID.isEmpty { CollaborationAgreementView(id: target.agreementID) }
                else { CollaborationConnectionView(id: target.connectionID) }
            }.task { if !viewed { await shared.viewed(target); viewed = true } }
        }
        .scrollDismissesKeyboard(.interactively)
    }

    /// The first section sits under the page title, so no rule; the kicker
    /// keeps its sentence-case accessibility label ("Your goals · 3 active").
    @ViewBuilder private func goalsSection(_ state: CollaborationState) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                InkKicker(text: "Your goals · \(state.activeGoals.count) active")
                    .accessibilityLabel("Your goals · \(state.activeGoals.count) active")
                Spacer(minLength: 12)
                NavigationLink("Add goal") { CollaborationEditor(kind: .goal(nil)) }
                    .buttonStyle(.inkSecondaryCompact)
                    .accessibilityIdentifier("collaboration.newGoal")
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    WorkReviewChoice(title: "All goals", selected: selectedGoalID.isEmpty) { selectedGoalID = "" }
                        .accessibilityIdentifier("workReview.goal.all")
                    ForEach(state.activeGoals) { goal in
                        WorkReviewChoice(title: goal.title.strippedEmojis, selected: selectedGoalID == goal.id, compact: true) { selectedGoalID = goal.id }
                            .accessibilityIdentifier("workReview.goal." + goal.id)
                    }
                }
            }.accessibilityIdentifier("workReview.goalTabs")
            ForEach(visibleGoals(state)) { goal in
                goalCard(goal, state: state)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func contextNow(_ state: CollaborationState) -> some View {
        Text("Tell Alicia how things are for you. Audio observations do not establish how you feel.")
            .font(InkType.meta).foregroundStyle(Theme.inkSoft)
        ForEach(state.signals) { row in
            VStack(alignment: .leading, spacing: 6) {
                Text(row.title).font(InkType.linkSmall.weight(.semibold))
                Text(row.value).font(InkType.body)
                Text(row.source + " · " + row.observed_at).font(InkType.meta).foregroundStyle(Theme.inkSoft)
                Text(row.notice).font(InkType.meta).foregroundStyle(Theme.inkSoft)
                if let id = row.recording_id, !id.isEmpty {
                    NavigationLink { VoiceRecordingsView(recordingID: id) } label: {
                        InkLinkLabel(title: "Review original voice", small: true)
                    }.buttonStyle(.inkLink)
                }
            }
            InkRule(opacity: 0.6)
        }
        TextField("What should she know now?", text: $signal, axis: .vertical)
            .lineLimit(3...8).focused($writing).inkField().accessibilityIdentifier("collaboration.signal")
            .disabled(!shared.canEdit)
        Button("Save my context") {
            writing = false
            let change = CollaborationMutation(action: "signal", priority: "more", text: signal)
            signalRequestID = change.event_id
            Task { await shared.submit(change, draftName: "signal") }
        }
        .buttonStyle(.inkPrimary)
        .accessibilityLabel("Save my context")
        .disabled(!shared.canEdit || !valid(signal))
        lengthNotice(signal)
    }

    @ViewBuilder private func returns(_ state: CollaborationState) -> some View {
        Text("Returns follow a relevant connection, agreed review or prepared result. There is no daily quota. This iPhone schedules them when it syncs, during 9am–7pm local time. Focus and notification permissions can silence them.")
            .font(.callout)
        if let next = state.followup {
            Text(next.message).font(InkType.body)
            Text(next.reason).font(InkType.meta).foregroundStyle(Theme.inkSoft)
        }
        Text(shared.locallyStopped ? "Stopped on this phone. Any pending server change stays queued below." : state.followups_enabled ? "iPhone returns allowed." : "iPhone returns paused.")
            .font(InkType.meta).foregroundStyle(Theme.inkSoft)
        VStack(alignment: .leading, spacing: 10) {
            Button("Stop returns on iPhone and Telegram") { Task { await shared.stopReturns() } }
                .buttonStyle(.inkDestructiveCompact)
                .accessibilityIdentifier("collaboration.stop")
            Button("Allow iPhone returns") {
                Task { await shared.submit(CollaborationMutation(action: "settings", followups_enabled: true, telegram_returns_enabled: state.telegram_returns_enabled)) }
            }
            .buttonStyle(.inkSecondaryCompact)
            .disabled(!shared.canEdit)
            Button(state.telegram_returns_enabled ? "Pause Telegram returns" : "Allow Telegram returns") {
                Task { await shared.submit(CollaborationMutation(action: "settings", followups_enabled: state.followups_enabled && !shared.locallyStopped, telegram_returns_enabled: !state.telegram_returns_enabled)) }
            }
            .buttonStyle(.inkSecondaryCompact)
            .disabled(!shared.canEdit)
            Button("iPhone notification permission") { ProactiveNotifier.requestPermission() }
                .buttonStyle(.inkQuiet)
        }
        if let research = state.impulse_research {
            InkRule(opacity: 0.6)
            ImpulseResearchStatusCard(research: research)
            NavigationLink { ImpulseResearchView() } label: { InkLinkLabel(title: "Review blind judgments", small: true) }
                .buttonStyle(.inkLink)
                .accessibilityIdentifier("impulseResearch.open")
        }
    }

    private func visibleGoals(_ state: CollaborationState) -> [CollaborationState.Goal] {
        // A finished goal lives in Finished together with its record, not as a stale card here.
        let ordered = state.activeGoals + state.goals.filter { $0.status != "active" && !state.hasRecord($0) }
        return ordered.filter { selectedGoalID.isEmpty || $0.id == selectedGoalID }
    }

    /// One goal and everything that belongs to it, in one card.
    private func goalCard(_ goal: CollaborationState.Goal, state: CollaborationState) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(goal.title.strippedEmojis).font(InkType.subhead)
                .fixedSize(horizontal: false, vertical: true)
            Text(goal.outcome.strippedEmojis).font(InkType.body)
                .fixedSize(horizontal: false, vertical: true)
            Text("Your goal · " + goal.status + " · " + goal.priority + " attention").font(InkType.meta).foregroundStyle(Theme.inkSoft)
            VStack(alignment: .leading, spacing: 0) {
                InkRule(opacity: 0.6)
                NavigationLink { CollaborationEditor(kind: .goal(goal)) } label: {
                    InkLinkLabel(title: "Edit goal or change direction", small: true)
                }
                .buttonStyle(.inkLink)
                .accessibilityIdentifier("collaboration.editGoal." + goal.id)
                if goal.status == "active" {
                    InkRule(opacity: 0.6)
                    NavigationLink { CloseGoalView(goal: goal) } label: {
                        InkLinkLabel(title: "Close this goal", small: true)
                    }
                    .buttonStyle(.inkLink)
                    .accessibilityIdentifier("collaboration.closeGoal." + goal.id)
                }
                InkRule(opacity: 0.6)
            }
            GoalWorkProgress(goal: goal, state: state)
            let results = state.results.filter { $0.agreement_id.isEmpty && $0.goal_id == goal.id }
            ForEach(Array(results.enumerated()), id: \.element.id) { index, result in
                if index > 0 { InkRule(opacity: 0.6) }
                NavigationLink { CollaborationResultView(result: result) } label: {
                    InkLinkLabel(title: result.title,
                                 detail: result.status == "blocked" ? "Blocked · your input may help" : "Prepared by Alicia · awaiting your review")
                }
                .buttonStyle(.inkLink)
                .accessibilityIdentifier("collaboration.result." + result.id)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 16, radius: 16)
        .id(goal.id)
    }
}

/// Sheet root: her title and CLOSE. Pushed (from Context enrichment): her BACK.
/// Both end in the same `dismiss()` the old Close button called.
private struct TogetherChrome: ViewModifier {
    let pushed: Bool
    let close: () -> Void
    func body(content: Content) -> some View {
        if pushed { content.inkPushedPage("Together") }
        else { content.inkSheetPage("Together", close: close) }
    }
}

private struct ImpulseResearchStatusCard: View {
    let research: ImpulseResearch
    private var status: ImpulseResearch.Status { research.status }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            InkKicker(text: "Jev impulse study")
            Text(status.active ? "Active · shadow only" : status.enabled ? "Enabled · observer unavailable" : "Paused")
                .font(InkType.linkSmall.weight(.semibold)).accessibilityIdentifier("impulseResearch.status")
            Text("\(status.observations) observations · \(status.labeled) labeled · \(status.failures) failed or unavailable")
                .font(InkType.meta).foregroundStyle(Theme.inkSoft)
            Text("Individual Jev judgments stay hidden until your label is saved.")
                .font(InkType.meta).foregroundStyle(Theme.inkSoft)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ImpulseResearchView: View {
    @Environment(AppStore.self) private var store
    private var shared: CollaborationStore { store.collaboration }
    private var research: ImpulseResearch? { shared.state?.impulse_research }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("A blind check on Alicia's impulse to speak")
                    .font(InkType.subhead)
                Text("First judge whether the communication was useful and whether its stance fit. Only after the save is confirmed does Aves reveal what Jev recommended. Jev remains an observer; it does not decide whether Alicia contacts you.")
                    .font(.callout)
                if let research {
                    ImpulseResearchStatusCard(research: research)
                    if research.items.isEmpty {
                        InkNotice(text: "No eligible observations yet. The active status above is the audit receipt; this list grows only when Alicia forms or sends an eligible return.")
                    }
                    ForEach(research.items) { item in
                        ImpulseResearchItemView(itemID: item.id)
                    }
                } else {
                    InkNotice(text: "The research status could not be loaded. No judgment has been inferred from this screen.", kind: .error)
                }
                CollaborationSaveStatus()
                Button("Refresh study") { Task { await shared.load() } }
                    .buttonStyle(.inkQuiet)
                    .accessibilityIdentifier("impulseResearch.refresh")
            }.frame(maxWidth: .infinity, alignment: .leading).padding(22)
        }
        .background(Theme.paper).foregroundStyle(Theme.ink).tint(Theme.ink)
        .inkPushedPage("Impulse study")
        .task { await shared.load() }
    }
}

private struct ImpulseResearchItemView: View {
    @Environment(AppStore.self) private var store
    let itemID: String

    private var shared: CollaborationStore { store.collaboration }
    private var usefulness: String { shared.impulseDraft(itemID, field: "usefulness") }
    private var stance: String { shared.impulseDraft(itemID, field: "stance") }
    private var item: ImpulseResearch.Item? {
        shared.state?.impulse_research?.items.first { $0.id == itemID }
    }
    private let usefulnessChoices = [
        ("useful_now", "Useful now"), ("useful_later", "Useful later"),
        ("not_useful", "Not useful"), ("wrong_connection", "Wrong connection"),
        ("unwanted_interruption", "Unwanted interruption"),
    ]
    private let stanceChoices = [("stance_fit", "Stance fit"), ("stance_mismatch", "Stance missed")]

    var body: some View {
        if let item {
            VStack(alignment: .leading, spacing: 13) {
                InkKicker(text: item.source == "circulation" ? "Sent communication" : "Candidate communication")
                Text(item.title.strippedEmojis).font(InkType.subhead)
                Text(item.text.strippedEmojis).font(InkType.body).textSelection(.enabled)
                Text(String(item.observed_at.prefix(19)).replacingOccurrences(of: "T", with: " · "))
                    .font(InkType.meta).foregroundStyle(Theme.inkSoft)
                if item.labeled, let feedback = item.feedback {
                    Text("Your saved label").font(.headline)
                    Text(label(feedback.usefulness) + " · " + label(feedback.stance))
                        .accessibilityIdentifier("impulseResearch.saved." + item.id)
                    InkRule(opacity: 0.6)
                    ImpulseResearchRevealView(item: item)
                } else {
                    Text("1. Was this communication useful?").font(.headline)
                    ImpulseChoiceList(choices: usefulnessChoices, selection: usefulness,
                                      identifier: "impulseResearch.usefulness.") { value in
                        shared.setImpulseDraft(item.id, field: "usefulness", value: value)
                    }
                    Text("2. Did Alicia's stance fit?").font(.headline)
                    ImpulseChoiceList(choices: stanceChoices, selection: stance,
                                      identifier: "impulseResearch.stance.") { value in
                        shared.setImpulseDraft(item.id, field: "stance", value: value)
                    }
                    Button("Save my judgment, then reveal Jev") {
                        let mutation = CollaborationMutation(action: "impulse_feedback",
                            candidate_id: item.id, source: item.source,
                            trace_state_hash: item.state_hash, usefulness: usefulness, stance: stance)
                        Task { await shared.submit(mutation) }
                    }
                    .buttonStyle(.inkPrimary)
                    .disabled(!shared.canEdit || usefulness.isEmpty || stance.isEmpty)
                    .accessibilityIdentifier("impulseResearch.save." + item.id)
                    Text("The model answer is not in this item until the server confirms your label.")
                        .font(InkType.meta).foregroundStyle(Theme.inkSoft)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card(padding: 16, radius: 16)
        }
    }

    private func label(_ raw: String) -> String {
        switch raw {
        case "useful_now": "Useful now"
        case "useful_later": "Useful later"
        case "not_useful": "Not useful"
        case "wrong_connection": "Wrong connection"
        case "unwanted_interruption": "Unwanted interruption"
        case "stance_fit": "Stance fit"
        case "stance_mismatch": "Stance missed"
        default: raw.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
}

private struct ImpulseChoiceList: View {
    let choices: [(String, String)]
    let selection: String
    let identifier: String
    let onSelect: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(choices, id: \.0) { value, title in
                Button {
                    onSelect(value)
                } label: {
                    HStack {
                        Text(title)
                        Spacer()
                        Text(selection == value ? "Selected" : "Choose")
                            .font(.caption).foregroundStyle(Theme.inkSoft)
                    }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .background(selection == value ? Theme.ink.opacity(0.10) : Theme.ink.opacity(0.035),
                            in: RoundedRectangle(cornerRadius: 10))
                .simultaneousGesture(TapGesture().onEnded { onSelect(value) })
                .accessibilityIdentifier(identifier + value)
            }
        }
    }
}

private struct ImpulseResearchRevealView: View {
    let item: ImpulseResearch.Item
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Jev's hidden judgment").font(.headline)
            if let reveal = item.reveal, reveal.outcome == "ok" {
                Text("Expression · " + (reveal.suggested_expression ?? "Unavailable").capitalized)
                if let confidence = reveal.suggested_expression_confidence {
                    Text("Expression confidence · \(Int((confidence * 100).rounded()))%")
                        .font(.caption)
                }
                Text("Stance · " + (reveal.stance ?? "Unavailable").capitalized)
                InkDisclosure("Inspect the typed answers") {
                    ForEach(reveal.answers.keys.sorted(), id: \.self) { key in
                        if let answer = reveal.answers[key] {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(key.replacingOccurrences(of: "_", with: " ").capitalized).font(.caption)
                                Text(answerText(answer)).font(.callout)
                            }
                        }
                    }
                }
                Text(reveal.model + " · " + reveal.question_version)
                    .font(InkType.meta).foregroundStyle(Theme.inkSoft)
            } else if let reveal = item.reveal {
                Text("No valid Jev judgment was available for this observation (\(reveal.reason_code ?? reveal.outcome)).")
                    .font(.callout)
            } else {
                InkNotice(text: "Your label is saved, but the reveal receipt is unavailable. Refresh before drawing a comparison.")
            }
            Text("Research evidence only. This answer did not change delivery.")
                .font(.caption).foregroundStyle(Theme.inkSoft)
        }.accessibilityIdentifier("impulseResearch.reveal." + item.id)
    }

    private func answerText(_ answer: ImpulseResearch.Answer) -> String {
        if let choice = answer.choice { return choice.capitalized + confidence(answer.confidence) }
        if let score = answer.score { return String(format: "%.2f", score) + confidence(answer.confidence) }
        if let probability = answer.noul { return "Yes probability \(Int((probability * 100).rounded()))%" }
        return "Unavailable"
    }
    private func confidence(_ value: Double?) -> String {
        guard let value else { return "" }
        return " · \(Int((value * 100).rounded()))% confidence"
    }
}

private struct CollaborationConnectionView: View {
    @Environment(AppStore.self) private var store
    let id: String
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let connection = store.collaboration.state?.connections.first(where: { $0.id == id }) {
                    Text(connection.title.strippedEmojis).font(InkType.subhead)
                        .fixedSize(horizontal: false, vertical: true)
                    VStack(alignment: .leading, spacing: 8) {
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 8) { connectionActions(connection) }
                            VStack(alignment: .leading, spacing: 8) { connectionActions(connection) }
                        }
                        if connection.status == "dismissed" { InkNotice(text: "Dismissed") }
                        Text("Using a connection keeps it in view. Commit only when you choose an action.")
                            .font(InkType.meta).foregroundStyle(Theme.inkSoft)
                        CollaborationSaveStatus()
                    }

                    InkSection(kicker: "The connection") {
                        Text(connection.claim.strippedEmojis).font(.system(size: 19, design: .serif))
                        Text(connection.why_now.strippedEmojis).font(InkType.body)
                        NaturalReviewButton(title: connection.title, text: connection.claim + "\n" + connection.why_now)
                        if !connection.question.isEmpty { Text(connection.question.strippedEmojis).font(.system(size: 19, design: .serif)).italic() }
                        InkDisclosure("Evidence and your words") {
                            if !connection.origin_text.isEmpty { Text(connection.origin_text).font(InkType.body).textSelection(.enabled) }
                            ForEach(Array(connection.evidence.enumerated()), id: \.element.id) { index, evidence in
                                if index > 0 { InkRule(opacity: 0.6) }
                                NavigationLink { CollaborationEvidenceView(evidence: evidence, connectionID: id) } label: {
                                    InkLinkLabel(title: evidence.title, small: true)
                                }.buttonStyle(.inkLink)
                            }
                        }
                    }
                    InkSection(kicker: "Decide", spacing: 4) {
                        NavigationLink { CollaborationEditor(kind: .commit(connection)) } label: {
                            InkLinkLabel(title: "Consider a commitment", detail: "What we will try, and when to review it")
                        }
                        .buttonStyle(.inkLink)
                        .accessibilityIdentifier("collaboration.commitEditor")
                    }
                } else { InkNotice(text: "This connection is unavailable. Refresh shared focus to try again.") }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(22)
        }
        .background(Theme.paper).foregroundStyle(Theme.ink).tint(Theme.ink)
        .inkPushedPage("The connection")
    }
    @ViewBuilder private func connectionActions(_ connection: CollaborationState.Connection) -> some View {
        ForEach([("Use this", "use"), ("Clarify", "clarify")], id: \.1) { label, verdict in
            WorkReviewChoice(title: label, selected: verdict == "use" && connection.status == "used") {
                verdictAction(connection, verdict)
            }.disabled(!store.collaboration.canEdit).accessibilityIdentifier("collaboration." + verdict)
        }
        Button("Dismiss") { verdictAction(connection, "dismiss") }
            .buttonStyle(.inkDestructiveCompact)
            .accessibilityAddTraits(connection.status == "dismissed" ? .isSelected : [])
            .disabled(!store.collaboration.canEdit).accessibilityIdentifier("collaboration.dismiss")
    }
    private func verdictAction(_ connection: CollaborationState.Connection, _ verdict: String) {
        Task { await store.collaboration.submit(CollaborationMutation(action: "connection", expected_revision: connection.revision, connection_id: id, verdict: verdict)) }
    }
}

private struct CollaborationAgreementView: View {
    @Environment(AppStore.self) private var store
    let id: String
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let agreement = store.collaboration.state?.agreements.first(where: { $0.id == id }) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(agreement.action.strippedEmojis).font(InkType.subhead)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(agreement.owner.capitalized + " · " + agreement.status).font(InkType.meta).foregroundStyle(Theme.inkSoft)
                        Text("Return when: " + agreement.review_condition).font(InkType.body)
                        if let time = agreement.review_at { Text(time).font(InkType.meta).foregroundStyle(Theme.inkSoft) }
                    }
                    if !agreement.outcome.isEmpty {
                        InkSection(kicker: "Your reported outcome") { Text(agreement.outcome).font(InkType.body) }
                    }
                    NaturalReviewButton(title: "Our agreement", text: agreement.action + "\n" + agreement.review_condition)
                    NavigationLink { CollaborationEditor(kind: .agreement(agreement)) } label: {
                        InkLinkLabel(title: "Update outcome or change course")
                    }
                    .buttonStyle(.inkLink)
                    .accessibilityIdentifier("collaboration.outcomeEditor")
                    ForEach(store.collaboration.state?.results.filter { $0.agreement_id == id } ?? []) { result in
                        InkRule()
                        WorkReviewContent(result: result)
                    }
                }
                CollaborationSaveStatus()
            }.frame(maxWidth: .infinity, alignment: .leading).padding(22)
        }
        .background(Theme.paper).foregroundStyle(Theme.ink).tint(Theme.ink)
        .inkPushedPage("Our agreement")
    }
}

struct CollaborationEvidenceView: View {
    @Environment(AppStore.self) private var store
    let evidence: CollaborationState.Evidence
    var connectionID = ""
    var resultID = ""
    @State private var source: ContextSource?
    @State private var error = ""
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(evidence.title).font(InkType.subhead)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(evidence.kind.replacingOccurrences(of: "_", with: " ") + " · " + evidence.relation).font(InkType.meta).foregroundStyle(Theme.inkSoft)
                }
                Text(evidence.excerpt).font(InkType.body).textSelection(.enabled)
                NaturalReviewButton(title: evidence.title, text: evidence.excerpt)
                VStack(alignment: .leading, spacing: 4) {
                    Text(evidence.path).font(InkType.meta).foregroundStyle(Theme.inkSoft).textSelection(.enabled)
                    if evidence.line_start > 0 { Text("Captured lines \(evidence.line_start)–\(evidence.line_end)").font(InkType.meta).foregroundStyle(Theme.inkSoft) }
                    if !evidence.episode_id.isEmpty { Text(evidence.episode_id).font(InkType.meta).foregroundStyle(Theme.inkSoft) }
                }
                let track = store.tracks.first(where: { $0.label == evidence.episode_id })
                if (track != nil && !evidence.episode_id.isEmpty) || !evidence.recording_id.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        if let track, !evidence.episode_id.isEmpty {
                            Button {
                                store.collaboration.route = nil
                                store.selectedSection = .studio
                                store.workEpisode = track
                            } label: { InkLinkLabel(title: "Open episode in Studio") }
                            .buttonStyle(.inkLink)
                            .accessibilityIdentifier("workReview.openStudio")
                        }
                        if !evidence.recording_id.isEmpty {
                            if track != nil && !evidence.episode_id.isEmpty { InkRule(opacity: 0.6) }
                            NavigationLink { VoiceRecordingsView(recordingID: evidence.recording_id) } label: {
                                InkLinkLabel(title: "Review original voice")
                            }.buttonStyle(.inkLink)
                        }
                    }
                }
                if !evidence.path.isEmpty {
                    Button("Open current source") {
                        Task {
                            source = await store.collaboration.source(connectionID: connectionID, resultID: resultID, evidenceID: evidence.id)
                            if source == nil { error = "The current source is unavailable. The captured passage remains above." }
                        }
                    }
                    .buttonStyle(.inkSecondaryCompact)
                    .accessibilityLabel("Open current source")
                }
                if let source {
                    InkSection(kicker: "Current source") {
                        InkNotice(text: source.notice)
                        Text(source.text).font(InkType.body).textSelection(.enabled)
                        NaturalReviewButton(title: source.title, text: source.text)
                    }
                }
                InkNotice(text: error, kind: .error)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(22)
        }
        .background(Theme.paper).foregroundStyle(Theme.ink).tint(Theme.ink)
        .inkPushedPage("Evidence")
    }
}

enum CollaborationEditorKind {
    case goal(CollaborationState.Goal?)
    case commit(CollaborationState.Connection)
    case agreement(CollaborationState.Agreement)
    var key: String {
        switch self { case .goal(let g): return "goal." + (g?.id ?? "new")
        case .commit(let c): return "commit." + c.id
        case .agreement(let a): return "agreement." + a.id }
    }
}

struct CollaborationEditor: View {
    @Environment(AppStore.self) private var store
    let kind: CollaborationEditorKind
    /// A next-goal seed from a finished goal; only a starting title, he writes the rest.
    var suggestedTitle: String? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var outcome = ""
    @State private var why = ""
    @State private var priority = "normal"
    @State private var action = ""
    @State private var owner = "together"
    @State private var condition = ""
    @State private var status = "active"
    @State private var report = ""
    @State private var revision: Int?
    @State private var requestID = ""
    @FocusState private var editing: String?
    private var key: String { kind.key }
    private var draft: [String: String] { ["title":title,"outcome":outcome,"why":why,"priority":priority,"action":action,"owner":owner,"condition":condition,"status":status,"report":report,"revision": revision.map(String.init) ?? "","request_id":requestID] }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Group {
                switch kind {
                case .goal(let goal):
                    Text(goal == nil ? "Add a goal" : "Edit your goal").font(InkType.subhead)
                    field("Title", text: $title); field("What would a useful outcome look like?", text: $outcome); field("Why does it matter?", text: $why)
                    Picker("Attention", selection: $priority) { Text("Less").tag("less"); Text("Normal").tag("normal"); Text("More").tag("more") }.pickerStyle(.segmented)
                    if goal != nil { Picker("Goal state", selection: $status) { Text("Active").tag("active"); Text("Paused").tag("paused"); Text("Completed").tag("completed") } }
                    Button("Save my goal") { send(CollaborationMutation(action: "goal", expected_revision: revision, goal_id: goal?.id, title: title, outcome: outcome, why: why, priority: priority, status: status)) }
                        .buttonStyle(.inkPrimary)
                        .disabled(!valid(title) || !valid(outcome) || why.unicodeScalars.count > 2000).accessibilityIdentifier("collaboration.saveGoal")
                case .commit(let connection):
                    Text("Make this our agreement").font(InkType.subhead)
                    Text("What will we try, and what would make it worth revisiting?").font(.callout).foregroundStyle(Theme.inkSoft)
                    field("What will happen?", text: $action)
                    Picker("Who takes it forward?", selection: $owner) { Text("Me").tag("hector"); Text("Alicia").tag("alicia"); Text("Together").tag("together") }.pickerStyle(.segmented)
                    field("When should we review it?", text: $condition)
                    Button("Commit to this agreement") { send(CollaborationMutation(action: "commit", expected_revision: revision, connection_id: connection.id, action_text: action, owner: owner, review_condition: condition)) }
                        .buttonStyle(.inkPrimary)
                        .disabled(!valid(action) || !valid(condition)).accessibilityIdentifier("collaboration.confirmCommit")
                case .agreement(let agreement):
                    Text("What happened, or what changed?").font(InkType.subhead)
                    field("In your words", text: $report)
                    Button("Record an observation") { send(CollaborationMutation(action: "outcome", expected_revision: revision, agreement_id: agreement.id, text: report)) }
                        .buttonStyle(.inkSecondary)
                        .accessibilityLabel("Record an observation")
                        .disabled(!valid(report))
                    InkSection(kicker: "The agreement itself") {
                        Picker("Agreement state", selection: $status) { Text("Active").tag("active"); Text("Pause").tag("paused"); Text("Complete").tag("completed"); Text("Change course / cancel").tag("cancelled") }
                        Text("Complete needs your account of the outcome. Change course keeps this agreement's history; you can then revise the goal or make a new agreement.").font(InkType.meta).foregroundStyle(Theme.inkSoft)
                        Button("Save agreement update") { send(CollaborationMutation(action: "agreement", expected_revision: revision, agreement_id: agreement.id, status: status, text: report)) }
                            .buttonStyle(.inkPrimary)
                            .disabled(report.unicodeScalars.count > 2000 || (status == "completed" && !valid(report)))
                    }
                }
                }.disabled(!store.collaboration.canEdit)
                CollaborationSaveStatus()
                VStack(alignment: .leading, spacing: 4) {
                    Text("Your draft stays until the save is confirmed. To revise a changed record, reload its current version first.")
                        .font(InkType.meta).foregroundStyle(Theme.inkSoft)
                    Button("Reload current version") {
                        editing = nil
                        Task { if await store.collaboration.reloadDraft(key) { seed(force: true) } }
                    }
                    .buttonStyle(.inkQuiet)
                    .disabled(!store.collaboration.canEdit)
                }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(22)
        }
        .background(Theme.paper).foregroundStyle(Theme.ink).tint(Theme.ink)
        .inkPushedPage("Your decision")
            .scrollDismissesKeyboard(.interactively)
            .toolbar { ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done writing") { editing = nil } } }
            .task { if store.collaboration.canEdit { store.collaboration.error = "" }; seed() }
            .onChange(of: draft) { _, value in store.collaboration.saveDraft(value, name: key) }
            .onChange(of: store.collaboration.lastConfirmedID) { _, id in
                if id == requestID { store.collaboration.clearDraft(key); dismiss() }
            }
    }
    private func field(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(InkType.linkSmall.weight(.semibold))
            TextField(label, text: text, axis: .vertical).lineLimit(2...8).focused($editing, equals: label)
                .inkField().accessibilityIdentifier("collaboration.field." + label)
            lengthNotice(text.wrappedValue)
        }
    }
    private func send(_ change: CollaborationMutation) {
        editing = nil
        requestID = change.event_id
        store.collaboration.saveDraft(draft, name: key)
        Task { await store.collaboration.submit(change, draftName: key) }
    }
    private func seed(force: Bool = false) {
        let state = store.collaboration.state
        requestID = ""
        switch kind {
        case .goal(let old):
            let g = state?.goals.first(where: { $0.id == old?.id }) ?? old
            title = g?.title ?? suggestedTitle ?? ""; outcome = g?.outcome ?? ""; why = g?.why ?? ""; priority = g?.priority ?? "normal"; status = g?.status ?? "active"; revision = g?.revision
        case .commit(let old):
            let c = state?.connections.first(where: { $0.id == old.id }) ?? old
            action = c.proposed_action; owner = c.action_owner; condition = c.review_condition; revision = c.revision
        case .agreement(let old):
            let a = state?.agreements.first(where: { $0.id == old.id }) ?? old
            status = a.status; report = a.outcome; revision = a.revision
        }
        if !force, let saved = store.collaboration.draft(key) {
            requestID = saved["request_id"] ?? ""
            if let savedRevision = saved["revision"] { revision = Int(savedRevision) }
            title = saved["title"] ?? title; outcome = saved["outcome"] ?? outcome; why = saved["why"] ?? why
            priority = saved["priority"] ?? priority; status = saved["status"] ?? status; action = saved["action"] ?? action
            owner = saved["owner"] ?? owner; condition = saved["condition"] ?? condition; report = saved["report"] ?? report
        }
    }
}

struct NaturalReviewButton: View {
    @Environment(AppStore.self) private var store
    let title, text: String
    private var item: Readable { Readable(title: title, body: text, kind: "collaboration_review") }
    var body: some View {
        ListenLine(item: item, label: "READ ALOUD")
    }
}

/// The store reports a confirmed save as "Saved." in the same field as its
/// failures; only the drawing distinguishes them (ink vs seal red).
struct CollaborationSaveStatus: View {
    @Environment(AppStore.self) private var store
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            let message = store.collaboration.error
            if !message.isEmpty {
                InkNotice(text: message, kind: message == "Saved." ? .success : .error)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("collaboration.status")
            }
            if !store.collaboration.pending.isEmpty {
                InkNotice(text: "Your exact change is saved on this phone until Alicia confirms it.")
                Button("Retry pending change") { Task { await store.collaboration.retry() } }
                    .buttonStyle(.inkQuiet)
                    .disabled(store.collaboration.busy)
            }
        }
    }
}
private func valid(_ text: String) -> Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && text.unicodeScalars.count <= 2000 }
@ViewBuilder private func lengthNotice(_ text: String) -> some View {
    if text.unicodeScalars.count > 2000 { InkNotice(text: "Keep this under 2,000 characters. Your draft is retained.", kind: .error) }
}
