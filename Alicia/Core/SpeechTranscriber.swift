import Foundation
import Speech
import AVFoundation

/// A small lock keeps the realtime tap independent of recognition restarts.
private final class SpeechRequestRelay: @unchecked Sendable {
    private let lock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var seconds = 0.0
    private var level = 0.0
    func reset() {
        lock.lock(); defer { lock.unlock() }
        seconds = 0; level = 0
    }
    func metrics() -> (seconds: Double, level: Double) {
        lock.lock(); defer { lock.unlock() }
        return (seconds, level)
    }
    func set(_ next: SFSpeechAudioBufferRecognitionRequest?) {
        lock.lock(); defer { lock.unlock() }
        request?.endAudio(); request = next
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
        request?.append(buffer)
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
    private var hasTap = false
    private var generation = 0
    private var recognitionGeneration = 0
    private var failures = 0
    private var words = SpeechTranscriptBuffer()
    private var recognitionStarted = 0.0
    private var retryAt = 0.0
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var task: SFSpeechRecognitionTask?
    private let engine = AVAudioEngine()
    private let relay = SpeechRequestRelay()
    private var sink: VoiceAudioSink?
    private var timer: Timer?
    private var interruption: NSObjectProtocol?
    private var deliverSegments: (([VoiceSegment]) -> Void)?
    private var deliverTranscript: ((String) -> Void)?

    func requestAuthorization() async -> Bool {
        let status = await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0) }
        }
        speechAuthorized = status == .authorized
        authorized = await AVAudioApplication.requestRecordPermission()
        return authorized // Speech failure must not prevent keeping the original.
    }

    func start(sink: VoiceAudioSink, onSegments: @escaping ([VoiceSegment]) -> Void,
               onTranscript: @escaping (String) -> Void) throws {
        stop()
        self.sink = sink
        deliverSegments = onSegments; deliverTranscript = onTranscript
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
        guard isRecording else { return }
        guard speechAuthorized, let recognizer, recognizer.isAvailable, recognizer.supportsOnDeviceRecognition else {
            liveTextAvailable = false; transcriptNeedsReview = true
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
                        self.lastError = "Audio is recording. Live text is reconnecting; check the words before sending."
                    }
                    self.finishRecognition()
                    self.retryAt = ProcessInfo.processInfo.systemUptime + (error == nil ? 0.2 : min(30, pow(2, Double(min(self.failures, 5)))))
                }
            }
        }
    }

    private func finishRecognition() {
        recognitionGeneration += 1
        words.finishRequest(); transcript = words.text
        relay.set(nil); task?.cancel(); task = nil
        liveTextAvailable = false
    }

    private func drainAudio() {
        guard let sink else { return }
        let metrics = relay.metrics()
        recordedSeconds = metrics.seconds; inputLevel = metrics.level
        let now = ProcessInfo.processInfo.systemUptime
        if isRecording, task != nil, now - recognitionStarted >= 40 {
            // Bound each recognition request; its saved words survive the next.
            finishRecognition(); retryAt = now + 0.2
        }
        if isRecording, task == nil, now >= retryAt { startRecognition() }
        if isRecording && !engine.isRunning {
            lastError = "Recording paused because the microphone route changed. Captured audio is kept; tap to resume."
            stop()
            return
        }
        let result = sink.drain()
        if !result.segments.isEmpty { deliverSegments?(result.segments) }
        if result.error != nil {
            lastError = "Recording stopped because the audio file could not be written. Earlier audio is kept."
            stop()
        }
    }

    func finishAndStop() async {
        guard isRecording, !isFinishing else { return }
        let stamp = generation
        isFinishing = true
        timer?.invalidate(); timer = nil
        engine.stop()
        if hasTap { engine.inputNode.removeTap(onBus: 0); hasTap = false }
        relay.set(nil) // Let Speech return its final hypothesis for the last buffers.
        if task != nil { try? await Task.sleep(for: .milliseconds(750)) }
        guard generation == stamp else { return } // A close/interruption owns its stop.
        stop()
    }

    func stop() {
        generation += 1
        timer?.invalidate(); timer = nil
        if let interruption { NotificationCenter.default.removeObserver(interruption); self.interruption = nil }
        let wasActive = hasTap || isRecording || engine.isRunning
        engine.stop()
        if hasTap { engine.inputNode.removeTap(onBus: 0); hasTap = false }
        finishRecognition()
        if let sink {
            let result = sink.drain(close: true)
            if !result.segments.isEmpty { deliverSegments?(result.segments) }
            if result.error != nil { lastError = "Some audio could not be finalized. Earlier files are kept." }
        }
        if wasActive, !transcript.isEmpty { deliverTranscript?(transcript) }
        sink = nil; deliverSegments = nil; deliverTranscript = nil
        isRecording = false
        isFinishing = false
        if wasActive { try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation) }
    }
}
