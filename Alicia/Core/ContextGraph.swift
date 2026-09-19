import Foundation

/// Hector's context graph — his situation as typed, dated nodes the backend
/// keeps as vault notes (`GET /api/context_graph`). Status is epistemic and
/// only his acts move it: `stated` is his words, `inferred` is her reading
/// and unconfirmed, `confirmed` he kept, `retired` he let go.
struct ContextNode: Codable, Identifiable, Hashable {
    struct Receipt: Codable, Hashable {
        var source, ref, observed_at, excerpt: String
    }
    var id, kind, title, status: String
    var summary: String
    var body: String
    var updated: String
    var importance: Int
    var needs_review: Bool
    var themes, links, related: [String]
    var receipts: [Receipt]
    var worth_hits, worth_misses: Int
    var superseded_by: String
    var why: [String]

    var isUnconfirmed: Bool { status == "inferred" && needs_review }
    /// "STATED · PROJECT" — the honest mark every row carries.
    var mark: String {
        let s = status == "inferred" ? (needs_review ? "unconfirmed reading" : "reading") : status
        return (s + " · " + kind).uppercased()
    }
    var isHis: Bool { status == "stated" || status == "confirmed" }

    /// A line for a node the arrangement names but the graph list did not carry.
    static func placeholder(from ref: ContextArrangement.ContextNodeRef) -> ContextNode {
        ContextNode(id: ref.id, kind: ref.kind, title: ref.title, status: ref.status, summary: ref.summary, body: ref.summary,
                    updated: ref.updated, importance: 5, needs_review: ref.needs_review, themes: [], links: [], related: [],
                    receipts: [], worth_hits: 0, worth_misses: 0, superseded_by: "", why: [])
    }
}

struct ContextGraph: Codable {
    var generatedAt: String
    var nodes: [ContextNode]
    var core: [ContextNode]
    var notice: String
    var needsReview: Int
    var total: Int

    static let kindOrder = ["situation", "project", "goal", "tension", "decision", "practice",
                            "person", "place", "body", "belief", "preference", "fact"]

    /// Nodes grouped by kind in a fixed editorial order; unconfirmed readings first.
    var groups: [(kind: String, nodes: [ContextNode])] {
        var out: [(String, [ContextNode])] = []
        let review = nodes.filter { $0.isUnconfirmed }
        if !review.isEmpty { out.append(("awaiting your review", review)) }
        for kind in Self.kindOrder {
            let rows = nodes.filter { $0.kind == kind && !$0.isUnconfirmed }
            if !rows.isEmpty { out.append((kind, rows)) }
        }
        return out
    }

    /// What Us shows above the goals: the core, then the most active nodes.
    var whereYouAre: [ContextNode] {
        var seen = Set<String>()
        var rows: [ContextNode] = []
        for n in core + nodes where !seen.contains(n.id) && n.status != "retired" {
            seen.insert(n.id); rows.append(n)
            if rows.count == 3 { break }
        }
        return rows
    }
}

/// What Us elevates for his situation (`GET /api/context_graph/elevate`).
/// Every item names the node it drew on and the line it was built from.
struct ContextElevation: Codable {
    struct Item: Codable, Identifiable, Hashable {
        struct Evidence: Codable, Hashable { var source, ref, excerpt: String }
        var kind, title, why: String
        var score: Double
        var node_id, node_title, node_kind: String
        var evidence: Evidence
        var episode_id: String
        var id: String { kind + ":" + title }
    }
    var generatedAt, status, reason, notice: String
    var refused: Bool
    var items: [Item]
    var episodeID: String
    var isReady: Bool { status == "ready" || status == "refreshing" }
}

/// The one node a passage bears on, with both sides cited (`translate`).
struct ContextTranslation: Codable {
    var refused: Bool
    var reason, title, why, passageExcerpt, nodeExcerpt: String
    var node: ContextNode?
    var sharedTerms: [String]
}

/// One of his acts on a node, kept verbatim on this phone until the save is
/// confirmed. The same `event_id` is reused while the payload is unchanged
/// (safe retry); an edit mints a new one, so it can never ride an old receipt.
struct ContextGraphMutation: Codable, Equatable {
    var action: String            // confirm | correct | retire | worth | propose
    var id = ""
    var event_id = UUID().uuidString
    var text = ""
    var note = ""
    var reason = ""
    var helped = true
    var ids: [String] = []

    var body: [String: Any] {
        var out: [String: Any] = ["action": action, "id": id, "event_id": event_id]
        if !text.isEmpty { out["text"] = text }
        if !note.isEmpty { out["note"] = note }
        if !reason.isEmpty { out["reason"] = reason }
        if action == "worth" { out["helped"] = helped; out["ids"] = ids.isEmpty ? [id] : ids }
        return out
    }
}

struct ContextGraphMutationResult: Codable {
    var ok: Bool
    var node: ContextNode?
    var error: String?
    var updated: Int?
}

/// A node named by a saved reply's inspector ("drew on your context").
struct ContextGraphRef: Codable, Identifiable, Hashable {
    var id, kind, title, status: String
    var needs_review: Bool?
    var updated: String?
}


/// The day arranged around what he is in the middle of
/// (`GET /api/context_graph/arrangement`): for each active node, the items
/// that bear on it today — questions, elevated thinkers/passages/goals,
/// mind/body findings, his place, his own words — each with the line it was
/// drawn from. A node with nothing around it still shows, unarranged.
struct ContextArrangement: Codable {
    struct Item: Codable, Identifiable, Hashable {
        struct Evidence: Codable, Hashable { var source, ref, excerpt: String }
        var kind, title, why, ref: String
        var score: Double
        var node_id, node_title, node_kind: String
        var evidence: Evidence
        var date: String
        var id: String { node_id + ":" + kind + ":" + ref + ":" + title }
        /// "QUESTION", "THINKER", "FINDING", "YOUR WORDS", "PLACE", "BODY GOAL"
        var label: String {
            switch kind {
            case "words": return "YOUR WORDS"
            case "body_goal": return "BODY GOAL"
            default: return kind.uppercased()
            }
        }
    }
    struct Group: Codable, Identifiable {
        var node: ContextNodeRef
        var items: [Item]
        var arranged: Bool
        var id: String { node.id }
    }
    struct ContextNodeRef: Codable, Hashable {
        var id, kind, title, status, summary, updated: String
        var needs_review: Bool
        var isUnconfirmed: Bool { status == "inferred" && needs_review }
        var isHis: Bool { status == "stated" || status == "confirmed" }
        var mark: String {
            let s = status == "inferred" ? (needs_review ? "unconfirmed reading" : "reading") : status
            return (s + " · " + kind).uppercased()
        }
    }
    var generatedAt, status, reason, notice, date, episodeID: String
    var refused: Bool
    var groups: [Group]
    var arrangedCount: Int
    /// Prepared, with or without a refresh in flight behind it.
    var isReady: Bool { status == "ready" || status == "refreshing" }
    var isRefreshing: Bool { status == "refreshing" }
    /// Whether this may be shown as what is around him *now*. A refresh in
    /// flight still renders the last good answer, but an arrangement made for
    /// another episode or another day is not today's context however recently
    /// it was prepared, so it renders as nothing and the plain node lines show.
    func isCurrent(day: String, episodeID: String) -> Bool {
        guard isReady, !day.isEmpty else { return false }
        if !date.isEmpty && date != day { return false }
        if self.episodeID != episodeID { return false }
        return true
    }
    func group(for nodeID: String) -> Group? { groups.first { $0.node.id == nodeID } }
}
