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
}

enum BodyCapture {
    static func timestamp() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
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
        return try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" && !isDiscarded($0.deletingPathExtension().lastPathComponent, directory: dir) }
            .map { try JSONDecoder().decode(BodyEvent.self, from: Data(contentsOf: $0)) }
            .sorted { ($0.captured_at, $0.id) < ($1.captured_at, $1.id) }
    }
    static func acknowledge(_ id: String, directory: URL? = nil) throws {
        let dir = try directory ?? root()
        try Data().write(to: dir.appendingPathComponent(id + ".ack"), options: .atomic)
    }
    static func discardRejected(_ id: String) throws {
        try Data().write(to: root().appendingPathComponent(id + ".discarded"), options: .atomic)
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
        events.last { $0.kind == "ritual" && $0.ritual == ritual && $0.local_day == day(date) }?.completed ?? false
    }
}
