import Foundation

struct ContextItem: Codable, Identifiable {
    var id, kind, title, text, source, as_of, priority, correction: String
}

struct ContextEnrichment: Codable {
    struct Followup: Codable { var id, text, anchor, due_at: String }
    var about, items: [ContextItem]
    var reply_id, exposure: String
    var followups_enabled: Bool
    var followup: Followup?
}

struct ContextSource: Codable { var title, text, notice: String }

struct ContextChange: Codable, Equatable {
    var action: String
    var event_id = UUID().uuidString
    var reply_id = ""
    var item_id = ""
    var priority = "normal"
    var correction = ""
    var text = ""
    var followups_enabled = true

    var body: [String: Any] {
        ["action": action, "event_id": event_id, "reply_id": reply_id,
         "item_id": item_id, "priority": priority, "correction": correction,
         "text": text, "followups_enabled": followups_enabled]
    }
}

struct ContextChangeResult: Codable {
    var ok: Bool
    var context: ContextEnrichment?
    var error: String?
}

#if DEBUG
actor ContextPreviewStore {
    static let shared = ContextPreviewStore()
    private var value = ContextEnrichment(about: [ContextItem(id: "preview-own", kind: "your_words",
        title: "You kept", text: "We have to develop this aesthetic, or maybe it is already there and we have not named it.",
        source: "Preview fixture", as_of: "", priority: "normal", correction: ""),
        ContextItem(id: "preview-reading", kind: "inferred", title: "Her working picture · learning",
        text: "You may want to compare the choices we make across weeks.", source: "Preview interpretation", as_of: "", priority: "normal", correction: "")],
        items: [ContextItem(id: "preview-source", kind: "source", title: "Episode · pruning and attention",
        text: "The episode describes a discard log. This narrative is not a verified operational count.",
        source: "Preview source", as_of: "", priority: "normal", correction: "")], reply_id: "",
        exposure: "Fixture. No model or live memory is contacted.", followups_enabled: true)
    func read(_ replyID: String) -> ContextEnrichment { var copy = value; copy.reply_id = replyID; return copy }
    func save(_ change: ContextChange) -> ContextChangeResult {
        if change.action == "settings" { value.followups_enabled = change.followups_enabled }
        if change.action == "add_note" { value.about.insert(ContextItem(id: change.event_id, kind: "your_note", title: "You added",
            text: change.text, source: "Your preview context", as_of: "", priority: change.priority, correction: change.correction), at: 0) }
        for i in value.about.indices where value.about[i].id == change.item_id {
            value.about[i].priority = change.priority; value.about[i].correction = change.correction
        }
        for i in value.items.indices where value.items[i].id == change.item_id {
            value.items[i].priority = change.priority; value.items[i].correction = change.correction
        }
        return ContextChangeResult(ok: true, context: read(change.reply_id))
    }
}
#endif
