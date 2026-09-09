import Foundation
import Speech
import AVFoundation

/// The audio tap's memory is reused after its callback. Retain owned copies only
/// while recognition hands off; both byte and buffer counts have hard bounds.
private struct SpeechPCMQueue {
    var maxBytes = 2_000_000
    var maxBuffers = 128
    private(set) var byteCount = 0
    private(set) var dropped = false
    private var buffers: [AVAudioPCMBuffer] = []

    mutating func append(_ input: AVAudioPCMBuffer) {
        let source = UnsafeMutableAudioBufferListPointer(input.mutableAudioBufferList)
        let bytes = source.reduce(0) { $0 + Int($1.mDataByteSize) }
        guard input.frameLength > 0, bytes > 0 else { return }
        guard buffers.count < maxBuffers, bytes <= maxBytes - byteCount,
              let copy = AVAudioPCMBuffer(pcmFormat: input.format, frameCapacity: input.frameLength) else {
            dropped = true; return
        }
        copy.frameLength = input.frameLength
        let target = UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)
        guard source.count == target.count else { dropped = true; return }
        for index in source.indices {
            guard let from = source[index].mData, let to = target[index].mData,
                  target[index].mDataByteSize >= source[index].mDataByteSize else { dropped = true; return }
            memcpy(to, from, Int(source[index].mDataByteSize))
        }
        buffers.append(copy); byteCount += bytes
    }

    mutating func take() -> [AVAudioPCMBuffer] {
        let result = buffers
        buffers = []; byteCount = 0
        return result
    }

    mutating func discard() {
        if byteCount > 0 { dropped = true }
        _ = take()
    }
}

/// A small lock keeps the realtime tap independent of recognition restarts.
private final class SpeechRequestRelay: @unchecked Sendable {
    private let lock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var seconds = 0.0
    private var level = 0.0
    private var buffering = false
    private var pending = SpeechPCMQueue()
    func reset() {
        lock.lock(); defer { lock.unlock() }
        seconds = 0; level = 0
        pending = SpeechPCMQueue(); buffering = false
    }
    func metrics() -> (seconds: Double, level: Double, dropped: Bool) {
        lock.lock(); defer { lock.unlock() }
        return (seconds, level, pending.dropped)
    }
    var hasBufferedAudio: Bool {
        lock.lock(); defer { lock.unlock() }
        return pending.byteCount > 0
    }
    func set(_ next: SFSpeechAudioBufferRecognitionRequest?, bufferWhileUnavailable: Bool = false) {
        lock.lock(); defer { lock.unlock() }
        request?.endAudio(); request = next
        buffering = bufferWhileUnavailable
        if let next {
            for buffer in pending.take() { next.append(buffer) }
        } else if !buffering { pending.discard() }
    }
    func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock(); defer { lock.unlock() }
        if buffer.format.sampleRate > 0 {
            seconds += Double(buffer.frameLength) / buffer.format.sampleRate
        }
        if let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 {
            var sum: Double = 0
            for index in 0..<Int(buffer.frameLength) { sum += Double(samples[index] * samples[index]) }
            let rms = sqrt(sum / Double(buffer.frameLength))
            // Meter only. Original samples and the recognizer input are unchanged.
            level = max(0, min(1, (20 * log10(max(rms, 0.00001)) + 65) / 55))
        }
        if let request { request.append(buffer) }
        else if buffering { pending.append(buffer) }
    }
}

/// Original audio is captured independently of on-device live transcription.
@MainActor @Observable
final class SpeechTranscriber {
    var isRecording = false
    var isFinishing = false
    var transcript = ""
    var authorized = false
    var lastError: String?
    var recordedSeconds = 0.0
    var inputLevel = 0.0
    var microphoneName = "Microphone"
    var liveTextAvailable = false
    var transcriptNeedsReview = false
    private var speechAuthorized = false
    private var liveTranscription = true
    var audioCaptureFailed = false
    private var hasTap = false
    private var generation = 0
    private var recognitionGeneration = 0
    private var failures = 0
    private var words = SpeechTranscriptBuffer()
    private var recognitionStarted = 0.0
    private var retryAt = 0.0
    private var recognitionDeadline: Double?
    private let finalizationGrace = 0.75
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var task: SFSpeechRecognitionTask?
    private let engine = AVAudioEngine()
    private let relay = SpeechRequestRelay()
    private var sink: VoiceAudioSink?
    private var timer: Timer?
    private var interruption: NSObjectProtocol?
    private var deliverSegments: (([VoiceSegment]) -> Void)?
    private var deliverTranscript: ((String) -> Void)?
    private var deliverCaptureError: ((String) -> Void)?

    func requestMicrophoneAuthorization() async -> Bool {
        authorized = await AVAudioApplication.requestRecordPermission()
        return authorized
    }

    func requestAuthorization() async -> Bool {
        let status = await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0) }
        }
        speechAuthorized = status == .authorized
        authorized = await AVAudioApplication.requestRecordPermission()
        return authorized // Speech failure must not prevent keeping the original.
    }

    func start(sink: VoiceAudioSink, onSegments: @escaping ([VoiceSegment]) -> Void,
               onTranscript: @escaping (String) -> Void, liveTranscription: Bool = true, onCaptureError: ((String) -> Void)? = nil) throws {
        stop()
        self.sink = sink
        self.liveTranscription = liveTranscription; audioCaptureFailed = false
        deliverSegments = onSegments; deliverTranscript = onTranscript; deliverCaptureError = onCaptureError
        transcript = ""; words = SpeechTranscriptBuffer(); failures = 0; lastError = nil; isFinishing = false
        recordedSeconds = 0; inputLevel = 0; liveTextAvailable = false
        transcriptNeedsReview = false; retryAt = 0; relay.reset()
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.allowBluetooth, .defaultToSpeaker])
        try session.setActive(true, options: .notifyOthersOnDeactivation)
        microphoneName = session.currentRoute.inputs.first?.portName ?? "Microphone"
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, (1...2).contains(format.channelCount) else {
            stop()
            throw NSError(domain: "AliciaSpeech", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "The microphone format is unavailable."])
        }
        let relay = relay
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            sink.append(buffer)
            relay.append(buffer)
        }
        hasTap = true
        engine.prepare()
        do { try engine.start() } catch { stop(); throw error }
        isRecording = true
        startRecognition()
        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.drainAudio() }
        }
        interruption = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
                guard (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt) == AVAudioSession.InterruptionType.began.rawValue else { return }
                Task { @MainActor in
                    self?.lastError = "Recording paused by an interruption. The captured audio is kept."
                    self?.stop()
                }
            }
    }

    private func startRecognition() {
        guard isRecording, liveTranscription else { return }
        guard speechAuthorized, let recognizer, recognizer.isAvailable, recognizer.supportsOnDeviceRecognition else {
            liveTextAvailable = false; transcriptNeedsReview = true
            relay.set(nil)
            retryAt = ProcessInfo.processInfo.systemUptime + 30
            lastError = "Audio is recording. Live text is unavailable; the transcript may be incomplete."
            return
        }
        liveTextAvailable = true
        recognitionStarted = ProcessInfo.processInfo.systemUptime
        recognitionGeneration += 1
        let stamp = generation, recognitionStamp = recognitionGeneration
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        relay.set(request)
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self, self.generation == stamp, self.recognitionGeneration == recognitionStamp,
                      self.isRecording else { return }
                if let result {
                    if !result.bestTranscription.segments.isEmpty, self.failures > 0 {
                        self.failures = 0
                        self.lastError = "Live text resumed. Check the transcript for words missed during reconnection."
                    }
                    self.words.receive(result.bestTranscription.segments.map {
                        SpeechTranscriptBuffer.Word(text: $0.substring, start: $0.timestamp, duration: $0.duration)
                    })
                    self.transcript = self.words.text
                    self.transcriptNeedsReview = self.transcriptNeedsReview || self.words.needsReview
                }
                if error != nil || (result?.isFinal ?? false) {
                    self.failures = error == nil ? 0 : self.failures + 1
                    if error != nil {
                        self.transcriptNeedsReview = true
                        self.lastError = self.isFinishing ? "Live text ended early. Check the words before sending."
                            : "Audio is recording. Live text is reconnecting; check the words before sending."
                    }
                    self.finishRecognition(preserveBufferedAudio: true)
                    self.retryAt = ProcessInfo.processInfo.systemUptime + (error == nil ? 0 : min(30, pow(2, Double(min(self.failures, 5)))))
                    if error == nil, !self.isFinishing { self.startRecognition() }
                }
            }
        }
    }

    private func finishRecognition(preserveBufferedAudio: Bool = false) {
        recognitionGeneration += 1
        words.finishRequest(); transcript = words.text
        relay.set(nil, bufferWhileUnavailable: preserveBufferedAudio); task?.cancel(); task = nil
        liveTextAvailable = false
        recognitionDeadline = nil
    }

    private func beginRecognitionFinalization(now: Double) {
        guard task != nil, recognitionDeadline == nil else { return }
        recognitionDeadline = now + finalizationGrace
        liveTextAvailable = false
        // Keep this request's generation alive so its final callback can update
        // the retained words. The raw sink and bounded PCM queue keep receiving.
        relay.set(nil, bufferWhileUnavailable: true)
    }

    private func drainAudio() {
        // Invalidating a Timer does not cancel a MainActor Task it already queued.
        guard !isFinishing, let sink else { return }
        let metrics = relay.metrics()
        recordedSeconds = metrics.seconds; inputLevel = metrics.level
        if metrics.dropped, !transcriptNeedsReview {
            transcriptNeedsReview = true
            lastError = "Live text may have missed words during reconnection. The original audio is still recording."
        }
        let now = ProcessInfo.processInfo.systemUptime
        if isRecording && !engine.isRunning {
            lastError = "Recording paused because the microphone route changed. Captured audio is kept; tap to resume."
            stop()
            return
        }
        if isRecording, let deadline = recognitionDeadline, now >= deadline {
            transcriptNeedsReview = true
            lastError = "Live text did not finish a passage. Review the original audio before sending."
            finishRecognition(preserveBufferedAudio: true); retryAt = now
        } else if isRecording, task != nil, now - recognitionStarted >= 40 {
            beginRecognitionFinalization(now: now)
        }
        if isRecording, task == nil, now >= retryAt { startRecognition() }
        let result = sink.drain()
        if !result.segments.isEmpty { deliverSegments?(result.segments) }
        if result.error != nil {
            audioCaptureFailed = true
            lastError = "Recording stopped because the audio file could not be written. Earlier audio is kept."
            stop()
        }
    }

    func finishAndStop() async {
        guard isRecording, !isFinishing else { return }
        if !liveTranscription { stop(); return }
        let stamp = generation
        isFinishing = true
        timer?.invalidate(); timer = nil
        engine.stop()
        if hasTap { engine.inputNode.removeTap(onBus: 0); hasTap = false }
        relay.set(nil, bufferWhileUnavailable: true)
        guard await awaitFinalRecognition(stamp: stamp) else { return }
        // Finish can be tapped during rollover or a retry. Those queued samples
        // belong to a final request, even though the microphone has now stopped.
        if relay.hasBufferedAudio {
            startRecognition()
            relay.set(nil, bufferWhileUnavailable: true)
            guard await awaitFinalRecognition(stamp: stamp) else { return }
        }
        stop()
    }

    private func awaitFinalRecognition(stamp: Int) async -> Bool {
        if task != nil {
            do { try await Task.sleep(for: .seconds(finalizationGrace)) }
            catch { if generation == stamp { stop() }; return false }
        }
        guard generation == stamp else { return false }
        if task != nil {
            transcriptNeedsReview = true
            lastError = "Live text did not finish. Review the original recording for the last words."
            finishRecognition(preserveBufferedAudio: true)
        }
        return true
    }

    func stop() {
        generation += 1
        timer?.invalidate(); timer = nil
        if let interruption { NotificationCenter.default.removeObserver(interruption); self.interruption = nil }
        let wasActive = hasTap || isRecording || engine.isRunning
        engine.stop()
        if hasTap { engine.inputNode.removeTap(onBus: 0); hasTap = false }
        let unfinishedText = task != nil || relay.hasBufferedAudio
        finishRecognition()
        let metrics = relay.metrics()
        recordedSeconds = metrics.seconds; inputLevel = 0
        transcriptNeedsReview = transcriptNeedsReview || unfinishedText || metrics.dropped
        if transcriptNeedsReview, lastError == nil || lastError?.hasPrefix("Audio is recording.") == true
            || lastError?.hasPrefix("Live text resumed.") == true
            || lastError?.contains("original audio is still recording") == true {
            lastError = "Live text may be incomplete. Review the original recording before sending."
        }
        if let sink {
            let result = sink.drain(close: true)
            if !result.segments.isEmpty { deliverSegments?(result.segments) }
            if result.error != nil { audioCaptureFailed = true; lastError = "Some audio could not be finalized. Earlier files are kept." }
        }
        if audioCaptureFailed { deliverCaptureError?(lastError ?? "Some audio could not be written.") }
        if wasActive, !transcript.isEmpty { deliverTranscript?(transcript) }
        sink = nil; deliverSegments = nil; deliverTranscript = nil; deliverCaptureError = nil
        isRecording = false
        isFinishing = false
        if wasActive { try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation) }
    }
}
