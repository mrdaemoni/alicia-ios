#!/usr/bin/env python3
"""Exercise retained long-form hypotheses from the actual Swift buffer."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='alicia-speech-buffer-') as temporary:
    folder = Path(temporary)
    main = folder / 'main.swift'
    main.write_text(r'''
import Foundation
typealias Word = SpeechTranscriptBuffer.Word
var count = 0
func check(_ ok: Bool, _ description: String) {
    guard ok else { fatalError(description) }
    count += 1
}
func word(_ text: String, _ start: Double) -> Word { Word(text: text, start: start, duration: 0.3) }
var buffer = SpeechTranscriptBuffer()
buffer.receive([word("Pruning", 1), word("versus", 1.5), word("shrinking", 2)])
buffer.receive([word("Pruning", 1), word("and", 1.5), word("shrinking", 2)])
check(buffer.text == "Pruning and shrinking", "Current hypothesis must remain correctable")
buffer.receive([word("A", 65), word("different", 65.5), word("altitude", 66)])
check(buffer.text == "Pruning and shrinking A different altitude", "A later utterance must not erase the earlier minute")
buffer.receive([])
check(buffer.text.contains("Pruning"), "Empty partial must preserve prior capture")
buffer.receive([word("altitude", 0)])
check(buffer.needsReview && buffer.text.contains("Pruning"), "Regressed timing must be visible and preserve captured words")
buffer.finishRequest()
buffer.receive([word("Enough", 0), word("before", 0.5), word("and", 1), word("after", 1.5)])
check(buffer.text.contains("altitude\n\nEnough"), "Request rollover must preserve preceding capture")
buffer.finishRequest()
let complete = buffer.text
buffer.finishRequest()
check(buffer.text == complete, "Repeated finish must not duplicate committed words")
var long = SpeechTranscriptBuffer()
for minute in 0..<6 {
    for sentence in 0..<6 {
        long.receive([word("minute\(minute)-sentence\(sentence)", Double(sentence * 9))])
    }
    long.finishRequest()
}
check(long.text.contains("minute0-sentence0") && long.text.contains("minute5-sentence5"), "Retain beginning and ending of several-minute recording")
check(long.text.split(whereSeparator: \.isWhitespace).count == 36, "Every timed sentence appears once")
var invalid = SpeechTranscriptBuffer()
invalid.receive([word("kept", 0)])
invalid.receive([Word(text:"bad",start:.nan,duration:1)])
check(invalid.needsReview && invalid.text == "kept", "Reject invalid timestamps without erasing words")

// Sept 8 production text repeats a leading phrase inside each request, already
// in on_device text. Callback timing was not logged. These synthetic revisions
// reproduce the proven zero-timing merge failure, not an invented device trace.
func provisional(_ phrase: String, start: Double = 0) -> [Word] {
    phrase.split(separator: " ").map { Word(text: String($0), start: start, duration: 0) }
}
func positioned(_ phrase: String, start: Double = 0.2) -> [Word] {
    phrase.split(separator: " ").enumerated().map {
        Word(text: String($0.element), start: start + Double($0.offset) * 0.25, duration: 0.2)
    }
}
let phrase = "I like this morning briefing because it gives us a shared place to begin thinking about the questions for today"
var short = SpeechTranscriptBuffer()
short.receive(provisional(phrase))
short.receive(positioned(phrase))
check(short.text == phrase, "Timed revision must replace the unresolved phrase, not duplicate its leading words")
short.receive(positioned(phrase + " and tomorrow"))
check(short.text == phrase + " and tomorrow", "Later cumulative expansion must not retain the provisional copy")
short.finishRequest(); short.finishRequest()
check(short.text == phrase + " and tomorrow", "Final callback and repeated finish commit a revised phrase only once")

var mixed = SpeechTranscriptBuffer()
mixed.receive([word("A", 0)] + provisional("small correction"))
mixed.receive(positioned("A small correction"))
check(mixed.text == "A small correction", "A partly unresolved hypothesis must be replaced as a unit")
var missingDuration = SpeechTranscriptBuffer()
missingDuration.receive(provisional("Words with unresolved duration", start: 2))
missingDuration.receive(positioned("Words with unresolved duration", start: 2.2))
check(missingDuration.text == "Words with unresolved duration", "Nonzero timestamps alone cannot prove a completed earlier phrase")

var earlier = SpeechTranscriptBuffer()
earlier.receive(positioned("An earlier thought", start: 0))
earlier.receive(provisional("The newest thought", start: 4))
earlier.receive(positioned("The revised thought", start: 4.2))
check(earlier.text == "An earlier thought The revised thought",
      "Replacing an unresolved latest hypothesis must preserve independently timed earlier speech")

var repeated = SpeechTranscriptBuffer()
repeated.receive(provisional("Again and again"))
repeated.receive(positioned("Again and again again and again"))
check(repeated.text == "Again and again again and again", "Intentional repetition within one hypothesis survives")
var distinct = SpeechTranscriptBuffer()
distinct.receive(positioned("Try it again", start: 0))
distinct.receive(positioned("Try it again", start: 5))
check(distinct.text == "Try it again Try it again", "The same words at later acoustic positions are new speech")
distinct.finishRequest(); distinct.receive(provisional("Try it again"))
distinct.receive(positioned("Try it again")); distinct.finishRequest()
check(distinct.text == "Try it again Try it again\n\nTry it again", "The same words in a new request are never deduplicated")

var walk = SpeechTranscriptBuffer()
let passages = ["The first photograph", "The empty frame", "A moving balance", "A different altitude", "The next thought"]
for passage in passages {
    walk.receive(provisional(passage))
    walk.receive(positioned(passage))
    walk.receive(positioned(passage + " opens a question"))
    walk.finishRequest()
}
check(walk.text == passages.map { $0 + " opens a question" }.joined(separator: "\n\n"),
      "A multi-request walk keeps each revised passage once, including the first and last")
print("\(count) speech transcript checks passed")
''')
    binary = folder / 'test'
    subprocess.run(['xcrun', 'swiftc', str(root / 'Alicia/Core/SpeechTranscriptBuffer.swift'), str(main), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)

    # Exercise actual owned PCM copies without a recognizer, microphone, or
    # simulator. AVAudioPCMBuffer here contains only generated sample values.
    speech = (root / 'Alicia/Core/SpeechTranscriber.swift').read_text()
    queue = speech[speech.index('private struct SpeechPCMQueue {'):speech.index('/// A small lock')]
    queue = queue.replace('private struct SpeechPCMQueue', 'struct SpeechPCMQueue')
    main.write_text('import Foundation\nimport AVFoundation\n' + queue + r'''
func check(_ ok: Bool, _ message: String) { precondition(ok, message) }
let format = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1)!
let input = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 8)!
input.frameLength = 8
for i in 0..<8 { input.floatChannelData![0][i] = 1 }
var queue = SpeechPCMQueue(); queue.maxBytes = 64; queue.maxBuffers = 2
queue.append(input)
input.floatChannelData![0][0] = 9
queue.append(input)
check(queue.byteCount == 64, "Byte accounting must include both retained buffers")
queue.append(input)
check(queue.byteCount == 64 && queue.dropped, "Byte overflow is bounded and visible")
let samples = queue.take()
check(samples.count == 2 && queue.byteCount == 0, "Handoff drains retained buffers once")
check(samples[0].floatChannelData![0][0] == 1, "Tap reuse cannot alter owned earlier audio")
check(samples[1].floatChannelData![0][0] == 9, "Handoff preserves FIFO order")
check(queue.take().isEmpty, "Retrying handoff cannot duplicate samples")
var countBound = SpeechPCMQueue(); countBound.maxBuffers = 1
countBound.append(input); countBound.append(input)
check(countBound.dropped && countBound.take().count == 1, "Buffer count also bounds allocation overhead")
var discarded = SpeechPCMQueue()
discarded.append(input); discarded.discard()
check(discarded.dropped && discarded.byteCount == 0, "Discarding unrecognized audio is visible")
let stereo = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
let channels = AVAudioPCMBuffer(pcmFormat: stereo, frameCapacity: 8)!
channels.frameLength = 8
channels.floatChannelData![0][0] = 3; channels.floatChannelData![1][0] = 7
var stereoQueue = SpeechPCMQueue(); stereoQueue.append(channels)
let result = stereoQueue.take()[0]
check(result.floatChannelData![0][0] == 3 && result.floatChannelData![1][0] == 7,
      "Every planar microphone channel survives")
print("9 PCM handoff checks passed")
''')
    subprocess.run(['xcrun', 'swiftc', str(main), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)

    # Run the actual drain/finalization methods against inert IO. In particular,
    # an already-queued timer callback must not undo Finish's final-result grace.
    def method(name):
        start = speech.index('    ' + name)
        opening = speech.index('{', start)
        depth = 1
        end = opening + 1
        while depth:
            depth += (speech[end] == '{') - (speech[end] == '}')
            end += 1
        return speech[start:end].replace('private func', 'func')

    methods = '\n'.join(method(name) for name in [
        'private func beginRecognitionFinalization(',
        'private func drainAudio()',
        'func finishAndStop() async',
        'private func awaitFinalRecognition('])
    main.write_text(r'''
import Foundation
struct Sink { func drain() -> (segments: [Int], error: String?) { ([], nil) } }
final class Relay {
    var hasBufferedAudio = false
    var buffering = false
    var endCalls = 0
    func metrics() -> (seconds: Double, level: Double, dropped: Bool) { (12, 0.5, false) }
    func set(_ value: String?, bufferWhileUnavailable: Bool = false) { endCalls += 1; buffering = bufferWhileUnavailable }
}
final class Engine {
    var isRunning = true
    var inputNode: Engine { self }
    func stop() { isRunning = false }
    func removeTap(onBus: Int) {}
}
@MainActor final class Probe {
    var sink: Sink? = Sink()
    let relay = Relay(), engine = Engine()
    var isRecording = true, isFinishing = false, hasTap = true
    var liveTextAvailable = true, transcriptNeedsReview = false
    var recordedSeconds = 0.0, inputLevel = 0.0
    var recognitionStarted = ProcessInfo.processInfo.systemUptime
    var retryAt = 0.0, recognitionDeadline: Double?
    let finalizationGrace = 0.03
    var timer: Timer?, task: String? = "active"
    var generation = 1, stopCount = 0, startCount = 0, finishCount = 0
    var lastError: String?
    var deliverSegments: (([Int]) -> Void)?
    func startRecognition() { startCount += 1; task = "new"; relay.hasBufferedAudio = false }
    func finishRecognition(preserveBufferedAudio: Bool = false) {
        finishCount += 1; task = nil; recognitionDeadline = nil
    }
    func stop() { stopCount += 1; generation += 1; isRecording = false; isFinishing = false; task = nil }
''' + methods + r'''
}
@main struct Run {
 @MainActor static func main() async {
    let finishing = Probe(); finishing.isFinishing = true; finishing.engine.isRunning = false
    finishing.drainAudio()
    precondition(finishing.stopCount == 0 && finishing.task != nil && finishing.lastError == nil,
                 "Queued drain cannot stop an intentional finish or invent a route error")
    let rollover = Probe(); rollover.recognitionStarted -= 41
    rollover.drainAudio()
    precondition(rollover.task != nil && rollover.finishCount == 0 && rollover.recognitionDeadline != nil
                 && rollover.relay.buffering, "Rollover must await a final result while buffering microphone input")
    rollover.recognitionDeadline = 0; rollover.drainAudio()
    precondition(rollover.transcriptNeedsReview && rollover.finishCount == 1 && rollover.startCount == 1,
                 "Expired final grace is visible and starts a bounded new request")
    let final = Probe()
    Task { @MainActor in try? await Task.sleep(for: .milliseconds(10)); final.task = nil }
    await final.finishAndStop()
    precondition(final.stopCount == 1 && !final.transcriptNeedsReview, "A final callback received in grace succeeds")
    let timeout = Probe(); await timeout.finishAndStop()
    precondition(timeout.stopCount == 1 && timeout.transcriptNeedsReview, "A missing final result needs review")
    let interruption = Probe()
    Task { @MainActor in try? await Task.sleep(for: .milliseconds(10)); interruption.stop() }
    await interruption.finishAndStop()
    precondition(interruption.stopCount == 1 && interruption.startCount == 0,
                 "An interruption invalidates the pending finish without restarting")
    let queued = Probe(); queued.task = nil; queued.relay.hasBufferedAudio = true
    await queued.finishAndStop()
    precondition(queued.startCount == 1 && queued.transcriptNeedsReview,
                 "Finishing during handoff submits queued audio to one final bounded request")
    print("7 recognition lifecycle checks passed")
 }
}
''')
    subprocess.run(['xcrun', 'swiftc', '-parse-as-library', str(main), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
