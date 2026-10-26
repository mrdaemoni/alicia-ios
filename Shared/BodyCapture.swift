import Foundation

/// Shared by the app and WidgetKit. Individual atomic files avoid lost updates
/// between processes; receipts remain byte-for-byte identical until acknowledged.
struct BodyEvent: Codable, Identifiable, Equatable {
    var request_id = UUID().uuidString
    var kind: String
    var captured_at = BodyCapture.timestamp()
    var timezone = TimeZone.current.identifier
    var local_day = BodyCapture.day(Date())
    var source = "ios"
    var ritual = ""
    var completed = false
    var goal_id = ""
    var previous_id = ""
    var text = ""
    var criterion = ""
    var status = "active"
    var metric = ""
    var source_ids: [String] = []
    var episode_id = ""
    var mind_goal_id = ""
    var id: String { request_id }
    init(kind: String, goal_id: String = "", now: Date = .now) {
        self.kind = kind; self.goal_id = goal_id
        self.captured_at = BodyCapture.timestamp(now)
        self.local_day = BodyCapture.day(now)
        self.timezone = TimeZone.current.identifier
    }
}

enum BodyCapture {
    /// ISO timestamps are immutable inputs. Reusing the parser and a bounded
    /// date cache avoids thousands of ICU formatter constructions in UI sorts.
    private final class TimestampCodec: @unchecked Sendable {
        let lock = NSLock()
        let fractional = ISO8601DateFormatter()
        let plain = ISO8601DateFormatter()
        let dates = NSCache<NSString, NSDate>()
        init() {
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            plain.formatOptions = [.withInternetDateTime]
            dates.countLimit = 4096
        }
    }
    private static let codec = TimestampCodec()
    static func timestamp(_ date: Date = .now) -> String {
        codec.lock.lock(); defer { codec.lock.unlock() }
        return codec.fractional.string(from: date)
    }
    static let rituals = [("exercise", "Exercise"), ("cold_plunge", "Cold plunge"), ("sauna", "Sauna")]
    static func day(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
    static func instant(_ text: String) -> Date {
        codec.lock.lock(); defer { codec.lock.unlock() }
        if let date = codec.dates.object(forKey: text as NSString) { return date as Date }
        let date = codec.fractional.date(from: text) ?? codec.plain.date(from: text) ?? .distantPast
        codec.dates.setObject(date as NSDate, forKey: text as NSString)
        return date
    }
    static func before(_ lhs: BodyEvent, _ rhs: BodyEvent) -> Bool {
        let a = instant(lhs.captured_at), b = instant(rhs.captured_at)
        return a == b ? lhs.id < rhs.id : a < b
    }
    static func sorted(_ events: [BodyEvent]) -> [BodyEvent] {
        // Parse once per event, never inside the O(n log n) comparator.
        let dated: [(event: BodyEvent, instant: Date)] = events.map { (event: $0, instant: instant($0.captured_at)) }
        let ordered = dated.sorted { left, right in
            if left.instant == right.instant { return left.event.id < right.event.id }
            return left.instant < right.instant
        }
        return ordered.map { $0.event }
    }
    static func root() throws -> URL {
        guard let group = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.myalicia.app") else {
            throw CocoaError(.fileNoSuchFile)
        }
        let directory = group.appendingPathComponent("BodyCaptures", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var resource = URLResourceValues(); resource.isExcludedFromBackup = true
        var url = directory; try url.setResourceValues(resource)
        return directory
    }
    static func save(_ event: BodyEvent, directory: URL? = nil) throws {
        let dir = try directory ?? root()
        let url = dir.appendingPathComponent(event.id + ".json")
        if FileManager.default.fileExists(atPath: url.path) {
            guard try JSONDecoder().decode(BodyEvent.self, from: Data(contentsOf: url)) == event else {
                throw CocoaError(.fileWriteFileExists)
            }
            return
        }
        try JSONEncoder().encode(event).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
    static func events(directory: URL? = nil) throws -> [BodyEvent] {
        let dir = try directory ?? root()
        let events = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" && !isDiscarded($0.deletingPathExtension().lastPathComponent, directory: dir) }
            .map { try JSONDecoder().decode(BodyEvent.self, from: Data(contentsOf: $0)) }
        return sorted(events)
    }
    static func acknowledge(_ id: String, directory: URL? = nil) throws {
        let dir = try directory ?? root()
        try Data().write(to: dir.appendingPathComponent(id + ".ack"), options: .atomic)
    }
    static func discardRejected(_ id: String, directory: URL? = nil) throws {
        let dir = try directory ?? root()
        try Data().write(to: dir.appendingPathComponent(id + ".discarded"), options: .atomic)
    }
    static func isDiscarded(_ id: String, directory: URL) -> Bool {
        FileManager.default.fileExists(atPath: directory.appendingPathComponent(id + ".discarded").path)
    }
    static func pending(directory: URL? = nil) throws -> [BodyEvent] {
        let dir = try directory ?? root()
        return try events(directory: dir).filter {
            !isDiscarded($0.id, directory: dir) && !FileManager.default.fileExists(atPath: dir.appendingPathComponent($0.id + ".ack").path)
        }
    }
    static func completed(_ ritual: String, at date: Date = .now, events: [BodyEvent]) -> Bool {
        let today = day(date)
        return events.last { $0.kind == "ritual" && $0.ritual == ritual && $0.local_day == today }?.completed ?? false
    }
    /// A ritual tap flips today's state, like the Body screen. Reads the record on
    /// disk at tap time, never a possibly stale widget timeline; the receipt is a
    /// new immutable event, so an undo syncs exactly like a record. The read and
    /// the append happen under one exclusive flock shared by the app and widget,
    /// so two overlapping taps alternate instead of both recording.
    @discardableResult
    static func toggle(_ ritual: String, source: String, now: Date = .now, directory: URL? = nil) throws -> BodyEvent {
        let dir = try directory ?? root()
        return try exclusively(in: dir) {
            let existing = try events(directory: dir)
            var event = BodyEvent(kind: "ritual", now: now)
            event.source = source; event.ritual = ritual
            event.completed = !completed(ritual, at: now, events: existing)
            // A tap stamped before the lock was won, or in the same millisecond,
            // must still sort after the receipt it read, or latest-wins would go
            // backwards.
            if let last = existing.last(where: { $0.kind == "ritual" && $0.ritual == ritual && $0.local_day == event.local_day }),
               instant(last.captured_at) >= instant(event.captured_at) {
                event.captured_at = timestamp(instant(last.captured_at).addingTimeInterval(0.001))
            }
            try save(event, directory: dir)
            return event
        }
    }
    /// Advisory lock on a file beside the receipts; flock holds across processes
    /// and between separate opens within one process, and drops if a process dies.
    static func exclusively<T>(in dir: URL, _ body: () throws -> T) throws -> T {
        let fd = open(dir.appendingPathComponent(".toggle.lock").path, O_RDWR | O_CREAT | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw CocoaError(.fileWriteUnknown) }
        defer { close(fd) }
        while flock(fd, LOCK_EX) != 0 {
            guard errno == EINTR else { throw CocoaError(.fileLocking) }
        }
        defer { flock(fd, LOCK_UN) }
        return try body()
    }
}
