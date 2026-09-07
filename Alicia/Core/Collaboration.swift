import Foundation
import Observation

struct CollaborationState: Codable {
    struct Goal: Codable, Identifiable {
        var id, title, outcome, why, status, priority: String
        var revision: Int
        var created_at, updated_at: String
    }
    struct Evidence: Codable, Identifiable {
        var id, kind, title, path, excerpt: String
        var line_start, line_end: Int
        var sha256, episode_id, recording_id, relation: String
    }
    struct Connection: Codable, Identifiable {
        var id, goal_id, title, claim, why_now, question, proposed_action, action_owner, review_condition, status: String
        var evidence: [Evidence]
        var origin_text, origin_id, created_at: String
        var revision: Int
    }
    struct Agreement: Codable, Identifiable {
        var id, goal_id, connection_id, action, owner, review_condition: String
        var review_at: String?
        var status, outcome: String
        var revision: Int
        var created_at, updated_at: String
    }
    struct Result: Codable, Identifiable {
        var id, agreement_id, title, body, status: String
        var evidence: [Evidence]
        var created_at: String
        var goal_id: String?
    }
    struct Signal: Codable, Identifiable {
        var id, kind, title, value, source, observed_at, notice: String
        var recording_id: String?
    }
    struct Followup: Codable, Equatable {
        var id, title, message, reason, not_before: String
        var expires_at: String?
        var goal_id, connection_id, agreement_id: String
        var revision: Int
    }
    var revision: Int
    var goals: [Goal]
    var connections: [Connection]
    var agreements: [Agreement]
    var results: [Result]
    var signals: [Signal]
    var pending: Bool
    var error: String
    var followups_enabled, telegram_returns_enabled: Bool
    var followup: Followup?
}

struct CollaborationMutation: Codable, Equatable {
    var action: String
    var event_id = UUID().uuidString
    var expected_revision: Int?
    var goal_id, connection_id, agreement_id: String?
    var title, outcome, why, priority, status, verdict, text: String?
    var action_text, owner, review_condition, review_at: String?
    var followups_enabled, telegram_returns_enabled: Bool?
    var candidate_id: String?
    var body: [String: Any] {
        guard let data = try? JSONEncoder().encode(self),
              let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return value
    }
}
struct CollaborationResponse: Codable {
    var ok: Bool
    var error: String?
    var state: CollaborationState?
}
struct CollaborationRoute: Identifiable, Codable, Sendable {
    var id = UUID().uuidString
    var candidateID = ""
    var goalID = ""
    var connectionID = ""
    var agreementID = ""
}

/// One durable outbox and monotonic shared snapshot for every mounted surface.
@MainActor @Observable
final class CollaborationStore {
    private(set) var state: CollaborationState?
    private(set) var pending: [CollaborationMutation] = []
    private(set) var busy = false
    private(set) var lastConfirmedID = ""
    var error = ""
    var route: CollaborationRoute?
    private let service: AliciaService
    private let defaults: UserDefaults
    private let key = "alicia.collaboration."
    private let notifications: Bool
    var canEdit: Bool { !busy && pending.isEmpty }
    var locallyStopped: Bool { defaults.bool(forKey: key + "stopped") }

    init(service: AliciaService, defaults: UserDefaults = .standard, notifications: Bool = true) {
        self.service = service; self.defaults = defaults; self.notifications = notifications
        if let data = defaults.data(forKey: key + "pending") { pending = (try? JSONDecoder().decode([CollaborationMutation].self, from: data)) ?? [] }
        if let data = defaults.data(forKey: key + "state") { state = try? JSONDecoder().decode(CollaborationState.self, from: data) }
    }
    func draft(_ name: String) -> [String: String]? { defaults.dictionary(forKey: key + "draft." + name) as? [String: String] }
    func clearDraft(_ name: String) { defaults.removeObject(forKey: key + "draft." + name) }
    func saveDraft(_ value: [String: String], name: String) {
        if let eventID = value["request_id"], (defaults.stringArray(forKey: key + "confirmed") ?? []).contains(eventID) {
            clearDraft(name); return
        }
        defaults.set(value, forKey: key + "draft." + name)
    }
    private func clearConfirmedDrafts(_ eventID: String) {
        let confirmed = (defaults.stringArray(forKey: key + "confirmed") ?? []) + [eventID]
        defaults.set(Array(confirmed.suffix(200)), forKey: key + "confirmed")
        for name in defaults.dictionaryRepresentation().keys where name.hasPrefix(key + "draft.") {
            if (defaults.dictionary(forKey: name) as? [String: String])?["request_id"] == eventID {
                defaults.removeObject(forKey: name)
            }
        }
    }
    private func persistQueue() { defaults.set(try? JSONEncoder().encode(pending), forKey: key + "pending") }
    @discardableResult func accept(_ fresh: CollaborationState) -> Bool {
        guard fresh.revision >= (state?.revision ?? -1) else { return false }
        if state?.revision != fresh.revision, notifications { CollaborationNotifier.cancel() }
        state = fresh
        defaults.set(try? JSONEncoder().encode(fresh), forKey: key + "state")
        return true
    }
    func load() async {
        if !pending.isEmpty { await retry() }
        if let fresh = await service.collaboration() { _ = accept(fresh) }
        else if state == nil { error = "Shared focus is unavailable. Your drafts stay on this phone." }
        await syncReturn()
    }
    func source(connectionID: String = "", resultID: String = "", evidenceID: String) async -> ContextSource? {
        await service.collaborationSource(connectionID: connectionID, resultID: resultID, evidenceID: evidenceID)
    }
    @discardableResult func submit(_ mutation: CollaborationMutation, draftName: String? = nil) async -> Bool {
        guard canEdit else { return false }
        if let draftName {
            var saved = draft(draftName) ?? [:]
            saved["request_id"] = mutation.event_id
            saveDraft(saved, name: draftName)
        }
        pending.append(mutation); persistQueue()
        if mutation.action == "settings", mutation.followups_enabled == false { stopLocally() }
        await retry()
        return lastConfirmedID == mutation.event_id
    }
    func stopLocally() {
        defaults.set(true, forKey: key + "stopped")
        if notifications { CollaborationNotifier.stop() }
    }
    /// Stop is always reachable, even behind an uncertain non-settings mutation.
    func stopReturns() async {
        stopLocally()
        if !pending.contains(where: { $0.action == "settings" && $0.followups_enabled == false }) {
            pending.append(CollaborationMutation(action: "settings", followups_enabled: false, telegram_returns_enabled: false))
            persistQueue()
        }
        await retry()
    }
    func retry() async {
        guard !busy, !pending.isEmpty else { return }
        busy = true
        defer { busy = false }
        var rejection = ""
        while let request = pending.first {
            guard let response = await service.collaborationAction(request) else {
                error = "Save unconfirmed. Retry keeps the exact words and receipt."; return
            }
            guard response.ok, let fresh = response.state else {
                if response.ok { error = "Save response was incomplete. Retry keeps the same receipt."; return }
                // A definite rejection unlocks drafts. No receipt is changed in place.
                pending.removeFirst(); persistQueue()
                rejection = response.error ?? "The change was rejected. Refresh and revise your draft."
                error = rejection
                if let fresh = response.state { _ = accept(fresh) }
                continue
            }
            pending.removeFirst(); persistQueue()
            clearConfirmedDrafts(request.event_id)
            lastConfirmedID = request.event_id
            _ = accept(fresh)
            if request.action == "settings", request.followups_enabled == true,
               !pending.contains(where: { $0.followups_enabled == false }) {
                defaults.set(false, forKey: key + "stopped")
                if notifications { CollaborationNotifier.allow() }
            }
            error = rejection.isEmpty ? "Saved." : rejection
        }
        await syncReturn()
    }
    func syncReturn() async {
        guard notifications, let state else { return }
        if locallyStopped { CollaborationNotifier.stop(); return }
        await CollaborationNotifier.sync(state)
    }
    func restoreRoute() {
        guard route == nil, let data = defaults.data(forKey: "alicia.collaboration.openTarget") else { return }
        route = try? JSONDecoder().decode(CollaborationRoute.self, from: data)
    }
    func viewed(_ route: CollaborationRoute) async {
        guard !route.candidateID.isEmpty, let state,
              state.connections.contains(where: { $0.id == route.connectionID }) || state.agreements.contains(where: { $0.id == route.agreementID }) || state.goals.contains(where: { $0.id == route.goalID }) else { return }
        defaults.removeObject(forKey: "alicia.collaboration.openTarget")
        await submit(CollaborationMutation(action: "seen", candidate_id: route.candidateID))
    }
}
