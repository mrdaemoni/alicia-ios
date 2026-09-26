import SwiftUI

/// Inspect one saved reply, never a reconstructed account of another turn.
struct DialogueReviewView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let message: Message
    @State private var detail: DialogueReview?
    @State private var loading = true
    @State private var busy = false
    @State private var error = ""
    @State private var correction = ""
    @State private var reason = ""
    @State private var allowTraining = false
    @State private var pending: DialogueMutation?
    @State private var selectedAnswer = "original"
    @State private var feedbackTarget = "reply"
    @State private var feedbackNote = ""
    @State private var reasonTags: Set<String> = []
    private enum EditingField: Hashable { case feedback, correction, reason }
    @FocusState private var editing: EditingField?

    private var storageKey: String { "alicia.replyReview." + (message.replyID ?? message.id.uuidString) }

    var body: some View {
        NavigationStack {
            reviewContent
        }
        .onChange(of: feedbackNote) { _, value in UserDefaults.standard.set(value, forKey: storageKey + ".feedbackNote." + selectedAnswer) }
        .onChange(of: reasonTags) { _, value in UserDefaults.standard.set(Array(value).sorted(), forKey: storageKey + ".reasonTags") }
        .onChange(of: correction) { _, value in UserDefaults.standard.set(value, forKey: storageKey + ".correction") }
        .onChange(of: allowTraining) { _, value in UserDefaults.standard.set(value, forKey: storageKey + ".training") }
        .onChange(of: reason) { _, value in UserDefaults.standard.set(value, forKey: storageKey + ".reason") }
    }

    private var reviewContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                InkKicker(text: "Behind this reply")
                NavigationLink {
                    ContextEnrichmentView(replyID: message.replyID ?? "")
                } label: {
                    InkLinkLabel(title: "Enrich context", detail: "About you and what shaped this reply")
                }
                .buttonStyle(.inkLink)
                .accessibilityIdentifier("review.context")
                if loading {
                    ProgressView("Loading saved context…")
                } else if let detail {
                    inspection(detail)
                } else {
                    Text(message.text.strippedEmojis).textSelection(.enabled)
                    Text(message.replyID == nil
                         ? "This older reply has no saved response context. Its original text is above."
                         : "The saved context could not be reached. Try again when Alicia is connected.")
                        .font(.callout).foregroundStyle(Theme.accentSoft)
                    if message.replyID != nil { Button("Try again") { Task { await load() } }.buttonStyle(.inkQuiet) }
                }
                InkNotice(text: error, kind: .error)
                if let pending {
                    // The saved request, its retry, and the way out, together.
                    VStack(alignment: .leading, spacing: 8) {
                        InkNotice(text: "Your \(pending.action == "compare" ? "comparison request" : "feedback") is kept on this phone until the save is confirmed.", kind: .info)
                        HStack(spacing: 20) {
                            Button(busy ? "Saving…" : "Try again") { Task { await retry() } }
                                .buttonStyle(.inkQuiet).disabled(busy)
                            // Discards the pending request: quiet, never primary.
                            Button("Edit my feedback") {
                                self.pending = nil
                                UserDefaults.standard.removeObject(forKey: storageKey + ".pending")
                                error = ""
                                Task { await load() }
                            }.buttonStyle(.inkQuiet).disabled(busy)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card(padding: 16, radius: 16)
                }
            }
            .padding(22)
            .frame(maxWidth: 700, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.paper)
        .foregroundStyle(Theme.ink)
        .fontDesign(.serif)
        .inkSheetPage("Alicia’s reply") { dismiss() }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done writing") { editing = nil } }
        }
        .task { await restoreDraft() }
        .task(id: detail?.comparison.status) {
            guard detail?.comparison.status == "pending" else { return }
            for _ in 0..<240 {
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
                guard !Task.isCancelled, detail?.comparison.status == "pending" else { return }
                await refresh()
            }
        }
        .onChange(of: selectedAnswer) { oldAnswer, answer in
            UserDefaults.standard.set(feedbackNote, forKey: storageKey + ".feedbackNote." + oldAnswer)
            feedbackNote = UserDefaults.standard.string(forKey: storageKey + ".feedbackNote." + answer) ?? ""
            feedbackTarget = "reply"
            if answer == "alternative", let value = detail, value.comparison_eligible,
               value.comparison.status == "not_requested", !busy, pending == nil {
                submit(DialogueMutation(action: "compare", reply_id: value.id))
            }
        }

    }

    private func restoreDraft() async {
        if let data = UserDefaults.standard.data(forKey: storageKey + ".pending") {
            pending = try? JSONDecoder().decode(DialogueMutation.self, from: data)
        }
        await load()
        correction = UserDefaults.standard.string(forKey: storageKey + ".correction") ?? ""
        feedbackNote = UserDefaults.standard.string(forKey: storageKey + ".feedbackNote." + selectedAnswer) ?? (selectedAnswer == "original" ? UserDefaults.standard.string(forKey: storageKey + ".feedbackNote") : nil) ?? ""
        reason = UserDefaults.standard.string(forKey: storageKey + ".reason") ?? detail?.preference?.reason ?? ""
        reasonTags = Set(UserDefaults.standard.stringArray(forKey: storageKey + ".reasonTags") ?? detail?.preference?.reason_tags ?? [])
        allowTraining = (UserDefaults.standard.object(forKey: storageKey + ".training") as? Bool) ?? detail?.preference?.training_allowed ?? false
    }



    @ViewBuilder
    private func inspection(_ value: DialogueReview) -> some View {
        if let nodes = value.context_graph_nodes, !nodes.isEmpty {
            InkSection(kicker: "Drew on your context", spacing: 2) {
                ForEach(Array(nodes.enumerated()), id: \.element.id) { index, n in
                    if index > 0 { InkRule(opacity: 0.6) }
                    NavigationLink { ContextNodeView(nodeID: n.id) } label: {
                        InkLinkLabel(title: n.title.isEmpty ? n.id : n.title,
                                     detail: n.status == "inferred" ? "unconfirmed reading" : n.status, small: true)
                    }.buttonStyle(.inkLink).accessibilityIdentifier("review.contextNode." + n.id)
                }
            }
        }
        modelAnswers(value)
        if selectedAnswer == "original" || value.comparison.status == "ready" {
            section("Quick feedback") {
                saveHint
                feedbackRow("reply", labels: ["Helpful", "Okay", "Missed me"], values: ["helpful", "okay", "missed_me"], answer: selectedAnswer)
                InkDisclosure("More precise feedback (optional)") {
                    VStack(alignment: .leading, spacing: 14) {
                        // Chooses what the rating is about; nothing is saved here.
                        InkKicker(text: "About")
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), alignment: .leading)], alignment: .leading, spacing: 8) {
                            ForEach([("reply", "Overall response"), ("depth", "Depth"), ("tone", "Tone"), ("brevity", "Length")], id: \.0) { tag, label in
                                WorkReviewChoice(title: label, selected: feedbackTarget == tag, compact: true) { feedbackTarget = tag }
                            }
                        }
                        TextField("What would make this answer better?", text: $feedbackNote, axis: .vertical)
                            .focused($editing, equals: .feedback).accessibilityIdentifier("review.feedbackNote")
                            .lineLimit(2...6).inkField()
                        if feedbackNote.unicodeScalars.count > 2000 {
                            Text("Keep the note under 2,000 characters. Your draft is retained.").font(.caption).foregroundStyle(Theme.rose)
                        }
                        feedbackRow(feedbackTarget, labels: feedbackLabels(feedbackTarget),
                                    values: feedbackValues(feedbackTarget), answer: selectedAnswer, note: feedbackNote)
                        Text("Tap a rating to save it with your optional note.").font(.caption).foregroundStyle(Theme.inkSoft)
                    }
                }
            }
        }
        if value.comparison.status == "ready" { preferenceControls(value) }
        InkDisclosure("What informed the original reply") {
            VStack(alignment: .leading, spacing: 24) {
                originalContext(value)
            }.padding(.top, 6)
        }
    }

    @ViewBuilder
    private func originalContext(_ value: DialogueReview) -> some View {
        section("Your words") { Text(value.user_text).textSelection(.enabled) }
        if !value.reading.isEmpty {
            section("What she took from your words") {
                Text(value.reading.strippedEmojis).textSelection(.enabled)
                Text("A tentative reading you can correct.").font(.caption).foregroundStyle(Theme.accentSoft)
                TextField("What did she miss?", text: $correction, axis: .vertical)
                    .focused($editing, equals: .correction)
                    .lineLimit(2...6).inkField()
                if correction.unicodeScalars.count > 2000 {
                    Text("Keep the correction under 2,000 characters before saving. Your draft is retained.")
                        .font(.caption).foregroundStyle(Theme.rose)
                }
                saveHint
                feedbackRow("reading", labels: ["That’s right", "She misread me"], values: ["accurate", "misread"])
            }
        }
        if value.lens != "neutral" {
            section("Archetype lens") {
                HStack(spacing: 12) {
                    ArchetypeEmblem(id: value.lens, size: 30)
                    Text(value.lens.capitalized).font(.title3)
                }
                Text("The lens named with this reply. You can tell her whether it fits.")
                    .font(.caption).foregroundStyle(Theme.accentSoft)
                saveHint
                feedbackRow("lens", labels: ["Fits", "Doesn’t fit"], values: ["fits", "does_not_fit"])
            }
        }
        if !value.detail.isEmpty {
            section("More from this answer") {
                Text(value.detail.strippedEmojis).textSelection(.enabled)
                listen(value.detail, title: "More from this answer")
            }
        }
        if !value.context_modules.isEmpty {
            section("Context available") {
                Text(value.context_modules.map(contextLabel).joined(separator: " · "))
                    .font(.callout).foregroundStyle(Theme.accentSoft)
                Text("These parts of Alicia’s context were present in the saved input. Some may have been excerpted to fit the model.")
                    .font(.caption).foregroundStyle(Theme.accentSoft)
            }
        }
        section("Sources supplied") {
            if value.sources.isEmpty {
                Text("No named vault source was captured in the input for this reply.")
                    .font(.callout).foregroundStyle(Theme.accentSoft)
            } else {
                Text("This material was supplied to the model; it may include retrieval summaries. It does not prove which passage shaped the answer. Open Context enrichment to inspect the current source file.")
                    .font(.caption).foregroundStyle(Theme.accentSoft)
                ForEach(value.sources) { source in
                    VStack(alignment: .leading, spacing: 8) {
                        if let url = URL(string: source.url) {
                            Link(destination: url) { InkLinkLabel(title: source.title, small: true, external: true) }
                                .buttonStyle(.inkLink)
                        } else { Text(source.title.strippedEmojis).font(.headline) }
                        Text(source.excerpt.strippedEmojis).font(.callout).textSelection(.enabled)
                    }.padding(.vertical, 6)
                }
                saveHint
                feedbackRow("sources", labels: ["Relevant", "Wrong connection"], values: ["relevant", "not_relevant"])
            }
        }
        if !value.tools.isEmpty {
            section("Tools consulted") {
                ForEach(value.tools, id: \.self) { tool in Text(tool.replacingOccurrences(of: "_", with: " ")) }
            }
        }
    }

    private func modelName(_ value: DialogueReview, answer: String) -> String {
        let provider = answer == "original" ? value.provider : (value.comparison.provider ?? (value.provider == "qwen" ? "claude" : "qwen"))
        return provider == "qwen" ? "Qwen" : "Claude"
    }

    @ViewBuilder
    private func modelAnswers(_ value: DialogueReview) -> some View {
        Picker("Model answer", selection: $selectedAnswer) {
            Text(modelName(value, answer: "original")).tag("original")
            Text(modelName(value, answer: "alternative")).tag("alternative")
        }.pickerStyle(.segmented)
        if selectedAnswer == "original" {
            Text("Original reply · \(value.providerLabel)").font(.caption).foregroundStyle(Theme.accentSoft)
            Text(value.reply.strippedEmojis).font(.title3).textSelection(.enabled)
            listen(value.reply, title: "Original reply")
            if !value.detail.isEmpty {
                InkDisclosure("Read the full answer") { Text(value.detail.strippedEmojis).textSelection(.enabled) }
            }
        } else if value.comparison.status == "ready", let answer = value.comparison.reply {
            Text("Alternative · \(modelName(value, answer: "alternative"))").font(.caption).foregroundStyle(Theme.accentSoft)
            Text(answer.strippedEmojis).font(.title3).textSelection(.enabled)
            listen(answer, title: "Alternative reply")
            if let more = value.comparison.detail, !more.isEmpty {
                InkDisclosure("Read the full answer") { Text(more.strippedEmojis).textSelection(.enabled) }
            }
            if let reading = value.comparison.reading, !reading.isEmpty {
                InkDisclosure("What this answer took from your words") {
                    Text(reading.strippedEmojis).textSelection(.enabled)
                    feedbackRow("reading", labels: ["That’s right", "She misread me"], values: ["accurate", "misread"], answer: "alternative")
                }
            }
            if let lens = value.comparison.lens, lens != "neutral" {
                HStack(spacing: 12) {
                    ArchetypeEmblem(id: lens, size: 26)
                    Text("Archetype lens · " + lens.capitalized).font(.callout)
                }
                feedbackRow("lens", labels: ["Fits", "Doesn’t fit"], values: ["fits", "does_not_fit"], answer: "alternative")
            }
            if let note = value.comparison.context_note, !note.isEmpty {
                Text(note).font(.caption).foregroundStyle(Theme.accentSoft)
            }
        } else if !value.comparison_eligible {
            Text(value.comparison_reason).font(.callout).foregroundStyle(Theme.accentSoft)
        } else if value.comparison.status == "pending" || busy {
            ProgressView("Preparing the other answer…")
            Text("You can switch tabs or return later.").font(.caption).foregroundStyle(Theme.accentSoft)
        } else {
            if let failure = value.comparison.error { InkNotice(text: failure, kind: .error) }
            Button("Prepare this answer") { submit(DialogueMutation(action: "compare", reply_id: value.id)) }
                .buttonStyle(.inkSecondaryCompact).disabled(busy || pending != nil)
        }
    }

    @ViewBuilder
    private func preferenceControls(_ value: DialogueReview) -> some View {
        section("Which helped more?") {
            Text("Tap once to vote; it saves. A reason is optional.").font(.caption).foregroundStyle(Theme.inkSoft)
            HStack(spacing: 10) {
                voteButton("Prefer " + modelName(value, answer: "original"), choice: "original", value: value)
                voteButton("Prefer " + modelName(value, answer: "alternative"), choice: "alternative", value: value)
            }
            HStack(spacing: 10) {
                voteButton("Tie", choice: "tie", value: value)
                voteButton("Neither", choice: "neither", value: value)
            }
            if let saved = value.preference {
                Text("Vote saved. You can change it.").font(.caption).foregroundStyle(Theme.accentSoft)
                InkDisclosure("Add why (optional)") {
                    VStack(alignment: .leading, spacing: 14) {
                        // These only toggle; "Save optional details" saves them.
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), alignment: .leading)], alignment: .leading, spacing: 8) {
                            ForEach(reasonOptions, id: \.0) { tag, label in
                                WorkReviewChoice(title: label, selected: reasonTags.contains(tag), compact: true) {
                                    if reasonTags.contains(tag) { reasonTags.remove(tag) } else { reasonTags.insert(tag) }
                                }
                            }
                        }
                        TextField("Anything more specific?", text: $reason, axis: .vertical)
                            .focused($editing, equals: .reason).accessibilityIdentifier("review.reason")
                            .lineLimit(2...6).inkField()
                        if reason.unicodeScalars.count > 2000 {
                            Text("Keep the note under 2,000 characters. Your draft is retained.").font(.caption).foregroundStyle(Theme.rose)
                        }
                        if value.comparison.same_input == true {
                            Toggle("Include this pair in training review", isOn: $allowTraining).font(.callout)
                        }
                        Button("Save optional details") {
                            submit(DialogueMutation(action: "preference", reply_id: value.id,
                                reason_tags: reasonTags.sorted(), choice: saved.choice, reason: reason,
                                training_allowed: allowTraining && value.comparison.same_input == true))
                        }.buttonStyle(.inkSecondary).disabled(busy || pending != nil || reason.unicodeScalars.count > 2000)
                        if saved.reason == reason && Set(saved.reason_tags ?? []) == reasonTags && saved.training_allowed == allowTraining {
                            Text("Optional details saved.").font(.caption).foregroundStyle(Theme.accentSoft)
                        }
                        Text(value.training_status == "pending_review" ? "Selected for training review. No model has been trained." : "Your vote guides conversation. Training is a separate reviewed step.")
                            .font(.caption).foregroundStyle(Theme.accentSoft)
                    }
                }
            }
        }
    }

    private let reasonOptions = [("clearer", "Clearer"), ("more_relevant", "More relevant"),
        ("better_connections", "Better connections"), ("less_assumptive", "Fewer assumptions"),
        ("more_concise", "More concise"), ("more_challenging", "Made me think")]

    private func voteButton(_ label: String, choice: String, value: DialogueReview) -> some View {
        // A chip that saves on tap (the line above says so).
        WorkReviewChoice(title: label, selected: value.preference?.choice == choice) {
            guard value.preference?.choice != choice else { return }
            // A quick vote stands alone. Explanations are added deliberately afterward.
            submit(DialogueMutation(action: "preference", reply_id: value.id, choice: choice,
                                    training_allowed: value.preference?.training_allowed == true && value.comparison.same_input == true))
        }
            .disabled(busy || pending != nil)
            .accessibilityValue(value.preference?.choice == choice ? "Saved" : "")
    }

    private func feedbackLabels(_ target: String) -> [String] {
        switch target {
        case "depth": return ["Go deeper", "More practical"]
        case "tone": return ["Warmer", "More direct"]
        case "brevity": return ["Right length", "Too long"]
        default: return ["Helpful", "Okay", "Missed me"]
        }
    }
    private func feedbackValues(_ target: String) -> [String] {
        switch target {
        case "depth": return ["deeper", "more_practical"]
        case "tone": return ["warmer", "more_direct"]
        case "brevity": return ["right_length", "too_long"]
        default: return ["helpful", "okay", "missed_me"]
        }
    }

    private func feedbackRow(_ target: String, labels: [String], values: [String], answer: String = "original", note: String = "") -> some View {
        let key = (answer == "alternative" ? "alternative:" : "") + target
        return HStack(spacing: 8) {
            ForEach(values.indices, id: \.self) { index in
                WorkReviewChoice(title: labels[index], selected: detail?.feedback[key]?.verdict == values[index]) {
                    guard let id = message.replyID else { return }
                    submit(DialogueMutation(action: "feedback", reply_id: id, answer: answer, target: target,
                                            verdict: values[index], note: target == "reading" && answer == "original" ? correction : note))
                }
                    .accessibilityValue(detail?.feedback[key]?.verdict == values[index] ? "Saved" : "")
                    .disabled(busy || pending != nil || ((target == "reading" && answer == "original" ? correction : note).unicodeScalars.count > 2000))
            }
        }
    }

    private func contextLabel(_ name: String) -> String {
        ["dialogue_delivery": "Reply style", "dialogue_feedback": "Your response feedback",
         "episode_day": "The shared episode and day", "memory": "Conversation memory",
         "identity": "Alicia’s identity", "behavior": "Conversation guidance",
         "operating": "Operating instructions", "evidence": "Retrieved vault material",
         "optional": "Additional context"][name] ?? name.replacingOccurrences(of: "_", with: " ")
    }

    /// Listening keeps its one established control.
    private func listen(_ text: String, title: String) -> some View {
        ListenLine(item: Readable(title: title, body: text, kind: "dialogue"))
    }

    /// Chips under this line save when tapped — unlike the reason tags, which
    /// only toggle until "Save optional details".
    private var saveHint: some View {
        InkKicker(text: "Tap to save")
    }

    /// One header system for the sheet: the same section as everywhere else.
    private func section<Content: View>(_ title: String, @ViewBuilder content: @escaping () -> Content) -> some View {
        InkSection(kicker: title, content: content)
    }

    private func load() async {
        loading = detail == nil
        await refresh()
        loading = false
    }

    private func refresh() async {
        guard editing == nil, let id = message.replyID, let fresh = await store.replyInspection(id), editing == nil else { return }
        detail = fresh
    }

    private func submit(_ mutation: DialogueMutation) {
        guard !busy, pending == nil else { return }
        editing = nil
        pending = mutation
        UserDefaults.standard.set(try? JSONEncoder().encode(mutation), forKey: storageKey + ".pending")
        Task { await retry() }
    }

    private func retry() async {
        guard let request = pending, !busy else { return }
        busy = true
        defer { busy = false }
        guard let result = await store.saveReplyReview(request), result.ok, let fresh = result.response else {
            error = "The save wasn’t confirmed. Your exact request is kept for retry."
            return
        }
        detail = fresh
        if pending?.event_id == request.event_id {
            pending = nil
            UserDefaults.standard.removeObject(forKey: storageKey + ".pending")
        }
        error = ""
    }
}
