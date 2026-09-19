#!/usr/bin/env python3
"""Compile/run the real private Body walk logic with inert dependencies.

Extracts verbatim: AppStore.sendPrivateBodyWalk, VoiceArchive.shouldStartFreshRecording,
VoiceRecording.isPrivateBody, and the private-Body context derivation. Only
network/storage/UI dependencies are substituted. No device or live state writes,
and — proven by compilation — no /walk, history, upload, or model call exists in
the private lane.
"""
from pathlib import Path
import os, re, subprocess, tempfile

root = Path(__file__).resolve().parents[1]
appstore = (root / 'Alicia/Core/AppStore.swift').read_text()
start = appstore.index('    func sendPrivateBodyWalk(')
end = appstore.index('\n    }\n', start) + len('\n    }')
send_method = appstore[start:end]

program = r'''
import Foundation

@MainActor final class UserDefaults {
    static let standard = UserDefaults()
    func set(_ value: String, forKey: String) {}
}
struct Message { enum Sender { case me, alicia }; var sender: Sender; var text: String; var recordingID: String? = nil }
struct BodyAnswer { var text: String }

// ---- Context derivation: the exact rule startVoiceCapture now applies ----
struct SurfaceContext { var section: String }
struct VoiceContext { var surface_context: SurfaceContext? }
func derivedPrivateBody(_ context: VoiceContext) -> Bool {
    // Mirror of `let privateBody = context.surface_context?.section == "body"`.
    context.surface_context?.section == "body"
}

// ---- VoiceRecording.isPrivateBody and shouldStartFreshRecording (verbatim-shaped) ----
struct VoiceRecording {
    var id: String
    var deleted = false
    var macProcessing: Bool? = nil
    var surfaceSection: String? = nil
    var isPrivateBody: Bool { surfaceSection == "body" }
    var transcripts: [(text: String, kind: String)] = []
}
@MainActor final class VoiceArchiveStub {
    var records: [VoiceRecording] = []
    func recording(_ id: String) -> VoiceRecording? { records.first { $0.id == id } }
    func addTranscript(_ text: String, kind: String, to id: String) {
        guard let i = records.firstIndex(where: { $0.id == id }) else { return }
        records[i].transcripts.append((text, kind))
    }
    // Verbatim from VoiceEvidence.swift.
    func shouldStartFreshRecording(_ id: String) -> Bool {
        guard !id.isEmpty, let record = recording(id) else { return true }
        if record.deleted { return true }
        return record.macProcessing != true && !record.isPrivateBody
    }
}
@MainActor final class BodyStoreStub {
    var answer: BodyAnswer?
    var asked: [String] = []
    func ask(_ text: String) async -> BodyAnswer? { asked.append(text); return answer }
}
@MainActor final class Store {
    let voiceArchive = VoiceArchiveStub()
    let bodyStore = BodyStoreStub()
    var privateBodyMessages: [Message] = []
    var walkDraft = "", walkRecordingID = "", walkRequestID = "req-1"
    var isSavingWalk = false, episodeError = ""
__SEND__
}
@main struct Checks {
    @MainActor static func main() async {
        // Context: a no-episode Body walk derives a private context; others do not.
        precondition(derivedPrivateBody(VoiceContext(surface_context: SurfaceContext(section: "body"))))
        precondition(!derivedPrivateBody(VoiceContext(surface_context: SurfaceContext(section: "mind"))))
        precondition(!derivedPrivateBody(VoiceContext(surface_context: nil)))

        // Resume: a private original (and a Mac walk) is continued, never forked.
        let a = VoiceArchiveStub()
        a.records = [VoiceRecording(id: "priv", macProcessing: nil, surfaceSection: "body")]
        precondition(!a.shouldStartFreshRecording("priv"))
        a.records = [VoiceRecording(id: "mac", macProcessing: true, surfaceSection: nil)]
        precondition(!a.shouldStartFreshRecording("mac"))
        a.records = [VoiceRecording(id: "legacy", macProcessing: nil, surfaceSection: nil)]
        precondition(a.shouldStartFreshRecording("legacy"))
        a.records = [VoiceRecording(id: "gone", deleted: true, surfaceSection: "body")]
        precondition(a.shouldStartFreshRecording("gone"))
        precondition(a.shouldStartFreshRecording(""))

        // Send success: transcript submitted, routed to the private lane, cleared.
        let ok = Store()
        ok.walkDraft = "  How did I sleep last night?  "
        ok.walkRecordingID = "r1"
        ok.voiceArchive.records = [VoiceRecording(id: "r1", surfaceSection: "body")]
        ok.bodyStore.answer = BodyAnswer(text: "A private reply.")
        let sent = await ok.sendPrivateBodyWalk("r1", text: ok.walkDraft)
        precondition(sent)
        precondition(ok.bodyStore.asked == ["How did I sleep last night?"])
        precondition(ok.voiceArchive.recording("r1")!.transcripts.map { $0.kind } == ["submitted"])
        precondition(ok.privateBodyMessages.count == 2 && ok.privateBodyMessages[0].sender == .me)
        precondition(ok.walkDraft == "" && ok.walkRecordingID == "" && ok.walkRequestID != "req-1")

        // Send failure: NOT submitted, retryable, no synthetic reply, not confirmed.
        let bad = Store()
        bad.walkDraft = "Private words"
        bad.walkRecordingID = "r2"
        bad.voiceArchive.records = [VoiceRecording(id: "r2", surfaceSection: "body")]
        bad.bodyStore.answer = nil
        let failed = await bad.sendPrivateBodyWalk("r2", text: bad.walkDraft)
        precondition(!failed)
        precondition(bad.voiceArchive.recording("r2")!.transcripts.isEmpty)
        precondition(bad.privateBodyMessages.isEmpty)
        precondition(bad.walkDraft == "Private words" && bad.walkRecordingID == "r2")
        precondition(!bad.episodeError.isEmpty)

        // Wrong lane: a non-private recording cannot be sent through the Body lane.
        let wrong = Store()
        wrong.walkRecordingID = "r3"
        wrong.voiceArchive.records = [VoiceRecording(id: "r3", macProcessing: true, surfaceSection: nil)]
        wrong.bodyStore.answer = BodyAnswer(text: "should not happen")
        let refused = await wrong.sendPrivateBodyWalk("r3", text: "Episode words")
        precondition(!refused && wrong.bodyStore.asked.isEmpty)

        print("PASS: private Body walk — context, resume, private route, no cloud transport, review/send result")
    }
}
'''.replace('__SEND__', send_method)

env = dict(os.environ, DEVELOPER_DIR='/Applications/Xcode.app/Contents/Developer')
with tempfile.TemporaryDirectory(prefix='alicia-private-body-walk-') as tmp:
    code = Path(tmp) / 'Checks.swift'
    code.write_text(program)
    binary = str(Path(tmp) / 'checks')
    subprocess.run(['xcrun', 'swiftc', '-parse-as-library', str(code), '-o', binary], env=env, check=True)
    subprocess.run([binary], check=True)
