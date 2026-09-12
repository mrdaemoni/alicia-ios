#!/usr/bin/env python3
"""Run actual reader state/retry methods with inert player IO; never load audio."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
source = (root / 'Alicia/Core/SpeechReader.swift').read_text()


def method(name):
    start = source.index('    ' + name)
    opening = source.index('{', start)
    depth, end = 1, opening + 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[start:end].replace('private func', 'func')


methods = '\n'.join(method(name) for name in [
    'func toggle()', 'private func locate(', 'private func rebuildQueue(',
    'private func updateMediaState(', 'private func mediaDidFail(',
    'private func retryMedia()', 'private func extend(', 'func seekToNarration('])

# Keep the fake IO separate; only the production methods above decide state.
harness = r'''
import Foundation
struct Readable: Equatable { var id: String; var episodeID: String? = nil }
struct SpeechChunk { var duration: Double }
struct CMTime { var seconds: Double; var preferredTimescale: Int }
enum Status { case unknown, readyToPlay, failed }
enum TimeStatus { case paused, waitingToPlayAtSpecifiedRate, playing }
final class AVPlayerItem {
    var status = Status.unknown
    var sought = 0.0
    func seek(to time: CMTime, completionHandler: ((Bool) -> Void)?) { sought = time.seconds }
}
final class AVQueuePlayer {
    enum Action { case advance }
    var status = Status.readyToPlay
    var timeControlStatus = TimeStatus.paused
    var items: [AVPlayerItem] = []
    var currentItem: AVPlayerItem? { items.first }
    var actionAtItemEnd = Action.advance
    var rate: Float = 0
    var playCount = 0
    var beforePlay: (() -> Void)?
    func pause() { rate = 0; timeControlStatus = .paused }
    func play() { beforePlay?(); playCount += 1; timeControlStatus = .waitingToPlayAtSpecifiedRate }
    func removeAllItems() { items = [] }
}
final class Synth {
    enum Boundary { case word }
    func pauseSpeaking(at: Boundary) {}
    func continueSpeaking() -> Bool { true }
}
@MainActor final class Probe {
    enum Voice { case her, device }
    var current: Readable? = Readable(id: "morning:fixture")
    var queueItems = [Readable(id: "earlier"), Readable(id: "morning:fixture"), Readable(id: "later")]
    var queuePosition = 1, playlistName = "Morning"
    var isActive: Bool { current != nil }
    var voice = Voice.her
    var isSpeaking = true, isLoadingMedia = false, isPreparing = false, isStreaming = false
    var mediaFailed = false, failure: String?
    var mediaGeneration = 1, currentIndex = 0, queuedCount = 0
    var chunks = [SpeechChunk(duration: 10), SpeechChunk(duration: 20)]
    var duration = 30.0, progress = 0.5
    var rate: Float = 1.5
    var queue = AVQueuePlayer(), synth = Synth()
    var indexOfItem: [ObjectIdentifier: Int] = [:]
    var pollTask: Task<Void, Never>?
    var requested: [String] = []
    var seekFractions: [Double] = []
    func seek(to fraction: Double) { seekFractions.append(fraction) }
    var episodeStopped: ((Bool) -> Void)?
    var appendShouldFail = false
    func activateAudioSession() {}
    func publishNowPlaying() {}
    func deviceCharIndex(for: Double) -> Int { 0 }
    func speakOnDevice(from: Int) { fatalError("Media failure must not invent a stand-in voice") }
    func requestHerVoice(for item: Readable) { requested.append(item.id) }
    func detachObservers() { mediaGeneration += 1 }
    func attachObservers() {}
    func append(chunkAt index: Int) {
        guard !mediaFailed else { return }
        let item = AVPlayerItem()
        indexOfItem[ObjectIdentifier(item)] = index
        if appendShouldFail {
            mediaDidFail(generation: mediaGeneration, itemID: ObjectIdentifier(item))
        } else {
            queue.items.append(item); queuedCount = max(queuedCount, index + 1)
        }
    }
''' + methods + r'''
}
@main struct Run {
 @MainActor static func main() {
    var count = 0
    func check(_ ok: Bool, _ message: String) { precondition(ok, message); count += 1 }
    let seek = Probe()
    seek.seekToNarration(seconds: 12)
    check(seek.seekFractions == [0.4], "Measured word seeks across chunk boundaries")
    seek.seekToNarration(seconds: 90)
    check(seek.seekFractions.last == 1, "Seek clamps to rendered audio")
    seek.seekToNarration(seconds: -2)
    check(seek.seekFractions.last == 0, "Negative seek lands at the beginning")
    let beforeInvalid = seek.seekFractions.count
    seek.seekToNarration(seconds: .nan)
    check(seek.seekFractions.count == beforeInvalid, "Non-finite timestamps do not reach the player")
    let finished = Probe(); finished.isSpeaking = false; finished.progress = 1
    finished.toggle()
    check(finished.isSpeaking && finished.progress == 0, "A finished reading restarts explicitly")
    let startup = Probe()
    startup.updateMediaState(generation: 1)
    check(startup.isSpeaking && startup.isLoadingMedia, "Startup intent remains loading before the first player callback")
    startup.queue.timeControlStatus = .playing; startup.updateMediaState(generation: 1)
    check(startup.isSpeaking && !startup.isLoadingMedia, "Actual playing clears loading")
    startup.queue.timeControlStatus = .waitingToPlayAtSpecifiedRate; startup.updateMediaState(generation: 1)
    check(startup.isSpeaking && startup.isLoadingMedia, "Buffer stall remains visibly loading")
    startup.toggle()
    check(!startup.isSpeaking && !startup.isLoadingMedia && startup.queue.rate == 0, "Pause clears playback intent and loading")
    startup.queue.beforePlay = { precondition(startup.isLoadingMedia, "Loading precedes queue.play") }
    startup.toggle()
    check(startup.isSpeaking && startup.isLoadingMedia && startup.progress == 0.5, "Resume keeps place and signals loading before play")

    let failed = Probe(), dead = AVPlayerItem()
    failed.queue.items = [dead]; failed.indexOfItem[ObjectIdentifier(dead)] = 0
    dead.status = .failed
    let oldTask = Task<Void, Never> {}; failed.pollTask = oldTask
    var morningStops: [Bool] = []; failed.episodeStopped = { morningStops.append($0) }
    failed.updateMediaState(generation: 1)
    check(!failed.isSpeaking && !failed.isLoadingMedia && failed.failure != nil && oldTask.isCancelled,
          "A failed item stops intent/loading, cancels render polling and exposes failure")
    check(failed.current?.id == "morning:fixture" && failed.queuePosition == 1 && failed.queueItems.count == 3
          && failed.playlistName == "Morning" && failed.progress == 0.5 && morningStops.isEmpty,
          "Failure keeps the exact reading/playlist/place and does not invent podcast evidence")
    failed.toggle()
    check(failed.queue.currentItem !== dead && failed.currentIndex == 1 && failed.queue.currentItem?.sought == 5
          && failed.isSpeaking && failed.isLoadingMedia && failed.failure == nil,
          "Retry builds fresh items at the preserved whole-piece offset")
    check(failed.requested.isEmpty && failed.voice == .her && failed.queuePosition == 1,
          "Prepared media retries the same recording without a render or device voice")
    failed.mediaDidFail(generation: 1, itemID: ObjectIdentifier(dead))
    check(!failed.mediaFailed, "An old queued failure callback cannot break a successful retry")
    failed.mediaDidFail(generation: failed.mediaGeneration, itemID: ObjectIdentifier(dead))
    check(!failed.mediaFailed, "A foreign or removed item cannot fail the current reading")

    let playerFailure = Probe(); let oldPlayer = playerFailure.queue
    oldPlayer.status = .failed
    playerFailure.updateMediaState(generation: 1); playerFailure.toggle()
    check(playerFailure.queue !== oldPlayer && playerFailure.isSpeaking && playerFailure.queuePosition == 1,
          "A failed AVQueuePlayer itself is replaced on retry without replacing the playlist")
    let episode = Probe(); episode.current?.episodeID = "S15E08"
    var stopped: [Bool] = []; episode.episodeStopped = { stopped.append($0) }
    episode.mediaDidFail(generation: 1); episode.mediaDidFail(generation: 1)
    check(stopped == [false], "Episode failure closes observation once, never claims completion")
    let unavailable = Probe(); unavailable.failure = "Offline"; unavailable.isSpeaking = false
    unavailable.toggle()
    check(unavailable.requested == ["morning:fixture"] && unavailable.isPreparing && !unavailable.isSpeaking,
          "Unavailable narration retries the server without fabricating playback")
    let preparing = Probe(); preparing.chunks = []; preparing.isSpeaking = false; preparing.isPreparing = true
    preparing.toggle()
    check(!preparing.isSpeaking && preparing.queue.playCount == 0, "Preparing cannot pretend audio is playing")
    let stale = Probe(); stale.queue.status = .failed; stale.updateMediaState(generation: 0)
    check(stale.isSpeaking && stale.failure == nil, "Previous-generation status callbacks are ignored")

    let streaming = Probe(); streaming.isPreparing = true; streaming.queuedCount = 2
    streaming.appendShouldFail = true
    streaming.extend(with: streaming.chunks + [SpeechChunk(duration: 5)], total: 35, complete: false)
    check(streaming.mediaFailed && !streaming.isSpeaking && !streaming.isLoadingMedia && streaming.queue.playCount == 0,
          "A synchronous append failure cannot be resurrected by the remaining streaming update")
    let waiting = Probe(); waiting.isPreparing = true; waiting.isSpeaking = false; waiting.queuedCount = 2
    waiting.queue.beforePlay = { precondition(waiting.isLoadingMedia && waiting.isSpeaking) }
    waiting.extend(with: waiting.chunks + [SpeechChunk(duration: 5)], total: 35, complete: false)
    check(waiting.isSpeaking && waiting.isLoadingMedia, "New rendered audio reports loading before resuming an exhausted stream")
    let paused = Probe(); paused.isSpeaking = false; paused.queuedCount = 2
    paused.extend(with: paused.chunks + [SpeechChunk(duration: 5)], total: 35, complete: true)
    check(!paused.isSpeaking && !paused.isLoadingMedia && paused.queue.playCount == 0,
          "A background render update cannot resume a manually paused ready reading")
    let rendering = Probe(); rendering.isStreaming = true; rendering.mediaDidFail(generation: 1); rendering.toggle()
    check(rendering.requested == ["morning:fixture"], "An incomplete stream resumes its existing render only after deliberate retry")
    let switched = Probe(); switched.queue.status = .failed; let replaced = switched.queue
    switched.rebuildQueue(from: 0, offset: 0)
    check(switched.queue !== replaced && switched.isSpeaking, "Selecting a new recording also replaces a failed old player")
    print("\(count) actual reader media lifecycle checks passed")
 }
}
'''
with tempfile.TemporaryDirectory(prefix='alicia-reading-media-') as temporary:
    folder = Path(temporary)
    main = folder / 'main.swift'
    main.write_text(harness)
    binary = folder / 'test'
    subprocess.run(['xcrun', 'swiftc', '-parse-as-library', str(main), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
