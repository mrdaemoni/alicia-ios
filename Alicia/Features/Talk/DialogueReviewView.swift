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
    @State private var showWhy = false
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
                NavigationLink("Enrich context · about you and what shaped this reply") {
                    ContextEnrichmentView(replyID: message.replyID ?? "")
                }.font(.callout).frame(minHeight: 44)
                Text("BEHIND THIS REPLY")
                    .font(.system(size: 11, design: .monospaced)).tracking(2)
                    .foregroundStyle(Theme.accentSoft)
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
                    if message.replyID != nil { Button("Try again") { Task { await load() } } }
                }
                if !error.isEmpty {
                    Text(error).font(.callout).foregroundStyle(Theme.rose)
                }
                if let pending {
                    Text("Your \(pending.action == "compare" ? "comparison request" : "feedback") is kept on this phone until the save is confirmed.")
                        .font(.callout)
                    Button(busy ? "Saving…" : "Retry saved request") { Task { await retry() } }
                        .frame(minHeight: 44).disabled(busy)
                    Button("Edit my feedback") {
                        self.pending = nil
                        UserDefaults.standard.removeObject(forKey: storageKey + ".pending")
                        error = ""
                        Task { await load() }
                    }.frame(minHeight: 44).disabled(busy)
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
        .navigationTitle("Alicia’s reply")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
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
        feedbackNote = UserDefaults.standard.string(forKey: storageKey + ".feedbackNote.original") ?? UserDefaults.standard.string(forKey: storageKey + ".feedbackNote") ?? ""
        reason = UserDefaults.standard.string(forKey: storageKey + ".reason") ?? detail?.preference?.reason ?? ""
        reasonTags = Set(UserDefaults.standard.stringArray(forKey: storageKey + ".reasonTags") ?? detail?.preference?.reason_tags ?? [])
        allowTraining = (UserDefaults.standard.object(forKey: storageKey + ".training") as? Bool) ?? detail?.preference?.training_allowed ?? false
    }



    @ViewBuilder
    private func inspection(_ value: DialogueReview) -> some View {
        modelAnswers(value)
        if selectedAnswer == "original" || value.comparison.status == "ready" {
            section("Quick feedback") {
                feedbackRow("reply", labels: ["Helpful", "Okay", "Missed me"], values: ["helpful", "okay", "missed_me"], answer: selectedAnswer)
                DisclosureGroup("More precise feedback (optional)") {
                    VStack(alignment: .leading, spacing: 14) {
                        Picker("About", selection: $feedbackTarget) {
                            Text("Overall response").tag("reply")
                            Text("Depth").tag("depth")
                            Text("Tone").tag("tone")
                            Text("Length").tag("brevity")
                        }.frame(minHeight: 44)
                        TextField("What would make this answer better?", text: $feedbackNote, axis: .vertical)
                            .focused($editing, equals: .feedback)
                            .lineLimit(2...6).padding(12)
                            .background(Theme.ink.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
                        if feedbackNote.unicodeScalars.count > 2000 {
                            Text("Keep the note under 2,000 characters. Your draft is retained.").font(.caption).foregroundStyle(Theme.rose)
                        }
                        feedbackRow(feedbackTarget, labels: feedbackLabels(feedbackTarget),
                                    values: feedbackValues(feedbackTarget), answer: selectedAnswer, note: feedbackNote)
                        Text("Tap a rating to save it with your optional note.").font(.caption).foregroundStyle(Theme.accentSoft)
                    }.padding(.top, 12)
                }
            }
        }
        if value.comparison.status == "ready" { preferenceControls(value) }
        DisclosureGroup("What informed the original reply") {
            VStack(alignment: .leading, spacing: 24) {
                originalContext(value)
            }.padding(.top, 18)
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
                    .lineLimit(2...6).padding(12)
                    .background(Theme.ink.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
                if correction.unicodeScalars.count > 2000 {
                    Text("Keep the correction under 2,000 characters before saving. Your draft is retained.")
                        .font(.caption).foregroundStyle(Theme.rose)
                }
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
                            Link(source.title, destination: url).font(.headline)
                        } else { Text(source.title).font(.headline) }
                        Text(source.excerpt.strippedEmojis).font(.callout).textSelection(.enabled)
                    }.padding(.vertical, 6)
                }
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
                DisclosureGroup("Read the full answer") { Text(value.detail.strippedEmojis).textSelection(.enabled) }
            }
        } else if value.comparison.status == "ready", let answer = value.comparison.reply {
            Text("Alternative · \(modelName(value, answer: "alternative"))").font(.caption).foregroundStyle(Theme.accentSoft)
            Text(answer.strippedEmojis).font(.title3).textSelection(.enabled)
            listen(answer, title: "Alternative reply")
            if let more = value.comparison.detail, !more.isEmpty {
                DisclosureGroup("Read the full answer") { Text(more.strippedEmojis).textSelection(.enabled) }
            }
            if let reading = value.comparison.reading, !reading.isEmpty {
                DisclosureGroup("What this answer took from your words") {
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
            if let failure = value.comparison.error { Text(failure).font(.caption).foregroundStyle(Theme.rose) }
            Button("Prepare this answer") { submit(DialogueMutation(action: "compare", reply_id: value.id)) }
                .frame(minHeight: 44).disabled(busy || pending != nil)
        }
    }

    @ViewBuilder
    private func preferenceControls(_ value: DialogueReview) -> some View {
        section("Which helped more?") {
            Text("Tap once to vote. A reason is optional.").font(.caption).foregroundStyle(Theme.accentSoft)
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
                DisclosureGroup("Add why (optional)", isExpanded: $showWhy) {
                    VStack(alignment: .leading, spacing: 14) {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 130))], spacing: 10) {
                            ForEach(reasonOptions, id: \.0) { tag, label in
                                Button { if reasonTags.contains(tag) { reasonTags.remove(tag) } else { reasonTags.insert(tag) } } label: {
                                    Text(label).font(.callout).frame(maxWidth: .infinity, minHeight: 44)
                                        .padding(.horizontal, 8)
                                        .background(reasonTags.contains(tag) ? Theme.accent.opacity(0.18) : Theme.ink.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
                                }.buttonStyle(.plain)
                                    .accessibilityAddTraits(reasonTags.contains(tag) ? .isSelected : [])
                            }
                        }
                        TextField("Anything more specific?", text: $reason, axis: .vertical)
                            .focused($editing, equals: .reason)
                            .lineLimit(2...6).padding(12)
                            .background(Theme.ink.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
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
                        }.frame(minHeight: 44).disabled(busy || pending != nil || reason.unicodeScalars.count > 2000)
                        if saved.reason == reason && Set(saved.reason_tags ?? []) == reasonTags && saved.training_allowed == allowTraining {
                            Text("Optional details saved.").font(.caption).foregroundStyle(Theme.accentSoft)
                        }
                        Text(value.training_status == "pending_review" ? "Selected for training review. No model has been trained." : "Your vote guides conversation. Training is a separate reviewed step.")
                            .font(.caption).foregroundStyle(Theme.accentSoft)
                    }.padding(.top, 14)
                }
            }
        }
    }

    private let reasonOptions = [("clearer", "Clearer"), ("more_relevant", "More relevant"),
        ("better_connections", "Better connections"), ("less_assumptive", "Fewer assumptions"),
        ("more_concise", "More concise"), ("more_challenging", "Made me think")]

    private func voteButton(_ label: String, choice: String, value: DialogueReview) -> some View {
        Button {
            guard value.preference?.choice != choice else { return }
            // A quick vote stands alone. Explanations are added deliberately afterward.
            submit(DialogueMutation(action: "preference", reply_id: value.id, choice: choice,
                                    training_allowed: value.preference?.training_allowed == true && value.comparison.same_input == true))
        } label: {
            Text(label).font(.callout).frame(maxWidth: .infinity, minHeight: 44).padding(.horizontal, 8)
                .background(value.preference?.choice == choice ? Theme.accent.opacity(0.18) : Theme.ink.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
        }.buttonStyle(.plain).disabled(busy || pending != nil)
            .accessibilityAddTraits(value.preference?.choice == choice ? .isSelected : [])
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
        return HStack(spacing: 10) {
            ForEach(values.indices, id: \.self) { index in
                Button {
                    guard let id = message.replyID else { return }
                    submit(DialogueMutation(action: "feedback", reply_id: id, answer: answer, target: target,
                                            verdict: values[index], note: target == "reading" && answer == "original" ? correction : note))
                } label: {
                    Text(labels[index]).font(.callout)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .padding(.horizontal, 7)
                        .background(detail?.feedback[key]?.verdict == values[index]
                                    ? Theme.accent.opacity(0.18) : Theme.ink.opacity(0.04),
                                    in: RoundedRectangle(cornerRadius: 10))
                }.buttonStyle(.plain)
                    .accessibilityAddTraits(detail?.feedback[key]?.verdict == values[index] ? .isSelected : [])
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

    private func listen(_ text: String, title: String) -> some View {
        Button("Listen") { store.readAloud(Readable(title: title, body: text, kind: "dialogue")) }
            .font(.callout).frame(minHeight: 44)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Rectangle().fill(Theme.ink.opacity(0.12)).frame(height: 1)
            Text(title).font(.headline)
            content()
        }
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
