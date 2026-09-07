import SwiftUI

struct CollaborationSummary: View {
    @Environment(AppStore.self) private var store
    var body: some View {
        Button { store.collaboration.route = CollaborationRoute() } label: {
            VStack(alignment: .leading, spacing: 8) {
                Text("OUR SHARED FOCUS").font(.caption.monospaced()).tracking(1.2)
                if let state = store.collaboration.state {
                    if let goal = state.goals.first(where: { $0.status == "active" }) {
                        Text(goal.title.strippedEmojis).font(.system(size: 23, design: .serif))
                        Text(goal.outcome.strippedEmojis).font(.subheadline).lineLimit(2)
                    } else { Text("What would you like us to work toward?").font(.system(size: 21, design: .serif)) }
                    if let connection = state.connections.first(where: { $0.status == "proposed" }) {
                        Text(connection.title.strippedEmojis).font(.subheadline).italic().lineLimit(2)
                    } else if let agreement = state.agreements.first(where: { $0.status == "active" }) {
                        Text("Agreed: " + agreement.action.strippedEmojis).font(.subheadline).lineLimit(2)
                    }
                    if state.pending { Text("Revisiting the evidence…").font(.caption) }
                } else { Text("Open goals, connections and agreements").font(.subheadline) }
                Text("OPEN TOGETHER").font(.caption.monospaced())
            }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .padding(.vertical, 12)
        }.buttonStyle(.plain).accessibilityIdentifier("collaboration.open")
    }
}

struct CollaborationView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var target = CollaborationRoute()
    @State private var viewed = false
    @State private var openTarget = false
    @State private var signal = ""
    @State private var signalRequestID = ""
    @FocusState private var writing: Bool
    private var shared: CollaborationStore { store.collaboration }

    var body: some View {
        ScrollViewReader { scroll in
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("What we're working toward").font(.system(size: 29, design: .serif))
                    if let state = shared.state {
                        if !target.candidateID.isEmpty {
                            Text("Returning to the exact idea you opened.").font(.caption)
                            if let candidate = state.followup, candidate.id == target.candidateID {
                                Text(candidate.reason).font(.callout)
                            }
                        }
                        if state.pending { Text("Alicia is revisiting the evidence. Prepared work will appear here.").font(.callout) }
                        if !state.error.isEmpty { Text(state.error).font(.callout).foregroundStyle(Theme.rose) }
                        ForEach(state.goals) { goal in
                            VStack(alignment: .leading, spacing: 9) {
                                Text(goal.title.strippedEmojis).font(.title2)
                                Text(goal.outcome.strippedEmojis)
                                Text("Your goal · " + goal.status + " · " + goal.priority + " attention").font(.caption).foregroundStyle(Theme.inkSoft)
                                NavigationLink("Edit goal or change direction") { CollaborationEditor(kind: .goal(goal)) }
                                ForEach(state.results.filter { $0.agreement_id.isEmpty && $0.goal_id == goal.id }) { result in
                                    NavigationLink { CollaborationResultView(result: result) } label: {
                                        VStack(alignment: .leading, spacing: 6) {
                                            Text(result.title.strippedEmojis).font(.headline)
                                            Text(result.status == "blocked" ? "Blocked · your input may help" : "Prepared by Alicia · awaiting your review").font(.caption)
                                        }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                    }.accessibilityIdentifier("collaboration.result." + result.id)
                                }
                            }.id(goal.id)
                        }
                        NavigationLink("Set a goal in your words") { CollaborationEditor(kind: .goal(nil)) }
                            .accessibilityIdentifier("collaboration.newGoal")
                        if !state.connections.isEmpty {
                            Divider()
                            Text("Connections to consider").font(.title2)
                            ForEach(state.connections.filter { $0.status != "dismissed" || $0.id == target.connectionID }) { connection in
                                NavigationLink { CollaborationConnectionView(id: connection.id) } label: {
                                    VStack(alignment: .leading, spacing: 7) {
                                        Text(connection.title.strippedEmojis).font(.headline)
                                        Text(connection.why_now.strippedEmojis).font(.callout).lineLimit(3)
                                        Text(connection.status == "used" ? "In use · no commitment implied" : connection.status == "dismissed" ? "Dismissed" : "Alicia proposes · inspect and decide").font(.caption)
                                    }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                }.id(connection.id).accessibilityIdentifier("collaboration.connection." + connection.id)
                            }
                        }
                        if !state.agreements.isEmpty {
                            Divider(); Text("What we agreed").font(.title2)
                            ForEach(state.agreements) { agreement in
                                NavigationLink { CollaborationAgreementView(id: agreement.id) } label: {
                                    VStack(alignment: .leading, spacing: 7) {
                                        Text(agreement.action.strippedEmojis).font(.headline)
                                        Text(agreement.owner.capitalized + " · " + agreement.status).font(.caption)
                                        if !agreement.outcome.isEmpty { Text(agreement.outcome.strippedEmojis).font(.callout).lineLimit(2) }
                                    }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                }.id(agreement.id).accessibilityIdentifier("collaboration.agreement." + agreement.id)
                            }
                        }
                        Divider()
                        DisclosureGroup("Your context right now") {
                            VStack(alignment: .leading, spacing: 14) {
                                Text("Tell Alicia how things are for you. Audio observations do not establish how you feel.").font(.caption)
                                ForEach(state.signals) { row in
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(row.title).font(.headline); Text(row.value)
                                        Text(row.source + " · " + row.observed_at).font(.caption)
                                        Text(row.notice).font(.caption).foregroundStyle(Theme.inkSoft)
                                        if let id = row.recording_id, !id.isEmpty {
                                            NavigationLink("Review original voice") { VoiceRecordingsView(recordingID: id) }
                                        }
                                    }
                                }
                                TextField("What should she know now?", text: $signal, axis: .vertical)
                                    .lineLimit(3...8).focused($writing).accessibilityIdentifier("collaboration.signal")
                                Button("Save my context") {
                                    writing = false
                                    let change = CollaborationMutation(action: "signal", priority: "more", text: signal)
                                    signalRequestID = change.event_id
                                    Task { await shared.submit(change, draftName: "signal") }
                                }.disabled(!shared.canEdit || !valid(signal))
                                lengthNotice(signal)
                            }.padding(.top, 12)
                        }
                        DisclosureGroup("When Alicia returns") {
                            VStack(alignment: .leading, spacing: 14) {
                                Text("Returns follow a relevant connection, agreed review or prepared result. There is no daily quota. This iPhone schedules them when it syncs, during 9am–7pm local time. Focus and notification permissions can silence them.").font(.callout)
                                if let next = state.followup { Text(next.message); Text(next.reason).font(.caption) }
                                Button("Stop returns on iPhone and Telegram") { Task { await shared.stopReturns() } }
                                    .accessibilityIdentifier("collaboration.stop")
                                Text(shared.locallyStopped ? "Stopped on this phone. Any pending server change stays queued below." : state.followups_enabled ? "iPhone returns allowed." : "iPhone returns paused.").font(.caption)
                                Button("Allow iPhone returns") {
                                    Task { await shared.submit(CollaborationMutation(action: "settings", followups_enabled: true, telegram_returns_enabled: state.telegram_returns_enabled)) }
                                }.disabled(!shared.canEdit)
                                Button(state.telegram_returns_enabled ? "Pause Telegram returns" : "Allow Telegram returns") {
                                    Task { await shared.submit(CollaborationMutation(action: "settings", followups_enabled: state.followups_enabled && !shared.locallyStopped, telegram_returns_enabled: !state.telegram_returns_enabled)) }
                                }.disabled(!shared.canEdit)
                                Button("iPhone notification permission") { ProactiveNotifier.requestPermission() }
                            }.padding(.top, 12)
                        }
                        Button("Revisit the evidence") { Task { await shared.submit(CollaborationMutation(action: "refresh")) } }
                            .disabled(!shared.canEdit)
                    } else {
                        Text("Connect to Alicia to see the shared focus. Your saved drafts remain here.")
                    }
                    CollaborationSaveStatus()
                    Button("Refresh shared focus") { Task { await shared.load() } }
                }.padding(22)
            }
            .task {
                signal = shared.draft("signal")?["text"] ?? ""
                signalRequestID = shared.draft("signal")?["request_id"] ?? ""
                await shared.load()
                let id = !target.agreementID.isEmpty ? target.agreementID : !target.connectionID.isEmpty ? target.connectionID : target.goalID
                if !id.isEmpty { scroll.scrollTo(id, anchor: .top) }
                if !viewed {
                    if shared.state?.agreements.contains(where: { $0.id == target.agreementID }) == true || shared.state?.connections.contains(where: { $0.id == target.connectionID }) == true { openTarget = true }
                    else { await shared.viewed(target); viewed = true }
                }
            }
        }
        .onChange(of: signal) { _, text in shared.saveDraft(["text": text,"request_id": signalRequestID], name: "signal") }
        .onChange(of: shared.lastConfirmedID) { _, id in
            if id == signalRequestID { signal = ""; signalRequestID = ""; shared.clearDraft("signal") }
        }
        .background(Theme.paper).foregroundStyle(Theme.ink)
        .navigationTitle("Together").navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $openTarget) {
            Group {
                if !target.agreementID.isEmpty { CollaborationAgreementView(id: target.agreementID) }
                else { CollaborationConnectionView(id: target.connectionID) }
            }.task { if !viewed { await shared.viewed(target); viewed = true } }
        }
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Close") { dismiss() } } }
        .scrollDismissesKeyboard(.interactively)
        .buttonStyle(CollaborationButtonStyle())
    }
}

private struct CollaborationConnectionView: View {
    @Environment(AppStore.self) private var store
    let id: String
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let connection = store.collaboration.state?.connections.first(where: { $0.id == id }) {
                    Text(connection.title.strippedEmojis).font(.title)
                    Text(connection.claim.strippedEmojis).font(.title3)
                    Text(connection.why_now.strippedEmojis)
                    LocalReviewButton(title: connection.title, text: connection.claim + "\n" + connection.why_now)
                    if !connection.question.isEmpty { Text(connection.question.strippedEmojis).font(.title3).italic() }
                    DisclosureGroup("Evidence and your words") {
                        VStack(alignment: .leading, spacing: 18) {
                            if !connection.origin_text.isEmpty { Text(connection.origin_text).textSelection(.enabled) }
                            ForEach(connection.evidence) { evidence in
                                NavigationLink(evidence.title) { CollaborationEvidenceView(evidence: evidence, connectionID: id) }
                            }
                        }.padding(.top, 12)
                    }
                    Text("Using a connection keeps it in view. Only your explicit agreement creates a commitment.").font(.caption)
                    ForEach([("Use this", "use"), ("Clarify this", "clarify"), ("Dismiss this", "dismiss")], id: \.1) { label, verdict in
                        Button(label) { Task { await store.collaboration.submit(CollaborationMutation(action: "connection", expected_revision: connection.revision, connection_id: id, verdict: verdict)) } }
                            .disabled(!store.collaboration.canEdit).accessibilityIdentifier("collaboration." + verdict)
                    }
                    NavigationLink("Consider a commitment") { CollaborationEditor(kind: .commit(connection)) }
                        .accessibilityIdentifier("collaboration.commitEditor")
                    CollaborationSaveStatus()
                } else { Text("This connection is unavailable. Refresh shared focus to try again.") }
            }.padding(22)
        }.background(Theme.paper).navigationTitle("The connection").buttonStyle(CollaborationButtonStyle())
    }
}

private struct CollaborationAgreementView: View {
    @Environment(AppStore.self) private var store
    let id: String
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let agreement = store.collaboration.state?.agreements.first(where: { $0.id == id }) {
                    Text(agreement.action.strippedEmojis).font(.title2)
                    Text(agreement.owner.capitalized + " · " + agreement.status).font(.caption)
                    Text("Return when: " + agreement.review_condition)
                    if let time = agreement.review_at { Text(time).font(.caption) }
                    if !agreement.outcome.isEmpty { Text("Your reported outcome").font(.headline); Text(agreement.outcome) }
                    LocalReviewButton(title: "Our agreement", text: agreement.action + "\n" + agreement.review_condition)
                    NavigationLink("Update outcome or change course") { CollaborationEditor(kind: .agreement(agreement)) }
                        .accessibilityIdentifier("collaboration.outcomeEditor")
                    ForEach(store.collaboration.state?.results.filter { $0.agreement_id == id } ?? []) { result in
                        Divider(); Text(result.title).font(.title2)
                        Text(result.status == "blocked" ? "Blocked · your input may help" : "Prepared by Alicia · awaiting your review").font(.caption)
                        Text(result.body).textSelection(.enabled)
                        LocalReviewButton(title: result.title, text: result.body)
                        ForEach(result.evidence) { evidence in
                            NavigationLink(evidence.title) { CollaborationEvidenceView(evidence: evidence, resultID: result.id) }
                        }
                    }
                }
                CollaborationSaveStatus()
            }.padding(22)
        }.background(Theme.paper).navigationTitle("Our agreement").buttonStyle(CollaborationButtonStyle())
    }
}

private struct CollaborationResultView: View {
    let result: CollaborationState.Result
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(result.title.strippedEmojis).font(.title2)
                Text(result.status == "blocked" ? "Blocked · your input may help" : "Prepared by Alicia · awaiting your review").font(.caption)
                Text("Prepared toward your saved goal. This is work to inspect, not an agreed action or a verified outcome.").font(.callout)
                Text(result.body.strippedEmojis).textSelection(.enabled)
                LocalReviewButton(title: result.title, text: result.body)
                ForEach(result.evidence) { evidence in
                    NavigationLink(evidence.title) { CollaborationEvidenceView(evidence: evidence, resultID: result.id) }
                }
            }.padding(22)
        }.background(Theme.paper).navigationTitle("Prepared work").buttonStyle(CollaborationButtonStyle())
    }
}

private struct CollaborationEvidenceView: View {
    @Environment(AppStore.self) private var store
    let evidence: CollaborationState.Evidence
    var connectionID = ""
    var resultID = ""
    @State private var source: ContextSource?
    @State private var error = ""
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(evidence.title).font(.title2)
                Text(evidence.kind.replacingOccurrences(of: "_", with: " ") + " · " + evidence.relation).font(.caption)
                Text(evidence.excerpt).textSelection(.enabled)
                LocalReviewButton(title: evidence.title, text: evidence.excerpt)
                Text(evidence.path).font(.caption).textSelection(.enabled)
                if evidence.line_start > 0 { Text("Captured lines \(evidence.line_start)–\(evidence.line_end)").font(.caption) }
                if !evidence.episode_id.isEmpty { Text(evidence.episode_id).font(.caption) }
                if !evidence.recording_id.isEmpty {
                    NavigationLink("Review original voice") { VoiceRecordingsView(recordingID: evidence.recording_id) }
                }
                if !evidence.path.isEmpty {
                    Button("Open current source") {
                        Task {
                            source = await store.collaboration.source(connectionID: connectionID, resultID: resultID, evidenceID: evidence.id)
                            if source == nil { error = "The current source is unavailable. The captured passage remains above." }
                        }
                    }
                }
                if let source { Text(source.notice).font(.caption); Text(source.text).textSelection(.enabled); LocalReviewButton(title: source.title, text: source.text) }
                if !error.isEmpty { Text(error).font(.caption) }
            }.padding(22)
        }.background(Theme.paper).navigationTitle("Evidence").buttonStyle(CollaborationButtonStyle())
    }
}

private enum CollaborationEditorKind {
    case goal(CollaborationState.Goal?)
    case commit(CollaborationState.Connection)
    case agreement(CollaborationState.Agreement)
    var key: String {
        switch self { case .goal(let g): return "goal." + (g?.id ?? "new")
        case .commit(let c): return "commit." + c.id
        case .agreement(let a): return "agreement." + a.id }
    }
}

private struct CollaborationEditor: View {
    @Environment(AppStore.self) private var store
    let kind: CollaborationEditorKind
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
                    Text("A goal in your words").font(.title2)
                    field("Title", text: $title); field("What would a useful outcome look like?", text: $outcome); field("Why does it matter?", text: $why)
                    Picker("Attention", selection: $priority) { Text("Less").tag("less"); Text("Normal").tag("normal"); Text("More").tag("more") }.pickerStyle(.segmented)
                    if goal != nil { Picker("Goal state", selection: $status) { Text("Active").tag("active"); Text("Paused").tag("paused"); Text("Completed").tag("completed") } }
                    Button("Save my goal") { send(CollaborationMutation(action: "goal", expected_revision: revision, goal_id: goal?.id, title: title, outcome: outcome, why: why, priority: priority, status: status)) }
                        .disabled(!valid(title) || !valid(outcome) || why.unicodeScalars.count > 2000).accessibilityIdentifier("collaboration.saveGoal")
                case .commit(let connection):
                    Text("Make this our agreement").font(.title2)
                    Text("Edit Alicia's proposal before committing. This authorizes the stated internal work; it does not mark the outcome achieved.").font(.callout)
                    field("What will happen?", text: $action)
                    Picker("Who takes it forward?", selection: $owner) { Text("Me").tag("hector"); Text("Alicia").tag("alicia"); Text("Together").tag("together") }.pickerStyle(.segmented)
                    field("When should we review it?", text: $condition)
                    Button("Commit to this agreement") { send(CollaborationMutation(action: "commit", expected_revision: revision, connection_id: connection.id, action_text: action, owner: owner, review_condition: condition)) }
                        .disabled(!valid(action) || !valid(condition)).accessibilityIdentifier("collaboration.confirmCommit")
                case .agreement(let agreement):
                    Text("What happened, or what changed?").font(.title2)
                    field("In your words", text: $report)
                    Button("Record an observation") { send(CollaborationMutation(action: "outcome", expected_revision: revision, agreement_id: agreement.id, text: report)) }.disabled(!valid(report))
                    Picker("Agreement state", selection: $status) { Text("Active").tag("active"); Text("Pause").tag("paused"); Text("Complete").tag("completed"); Text("Change course / cancel").tag("cancelled") }
                    Text("Complete needs your account of the outcome. Change course keeps this agreement's history; you can then revise the goal or make a new agreement.").font(.caption)
                    Button("Save agreement update") { send(CollaborationMutation(action: "agreement", expected_revision: revision, agreement_id: agreement.id, status: status, text: report)) }
                        .disabled(report.unicodeScalars.count > 2000 || (status == "completed" && !valid(report)))
                }
                }.disabled(!store.collaboration.canEdit)
                CollaborationSaveStatus()
                Text("Your draft stays until the save is confirmed. To revise a changed record, reload its current version first.").font(.caption)
                Button("Reload current version") { seed(force: true) }.disabled(!store.collaboration.canEdit)
            }.padding(22)
        }.background(Theme.paper).navigationTitle("Your decision")
            .scrollDismissesKeyboard(.interactively)
            .toolbar { ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done writing") { editing = nil } } }
            .buttonStyle(CollaborationButtonStyle())
            .task { if store.collaboration.canEdit { store.collaboration.error = "" }; seed() }
            .onChange(of: draft) { _, value in store.collaboration.saveDraft(value, name: key) }
            .onChange(of: store.collaboration.lastConfirmedID) { _, id in
                if id == requestID { store.collaboration.clearDraft(key); dismiss() }
            }
    }
    private func field(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.headline)
            TextField(label, text: text, axis: .vertical).lineLimit(2...8).focused($editing, equals: label)
                .padding(12).background(Theme.ink.opacity(0.04)).accessibilityIdentifier("collaboration.field." + label)
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
            title = g?.title ?? ""; outcome = g?.outcome ?? ""; why = g?.why ?? ""; priority = g?.priority ?? "normal"; status = g?.status ?? "active"; revision = g?.revision
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

private struct LocalReviewButton: View {
    @Environment(AppStore.self) private var store
    let title, text: String
    private var item: Readable { Readable(title: title, body: text, kind: "collaboration_review") }
    private var isCurrent: Bool { store.reader.current == item && store.reader.voice == .device }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(isCurrent ? store.reader.isSpeaking ? "Pause reading · device voice" : "Resume reading · device voice" : "Read aloud · device voice") {
                if !isCurrent { store.prepareForRecording() }
                store.reader.readLocally(item)
            }
            if store.reader.current?.kind == "collaboration_review" {
                Button("Stop reading") { store.reader.stop() }
            }
        }.font(.callout)
    }
}
private struct CollaborationSaveStatus: View {
    @Environment(AppStore.self) private var store
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !store.collaboration.error.isEmpty { Text(store.collaboration.error).font(.callout).accessibilityIdentifier("collaboration.status") }
            if !store.collaboration.pending.isEmpty {
                Text("Your exact change is saved on this phone until Alicia confirms it.").font(.caption)
                Button("Retry pending change") { Task { await store.collaboration.retry() } }.disabled(store.collaboration.busy)
            }
        }
    }
}
private struct CollaborationButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.frame(minHeight: 44).contentShape(Rectangle())
            .foregroundStyle(Theme.ink).opacity(configuration.isPressed ? 0.55 : 1)
    }
}
private func valid(_ text: String) -> Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && text.unicodeScalars.count <= 2000 }
@ViewBuilder private func lengthNotice(_ text: String) -> some View {
    if text.unicodeScalars.count > 2000 { Text("Keep this under 2,000 characters. Your draft is retained.").font(.caption).foregroundStyle(Theme.rose) }
}
