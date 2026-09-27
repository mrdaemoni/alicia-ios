import SwiftUI

struct ContextEnrichmentView: View {
    @Environment(AppStore.self) private var store
    var replyID = ""
    @State private var value: ContextEnrichment?
    @State private var error = ""
    @State private var note = ""
    @State private var busy = false
    @State private var pending: ContextChange?
    @FocusState private var writing: Bool
    private var key: String { "alicia.context." + replyID }
    /// A confirmed save is reported in `error` too; only its drawing differs.
    private static let savedMessage = "Context saved. It will shape future replies."

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("See what Alicia is holding, correct a reading, or give an idea more attention. Changes guide future replies.")
                    .font(.callout).foregroundStyle(Theme.inkSoft)
                NavigationLink { CollaborationView(pushed: true) } label: {
                    InkLinkLabel(title: "Our shared focus", detail: "Goals and agreements, in Together")
                }.buttonStyle(.inkLink)
                if let value {
                    context(value)
                } else {
                    Button("Load context") { Task { await load() } }
                        .buttonStyle(.inkSecondaryCompact)
                }
                InkNotice(text: error, kind: error == Self.savedMessage ? .success : .error)
                if pending != nil {
                    VStack(alignment: .leading, spacing: 4) {
                        InkNotice(text: "Your exact change is kept until its save is confirmed.")
                        HStack(spacing: 24) {
                            Button("Retry saved change") { Task { await retry() } }
                                .buttonStyle(.inkQuiet)
                                .disabled(busy)
                            Button("Edit instead") { pending = nil; UserDefaults.standard.removeObject(forKey: key + ".pending") }
                                .buttonStyle(.inkQuiet)
                                .disabled(busy)
                        }
                    }
                }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(22)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.paper).foregroundStyle(Theme.ink).tint(Theme.ink)
        .inkPushedPage("Context enrichment")
        .toolbar { ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done writing") { writing = false } } }
        .task {
            note = UserDefaults.standard.string(forKey: key + ".note") ?? ""
            if let data = UserDefaults.standard.data(forKey: key + ".pending") {
                pending = try? JSONDecoder().decode(ContextChange.self, from: data)
            }
            await load()
        }
        .onChange(of: note) { _, text in UserDefaults.standard.set(text, forKey: key + ".note") }
    }

    @ViewBuilder private func context(_ value: ContextEnrichment) -> some View {
        InkSection(kicker: "About you", spacing: 4) {
            Text("Her working picture is tentative. Your words and corrections are labelled separately.")
                .font(InkType.meta).foregroundStyle(Theme.inkSoft).padding(.bottom, 6)
            if value.about.isEmpty { InkNotice(text: "No working picture is available yet. You can add context below.") }
            rows(value.about)
        }
        if !replyID.isEmpty {
            InkSection(kicker: "Supplied for this reply", spacing: 4) {
                if value.items.isEmpty { InkNotice(text: "This older reply has no detailed context snapshot.") }
                rows(value.items)
            }
        }
        InkSection(kicker: "Something she should know now") {
            TextField("In your words…", text: $note, axis: .vertical)
                .focused($writing).lineLimit(3...8).inkField().disabled(pending != nil)
            Button("Add to my context") {
                submit(ContextChange(action: "add_note", reply_id: replyID, priority: "more", text: note))
            }
            .buttonStyle(.inkPrimary)
            .disabled(busy || pending != nil || note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || note.unicodeScalars.count > 2000)
            if note.unicodeScalars.count > 2000 { InkNotice(text: "Keep the note under 2,000 characters; your draft is retained.", kind: .error) }
        }
        // The old gentle-return policy, shown only when the shared focus
        // (which supersedes it) is not loaded.
        if store.collaboration.state == nil {
            InkSection(kicker: "A gentle return") {
                Text("At most one prepared invitation a day, at least two hours after a conversation or reflection, between 9am and 7pm. It needs a specific unresolved idea; quiet days stay quiet.")
                    .font(.callout)
                if let next = value.followup {
                    Text(next.text).font(InkType.body)
                    Text("From your words: “\(next.anchor)”").font(InkType.meta).foregroundStyle(Theme.inkSoft)
                }
                let enabled = value.followups_enabled && !ThoughtReturnNotifier.locallyStopped
                Button(enabled ? "Stop these follow-ups" : "Allow gentle follow-ups") {
                    submit(ContextChange(action: "settings", reply_id: replyID, followups_enabled: !(value.followups_enabled && !ThoughtReturnNotifier.locallyStopped)))
                }
                .buttonStyle(InkButtonStyle(role: enabled ? .destructive : .secondary, fullWidth: false))
                .disabled(busy || pending != nil)
                Text("Scheduled on this iPhone when the app syncs. New activity here cancels the pending invitation. Activity elsewhere is checked on the next sync.")
                    .font(InkType.meta).foregroundStyle(Theme.inkSoft)
                Button("Allow iPhone notifications") { ProactiveNotifier.requestPermission() }
                    .buttonStyle(.inkQuiet)
            }
        }
        InkDisclosure("When context is shared") { Text(value.exposure).font(.callout) }
    }

    @ViewBuilder private func rows(_ items: [ContextItem]) -> some View {
        ForEach(Array(items.enumerated()), id: \.element.id) { index, row in
            if index > 0 { InkRule(opacity: 0.6) }
            link(row)
        }
    }

    private func link(_ row: ContextItem) -> some View {
        NavigationLink {
            ContextItemView(item: row, replyID: replyID)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                InkLinkLabel(title: row.title,
                             detail: (row.kind == "inferred" ? "Tentative interpretation" : row.kind == "your_words" || row.kind == "your_note" ? "Your words" : "Captured context") + " · " + row.priority.capitalized)
                Text(row.correction.isEmpty ? row.text : row.correction).font(.callout).foregroundStyle(Theme.inkSoft)
                    .lineLimit(3).multilineTextAlignment(.leading).padding(.bottom, 8)
            }
        }.buttonStyle(.inkLink)
    }

    private func load() async {
        if let fresh = await store.contextEnrichment(replyID) { value = fresh; error = "" }
        else { error = "Context could not be reached. Your draft is kept." }
    }
    private func submit(_ request: ContextChange) {
        guard !busy, pending == nil else { return }
        writing = false
        pending = request
        UserDefaults.standard.set(try? JSONEncoder().encode(request), forKey: key + ".pending")
        Task { await retry() }
    }
    private func retry() async {
        guard let request = pending, !busy else { return }
        busy = true
        defer { busy = false }
        guard let result = await store.changeContext(request), result.ok, let fresh = result.context else {
            error = "The change was not confirmed. Retry sends the same request."; return
        }
        value = fresh; pending = nil; error = Self.savedMessage
        UserDefaults.standard.removeObject(forKey: key + ".pending")
        if request.action == "add_note" { note = "" }
    }
}

private struct ContextItemView: View {
    @Environment(AppStore.self) private var store
    let item: ContextItem
    let replyID: String
    @State private var priority = "normal"
    @State private var correction = ""
    @State private var pending: ContextChange?
    @State private var status = ""
    @State private var busy = false
    @State private var source: ContextSource?
    @FocusState private var writing: Bool
    private var key: String { "alicia.context.item." + item.id }
    private static let savedMessage = "Saved for future replies. Open a new reply to see what was actually supplied."

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(item.title).font(InkType.subhead)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(item.kind == "inferred" ? "A tentative interpretation, open to correction." : item.kind == "source" ? "Material supplied for this reply. A retrieval summary can differ from the source file." : "The saved material, preserved as it was.")
                        .font(InkType.meta).foregroundStyle(Theme.inkSoft)
                }
                Text(item.text).font(InkType.body).textSelection(.enabled)
                ListenLine(item: Readable(title: item.title, body: item.text, kind: "context"))
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.source).font(InkType.meta).foregroundStyle(Theme.inkSoft).textSelection(.enabled)
                    if !item.as_of.isEmpty { Text("Recorded: " + item.as_of).font(InkType.meta).foregroundStyle(Theme.inkSoft) }
                }
                InkSection(kicker: "Attention") {
                    Picker("Attention", selection: $priority) {
                        Text("Less").tag("less"); Text("Normal").tag("normal"); Text("More").tag("more")
                    }.pickerStyle(.segmented).disabled(pending != nil)
                    Text("More requests attention in the next reply; the latest choices come first. Long items use a labelled excerpt, and space may limit what fits. Less asks for less emphasis. These controls do not delete sources or change model weights.")
                        .font(InkType.meta).foregroundStyle(Theme.inkSoft)
                }
                InkSection(kicker: "Your correction") {
                    TextField("What should she understand differently?", text: $correction, axis: .vertical)
                        .focused($writing).accessibilityIdentifier("context.correction").lineLimit(3...8).inkField()
                        .disabled(pending != nil)
                    if correction.unicodeScalars.count > 2000 { InkNotice(text: "Keep the correction under 2,000 characters. Your draft is retained.", kind: .error) }
                    Button(pending == nil ? "Save context" : "Retry saved change") { Task { await save() } }
                        .buttonStyle(.inkPrimary)
                        .disabled(busy || correction.unicodeScalars.count > 2000)
                    if pending != nil {
                        Button("Edit instead") { pending = nil; UserDefaults.standard.removeObject(forKey: key + ".pending") }
                            .buttonStyle(.inkQuiet)
                            .disabled(busy)
                    }
                    InkNotice(text: status, kind: status == Self.savedMessage ? .success : .error)
                }
                if item.kind == "source" || source != nil {
                    InkSection(kicker: "The source") {
                        if item.kind == "source" {
                            Button("Open the source here") {
                                Task { source = await store.contextSource(replyID, itemID: item.id); if source == nil { status = "The source could not be opened." } }
                            }
                            .buttonStyle(.inkSecondaryCompact)
                        }
                        if let source {
                            InkNotice(text: source.notice)
                            Text(source.text).font(InkType.body).textSelection(.enabled)
                            ListenLine(item: Readable(title: source.title, body: source.text, kind: "context"), label: "LISTEN TO THE SOURCE")
                        }
                    }
                }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(22)
        }.background(Theme.paper).foregroundStyle(Theme.ink).tint(Theme.ink)
        .inkPushedPage("Enrich this context")
        .scrollDismissesKeyboard(.interactively)
        .toolbar { ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done writing") { writing = false } } }
        .task {
            correction = UserDefaults.standard.string(forKey: key + ".correction") ?? item.correction
            priority = UserDefaults.standard.string(forKey: key + ".priority") ?? item.priority
            if let data = UserDefaults.standard.data(forKey: key + ".pending") { pending = try? JSONDecoder().decode(ContextChange.self, from: data) }
        }
        .onChange(of: correction) { _, value in UserDefaults.standard.set(value, forKey: key + ".correction") }
        .onChange(of: priority) { _, value in UserDefaults.standard.set(value, forKey: key + ".priority") }
    }

    private func save() async {
        guard !busy else { return }
        writing = false; busy = true
        defer { busy = false }
        let request = pending ?? ContextChange(action: "item", reply_id: replyID, item_id: item.id, priority: priority, correction: correction)
        pending = request
        UserDefaults.standard.set(try? JSONEncoder().encode(request), forKey: key + ".pending")
        guard let result = await store.changeContext(request), result.ok, result.context != nil else { status = "Save unconfirmed. Your exact change is kept for retry."; return }
        pending = nil
        UserDefaults.standard.removeObject(forKey: key + ".pending")
        UserDefaults.standard.removeObject(forKey: key + ".priority")
        UserDefaults.standard.removeObject(forKey: key + ".correction")
        status = Self.savedMessage
    }
}
