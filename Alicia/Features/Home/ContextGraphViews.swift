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
            InkSection(kicker: "In the middle of", spacing: 8) {
                // The arrangement, when it is prepared and about this day and
                // episode: each node with what today bears on it beneath.
                // Otherwise the plain lines, never a wait and never yesterday.
                if let arrangement = store.currentContextArrangement, !arrangement.groups.isEmpty {
                    ForEach(Array(arrangement.groups.enumerated()), id: \.element.id) { index, group in
                        if index > 0 { InkRule(opacity: 0.6) }
                        VStack(alignment: .leading, spacing: 8) {
                            NavigationLink { ContextNodeView(nodeID: group.node.id) } label: {
                                ContextNodeLine(node: graph.whereYouAre.first { $0.id == group.node.id }
                                                ?? graph.nodes.first { $0.id == group.node.id }
                                                ?? ContextNode.placeholder(from: group.node))
                            }
                            .buttonStyle(.inkLink)
                            .accessibilityIdentifier("us.contextGraph.node." + group.node.id)
                            ForEach(group.items) { item in
                                NavigationLink { ContextNodeView(nodeID: group.node.id, around: item) } label: {
                                    ArrangedItemLine(item: item)
                                }
                                .buttonStyle(.inkLink)
                                .accessibilityIdentifier("us.arranged." + item.id)
                            }
                        }
                    }
                } else {
                    ForEach(Array(graph.whereYouAre.enumerated()), id: \.element.id) { index, node in
                        if index > 0 { InkRule(opacity: 0.6) }
                        NavigationLink { ContextNodeView(nodeID: node.id) } label: {
                            ContextNodeLine(node: node)
                        }
                        .buttonStyle(.inkLink)
                        .accessibilityIdentifier("us.contextGraph.node." + node.id)
                    }
                }
                InkRule(opacity: 0.6)
                NavigationLink {
                    ContextGraphRoom()
                } label: {
                    InkLinkLabel(title: "Your whole situation",
                                 detail: (graph.needsReview > 0 ? "\(graph.needsReview) to review · " : "")
                                    + "Everything she holds of it, grouped")
                }
                .buttonStyle(.inkLink)
                .accessibilityIdentifier("us.contextGraph.open")
            }
        }
    }
}

/// One thing arranged around a node: a kicker for what it is, the line
/// itself, and the why in a smaller hand. Indented under the node it bears on.
struct ArrangedItemLine: View {
    let item: ContextArrangement.Item
    /// Inside a link it carries her chevron; shown as evidence it does not.
    var navigates = true

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Rectangle().fill(Theme.stroke).frame(width: 0.7).padding(.vertical, 2)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.label)
                    .font(.system(size: 9, design: .monospaced)).tracking(1.6)
                    .foregroundStyle(item.kind == "words" ? Theme.ink : Theme.inkSoft)
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
            .frame(maxWidth: .infinity, alignment: .leading)
            if navigates {
                InkChevron(pointing: .right, size: 12, color: Theme.inkSoft, seed: item.id.inkSeed)
            }
        }
        .padding(.leading, 6)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
    }
}

/// One node as a line: title in serif, the mark beneath it, and her chevron
/// (seeded by the node id, never by state — the v26 lesson), because every
/// place it appears opens the node.
struct ContextNodeLine: View {
    let node: ContextNode
    var showSummary = false

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
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
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        InkChevron(pointing: .right, size: 14, color: Theme.inkSoft, seed: node.id.inkSeed)
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
                    InkNotice(text: graph.notice)
                    elevated
                    ForEach(graph.groups, id: \.kind) { group in
                        InkSection(kicker: group.kind, spacing: 8) {
                            // What waits on him keeps its amber mark.
                            if group.kind == "awaiting your review" {
                                InkSpark(size: 9, color: Theme.amber, seed: 3).accessibilityHidden(true)
                            }
                        } content: {
                            ForEach(Array(group.nodes.enumerated()), id: \.element.id) { index, node in
                                if index > 0 { InkRule(opacity: 0.6) }
                                NavigationLink { ContextNodeView(nodeID: node.id) } label: {
                                    ContextNodeLine(node: node, showSummary: true)
                                }
                                .buttonStyle(.inkLink)
                                .accessibilityIdentifier("contextGraph.node." + node.id)
                            }
                        }
                    }
                    InkRule()
                    Text("\(graph.total) nodes · notes in Alicia/Hector/Context")
                        .font(.system(size: 10, design: .monospaced)).tracking(1.4)
                        .foregroundStyle(Theme.inkSoft.opacity(0.7))
                } else if store.contextGraphError.isEmpty {
                    InkNotice(text: "Reading what she is holding of your situation…")
                } else {
                    InkNotice(text: store.contextGraphError, kind: .error)
                    Button("Try again") { Task { await store.refreshContextGraph() } }
                        .buttonStyle(.inkQuiet)
                }
            }
            .padding(22)
        }
        .presenceBackground(.us, store: store)
        .inkPushedPage("In the middle of")
        .task { await store.refreshContextGraph(); await store.refreshContextArrangement(); await store.refreshContextElevation() }
        .refreshable { await store.refreshContextGraph(); await store.refreshContextArrangement(); await store.refreshContextElevation() }
    }

    @ViewBuilder private var elevated: some View {
        if let arrangement = store.currentContextArrangement, arrangement.arrangedCount > 0 {
            InkSection(kicker: "Arranged today") {
                // A refresh in flight says so rather than passing the last
                // good answer off as this minute's.
                if arrangement.isRefreshing {
                    Text("REFRESHING")
                        .font(.system(size: 9, design: .monospaced)).tracking(1.4)
                        .foregroundStyle(Theme.inkSoft.opacity(0.8))
                }
            } content: {
                if !arrangement.episodeID.isEmpty {
                    Text(("around " + arrangement.episodeID).uppercased())
                        .font(.system(size: 9, design: .monospaced)).tracking(1.4)
                        .foregroundStyle(Theme.inkSoft.opacity(0.8))
                }
                ForEach(Array(arrangement.groups.filter { $0.arranged }.enumerated()), id: \.element.id) { index, group in
                    if index > 0 { InkRule(opacity: 0.6) }
                    VStack(alignment: .leading, spacing: 6) {
                        // The node these gather around: a heading, not a link.
                        Text(group.node.title.strippedEmojis)
                            .font(.system(size: 15, design: .serif)).italic()
                            .foregroundStyle(Theme.inkSoft)
                            .accessibilityAddTraits(.isHeader)
                        ForEach(group.items) { item in
                            NavigationLink { ContextNodeView(nodeID: group.node.id, around: item) } label: {
                                ArrangedItemLine(item: item)
                            }.buttonStyle(.inkLink)
                        }
                    }
                }
                InkNotice(text: arrangement.notice)
            }
        } else if let elevation = store.contextElevation {
            InkSection(kicker: "Elevated today", spacing: 10) {
                if !elevation.episodeID.isEmpty {
                    Text(("from " + elevation.episodeID).uppercased())
                        .font(.system(size: 9, design: .monospaced)).tracking(1.4)
                        .foregroundStyle(Theme.inkSoft.opacity(0.8))
                }
                if elevation.status == "preparing" {
                    InkNotice(text: "Preparing.")
                } else if elevation.items.isEmpty {
                    InkNotice(text: "Nothing today — " + (elevation.reason.isEmpty ? "nothing cleared the threshold." : elevation.reason + "."))
                } else {
                    ForEach(Array(elevation.items.enumerated()), id: \.element.id) { index, item in
                        if index > 0 { InkRule(opacity: 0.6) }
                        NavigationLink { ContextNodeView(nodeID: item.node_id, elevated: item) } label: {
                            InkLinkLabel(title: item.kind.capitalized + " · " + item.title, detail: item.why)
                        }.buttonStyle(.inkLink)
                    }
                }
            }
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
                    InkNotice(text: "Opening…")
                } else {
                    InkNotice(text: error, kind: .error)
                    Button("Try again") { Task { await load() } }.buttonStyle(.inkQuiet)
                }
            }
            .padding(22)
        }
        .scrollDismissesKeyboard(.interactively)
        .presenceBackground(.us, store: store)
        .inkPushedPage(node?.kind.capitalized ?? "Node")
        .toolbar {
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
                InkKicker(text: "Why this was elevated")
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
            .frame(maxWidth: .infinity, alignment: .leading)
            .card(padding: 14, radius: 14)
        }
        Text(node.body.strippedEmojis)
            .font(.system(size: 17, design: .serif))
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
        if let group = store.currentContextArrangement?.group(for: node.id), !group.items.isEmpty {
            InkSection(kicker: "Around this today", spacing: 10) {
                ForEach(Array(group.items.enumerated()), id: \.element.id) { index, item in
                    if index > 0 { InkRule(opacity: 0.6) }
                    VStack(alignment: .leading, spacing: 4) {
                        ArrangedItemLine(item: item, navigates: false)
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
        InkSection(kicker: "Is this right?") {
            if node.status != "retired" {
                acts(node)
            } else {
                InkNotice(text: "Let go" + (node.superseded_by.isEmpty ? "." : " · superseded."))
            }
            InkNotice(text: confirmation, kind: .success)
            InkNotice(text: error, kind: .error)
            if pending != nil {
                InkNotice(text: "Your exact change is kept on this phone until the save is confirmed.")
                HStack(spacing: 22) {
                    Button(busy ? "Saving…" : "Retry saved change") { Task { await retry() } }
                        .buttonStyle(.inkQuiet).disabled(busy)
                    Button("Edit instead") { pending = nil; UserDefaults.standard.removeObject(forKey: key + ".pending") }
                        .buttonStyle(.inkQuiet).disabled(busy)
                }
            }
        }
        if !node.receipts.isEmpty {
            InkSection(kicker: "Receipts", spacing: 10) {
                ForEach(Array(node.receipts.suffix(6).enumerated()), id: \.offset) { index, r in
                    if index > 0 { InkRule(opacity: 0.6) }
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
            // Vault note names, not destinations in the app: one line of
            // plain text, so nothing here reads as a link.
            InkSection(kicker: "Connects to", spacing: 8) {
                Text(node.links.map { $0.split(separator: "/").last.map(String.init) ?? $0 }.joined(separator: " · "))
                    .font(.system(size: 14, design: .serif)).italic().foregroundStyle(Theme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        if !related.isEmpty {
            InkSection(kicker: "Related", spacing: 8) {
                ForEach(Array(related.enumerated()), id: \.element.id) { index, r in
                    if index > 0 { InkRule(opacity: 0.6) }
                    NavigationLink { ContextNodeView(nodeID: r.id) } label: { ContextNodeLine(node: r) }.buttonStyle(.inkLink)
                }
            }
        }
        if node.worth_hits + node.worth_misses > 0 {
            Text("helped \(node.worth_hits) · missed \(node.worth_misses)".uppercased())
                .font(.system(size: 9, design: .monospaced)).tracking(1.2)
                .foregroundStyle(Theme.inkSoft.opacity(0.7))
        }
    }

    // The three acts, each drawn as what it is: keeping is an action, a
    // correction opens its editor here, and letting go is the removing kind
    // and asks first. Keep is not undone by keep.
    @ViewBuilder private func acts(_ node: ContextNode) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Button(node.status == "confirmed" ? "Kept" : "Keep") {
                    guard node.status != "confirmed" else { return }
                    submit(ContextGraphMutation(action: "confirm", id: node.id, event_id: receipt("confirm")))
                }
                .buttonStyle(.inkSecondaryCompact)
                .disabled(node.status == "confirmed")
                .accessibilityAddTraits(node.status == "confirmed" ? .isSelected : [])
                .accessibilityIdentifier("contextNode.keep")
                Button("Let go") { lettingGo.toggle(); correcting = false }
                    .buttonStyle(.inkDestructiveCompact)
                    .accessibilityAddTraits(lettingGo ? .isSelected : [])
                    .accessibilityIdentifier("contextNode.letGo")
            }
            if lettingGo {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Let go of this? It stays in the notes as retired and stops shaping replies.")
                        .font(.caption).foregroundStyle(Theme.inkSoft)
                    HStack(spacing: 22) {
                        Button("Yes, let it go") {
                            submit(ContextGraphMutation(action: "retire", id: node.id, event_id: receipt("retire"), reason: "let go from the app"))
                        }
                        .buttonStyle(.inkDestructiveCompact)
                        .disabled(busy || pending != nil)
                        .accessibilityIdentifier("contextNode.confirmRetire")
                        Button("Keep it") { lettingGo = false }
                            .buttonStyle(.inkQuiet)
                    }
                }
                .card(padding: 14, radius: 14)
            }
            InkDisclosureToggle(title: "Correct this in your words", open: correcting) {
                correcting.toggle(); lettingGo = false
                if correcting { writing = true }
            }
            .accessibilityIdentifier("contextNode.correct")
            if correcting {
                VStack(alignment: .leading, spacing: 8) {
                    Text("In your words — this replaces her reading and becomes stated.")
                        .font(.caption).foregroundStyle(Theme.inkSoft)
                    TextField("What is actually true here…", text: $correction, axis: .vertical)
                        .focused($writing).lineLimit(3...8)
                        .inkField()
                        .disabled(pending != nil)
                    Button("Save my words") {
                        submit(ContextGraphMutation(action: "correct", id: node.id, event_id: receipt("correct|" + correction), text: correction))
                    }
                    .buttonStyle(.inkPrimary)
                    .disabled(busy || pending != nil || correction.trimmingCharacters(in: .whitespacesAndNewlines).count < 3 || correction.unicodeScalars.count > 2000)
                    .accessibilityIdentifier("contextNode.saveCorrection")
                    Button("Not now") { correcting = false; writing = false }
                        .buttonStyle(.inkQuiet)
                }
            }
        }
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
