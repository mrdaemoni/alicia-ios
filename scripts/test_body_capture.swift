import Foundation

@main struct BodyCaptureTests {
    static func main() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        var event = BodyEvent(kind: "ritual")
        event.ritual = "exercise"; event.completed = true
        try BodyCapture.save(event, directory: directory)
        try BodyCapture.save(event, directory: directory)
        let first = try BodyCapture.events(directory: directory)
        assert(first.count == 1)
        let pending = try BodyCapture.pending(directory: directory)
        assert(pending.count == 1)
        assert(BodyCapture.completed("exercise", events: first))
        try BodyCapture.acknowledge(event.id, directory: directory)
        let acknowledged = try BodyCapture.pending(directory: directory)
        assert(acknowledged.isEmpty)
        var changed = event; changed.completed = false
        do { try BodyCapture.save(changed, directory: directory); fatalError("Receipt conflict accepted") } catch {}
        var undo = BodyEvent(kind: "ritual")
        undo.ritual = "exercise"; undo.completed = false
        undo.captured_at = "2099-01-01T00:00:00.001Z"
        try BodyCapture.save(undo, directory: directory)
        let afterUndo = try BodyCapture.events(directory: directory)
        assert(!BodyCapture.completed("exercise", events: afterUndo))
        assert(!BodyCapture.completed("exercise", at: .now.addingTimeInterval(86400), events: [event]))
        let yesterday = BodyCapture.day(.now.addingTimeInterval(-86400))
        var old = event; old.local_day = yesterday
        assert(!BodyCapture.completed("exercise", events: [old]))
        try Data("broken".utf8).write(to: directory.appendingPathComponent("bad.json"))
        do { _ = try BodyCapture.events(directory: directory); fatalError("Corrupt record silently ignored") } catch {}
        print("10 body capture checks passed; only a temporary directory was used")
    }
}
