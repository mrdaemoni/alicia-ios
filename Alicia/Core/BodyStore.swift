import Foundation
import Observation
import WidgetKit

struct BodyOverview: Decodable {
    struct Metric: Decodable, Identifiable {
        struct Point: Decodable { var date: String; var value: Double }
        var id, label, unit: String
        var value, baseline: Double?
        var date, baseline_from, baseline_to: String?
        var baseline_days: Int?
        var series: [Point]
        func display(_ value: Double?) -> String {
            guard let value else { return "Not available" }
            return value.formatted(.number.precision(.fractionLength(id == "steps" ? 0 : 1))) + " " + unit
        }
    }
    struct Source: Decodable, Identifiable {
        var source_id, source_path, title, category: String
        var report_date, measurement_date, sha256: String?
        var id: String { source_id }
    }
    var status, state_status, privacy, historical_note: String
    var as_of, generated_at: String?
    var metrics: [Metric]
    var sources: [Source]
    var goals, events: [BodyEvent]
}
struct BodyAnswer: Decodable { var status, text: String; var model, as_of: String? }
struct BodySaveResult: Decodable { var status: String; var request_id: String? }
struct BodySourcePage: Decodable {
    struct Passage: Decodable, Identifiable { var chunk_index: Int; var excerpt: String; var id: Int { chunk_index } }
    var status: String
    var title: String?
    var passages: [Passage]?
    var next_offset: Int?
}

@MainActor @Observable final class BodyStore {
    private let service: AliciaService
    var overview: BodyOverview?
    var local: [BodyEvent] = []
    var pendingIDs: Set<String> = []
    var conflictedIDs: Set<String> = []
    var error: String?
    var refreshing = false
    var lastRefresh: Date?
    init(service: AliciaService) { self.service = service }

    var events: [BodyEvent] {
        var byID: [String: BodyEvent] = [:]
        for event in (overview?.events ?? []) + local { byID[event.id] = event }
        return byID.values.sorted { ($0.captured_at, $0.id) < ($1.captured_at, $1.id) }
    }
    var goals: [BodyEvent] {
        var byID: [String: BodyEvent] = [:]
        for event in overview?.goals ?? [] { byID[event.goal_id] = event }
        // Pending edits remain visible and explicitly labelled until saved.
        for event in local where event.kind == "goal" && pendingIDs.contains(event.id) { byID[event.goal_id] = event }
        return byID.values.sorted { $0.captured_at < $1.captured_at }
    }
    func reread() {
        do { let directory = try BodyCapture.root(); local = try BodyCapture.events(directory: directory).filter { !BodyCapture.isDiscarded($0.id, directory: directory) }; pendingIDs = Set(try BodyCapture.pending().map(\.id)) }
        catch { self.error = "The local ritual record could not be read. Your files have been kept." }
    }
    func refresh() async {
        guard !refreshing, !(service is MockAliciaService) else { return }
        refreshing = true; defer { refreshing = false }
        error = nil; reread()
        // Read first: acknowledge a write whose successful HTTP response was lost.
        if let fresh = await service.bodyOverview() {
            overview = fresh; lastRefresh = .now
            for event in fresh.events {
                if let original = local.first(where: { $0.id == event.id }), original == event {
                    try? BodyCapture.acknowledge(event.id)
                }
            }
        } else {
            error = "Cannot reach your Mac. Showing the last view; new captures stay on this phone."
        }
        do {
            for event in try BodyCapture.pending() {
                let result = await service.saveBodyEvent(event)
                if result?.status == "not_saved" {
                    conflictedIDs.insert(event.id)
                    error = "A capture needs review before it can be saved with Alicia. Its original is kept on this phone."
                    continue
                }
                guard result?.status == "saved", result?.request_id == event.id else {
                    error = "Saved on this phone, waiting for Alicia. Refresh to retry the same capture."
                    break
                }
                try BodyCapture.acknowledge(event.id)
            }
            reread()
            if let fresh = await service.bodyOverview() { overview = fresh; lastRefresh = .now }
        } catch { self.error = "The local capture could not be read or acknowledged. It has not been discarded." }
        WidgetCenter.shared.reloadTimelines(ofKind: "AliciaRituals")
    }
    @discardableResult func capture(_ event: BodyEvent) async -> Bool {
        guard !(service is MockAliciaService) else { error = "Preview only — no personal record was saved."; return false }
        do {
            try BodyCapture.save(event); reread()
            WidgetCenter.shared.reloadTimelines(ofKind: "AliciaRituals")
            Task { await refresh() }
            return true // Durable on this device; network acknowledgement has its own status.
        } catch { self.error = "Not saved. Keep this page open and try again."; return false }
    }
    func discardRejected(_ event: BodyEvent) {
        guard conflictedIDs.contains(event.id) else { return }
        do { try BodyCapture.discardRejected(event.id); conflictedIDs.remove(event.id); reread() }
        catch { self.error = "Could not discard this rejected edit. Its original has been kept." }
    }
    func ask(_ text: String) async -> BodyAnswer? { await service.askBody(text) }
    func source(_ id: String, offset: Int) async -> BodySourcePage? { await service.bodySource(id: id, offset: offset) }
}
