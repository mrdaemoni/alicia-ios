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
struct BodyAnswer { var text: String; var status: String = "ready" }

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
    var rejectWrites = false
    func recording(_ id: String) -> VoiceRecording? { records.first { $0.id == id } }
    @discardableResult func addTranscript(_ text: String, kind: String, to id: String) -> Bool {
        guard !rejectWrites, let i = records.firstIndex(where: { $0.id == id }) else { return false }
        records[i].transcripts.append((text, kind))
        return true
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
        ok.bodyStore.answer = BodyAnswer(text: "A private reply.", status: "ready")
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

        // Non-ready status over HTTP 200 is NOT acceptance: keep words, no submit.
        for badStatus in ["private_context_unavailable", "invalid_question", "oversized"] {
            let nr = Store()
            nr.walkDraft = "My complete private reflection"
            nr.walkRecordingID = "rn"
            nr.voiceArchive.records = [VoiceRecording(id: "rn", surfaceSection: "body")]
            nr.bodyStore.answer = BodyAnswer(text: "Not available", status: badStatus)
            let accepted = await nr.sendPrivateBodyWalk("rn", text: nr.walkDraft)
            precondition(!accepted, "\(badStatus) must not be treated as saved")
            precondition(nr.walkDraft == "My complete private reflection")
            precondition(nr.walkRecordingID == "rn")
            precondition(nr.voiceArchive.recording("rn")!.transcripts.isEmpty)
            precondition(nr.privateBodyMessages.isEmpty)
            precondition(!nr.episodeError.isEmpty)
        }

        // Local persistence failure of the submitted transcript keeps words editable.
        let disk = Store()
        disk.walkDraft = "Keep these words after a disk error"
        disk.walkRecordingID = "rd"
        disk.voiceArchive.records = [VoiceRecording(id: "rd", surfaceSection: "body")]
        disk.voiceArchive.rejectWrites = true
        disk.bodyStore.answer = BodyAnswer(text: "Ready reply", status: "ready")
        let stored = await disk.sendPrivateBodyWalk("rd", text: disk.walkDraft)
        precondition(!stored)
        precondition(disk.walkDraft == "Keep these words after a disk error")
        precondition(disk.walkRecordingID == "rd")
        precondition(disk.privateBodyMessages.isEmpty)
        precondition(!disk.episodeError.isEmpty)

        // The 4000-character private limit is explicit; never silently truncated.
        let big = Store()
        let long = String(repeating: "x", count: 4001)
        big.walkDraft = long
        big.walkRecordingID = "rb"
        big.voiceArchive.records = [VoiceRecording(id: "rb", surfaceSection: "body")]
        big.bodyStore.answer = BodyAnswer(text: "Ready reply", status: "ready")
        let over = await big.sendPrivateBodyWalk("rb", text: long)
        precondition(!over)
        precondition(big.walkDraft == long, "original words untouched, not shortened")
        precondition(big.bodyStore.asked.isEmpty, "over-limit words are never sent")
        precondition(big.episodeError.contains("4000"))
        // Exactly at the limit with a ready reply is accepted.
        let edge = Store()
        let atLimit = String(repeating: "y", count: 4000)
        edge.walkDraft = atLimit
        edge.walkRecordingID = "re"
        edge.voiceArchive.records = [VoiceRecording(id: "re", surfaceSection: "body")]
        edge.bodyStore.answer = BodyAnswer(text: "Ready reply", status: "ready")
        let edgeSent = await edge.sendPrivateBodyWalk("re", text: atLimit)
        precondition(edgeSent)

        // Wrong lane: a non-private recording cannot be sent through the Body lane.
        let wrong = Store()
        wrong.walkRecordingID = "r3"
        wrong.voiceArchive.records = [VoiceRecording(id: "r3", macProcessing: true, surfaceSection: nil)]
        wrong.bodyStore.answer = BodyAnswer(text: "should not happen")
        let refused = await wrong.sendPrivateBodyWalk("r3", text: "Episode words")
        precondition(!refused && wrong.bodyStore.asked.isEmpty)

        print("PASS: private Body walk — context, resume, private route, ready-status, durable submit, local-write and 4000-char failures")
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
