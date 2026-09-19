import Foundation
import Observation

struct SurfaceContext: Codable, Equatable {
    var section: String
    var captured_at: String
    var episode_id: String = ""
    /// Where he was when he said it — a locality and whether that was home,
    /// the office or away. Never a coordinate. Absent when he has not granted
    /// location or the place has not resolved, which is an ordinary state.
    var place: [String: String]? = nil
    var title: String {
        ["us": "Us · home", "mind": "Mind", "body": "Body · private", "alicia": "Alicia", "studio": "Studio", "dialogue": "Dialogue"][section] ?? "Dialogue"
    }
    var wire: [String: String] {
        var out = ["section": section, "captured_at": captured_at, "episode_id": episode_id]
        for (key, value) in place ?? [:] { out["place_" + key] = value }
        return out
    }
}

/// Separate durable drafts prevent a Body draft becoming a Mind message on a tab change.
@MainActor @Observable final class ComposerDrafts {
    private var values: [String: String] = [:]
    private let directory: URL
    var error: String?
    private var corrupt = false
    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("PrivateComposer", isDirectory: true)
        do {
            if FileManager.default.fileExists(atPath: file.path) { values = try JSONDecoder().decode([String: String].self, from: Data(contentsOf: file)) }
        } catch { self.corrupt = true; self.error = "Your saved drafts need recovery. They have not been replaced." }
    }
    private var file: URL { directory.appendingPathComponent("drafts.json") }
    func text(for section: String) -> String { values[section] ?? "" }

    /// Drafts are durable on purpose, which means a UI test inherits whatever
    /// the last one typed. `--reset-drafts` gives a run a clean slate without
    /// reinstalling the app; it exists only in DEBUG and is never a product
    /// affordance — nothing in the app erases his unsent words.
    func resetForTesting() {
        values = [:]
        try? FileManager.default.removeItem(at: file)
        error = nil
    }
    func set(_ text: String, for section: String) {
        guard !corrupt else { return }
        values[section] = text
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            var folder = directory; var flags = URLResourceValues(); flags.isExcludedFromBackup = true
            try folder.setResourceValues(flags)
            try JSONEncoder().encode(values).write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            error = nil
        } catch { self.error = "The draft is on screen but could not be saved on this phone." }
    }
}
