#!/usr/bin/env python3
"""Compile/run AppStore's actual save method with inert dependencies.

No Xcode test target is needed. The tested method is extracted verbatim; only
network/UI/storage dependencies are substituted. No device or live state writes.
"""
from pathlib import Path
import os
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
source = (root / 'Alicia/Core/AppStore.swift').read_text()
start = source.index('    func finishEpisodeWalk() async -> Bool {')
end = source.index('    /// Positive, continuous AVPlayer', start)
method = source[start:end]
program = r'''
import Foundation

@MainActor final class UserDefaults {
    static let standard = UserDefaults()
    func set(_ value: String, forKey: String) {}
}
struct WalkReceipt { var ok: Bool; var message: String? = nil }
struct Message { enum Sender { case me }; var sender: Sender; var text: String }
enum Section { case us, mind }
@MainActor final class FakeService {
    var result: WalkReceipt?
    var sent: [[String: String]] = []
    var duringSave: (() -> Void)?
    func finishWalk(text: String, episodeID: String, requestID: String, prompt: String, recordingID: String) async -> WalkReceipt? {
        sent.append(["text": text, "episode_id": episodeID, "request_id": requestID, "prompt": prompt, "recording_id": recordingID])
        duringSave?()
        return result
    }
}
struct VoiceArchiveStub {
 func hasAudio(_ id:String)->Bool { false }
 func recording(_ id:String)->Bool? { nil }
 func addTranscript(_ text:String, kind:String, to:String) {}
}
@MainActor final class Store {
 let voiceArchive=VoiceArchiveStub()
 var walkRecordingID=""
 func syncVoiceArchive() async {}
 func pauseEpisodeWalk() {}
    let service = FakeService()
    var pendingWalkSave: [String: String]?
    var walkDraft = "My reflection", walkEpisodeID = "S1E01", walkRequestID = "receipt-1", walkPrompt = "The actual question"
    var isSavingWalk = false, showWalk = true
    var episodeError = "", thinkingMode = "walk"
    var messages: [Message] = []
    var selectedSection = Section.us
    func refreshEpisodeDay() async {}
    func awaitEpisodeFrame() {}
__METHOD__
}
@main struct Checks {
    @MainActor static func main() async {
        let successful = Store()
        successful.service.result = WalkReceipt(ok: true)
        let saved = await successful.finishEpisodeWalk()
        precondition(saved && successful.walkDraft.isEmpty && successful.pendingWalkSave == nil)
        precondition(successful.messages.count == 1 && !successful.showWalk && successful.selectedSection == .mind)

        let uncertain = Store()
        let unknown = await uncertain.finishEpisodeWalk()
        precondition(!unknown && uncertain.pendingWalkSave?["text"] == "My reflection")
        let snapshot = uncertain.pendingWalkSave!
        // Relaunch with the persisted pending payload: retry its exact words/id.
        let restored = Store()
        restored.pendingWalkSave = snapshot
        restored.walkDraft = "Additional words that must survive"
        restored.service.result = WalkReceipt(ok: true)
        let retried = await restored.finishEpisodeWalk()
        precondition(retried && restored.service.sent[0] == snapshot)
        precondition(restored.walkDraft == "Additional words that must survive")

        let rejected = Store()
        rejected.service.result = WalkReceipt(ok: false, message: "Please edit this")
        let refused = await rejected.finishEpisodeWalk()
        precondition(!refused && rejected.pendingWalkSave == nil && rejected.walkDraft == "My reflection")
        precondition(rejected.episodeError == "Please edit this" && rejected.walkRequestID != "receipt-1")

        let long = Store()
        long.walkDraft = String(repeating: "a", count: 60001)
        let tooLong = await long.finishEpisodeWalk()
        precondition(!tooLong && long.pendingWalkSave == nil && long.service.sent.isEmpty && !long.walkDraft.isEmpty)

        let changed = Store()
        changed.service.result = WalkReceipt(ok: true)
        changed.service.duringSave = { changed.walkDraft = "Newer words" }
        let changedResult = await changed.finishEpisodeWalk()
        precondition(changedResult && changed.walkDraft == "Newer words")
        print("PASS: walk success, immutable retry, relaunch, definite rejection, size bound, concurrent edit")
    }
}
'''.replace('__METHOD__', method)
env = dict(os.environ, DEVELOPER_DIR='/Applications/Xcode.app/Contents/Developer')
with tempfile.TemporaryDirectory(prefix='alicia-walk-save-') as tmp:
    code = Path(tmp) / 'Checks.swift'
    code.write_text(program)
    binary = str(Path(tmp) / 'checks')
    subprocess.run(['xcrun', 'swiftc', '-parse-as-library', str(code), '-o', binary], env=env, check=True)
    subprocess.run([binary], check=True)
