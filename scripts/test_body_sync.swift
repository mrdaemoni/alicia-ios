import Foundation

// Minimal transport seam for compiling the real BodyStore on the host. No
// provider, live endpoint, real app-group directory or widget reload is used.
protocol AliciaService {
    func bodyOverview() async -> BodyOverview?
    func saveBodyEvent(_ event: BodyEvent) async -> BodySaveResult?
    func bodySource(id: String, offset: Int, expectedHash: String) async -> BodySourcePage?
    func askBody(_ text: String) async -> BodyAnswer?
}
extension AliciaService {
    func bodySource(id: String, offset: Int, expectedHash: String) async -> BodySourcePage? { nil }
    func askBody(_ text: String) async -> BodyAnswer? { nil }
}
struct MockAliciaService: AliciaService {
    func bodyOverview() async -> BodyOverview? { nil }
    func saveBodyEvent(_ event: BodyEvent) async -> BodySaveResult? { nil }
}
actor DelayedBodyService: AliciaService {
    var inFlight = false
    var records: [String: BodyEvent] = [:]
    var writes = 0
    let loseReply: Bool
    let reject: Bool
    init(loseReply: Bool = false, reject: Bool = false) { self.loseReply = loseReply; self.reject = reject }
    func bodyOverview() async -> BodyOverview? {
        .init(status: "ready", state_status: "ready", privacy: "synthetic", historical_note: "synthetic",
              as_of: nil, generated_at: nil, metrics: [], sources: [], goals: [], events: Array(records.values))
    }
    func saveBodyEvent(_ event: BodyEvent) async -> BodySaveResult? {
        writes += 1; inFlight = true
        try? await Task.sleep(nanoseconds: 200_000_000)
        inFlight = false
        if reject { return .init(status: "not_saved", request_id: nil) }
        records[event.id] = event
        if loseReply && writes == 1 { return nil }
        return .init(status: "saved", request_id: event.id)
    }
}
@main struct BodySyncTests {
    @MainActor static func until(_ condition: @escaping () async -> Bool) async {
        for _ in 0..<60 {
            if await condition() { return }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        fatalError("Timed out waiting for expected sync state")
    }
    @MainActor static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        func directory(_ name: String) throws -> URL {
            let value = root.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: value, withIntermediateDirectories: true)
            return value
        }
        func ritual(_ name: String) -> BodyEvent {
            var value = BodyEvent(kind: "ritual"); value.ritual = name; value.completed = true; return value
        }
        let service = DelayedBodyService()
        let store = BodyStore(service: service, captureDirectory: try directory("burst"), refreshWidgets: {})
        let first = ritual("exercise"), second = ritual("cold_plunge"), third = ritual("sauna")
        let savedFirst = await store.capture(first); assert(savedFirst)
        await until { await service.inFlight }
        let savedSecond = await store.capture(second), savedThird = await store.capture(third)
        assert(savedSecond && savedThird)
        await until { store.pendingIDs.isEmpty && !store.refreshing }
        let burstRecords = await service.records
        assert(burstRecords.count == 3 && burstRecords[first.id] == first && burstRecords[second.id] == second && burstRecords[third.id] == third)

        let lostService = DelayedBodyService(loseReply: true)
        let lost = BodyStore(service: lostService, captureDirectory: try directory("lost"), refreshWidgets: {})
        let event = ritual("exercise")
        _ = await lost.capture(event)
        await until { await lostService.writes == 1 && !lost.refreshing }
        assert(lost.pendingIDs.contains(event.id))
        await lost.refresh()
        assert(lost.pendingIDs.isEmpty)
        let afterLost = await lostService.records
        assert(afterLost.count == 1 && afterLost[event.id] == event)

        let rejectService = DelayedBodyService(reject: true)
        let rejectedDirectory = try directory("rejected")
        let rejected = BodyStore(service: rejectService, captureDirectory: rejectedDirectory, refreshWidgets: {})
        let edit = ritual("sauna"); _ = await rejected.capture(edit)
        await until { rejected.conflictedIDs.contains(edit.id) && !rejected.refreshing }
        rejected.discardRejected(edit)
        assert(rejected.pendingIDs.isEmpty)
        assert(FileManager.default.fileExists(atPath: rejectedDirectory.appendingPathComponent(edit.id + ".json").path))
        print("3 real BodyStore sync scenarios passed: burst, lost response, explicit discard")
    }
}
