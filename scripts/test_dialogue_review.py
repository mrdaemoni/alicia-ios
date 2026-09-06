#!/usr/bin/env python3
"""Exercise the actual Swift outbox methods and public wire models, with inert IO."""
from pathlib import Path
import os
import subprocess
import tempfile
root = Path(__file__).resolve().parents[1]
models = (root / 'Alicia/Core/DialogueReview.swift').read_text()
view = (root / 'Alicia/Features/Talk/DialogueReviewView.swift').read_text()
start = view.index('    private func submit(')
methods = view[start:view.rfind('\n}')].replace('private func', 'func')
program = r'''
import Foundation
struct Message {
    enum Sender { case alicia, me }
    var sender: Sender
    var text: String
}
@MainActor final class UserDefaults {
    static let standard = UserDefaults()
    var values: [String: Data] = [:]
    func set(_ value: Data?, forKey key: String) { values[key] = value }
    func removeObject(forKey key: String) { values.removeValue(forKey: key) }
}
@MainActor final class FakeStore {
    var result: DialogueMutationResult?
    var sent: [DialogueMutation] = []
    var duringSave: (() -> Void)?
    func saveReplyReview(_ request: DialogueMutation) async -> DialogueMutationResult? {
        sent.append(request)
        duringSave?()
        return result
    }
}
@MainActor final class Harness {
    let store = FakeStore()
    let storageKey = "isolated-test"
    var editing: String?
    var busy = false
    var pending: DialogueMutation?
    var detail: DialogueReview?
    var error = ""
__METHODS__
}
@main struct Checks {
    @MainActor static func main() async throws {
        let original = DialogueMutation(action: "feedback", reply_id: DialogueReview.previewID,
            target: "reading", verdict: "misread", note: "I am tired, not ready.")
        precondition(UUID(uuidString: original.event_id) != nil)
        let uncertain = Harness()
        uncertain.pending = original
        await uncertain.retry()
        precondition(uncertain.pending == original && !uncertain.busy && !uncertain.error.isEmpty)
        let encoded = try JSONEncoder().encode(uncertain.pending)
        let restored = Harness()
        restored.pending = try JSONDecoder().decode(DialogueMutation.self, from: encoded)
        // Editing inputs cannot replace a request with uncertain delivery.
        restored.submit(DialogueMutation(action: "feedback", reply_id: original.reply_id,
            target: "reading", verdict: "accurate"))
        precondition(restored.pending == original)
        restored.store.result = DialogueMutationResult(ok: true, response: DialogueReview.preview)
        await restored.retry()
        precondition(restored.store.sent == [original] && restored.pending == nil && restored.error.isEmpty)
        precondition(restored.detail?.id == original.reply_id)
        let rejected = Harness()
        rejected.pending = original
        rejected.store.result = DialogueMutationResult(ok: false, error: "Not saved")
        await rejected.retry()
        precondition(rejected.pending == original && !rejected.error.isEmpty)
        let malformedSuccess = Harness()
        malformedSuccess.pending = original
        malformedSuccess.store.result = DialogueMutationResult(ok: true, response: nil)
        await malformedSuccess.retry()
        precondition(malformedSuccess.pending == original)
        let reentrant = Harness()
        reentrant.pending = original
        reentrant.busy = true
        await reentrant.retry()
        precondition(reentrant.store.sent.isEmpty)
        let encodedReview = try JSONEncoder().encode(DialogueReview.preview)
        let decoded = try JSONDecoder().decode(DialogueReview.self, from: encodedReview)
        precondition(decoded.comparison.status == "not_requested" && decoded.preference == nil)
        precondition(decoded.providerLabel == "Qwen · Mac mini")
        precondition(!original.training_allowed)
        let own = Message(sender: .me, text: String(repeating: "word ", count: 100))
        let old = Message(sender: .alicia, text: own.text)
        precondition(own.conversationalPreview == own.text)
        precondition(old.conversationalPreview.split(separator: " ").count <= 70)
        precondition(old.text == own.text)
        let choice = DialogueMutation(action: "preference", reply_id: original.reply_id,
            choice: "neither", reason: "Both overread my mood.")
        let decodedChoice = try JSONDecoder().decode(DialogueMutation.self, from: JSONEncoder().encode(choice))
        precondition(decodedChoice.choice == "neither" && !decodedChoice.training_allowed)
        let vote = DialogueMutation(action: "preference", reply_id: original.reply_id, choice: "alternative")
        precondition(vote.reason.isEmpty && vote.reason_tags.isEmpty && !vote.training_allowed)
        let alternative = DialogueMutation(action: "feedback", reply_id: original.reply_id, answer: "alternative", target: "tone", verdict: "warmer")
        precondition(alternative.body["answer"] as? String == "alternative")
        var oldWire = try JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as! [String: Any]
        oldWire.removeValue(forKey: "answer")
        oldWire.removeValue(forKey: "reason_tags")
        let oldPending = try JSONDecoder().decode(DialogueMutation.self, from: JSONSerialization.data(withJSONObject: oldWire))
        precondition(oldPending.event_id == original.event_id && oldPending.answer == "original")
        print("12 dialogue checks passed: quick vote, alternative attribution, legacy outbox migration, uncertain delivery, immutable retry, rejection, malformed success, reentrancy, wire decode, no implicit consent, legacy preview, neither choice")
    }
}
'''.replace('__METHODS__', methods)
with tempfile.TemporaryDirectory(prefix='alicia-dialogue-swift-') as temp:
    path = Path(temp)
    (path / 'Models.swift').write_text(models)
    (path / 'Checks.swift').write_text(program)
    env = dict(os.environ, DEVELOPER_DIR='/Applications/Xcode.app/Contents/Developer')
    subprocess.run(['xcrun','swiftc','-DDEBUG','-parse-as-library',str(path/'Models.swift'),str(path/'Checks.swift'),'-o',str(path/'checks')],check=True,env=env)
    subprocess.run([str(path/'checks')],check=True)
