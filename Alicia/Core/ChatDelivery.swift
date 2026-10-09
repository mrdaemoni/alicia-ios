import Foundation

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
}
