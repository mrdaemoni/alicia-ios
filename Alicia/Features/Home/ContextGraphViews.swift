import SwiftUI

// MARK: - Us: "In the middle of" (Option A, CL-20260918-context-graph-behaviours)
//
// Two to three lines above the goals summary — the core of his situation
// and what is most active today — each carrying its honest mark (stated is
// his; an unconfirmed reading says so). The kicker opens the room with the
// whole graph. Nothing here is a card; it is ink on the same paper as Us.

struct WhereYouAreSection: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        if let graph = store.contextGraph, !graph.whereYouAre.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                NavigationLink {
                    ContextGraphRoom()
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("IN THE MIDDLE OF")
                            .font(.system(size: 10, design: .monospaced)).tracking(2)
                            .foregroundStyle(Theme.inkSoft)
                        Spacer(minLength: 0)
                        Text(graph.needsReview > 0 ? "\(graph.needsReview) TO REVIEW" : "OPEN")
                            .font(.system(size: 9, design: .monospaced)).tracking(1.6)
                            .foregroundStyle(Theme.accentSoft)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("us.contextGraph.open")
                // The arrangement, when it is ready: each node with what today
                // bears on it beneath. Otherwise the plain lines, never a wait.
                if let arrangement = store.contextArrangement, arrangement.isReady, !arrangement.groups.isEmpty {
                    ForEach(arrangement.groups) { group in
                        VStack(alignment: .leading, spacing: 8) {
                            NavigationLink { ContextNodeView(nodeID: group.node.id) } label: {
                                ContextNodeLine(node: graph.whereYouAre.first { $0.id == group.node.id }
                                                ?? graph.nodes.first { $0.id == group.node.id }
                                                ?? ContextNode.placeholder(from: group.node))
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("us.contextGraph.node." + group.node.id)
                            ForEach(group.items) { item in
                                NavigationLink { ContextNodeView(nodeID: group.node.id, around: item) } label: {
                                    ArrangedItemLine(item: item)
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("us.arranged." + item.id)
                            }
                        }
                    }
                } else {
                    ForEach(graph.whereYouAre) { node in
                        NavigationLink { ContextNodeView(nodeID: node.id) } label: {
                            ContextNodeLine(node: node)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("us.contextGraph.node." + node.id)
                    }
                }
                Rectangle().fill(Theme.stroke).frame(height: 0.7)
            }
        }
    }
}

/// One thing arranged around a node: a kicker for what it is, the line
/// itself, and the why in a smaller hand. Indented under the node it bears on.
struct ArrangedItemLine: View {
    let item: ContextArrangement.Item

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Rectangle().fill(Theme.stroke).frame(width: 0.7).padding(.vertical, 2)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.label)
                    .font(.system(size: 9, design: .monospaced)).tracking(1.6)
                    .foregroundStyle(item.kind == "words" ? Theme.ink : Theme.accentSoft)
                Text(item.title.strippedEmojis)
                    .font(.system(size: 15, design: .serif))
                    .foregroundStyle(item.kind == "finding" ? Theme.inkSoft : Theme.ink)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                if !item.why.isEmpty && item.kind != "words" {
                    Text(item.why.strippedEmojis)
                        .font(.system(size: 12, design: .serif)).italic()
                        .foregroundStyle(Theme.inkSoft.opacity(0.85))
                        .lineLimit(2)
                }
            }
        }
        .padding(.leading, 6)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
    }
}

/// One node as a line: title in serif, the mark beneath it, a hand-drawn
/// underline seeded by the node id (never by state — the v26 lesson).
struct ContextNodeLine: View {
    let node: ContextNode
    var showSummary = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(node.title.strippedEmojis)
                .font(.system(size: 17, design: .serif))
                .foregroundStyle(node.isHis ? Theme.ink : Theme.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
            if showSummary, !node.summary.isEmpty {
                Text(node.summary.strippedEmojis)
                    .font(.system(size: 14, design: .serif))
                    .foregroundStyle(Theme.inkSoft)
                    .lineLimit(2)
            }
            HStack(spacing: 8) {
                Text(node.mark)
                    .font(.system(size: 9, design: .monospaced)).tracking(1.4)
                    .foregroundStyle(node.isUnconfirmed ? Theme.amber : Theme.inkSoft)
                if !node.updated.isEmpty {
                    Text(node.updated)
                        .font(.system(size: 9, design: .monospaced)).tracking(1.2)
                        .foregroundStyle(Theme.inkSoft.opacity(0.7))
                }
            }
            InkUnderline(seed: node.id.inkSeed)
                .frame(height: 3)
                .opacity(node.isHis ? 0.55 : 0.3)
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
    }
}

// MARK: - The room: the whole graph, grouped, with the day's elevation

struct ContextGraphRoom: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if let graph = store.contextGraph {
                    Text(graph.notice)
                        .font(.system(size: 13, design: .serif)).italic()
                        .foregroundStyle(Theme.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                    elevated
                    ForEach(graph.groups, id: \.kind) { group in
                        VStack(alignment: .leading, spacing: 12) {
                            Text(group.kind.uppercased())
                                .font(.system(size: 10, design: .monospaced)).tracking(2)
                                .foregroundStyle(group.kind == "awaiting your review" ? Theme.amber : Theme.inkSoft)
                            ForEach(group.nodes) { node in
                                NavigationLink { ContextNodeView(nodeID: node.id) } label: {
                                    ContextNodeLine(node: node, showSummary: true)
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("contextGraph.node." + node.id)
                            }
                        }
                    }
                    Text("\(graph.total) nodes · notes in Alicia/Hector/Context")
                        .font(.system(size: 10, design: .monospaced)).tracking(1.4)
                        .foregroundStyle(Theme.inkSoft.opacity(0.7))
                } else if store.contextGraphError.isEmpty {
                    Text("Reading what she is holding of your situation…")
                        .font(.system(size: 15, design: .serif)).italic()
                        .foregroundStyle(Theme.inkSoft)
                } else {
                    Text(store.contextGraphError)
                        .font(.system(size: 15, design: .serif))
                        .foregroundStyle(Theme.rose)
                    Button("Try again") { Task { await store.refreshContextGraph() } }
                        .font(.callout).frame(minHeight: 44)
                }
            }
            .padding(22)
        }
        .presenceBackground(.us, store: store)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { InkBackButton() }
            ToolbarItem(placement: .principal) { InkTitleLine(text: "In the middle of", size: 16) }
        }
        .task { await store.refreshContextGraph(); await store.refreshContextArrangement(); await store.refreshContextElevation() }
        .refreshable { await store.refreshContextGraph(); await store.refreshContextArrangement(); await store.refreshContextElevation() }
    }

    @ViewBuilder private var elevated: some View {
        if let arrangement = store.contextArrangement, arrangement.isReady, arrangement.arrangedCount > 0 {
            VStack(alignment: .leading, spacing: 12) {
                Text("ARRANGED TODAY")
                    .font(.system(size: 10, design: .monospaced)).tracking(2)
                    .foregroundStyle(Theme.inkSoft)
                if !arrangement.episodeID.isEmpty {
                    Text(("around " + arrangement.episodeID).uppercased())
                        .font(.system(size: 9, design: .monospaced)).tracking(1.4)
                        .foregroundStyle(Theme.inkSoft.opacity(0.8))
                }
                ForEach(arrangement.groups.filter { $0.arranged }) { group in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(group.node.title.strippedEmojis)
                            .font(.system(size: 15, design: .serif))
                        ForEach(group.items) { item in
                            NavigationLink { ContextNodeView(nodeID: group.node.id, around: item) } label: {
                                ArrangedItemLine(item: item)
                            }.buttonStyle(.plain)
                        }
                    }
                }
                Text(arrangement.notice)
                    .font(.system(size: 11, design: .serif)).italic()
                    .foregroundStyle(Theme.inkSoft.opacity(0.8))
            }
            Rectangle().fill(Theme.stroke).frame(height: 0.7)
        } else if let elevation = store.contextElevation {
            VStack(alignment: .leading, spacing: 10) {
                Text("ELEVATED TODAY")
                    .font(.system(size: 10, design: .monospaced)).tracking(2)
                    .foregroundStyle(Theme.inkSoft)
                if !elevation.episodeID.isEmpty {
                    Text(("from " + elevation.episodeID).uppercased())
                        .font(.system(size: 9, design: .monospaced)).tracking(1.4)
                        .foregroundStyle(Theme.inkSoft.opacity(0.8))
                }
                if elevation.status == "preparing" {
                    Text("Preparing.").font(.system(size: 14, design: .serif)).italic().foregroundStyle(Theme.inkSoft)
                } else if elevation.items.isEmpty {
                    Text("Nothing today — " + (elevation.reason.isEmpty ? "nothing cleared the threshold." : elevation.reason + "."))
                        .font(.system(size: 14, design: .serif)).italic()
                        .foregroundStyle(Theme.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(elevation.items) { item in
                        NavigationLink { ContextNodeView(nodeID: item.node_id, elevated: item) } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.kind.uppercased() + " · " + item.title.strippedEmojis)
                                    .font(.system(size: 15, design: .serif))
                                Text(item.why.strippedEmojis)
                                    .font(.system(size: 13, design: .serif))
                                    .foregroundStyle(Theme.inkSoft).lineLimit(3)
                            }
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                }
            }
            Rectangle().fill(Theme.stroke).frame(height: 0.7)
        }
    }
}

// MARK: - One node: body, receipts, related, and the three acts

struct ContextNodeView: View {
    @Environment(AppStore.self) private var store
    let nodeID: String
    var elevated: ContextElevation.Item? = nil
    var around: ContextArrangement.Item? = nil
    @State private var node: ContextNode?
    @State private var related: [ContextNode] = []
    @State private var error = ""
    @State private var busy = false
    @State private var pending: ContextGraphMutation?
    @State private var confirmation = ""
    @State private var correcting = false
    @State private var correction = ""
    @State private var lettingGo = false
    @State private var receiptID = UUID().uuidString
    @State private var receiptIdentity = ""
    @FocusState private var writing: Bool
    private var key: String { "alicia.contextNode." + nodeID }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if let node {
                    content(node)
                } else if error.isEmpty {
                    Text("Opening…").font(.system(size: 15, design: .serif)).italic().foregroundStyle(Theme.inkSoft)
                } else {
                    Text(error).font(.system(size: 15, design: .serif)).foregroundStyle(Theme.rose)
                    Button("Try again") { Task { await load() } }.font(.callout).frame(minHeight: 44)
                }
            }
            .padding(22)
        }
        .scrollDismissesKeyboard(.interactively)
        .presenceBackground(.us, store: store)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { InkBackButton() }
            ToolbarItem(placement: .principal) { InkTitleLine(text: node?.kind.capitalized ?? "Node", size: 16) }
            ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done writing") { writing = false } }
        }
        .task {
            correction = UserDefaults.standard.string(forKey: key + ".correction") ?? ""
            if let data = UserDefaults.standard.data(forKey: key + ".pending") {
                pending = try? JSONDecoder().decode(ContextGraphMutation.self, from: data)
            }
            await load()
        }
        .onChange(of: correction) { _, text in UserDefaults.standard.set(text, forKey: key + ".correction") }
    }

    @ViewBuilder private func content(_ node: ContextNode) -> some View {
        Text(node.title.strippedEmojis)
            .font(.system(size: 25, design: .serif))
            .fixedSize(horizontal: false, vertical: true)
        Text(node.mark + (node.updated.isEmpty ? "" : " · " + node.updated))
            .font(.system(size: 10, design: .monospaced)).tracking(1.6)
            .foregroundStyle(node.isUnconfirmed ? Theme.amber : Theme.inkSoft)
        if let elevated {
            VStack(alignment: .leading, spacing: 6) {
                Text("WHY THIS WAS ELEVATED")
                    .font(.system(size: 9, design: .monospaced)).tracking(1.6)
                    .foregroundStyle(Theme.accentSoft)
                Text(elevated.why.strippedEmojis)
                    .font(.system(size: 14, design: .serif)).foregroundStyle(Theme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                if !elevated.evidence.excerpt.isEmpty {
                    Text("“" + elevated.evidence.excerpt.strippedEmojis + "”")
                        .font(.system(size: 13, design: .serif)).italic()
                        .foregroundStyle(Theme.inkSoft.opacity(0.9))
                        .fixedSize(horizontal: false, vertical: true)
                    Text((elevated.evidence.source + " · " + elevated.evidence.ref).uppercased())
                        .font(.system(size: 9, design: .monospaced)).tracking(1.2)
                        .foregroundStyle(Theme.inkSoft.opacity(0.7)).lineLimit(2)
                }
            }
            .card(padding: 14, radius: 14)
        }
        Text(node.body.strippedEmojis)
            .font(.system(size: 17, design: .serif))
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
        if let group = store.contextArrangement?.group(for: node.id), !group.items.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("AROUND THIS TODAY")
                    .font(.system(size: 10, design: .monospaced)).tracking(2)
                    .foregroundStyle(Theme.inkSoft)
                ForEach(group.items) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        ArrangedItemLine(item: item)
                        if item.id == around?.id || group.items.count <= 2 {
                            if !item.evidence.excerpt.isEmpty, item.evidence.excerpt != item.title {
                                Text("“" + item.evidence.excerpt.strippedEmojis + "”")
                                    .font(.system(size: 13, design: .serif)).italic()
                                    .foregroundStyle(Theme.inkSoft.opacity(0.9))
                                    .padding(.leading, 18)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Text((item.evidence.source + (item.date.isEmpty ? "" : " · " + item.date)).uppercased())
                                .font(.system(size: 9, design: .monospaced)).tracking(1.2)
                                .foregroundStyle(Theme.inkSoft.opacity(0.7))
                                .padding(.leading, 18)
                                .lineLimit(2)
                        }
                    }
                }
            }
        }
        if node.status != "retired" {
            acts(node)
        } else {
            Text("Let go" + (node.superseded_by.isEmpty ? "." : " · superseded."))
                .font(.system(size: 13, design: .serif)).italic().foregroundStyle(Theme.inkSoft)
        }
        if !confirmation.isEmpty {
            Text(confirmation).font(.system(size: 13, design: .serif)).foregroundStyle(Theme.accent)
        }
        if !error.isEmpty { Text(error).font(.system(size: 13, design: .serif)).foregroundStyle(Theme.rose) }
        if pending != nil {
            Text("Your exact change is kept on this phone until the save is confirmed.").font(.caption)
            Button(busy ? "Saving…" : "Retry saved change") { Task { await retry() } }.font(.callout).frame(minHeight: 44).disabled(busy)
            Button("Edit instead") { pending = nil; UserDefaults.standard.removeObject(forKey: key + ".pending") }
                .font(.callout).frame(minHeight: 44).disabled(busy)
        }
        if !node.receipts.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("RECEIPTS").font(.system(size: 10, design: .monospaced)).tracking(2).foregroundStyle(Theme.inkSoft)
                ForEach(Array(node.receipts.suffix(6).enumerated()), id: \.offset) { _, r in
                    VStack(alignment: .leading, spacing: 3) {
                        Text("“" + r.excerpt.strippedEmojis + "”")
                            .font(.system(size: 14, design: .serif))
                            .fixedSize(horizontal: false, vertical: true)
                        Text((r.source + " · " + String(r.observed_at.prefix(10))).uppercased())
                            .font(.system(size: 9, design: .monospaced)).tracking(1.2)
                            .foregroundStyle(Theme.inkSoft.opacity(0.8))
                    }
                }
            }
        }
        if !node.links.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("CONNECTS TO").font(.system(size: 10, design: .monospaced)).tracking(2).foregroundStyle(Theme.inkSoft)
                ForEach(node.links, id: \.self) { link in
                    Text(link.split(separator: "/").last.map(String.init) ?? link)
                        .font(.system(size: 14, design: .serif)).foregroundStyle(Theme.inkSoft)
                }
            }
        }
        if !related.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("RELATED").font(.system(size: 10, design: .monospaced)).tracking(2).foregroundStyle(Theme.inkSoft)
                ForEach(related) { r in
                    NavigationLink { ContextNodeView(nodeID: r.id) } label: { ContextNodeLine(node: r) }.buttonStyle(.plain)
                }
            }
        }
        if node.worth_hits + node.worth_misses > 0 {
            Text("helped \(node.worth_hits) · missed \(node.worth_misses)".uppercased())
                .font(.system(size: 9, design: .monospaced)).tracking(1.2)
                .foregroundStyle(Theme.inkSoft.opacity(0.7))
        }
    }

    // The three acts, in the vocabulary Together already uses: a chip that
    // is selected when it is the current state; tapping never toggles a
    // state off (keep is not undone by keep), and "let go" asks first.
    @ViewBuilder private func acts(_ node: ContextNode) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { choices(node) }
                VStack(alignment: .leading, spacing: 10) { choices(node) }
            }
            if correcting {
                VStack(alignment: .leading, spacing: 8) {
                    Text("In your words — this replaces her reading and becomes stated.")
                        .font(.caption).foregroundStyle(Theme.inkSoft)
                    TextField("What is actually true here…", text: $correction, axis: .vertical)
                        .focused($writing).lineLimit(3...8).padding(14)
                        .background(Theme.ink.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
                        .disabled(pending != nil)
                    HStack(spacing: 22) {
                        Button("SAVE MY WORDS") {
                            submit(ContextGraphMutation(action: "correct", id: node.id, event_id: receipt("correct|" + correction), text: correction))
                        }
                        .font(.system(size: 10, design: .monospaced)).tracking(1.6)
                        .frame(minHeight: 44)
                        .disabled(busy || pending != nil || correction.trimmingCharacters(in: .whitespacesAndNewlines).count < 3 || correction.unicodeScalars.count > 2000)
                        .accessibilityIdentifier("contextNode.saveCorrection")
                        Button("NOT NOW") { correcting = false; writing = false }
                            .font(.system(size: 10, design: .monospaced)).tracking(1.6).frame(minHeight: 44)
                    }
                }
            }
            if lettingGo {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Let go of this? It stays in the notes as retired and stops shaping replies.")
                        .font(.caption).foregroundStyle(Theme.inkSoft)
                    HStack(spacing: 22) {
                        Button("YES, LET IT GO") {
                            submit(ContextGraphMutation(action: "retire", id: node.id, event_id: receipt("retire"), reason: "let go from the app"))
                        }
                        .font(.system(size: 10, design: .monospaced)).tracking(1.6).frame(minHeight: 44)
                        .disabled(busy || pending != nil)
                        .accessibilityIdentifier("contextNode.confirmRetire")
                        Button("KEEP IT") { lettingGo = false }
                            .font(.system(size: 10, design: .monospaced)).tracking(1.6).frame(minHeight: 44)
                    }
                }
            }
        }
    }

    @ViewBuilder private func choices(_ node: ContextNode) -> some View {
        WorkReviewChoice(title: node.status == "confirmed" ? "Kept" : "Keep", selected: node.status == "confirmed") {
            guard node.status != "confirmed" else { return }
            submit(ContextGraphMutation(action: "confirm", id: node.id, event_id: receipt("confirm")))
        }.accessibilityIdentifier("contextNode.keep")
        WorkReviewChoice(title: "Correct", selected: correcting) {
            correcting.toggle(); lettingGo = false
            if correcting { writing = true }
        }.accessibilityIdentifier("contextNode.correct")
        WorkReviewChoice(title: "Let go", selected: lettingGo) {
            lettingGo.toggle(); correcting = false
        }.accessibilityIdentifier("contextNode.letGo")
    }

    /// Same UUID while the payload is unchanged (safe retry); a new one when it changes.
    private func receipt(_ identity: String) -> String {
        let full = nodeID + "|" + identity
        if receiptIdentity != full { receiptID = UUID().uuidString; receiptIdentity = full }
        return receiptID
    }

    private func load() async {
        if let fresh = await store.contextNode(nodeID) {
            node = fresh.node; related = fresh.related; error = ""
        } else if node == nil {
            error = "This node could not be reached. Your draft is kept."
        }
    }

    private func submit(_ request: ContextGraphMutation) {
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
        guard let result = await store.contextGraphAct(request), result.ok else {
            error = "The change was not confirmed. Retry sends the same request."; return
        }
        if let fresh = result.node { node = fresh }
        pending = nil; error = ""
        UserDefaults.standard.removeObject(forKey: key + ".pending")
        switch request.action {
        case "confirm": confirmation = "Kept. It is yours now and ranks as such."
        case "correct": confirmation = "Your words replace her reading. The earlier reading stays visible in the note."; correction = ""; correcting = false
        case "retire": confirmation = "Let go. It stays in the notes as retired."; lettingGo = false
        default: confirmation = "Saved."
        }
        await store.refreshContextGraph()
    }
}
