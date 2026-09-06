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
    @State private var choice = ""
    @State private var reason = ""
    @State private var allowTraining = false
    @State private var pending: DialogueMutation?

    private var storageKey: String { "alicia.replyReview." + (message.replyID ?? message.id.uuidString) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
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
#if DEBUG
            .defaultScrollAnchor(ProcessInfo.processInfo.arguments.contains("--dialogue-review-comparison-preview") ? .bottom : .top)
#endif
            .background(Theme.paper)
            .foregroundStyle(Theme.ink)
            .fontDesign(.serif)
            .navigationTitle("Alicia’s reply")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task {
                correction = UserDefaults.standard.string(forKey: storageKey + ".correction") ?? ""
                reason = UserDefaults.standard.string(forKey: storageKey + ".reason") ?? ""
                choice = UserDefaults.standard.string(forKey: storageKey + ".choice") ?? ""
                allowTraining = UserDefaults.standard.bool(forKey: storageKey + ".training")
                if let data = UserDefaults.standard.data(forKey: storageKey + ".pending") {
                    pending = try? JSONDecoder().decode(DialogueMutation.self, from: data)
                }
                await load()
            }
            .task(id: detail?.comparison.status) {
                guard detail?.comparison.status == "pending" else { return }
                for _ in 0..<240 {
                    do { try await Task.sleep(for: .seconds(2)) } catch { return }
                    guard !Task.isCancelled, detail?.comparison.status == "pending" else { return }
                    await refresh()
                }
            }
            .onChange(of: correction) { _, value in UserDefaults.standard.set(value, forKey: storageKey + ".correction") }
            .onChange(of: choice) { _, value in UserDefaults.standard.set(value, forKey: storageKey + ".choice") }
            .onChange(of: allowTraining) { _, value in UserDefaults.standard.set(value, forKey: storageKey + ".training") }
            .onChange(of: reason) { _, value in UserDefaults.standard.set(value, forKey: storageKey + ".reason") }
        }
    }

    @ViewBuilder
    private func inspection(_ value: DialogueReview) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(value.reply.strippedEmojis).font(.title3).textSelection(.enabled)
            Text("Replied through \(value.providerLabel)").font(.caption).foregroundStyle(Theme.accentSoft)
            listen(value.reply, title: "Alicia’s reply")
            feedbackRow("reply", labels: ["Helpful", "Missed me"], values: ["helpful", "missed_me"])
            feedbackRow("brevity", labels: ["Right length", "Too long"], values: ["right_length", "too_long"])
        }
        section("Your words") { Text(value.user_text).textSelection(.enabled) }
        if !value.reading.isEmpty {
            section("What she took from your words") {
                Text(value.reading.strippedEmojis).textSelection(.enabled)
                Text("A tentative reading you can correct.").font(.caption).foregroundStyle(Theme.accentSoft)
                TextField("What did she miss?", text: $correction, axis: .vertical)
                    .lineLimit(2...6).padding(12)
                    .background(Theme.ink.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
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
                Text("These excerpts were available to the model. They do not prove which passage shaped the answer.")
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
        comparisonSection(value)
    }

    @ViewBuilder
    private func comparisonSection(_ value: DialogueReview) -> some View {
        section("Try the other model") {
            if !value.comparison_eligible {
                Text(value.comparison_reason).font(.callout).foregroundStyle(Theme.accentSoft)
            } else if value.comparison.status == "pending" {
                ProgressView("The other answer is being prepared…")
                Text("You can close this and return later.").font(.caption)
            } else if value.comparison.status == "ready", let answer = value.comparison.reply {
                Text("Original · \(value.providerLabel)").font(.headline)
                Text(value.reply.strippedEmojis).textSelection(.enabled)
                Text(value.comparison.provider == "qwen" ? "Other answer · Qwen · Mac mini" : "Other answer · Claude").font(.headline)
                Text(answer.strippedEmojis).textSelection(.enabled)
                listen(answer, title: "The other answer")
                if let more = value.comparison.detail, !more.isEmpty {
                    DisclosureGroup("More from this answer") { Text(more.strippedEmojis).textSelection(.enabled) }
                }
                Text("You’ve already seen the first answer. This preference belongs to our conversation, not a blind test.")
                    .font(.caption).foregroundStyle(Theme.accentSoft)
                Picker("Which helped more?", selection: $choice) {
                    Text("Choose…").tag("")
                    Text("Original answer").tag("original")
                    Text("Other answer").tag("alternative")
                    Text("Both equally").tag("tie")
                    Text("Neither").tag("neither")
                }.pickerStyle(.menu).frame(minHeight: 44)
                TextField("What made the difference?", text: $reason, axis: .vertical)
                    .lineLimit(2...5).padding(12)
                    .background(Theme.ink.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
                Toggle("Allow this pair to be reviewed for model training", isOn: $allowTraining)
                    .font(.callout)
                Text("A reviewed batch is a separate step. Saving feedback does not train or replace a model.")
                    .font(.caption).foregroundStyle(Theme.accentSoft)
                Button("Save preference") {
                    submit(DialogueMutation(action: "preference", reply_id: value.id,
                        choice: choice, reason: reason, training_allowed: allowTraining))
                }.frame(minHeight: 44)
                    .disabled(busy || pending != nil || choice.isEmpty || reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if let saved = value.preference {
                    Text("Saved: \(saved.choice.replacingOccurrences(of: "_", with: " ")) · \(saved.reason)")
                        .font(.caption).foregroundStyle(Theme.accentSoft)
                    if value.training_status == "pending_review" { Text("Pair selected for training review.").font(.caption) }
                }
            } else {
                Text("Use the saved context for one other answer. Compare it, then tell Alicia what helped.")
                    .font(.callout)
                if let failure = value.comparison.error { Text(failure).font(.caption).foregroundStyle(Theme.rose) }
                Button(value.provider == "qwen" ? "Compare with Claude" : "Compare with Qwen") {
                    submit(DialogueMutation(action: "compare", reply_id: value.id))
                }.frame(minHeight: 44).disabled(busy || pending != nil)
            }
        }
    }

    private func feedbackRow(_ target: String, labels: [String], values: [String]) -> some View {
        HStack(spacing: 10) {
            ForEach(values.indices, id: \.self) { index in
                Button {
                    guard let id = message.replyID else { return }
                    submit(DialogueMutation(action: "feedback", reply_id: id, target: target,
                                            verdict: values[index], note: target == "reading" ? correction : ""))
                } label: {
                    Text(labels[index]).font(.callout)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .padding(.horizontal, 7)
                        .background(detail?.feedback[target]?.verdict == values[index]
                                    ? Theme.accent.opacity(0.18) : Theme.ink.opacity(0.04),
                                    in: RoundedRectangle(cornerRadius: 10))
                }.buttonStyle(.plain).disabled(busy || pending != nil)
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
        guard let id = message.replyID, let fresh = await store.replyInspection(id) else { return }
        detail = fresh
    }

    private func submit(_ mutation: DialogueMutation) {
        guard !busy, pending == nil else { return }
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
