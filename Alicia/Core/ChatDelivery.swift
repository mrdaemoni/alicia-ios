import Foundation
import CryptoKit

struct ChatSendReceipt: Decodable {
    var request_id, state: String
    var reply, reply_id, error: String?
    var message_id: Int?
    var inspectable: Bool?

    func confirms(_ requestID: String) -> Bool {
        guard let expected = UUID(uuidString: requestID), let actual = UUID(uuidString: request_id),
              expected == actual, state == "completed", let reply, !reply.isEmpty else { return false }
        return reply_id.flatMap(UUID.init(uuidString:)) == expected
    }
}

struct PendingChatSend: Codable {
    var requestID, text, recordingID: String
    var voice: Bool
    var workContext: WorkDialogueContext?
    var surfaceContext: SurfaceContext?
}

/// Immutable pending words and original context stay on this phone, protected
/// and excluded from backup. No credentials or private Body sends are stored.
@MainActor final class ChatSendOutbox {
    private var entries: [String: PendingChatSend] = [:]
    private let directory: URL
    private var damaged = false
    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("PrivateComposer", isDirectory: true)
        do {
            if FileManager.default.fileExists(atPath: file.path) {
                let data = try Data(contentsOf: file)
                guard data.count <= 16_000_000 else { throw CocoaError(.fileReadTooLarge) }
                entries = try JSONDecoder().decode([String: PendingChatSend].self, from: data)
                guard entries.count <= 128, entries.values.allSatisfy({ UUID(uuidString: $0.requestID) != nil }) else { throw CocoaError(.fileReadCorruptFile) }
            }
        } catch { damaged = true }
    }
    private var file: URL { directory.appendingPathComponent("chat-sends.json") }
    private func persist() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var url = directory, flags = URLResourceValues(); flags.isExcludedFromBackup = true
        try url.setResourceValues(flags)
        let data = try JSONEncoder().encode(entries)
        guard data.count <= 16_000_000 else { throw CocoaError(.fileWriteOutOfSpace) }
        try data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
    func reserve(text: String, recordingID: String, voice: Bool, workContext: WorkDialogueContext?, surfaceContext: SurfaceContext?) throws -> PendingChatSend {
        guard !damaged else { throw CocoaError(.fileReadCorruptFile) }
        guard surfaceContext?.section != "body" else { throw CocoaError(.featureUnsupported) }
        let identity = ["text": text, "recording": recordingID, "section": surfaceContext?.section ?? "",
                        "episode": surfaceContext?.episode_id ?? "", "goal": workContext?.goal_id ?? "",
                        "result": workContext?.result_id ?? "", "passage": workContext?.section_id ?? "", "hash": workContext?.content_hash ?? ""]
        let bytes = try JSONSerialization.data(withJSONObject: identity, options: .sortedKeys)
        let key = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        if let original = entries[key] { return original }
        guard entries.count < 128 else { throw CocoaError(.fileWriteOutOfSpace) }
        let entry = PendingChatSend(requestID: UUID().uuidString, text: text, recordingID: recordingID,
            voice: voice, workContext: workContext, surfaceContext: surfaceContext)
        entries[key] = entry
        do { try persist() } catch { entries.removeValue(forKey: key); throw error }
        return entry
    }
    /// A completed assistant receipt clears only its original draft. This also
    /// repairs sends that finished after a connection loss or phone relaunch.
    func reconcileCompleted(_ replyIDs: Set<UUID>, drafts: ComposerDrafts) {
        let completed = entries.values.filter { UUID(uuidString: $0.requestID).map(replyIDs.contains) == true }
        for pending in completed {
            if let section = pending.surfaceContext?.section {
                drafts.acknowledge(pending.text, for: section)
            }
            acknowledge(pending.requestID)
        }
    }

    func acknowledge(_ requestID: String) {
        let old = entries
        entries = entries.filter { UUID(uuidString: $0.value.requestID) != UUID(uuidString: requestID) }
        do { try persist() } catch { entries = old }
    }
}

/// Transport/validation notices are not answers authored by Alicia.
struct ChatDeliveryFailure: Hashable, Sendable {
    var message: String
    /// Only an explicit rejection permits discarding a pending send identity.
    var definitelyRejected: Bool = false

    static func http(_ status: Int, body: Data) -> Self {
        if (400..<500).contains(status), status != 408 {
            let detail = (try? JSONSerialization.jsonObject(with: body) as? [String: Any])?["error"] as? String
            let reason = detail.map { String($0.prefix(500)) } ?? "The request was rejected."
            return .init(message: "Message not sent. " + reason + " Your words remain in the composer.", definitelyRejected: true)
        }
        return .interrupted
    }

    static let interrupted = Self(message: "Delivery could not be confirmed. Your words remain in the composer. Check Dialogue before trying again.")
    static let replyInterrupted = Self(message: "Your message was received, but the reply did not finish. Reopen Dialogue to recover the saved reply.")
    static let pending = Self(message: "Alicia has your message and is still preparing a reply. Check Dialogue shortly; this send has not been repeated.")
}
