import SwiftUI

struct VoiceEnrichmentView: View {
    @Environment(AppStore.self) private var store
    let recordingID: String
    @State private var enrichment: VoiceEnrichment?
    @State private var loading = false
    @State private var error = ""
    @State private var olderPending: [VoiceEnrichmentFeedback] = []
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("What Alicia heard").font(.system(size: 24, design: .serif))
                Spacer()
                Button("Refresh") { Task { await refresh() } }.disabled(loading)
            }
            Text("Interpretations from your recording. These do not submit a message, change your words, or commit you to a goal.")
                .font(.caption).foregroundStyle(Theme.inkSoft)
            if let enrichment {
                Text(enrichment.analysis_state.replacingOccurrences(of: "_", with: " ").capitalized)
                    .font(.caption.monospaced())
                if let reason = enrichment.stale_reason ?? enrichment.ineligible_reason, !reason.isEmpty { Text(reason).font(.caption) }
                if let coverage = enrichment.coverage {
                    Text("\(Int(coverage.covered_seconds ?? 0)) of \(Int(coverage.recorded_seconds ?? 0)) seconds covered · ending \(coverage.tail_covered == true ? "included" : "not verified")")
                        .font(.caption)
                }
                ForEach(enrichment.notes ?? [], id: \.self) { Text($0).font(.callout).italic() }
                if let analysisID = enrichment.analysis_id {
                    ForEach(enrichment.insights ?? []) { insight in
                        VoiceInsightCard(recordingID: recordingID, analysisID: analysisID, itemID: insight.id,
                            text: insight.text, uncertainty: insight.uncertainty ?? "", evidence: insight.evidence ?? [],
                            goalIDs: insight.goal_ids ?? [], provisional: false,
                            canReview: enrichment.analysis_state == "ready")
                            .id(analysisID + ":" + insight.id)
                    }
                    ForEach(enrichment.candidate_answers ?? []) { answer in
                        VoiceInsightCard(recordingID: recordingID, analysisID: analysisID, itemID: answer.id,
                            text: answer.text, uncertainty: "", evidence: (answer.evidence ?? []).flatMap { reference -> [VoiceEnrichment.Evidence] in
                                switch reference {
                                case .passage(let passage): return [passage]
                                case .finding(let id): return enrichment.insights?.first(where: { $0.id == id })?.evidence ?? []
                                }
                            }, goalIDs: [answer.goal_id],
                            provisional: true, canReview: enrichment.analysis_state == "ready")
                            .id(analysisID + ":" + answer.id)
                    }
                }
                DisclosureGroup("Analysis passes") {
                    ForEach(Array((enrichment.pass_receipts ?? []).enumerated()), id: \.offset) { _, receipt in
                        VStack(alignment: .leading, spacing: 4) {
                            Text((receipt.pass ?? "Pass").capitalized).font(.callout)
                            Text([receipt.provider, receipt.model, receipt.status].compactMap { $0 }.joined(separator: " · ")).font(.caption)
                            if let id = receipt.response_id { Text(id).font(.caption2).textSelection(.enabled) }
                        }.padding(.vertical, 4)
                    }
                }
            } else if !loading { Text("No analysis is available yet.").font(.callout) }
            ForEach(olderPending, id: \.request_id) { feedback in
                EarlierVoiceFeedback(feedback: feedback)
            }
            if !error.isEmpty { Text(error).font(.caption) }
        }
        .task(id: recordingID) { await refresh() }
    }
    private func refresh() async {
        loading = true
        defer { loading = false }
        guard let response = await store.voiceDetail(recordingID) else { error = "Could not refresh analysis. Try again when connected."; return }
        enrichment = response.recordings.first(where: { $0.id == recordingID && !$0.deleted })?.enrichment
        olderPending = UserDefaults.standard.dictionaryRepresentation().compactMap { key, value in
            guard key.hasPrefix("alicia.voiceEnrichmentFeedback." + recordingID + "."), let data = value as? Data,
                  let saved = try? JSONDecoder().decode(VoiceEnrichmentFeedback.self, from: data),
                  saved.analysis_id != enrichment?.analysis_id else { return nil }
            return saved
        }.sorted { $0.request_id < $1.request_id }
        error = ""
    }
}

private struct VoiceInsightCard: View {
    @Environment(AppStore.self) private var store
    let recordingID, analysisID, itemID, text, uncertainty: String
    let evidence: [VoiceEnrichment.Evidence]
    let goalIDs: [String]
    let provisional, canReview: Bool
    @State private var note = ""
    @State private var goalRoute: CollaborationRoute?
    @State private var pending: VoiceEnrichmentFeedback?
    @State private var saving = false
    @State private var status = ""
    private var key: String { "alicia.voiceEnrichmentFeedback." + recordingID + "." + analysisID + "." + itemID }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if provisional { Text("POSSIBLE ANSWER · NOT YET YOUR AGREEMENT").font(.caption2.monospaced()) }
            Text(text).font(.system(size: 20, design: .serif)).textSelection(.enabled)
            if !uncertainty.isEmpty { Text(uncertainty).font(.caption).italic() }
            ForEach(goalIDs, id: \.self) { goalID in
                if let goal = store.collaboration.state?.goals.first(where: { $0.id == goalID }) {
                    Button("With our goal · " + goal.title) { goalRoute = CollaborationRoute(goalID: goalID) }.font(.callout)
                }
            }
            DisclosureGroup("From the recording and context") {
                ForEach(Array(evidence.enumerated()), id: \.offset) { _, source in
                    VStack(alignment: .leading, spacing: 5) {
                        if let quote = source.quote { Text(quote).font(.callout).textSelection(.enabled) }
                        if let start = source.start, let end = source.end { Text(start.asClock + "–" + end.asClock).font(.caption.monospaced()) }
                        Text([source.source, source.ref].compactMap { $0 }.joined(separator: " · ")).font(.caption2)
                    }.padding(.vertical, 5)
                }
            }
            TextField("Add precision, if you want", text: $note, axis: .vertical)
                .lineLimit(2...6).disabled(pending != nil || !canReview)
            if pending == nil {
                ViewThatFits {
                    HStack { feedbackButtons }
                    VStack(alignment: .leading) { feedbackButtons }
                }.disabled(!canReview || saving)
            } else {
                Button(saving ? "Saving…" : "Retry this feedback") { Task { await send() } }.disabled(saving)
            }
            if !status.isEmpty { Text(status).font(.caption) }
        }.padding(.vertical, 14).overlay(alignment: .bottom) { Theme.stroke.frame(height: 0.7) }
        .sheet(item: $goalRoute) { route in NavigationStack { CollaborationView(target: route) } }
        .task(id: key) {
            note = ""; pending = nil; saving = false; status = ""
            guard let data = UserDefaults.standard.data(forKey: key), let saved = try? JSONDecoder().decode(VoiceEnrichmentFeedback.self, from: data) else { return }
            pending = saved; note = saved.text; status = "This exact feedback is waiting for confirmation."
        }
    }
    private var feedbackButtons: some View {
        ForEach([("Right", "right"), ("Not right", "wrong"), ("Salient", "salient"), ("Clarify", "clarify")], id: \.1) { label, verdict in
            Button(label) {
                let mutation = VoiceEnrichmentFeedback(originalText: text, recording_id: recordingID, analysis_id: analysisID, item_id: itemID,
                                                      verdict: verdict, text: note)
                mutation.persist(); pending = mutation
                Task { await send() }
            }.font(.callout).frame(minHeight: 44)
        }
    }
    private func send() async {
        guard let pending else { return }
        saving = true; defer { saving = false }
        guard let result = await store.voiceEnrichmentFeedback(pending) else { status = "Confirmation did not arrive. Retry keeps your exact feedback."; return }
        guard result.ok else { status = result.error ?? "Feedback was not accepted. Your words are retained."; return }
        UserDefaults.standard.removeObject(forKey: pending.storageKey)
        guard pending.storageKey == key, self.pending?.request_id == pending.request_id else { return }
        status = "Feedback saved · " + pending.verdict; self.pending = nil; note = ""
    }
}

private struct EarlierVoiceFeedback: View {
    @Environment(AppStore.self) private var store
    let feedback: VoiceEnrichmentFeedback
    @State private var saving = false
    @State private var confirmed = false
    @State private var status = "An earlier analysis has feedback waiting for confirmation. It has not been moved to this analysis."
    var body: some View {
        DisclosureGroup("Earlier feedback · " + feedback.verdict) {
            Text(feedback.originalText ?? "Earlier item: " + feedback.item_id).font(.callout)
            if !feedback.text.isEmpty { Text(feedback.text).font(.callout).italic() }
            Text(status).font(.caption)
            if !confirmed {
                Button(saving ? "Saving…" : "Retry the original feedback") {
                    saving = true
                    Task {
                        defer { saving = false }
                        guard let result = await store.voiceEnrichmentFeedback(feedback) else { status = "Confirmation did not arrive. Original feedback retained."; return }
                        guard result.ok else { status = result.error ?? "The earlier feedback was not accepted; its original words are retained."; return }
                        UserDefaults.standard.removeObject(forKey: feedback.storageKey)
                        confirmed = true; status = "Original feedback confirmed."
                    }
                }.disabled(saving).frame(minHeight: 44)
            }
        }.font(.caption)
    }
}
