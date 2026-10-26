import Foundation

@main struct BodyCaptureTests {
    static var checks = 0
    static func check(_ value: Bool) { precondition(value); checks += 1 }
    static func main() throws {
        // A child process standing in for the widget or the app: one tap, then exit.
        if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "tap" {
            let event = try BodyCapture.toggle("exercise", source: "widget", directory: URL(fileURLWithPath: CommandLine.arguments[2]))
            print(event.completed); return
        }
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
        try toggles()
        try overlappingTaps()
        try Data("broken".utf8).write(to: directory.appendingPathComponent("bad.json"))
        do { _ = try BodyCapture.events(directory: directory); fatalError("Corrupt record silently ignored") } catch { checks += 1 }
        print("\(checks) body capture checks passed; only a temporary directory was used")
    }
    /// The widget is a toggle: each tap flips today's state with a new receipt.
    static func toggles() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let noon = Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: .now)!
        func state(_ ritual: String) throws -> Bool {
            BodyCapture.completed(ritual, at: noon, events: try BodyCapture.events(directory: directory))
        }
        let first = try BodyCapture.toggle("exercise", source: "widget", now: noon, directory: directory)
        check(first.completed && first.source == "widget" && first.ritual == "exercise")
        check(try state("exercise"))
        let undo = try BodyCapture.toggle("exercise", source: "widget", now: noon.addingTimeInterval(1), directory: directory)
        check(!undo.completed && undo.id != first.id)
        check(!(try state("exercise")))
        try BodyCapture.toggle("exercise", source: "widget", now: noon.addingTimeInterval(2), directory: directory)
        check(try state("exercise"))
        check(!(try state("sauna")))
        // Yesterday's record never turns today's first tap into an undo.
        try BodyCapture.toggle("sauna", source: "widget", now: noon.addingTimeInterval(-86400), directory: directory)
        let today = try BodyCapture.toggle("sauna", source: "widget", now: noon, directory: directory)
        check(today.completed)
        check(try state("sauna"))
        // Every tap is its own immutable receipt awaiting sync.
        check(try BodyCapture.pending(directory: directory).count == 5)
    }
    /// Two taps that overlap — two threads, or the app and widget processes —
    /// must alternate: one records, one undoes, and the day ends undone.
    static func overlappingTaps() throws {
        func trial(_ tap: @escaping (URL) throws -> Bool) throws -> (Bool, Bool) {
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: dir) }
            let gate = DispatchSemaphore(value: 0), done = DispatchGroup(), lock = NSLock()
            var results: [Bool] = []
            for _ in 0..<2 {
                done.enter()
                DispatchQueue.global(qos: .userInitiated).async {
                    gate.wait()
                    if let value = try? tap(dir) { lock.lock(); results.append(value); lock.unlock() }
                    done.leave()
                }
            }
            gate.signal(); gate.signal(); done.wait()
            let events = try BodyCapture.events(directory: dir)
            let alternated = results.count == 2 && results.filter { $0 }.count == 1 && events.count == 2
            return (alternated, !BodyCapture.completed("exercise", events: events))
        }
        var threadFailures = 0
        for _ in 0..<500 {
            let (alternated, undone) = try trial { try BodyCapture.toggle("exercise", source: "widget", directory: $0).completed }
            if !(alternated && undone) { threadFailures += 1 }
        }
        print("threads: \(threadFailures) of 500 overlapping tap pairs failed to alternate")
        check(threadFailures == 0)
        let executable = URL(fileURLWithPath: CommandLine.arguments[0])
        var processFailures = 0
        for _ in 0..<40 {
            let (alternated, undone) = try trial { dir in
                let child = Process(), pipe = Pipe()
                child.executableURL = executable; child.arguments = ["tap", dir.path]; child.standardOutput = pipe
                try child.run(); child.waitUntilExit()
                let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                guard child.terminationStatus == 0 else { throw CocoaError(.fileWriteUnknown) }
                return output.hasPrefix("true")
            }
            if !(alternated && undone) { processFailures += 1 }
        }
        print("processes: \(processFailures) of 40 overlapping tap pairs failed to alternate")
        check(processFailures == 0)
    }
}
