import Foundation

// Minimal transport seam for compiling the real BodyStore on the host. No
// provider, live endpoint, real app-group directory or widget reload is used.
protocol AliciaService {
    func bodyOverview() async -> BodyOverview?
    func saveBodyEvent(_ event: BodyEvent) async -> BodySaveResult?
    func bodySource(id: String, offset: Int, expectedHash: String) async -> BodySourcePage?
    func askBody(_ text: String) async -> BodyAnswer?
    func askBody(_ text: String, requestID: String) async -> BodyAnswer?
}
extension AliciaService {
    func bodySource(id: String, offset: Int, expectedHash: String) async -> BodySourcePage? { nil }
    func askBody(_ text: String) async -> BodyAnswer? { nil }
    func askBody(_ text: String, requestID: String) async -> BodyAnswer? { await askBody(text) }
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
/// Offline, so a toggle's follow-up refresh returns at once and never syncs.
struct OfflineBodyService: AliciaService {
    func bodyOverview() async -> BodyOverview? { nil }
    func saveBodyEvent(_ event: BodyEvent) async -> BodySaveResult? { nil }
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
        // A child process standing in for the widget: one tap, then exit.
        if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "tap" {
            let event = try BodyCapture.toggle("exercise", source: "widget", directory: URL(fileURLWithPath: CommandLine.arguments[2]))
            print(event.completed); return
        }
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
        try await mixedTaps(root)
        print("4 real BodyStore sync scenarios passed: burst, lost response, explicit discard, mixed Body/widget taps")
    }
    /// The Body screen's button and a widget tap that overlap must alternate:
    /// one records, one undoes, and the day ends undone.
    @MainActor static func mixedTaps(_ root: URL) async throws {
        func trial(_ widget: @escaping (URL) throws -> Bool) async throws -> Bool {
            let dir = root.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let store = BodyStore(service: OfflineBodyService(), captureDirectory: dir, refreshWidgets: {})
            let gate = DispatchSemaphore(value: 0), done = DispatchSemaphore(value: 0)
            var widgetResult: Bool?
            DispatchQueue.global(qos: .userInitiated).async {
                gate.wait(); widgetResult = try? widget(dir); done.signal()
            }
            gate.signal()
            let saved = await store.toggleRitual("exercise")
            done.wait()
            let events = try BodyCapture.events(directory: dir)
            let body = events.filter { $0.source == "ios" }, tapped = events.filter { $0.source == "widget" }
            return saved && widgetResult != nil && store.error == nil && events.count == 2
                && body.count == 1 && tapped.count == 1
                && events.filter(\.completed).count == 1
                && body[0].completed != widgetResult
                && !BodyCapture.completed("exercise", events: events)
        }
        var threadFailures = 0
        for _ in 0..<500 {
            if !(try await trial { try BodyCapture.toggle("exercise", source: "widget", directory: $0).completed }) { threadFailures += 1 }
        }
        print("mixed threads: \(threadFailures) of 500 overlapping Body/widget tap pairs failed to alternate")
        precondition(threadFailures == 0)
        let executable = URL(fileURLWithPath: CommandLine.arguments[0])
        var processFailures = 0
        for _ in 0..<40 {
            let ok = try await trial { dir in
                let child = Process(), pipe = Pipe()
                child.executableURL = executable; child.arguments = ["tap", dir.path]; child.standardOutput = pipe
                try child.run(); child.waitUntilExit()
                let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                guard child.terminationStatus == 0 else { throw CocoaError(.fileWriteUnknown) }
                return output.hasPrefix("true")
            }
            if !ok { processFailures += 1 }
        }
        print("mixed processes: \(processFailures) of 40 overlapping Body/widget-process tap pairs failed to alternate")
        precondition(processFailures == 0)
    }
}
