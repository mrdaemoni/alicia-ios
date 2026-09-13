import Foundation

@main struct BodyCaptureTests {
    static var checks = 0
    static func check(_ value: Bool) { assert(value); checks += 1 }
    static func main() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        var event = BodyEvent(kind: "ritual")
        event.ritual = "exercise"; event.completed = true
        try BodyCapture.save(event, directory: directory)
        try BodyCapture.save(event, directory: directory)
        let first = try BodyCapture.events(directory: directory)
        check(first.count == 1)
        let pending = try BodyCapture.pending(directory: directory)
        check(pending.count == 1)
        check(BodyCapture.completed("exercise", events: first))
        try BodyCapture.acknowledge(event.id, directory: directory)
        let acknowledged = try BodyCapture.pending(directory: directory)
        check(acknowledged.isEmpty)
        var changed = event; changed.completed = false
        do { try BodyCapture.save(changed, directory: directory); fatalError("Receipt conflict accepted") } catch { checks += 1 }
        var undo = BodyEvent(kind: "ritual")
        undo.ritual = "exercise"; undo.completed = false
        undo.captured_at = "2099-01-01T00:00:00.001Z"
        try BodyCapture.save(undo, directory: directory)
        let afterUndo = try BodyCapture.events(directory: directory)
        check(!BodyCapture.completed("exercise", events: afterUndo))
        check(!BodyCapture.completed("exercise", at: .now.addingTimeInterval(86400), events: [event]))
        let yesterday = BodyCapture.day(.now.addingTimeInterval(-86400))
        var old = event; old.local_day = yesterday
        check(!BodyCapture.completed("exercise", events: [old]))
        var later = event; later.captured_at = "2026-09-13T07:30:00Z"
        var earlier = event; earlier.captured_at = "2026-09-13T09:00:00+02:00"
        check(BodyCapture.before(earlier, later))
        let originalInstant = BodyCapture.instant("2026-09-13T06:59:59Z")
        let nearMidnight = BodyEvent(kind: "ritual", now: originalInstant)
        check(nearMidnight.local_day == BodyCapture.day(originalInstant))
        try BodyCapture.discardRejected(undo.id, directory: directory)
        let afterDiscard = try BodyCapture.pending(directory: directory)
        check(afterDiscard.isEmpty)
        check(FileManager.default.fileExists(atPath: directory.appendingPathComponent(undo.id + ".json").path))
        try Data("broken".utf8).write(to: directory.appendingPathComponent("bad.json"))
        do { _ = try BodyCapture.events(directory: directory); fatalError("Corrupt record silently ignored") } catch { checks += 1 }
        print("\(checks) body capture checks passed; only a temporary directory was used")
    }
}
