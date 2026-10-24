import Foundation

/// The steering study's weekly note (CL-20261023-study-note-card).
///
/// Hector, 2026-10-23: "make sure that note is shown in the home screen of
/// Alicia … in such a way that I will not miss it." The Mac decides when the
/// card shows (`GET /api/study_note`): a study week's last day, and the next
/// day if that week's note is still missing. It is the same in both arms.
///
/// His words go to the Mac verbatim (`POST /api/study_note`), into the study
/// task's own notes, which Alicia never reads. Until the Mac confirms a save,
/// the words stay on this phone.
struct StudyNotePrompt: Codable, Hashable, Identifiable {
    var id: String
    var heading: String
    var hint: String
}

struct StudyNoteStatus: Codable, Equatable {
    var show = false
    var week = 0
    var late = false
    var arm = ""
    var dates = ""
    var saved = false
    var saved_today = false
    var saved_at = ""
    var title = ""
    var line = ""
    var prompts: [StudyNotePrompt] = []
    var mornings_prompt = ""

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        show = try c.decodeIfPresent(Bool.self, forKey: .show) ?? false
        week = try c.decodeIfPresent(Int.self, forKey: .week) ?? 0
        late = try c.decodeIfPresent(Bool.self, forKey: .late) ?? false
        arm = try c.decodeIfPresent(String.self, forKey: .arm) ?? ""
        dates = try c.decodeIfPresent(String.self, forKey: .dates) ?? ""
        saved = try c.decodeIfPresent(Bool.self, forKey: .saved) ?? false
        saved_today = try c.decodeIfPresent(Bool.self, forKey: .saved_today) ?? false
        saved_at = try c.decodeIfPresent(String.self, forKey: .saved_at) ?? ""
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        line = try c.decodeIfPresent(String.self, forKey: .line) ?? ""
        prompts = try c.decodeIfPresent([StudyNotePrompt].self, forKey: .prompts) ?? []
        mornings_prompt = try c.decodeIfPresent(String.self, forKey: .mornings_prompt) ?? ""
    }

    /// The card shows only a week the Mac named, with the prompts to answer.
    var isUsable: Bool { show && week > 0 && (saved || !prompts.isEmpty) }
}

/// What a save came to. Only `.saved` lets the phone forget the words.
enum StudyNoteSave: Equatable {
    case saved(savedAt: String)
    /// The Mac refused this receipt or these words. The words stay.
    case rejected(String)
    /// No answer, so the outcome is unknown. The words stay, and the same receipt retries.
    case unreachable
}

/// One week's words, kept on this phone until the Mac confirms them.
struct StudyNoteDraft: Codable, Equatable {
    var week: Int
    var answers: [String: String] = [:]
    var mornings = ""
    /// The receipt of the last attempt, and the words it carried. A retry with
    /// the same words reuses it, so the Mac saves them once. Changed words get a
    /// new receipt, because a receipt never binds to other words.
    var requestID = ""
    var attemptedDigest = ""

    init(week: Int) { self.week = week }

    /// Exactly what he typed, never trimmed. A blank answer is a valid answer.
    var words: String {
        let ordered = answers.keys.sorted().map { $0 + "\u{1F}" + (answers[$0] ?? "") }
        return ([String(week), mornings] + ordered).joined(separator: "\u{1E}")
    }

    var isEmpty: Bool { mornings.isEmpty && answers.values.allSatisfy(\.isEmpty) }

    /// The receipt for sending these words now.
    mutating func receipt(newID: () -> String = { UUID().uuidString }) -> String {
        if requestID.isEmpty || attemptedDigest != words {
            requestID = newID()
            attemptedDigest = words
        }
        return requestID
    }

    func body(requestID: String) -> Data {
        let payload: [String: Any] = ["request_id": requestID, "week": week,
                                      "answers": answers.filter { !$0.value.isEmpty }, "mornings": mornings]
        return (try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])) ?? Data()
    }
}

/// Drafts survive the app closing: protected, never backed up, one per week.
enum StudyNoteDrafts {
    static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("StudyNotes", isDirectory: true)
    }

    static func file(week: Int, in directory: URL = directory) -> URL {
        directory.appendingPathComponent("week-\(week).json")
    }

    static func load(week: Int, in directory: URL = directory) -> StudyNoteDraft? {
        guard let data = try? Data(contentsOf: file(week: week, in: directory)) else { return nil }
        return try? JSONDecoder().decode(StudyNoteDraft.self, from: data)
    }

    /// Returns false when the words could not be kept, so the sheet can say so.
    @discardableResult
    static func store(_ draft: StudyNoteDraft, in directory: URL = directory) -> Bool {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            var url = directory, values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? url.setResourceValues(values)
#if os(iOS)
            let options: Data.WritingOptions = [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
#else
            let options: Data.WritingOptions = [.atomic]
#endif
            try JSONEncoder().encode(draft).write(to: file(week: draft.week, in: directory), options: options)
            return true
        } catch {
            return false
        }
    }

    static func clear(week: Int, in directory: URL = directory) {
        try? FileManager.default.removeItem(at: file(week: week, in: directory))
    }
}

/// How the Mac's answer to a save reads, by status code.
enum StudyNoteResponse {
    static func decode(status: Int, data: Data) -> StudyNoteSave {
        let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        switch status {
        case 200 where object["ok"] as? Bool == true:
            return .saved(savedAt: object["saved_at"] as? String ?? "")
        case 400, 409:
            return .rejected((object["error"] as? String).map { String($0.prefix(200)) }
                             ?? "Not saved. Your words stay here; try again.")
        default:
            return .unreachable
        }
    }
}
