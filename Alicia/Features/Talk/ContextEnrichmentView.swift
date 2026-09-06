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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("Your context, open to revision").font(.title2)
                Text("See what Alicia is holding, correct a reading, or give an idea more attention. Changes guide future replies.")
                    .font(.callout).foregroundStyle(Theme.inkSoft)
                if let value {
                    context(value)
                } else {
                    Button("Load context") { Task { await load() } }
                }
                if !error.isEmpty { Text(error).font(.callout).foregroundStyle(Theme.rose) }
                if pending != nil {
                    Text("Your exact change is kept until its save is confirmed.").font(.caption)
                    Button("Retry saved change") { Task { await retry() } }.disabled(busy)
                    Button("Edit instead") { pending = nil; UserDefaults.standard.removeObject(forKey: key + ".pending") }
                        .disabled(busy)
                }
            }.padding(22)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.paper).foregroundStyle(Theme.ink)
        .navigationTitle("Context enrichment").navigationBarTitleDisplayMode(.inline)
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
        Text("ABOUT YOU").font(.caption.monospaced()).tracking(1.5)
        Text("Her working picture is tentative. Your words and corrections are labelled separately.")
            .font(.caption).foregroundStyle(Theme.inkSoft)
        if value.about.isEmpty { Text("No working picture is available yet. You can add context below.") }
        ForEach(value.about) { row in link(row) }
        if !replyID.isEmpty {
            Text("SUPPLIED FOR THIS REPLY").font(.caption.monospaced()).tracking(1.5)
            if value.items.isEmpty { Text("This older reply has no detailed context snapshot.") }
            ForEach(value.items) { row in link(row) }
        }
        Divider()
        Text("Something she should know now").font(.headline)
        TextField("In your words…", text: $note, axis: .vertical)
            .focused($writing).lineLimit(3...8).padding(14).disabled(pending != nil)
            .background(Theme.ink.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
        Button("Add to my context") {
            submit(ContextChange(action: "add_note", reply_id: replyID, priority: "more", text: note))
        }.frame(minHeight: 44)
            .disabled(busy || pending != nil || note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || note.unicodeScalars.count > 2000)
        if note.unicodeScalars.count > 2000 { Text("Keep the note under 2,000 characters; your draft is retained.").font(.caption) }
        Divider()
        Text("A gentle return").font(.headline)
        Text("At most one prepared invitation a day, at least two hours after a conversation or reflection, between 9am and 7pm. It needs a specific unresolved idea; quiet days stay quiet.")
            .font(.callout)
        if let next = value.followup {
            Text(next.text).font(.body)
            Text("From your words: “\(next.anchor)”").font(.caption).foregroundStyle(Theme.inkSoft)
        }
        Button(value.followups_enabled && !ThoughtReturnNotifier.locallyStopped ? "Stop these follow-ups" : "Allow gentle follow-ups") {
            submit(ContextChange(action: "settings", reply_id: replyID, followups_enabled: !(value.followups_enabled && !ThoughtReturnNotifier.locallyStopped)))
        }.frame(minHeight: 44).disabled(busy || pending != nil)
        Text("Scheduled on this iPhone when the app syncs. New activity here cancels the pending invitation. Activity elsewhere is checked on the next sync.")
            .font(.caption).foregroundStyle(Theme.inkSoft)
        Button("Allow iPhone notifications") { ProactiveNotifier.requestPermission() }.font(.callout).frame(minHeight: 44)
        DisclosureGroup("When context is shared") { Text(value.exposure).font(.callout) }
    }

    private func link(_ row: ContextItem) -> some View {
        NavigationLink {
            ContextItemView(item: row, replyID: replyID)
        } label: {
            VStack(alignment: .leading, spacing: 7) {
                Text(row.title).font(.headline)
                Text(row.correction.isEmpty ? row.text : row.correction).font(.callout).lineLimit(3)
                Text((row.kind == "inferred" ? "Tentative interpretation" : row.kind == "your_words" || row.kind == "your_note" ? "Your words" : "Captured context") + " · " + row.priority.capitalized)
                    .font(.caption).foregroundStyle(Theme.inkSoft)
            }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).padding(.vertical, 8)
        }.buttonStyle(.plain)
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
        value = fresh; pending = nil; error = "Context saved. It will shape future replies."
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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(item.title).font(.title2)
                Text(item.kind == "inferred" ? "A tentative interpretation, open to correction." : item.kind == "source" ? "Material supplied for this reply. A retrieval summary can differ from the source file." : "The saved material, preserved as it was.")
                    .font(.caption).foregroundStyle(Theme.inkSoft)
                Text(item.text).textSelection(.enabled)
                Button("Listen") { store.readAloud(Readable(title: item.title, body: item.text, kind: "context")) }
                Text(item.source).font(.caption).textSelection(.enabled)
                if !item.as_of.isEmpty { Text("Recorded: " + item.as_of).font(.caption) }
                Picker("Attention", selection: $priority) {
                    Text("Less").tag("less"); Text("Normal").tag("normal"); Text("More").tag("more")
                }.pickerStyle(.segmented).disabled(pending != nil)
                Text("More requests attention in the next reply; the latest choices come first. Long items use a labelled excerpt, and space may limit what fits. Less asks for less emphasis. These controls do not delete sources or change model weights.").font(.caption)
                TextField("What should she understand differently?", text: $correction, axis: .vertical)
                    .focused($writing).accessibilityIdentifier("context.correction").lineLimit(3...8).padding(14).background(Theme.ink.opacity(0.04))
                    .disabled(pending != nil)
                if correction.unicodeScalars.count > 2000 { Text("Keep the correction under 2,000 characters. Your draft is retained.").font(.caption) }
                Button(pending == nil ? "Save context" : "Retry saved change") { Task { await save() } }
                    .frame(minHeight: 44).disabled(busy || correction.unicodeScalars.count > 2000)
                if pending != nil {
                    Button("Edit instead") { pending = nil; UserDefaults.standard.removeObject(forKey: key + ".pending") }
                        .disabled(busy)
                }
                Text(status).font(.callout).foregroundStyle(Theme.inkSoft)
                if item.kind == "source" {
                    Button("Open the source here") {
                        Task { source = await store.contextSource(replyID, itemID: item.id); if source == nil { status = "The source could not be opened." } }
                    }.frame(minHeight: 44)
                }
                if let source {
                    Text(source.notice).font(.caption)
                    Text(source.text).textSelection(.enabled)
                    Button("Listen to the source") { store.readAloud(Readable(title: source.title, body: source.text, kind: "context")) }
                }
            }.padding(22)
        }.background(Theme.paper).foregroundStyle(Theme.ink)
        .navigationTitle("Enrich this context").navigationBarTitleDisplayMode(.inline)
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
        status = "Saved for future replies. Open a new reply to see what was actually supplied."
    }
}
