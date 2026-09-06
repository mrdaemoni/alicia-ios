import Foundation
import Speech
import AVFoundation

/// A small lock keeps the realtime tap independent of recognition restarts.
private final class SpeechRequestRelay: @unchecked Sendable {
    private let lock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    func set(_ next: SFSpeechAudioBufferRecognitionRequest?) {
        lock.lock(); defer { lock.unlock() }
        request?.endAudio(); request = next
    }
    func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock(); defer { lock.unlock() }
        request?.append(buffer)
    }
}

/// Original audio is captured independently of on-device live transcription.
@MainActor @Observable
final class SpeechTranscriber {
    var isRecording = false
    var transcript = ""
    var authorized = false
    var lastError: String?
    private var speechAuthorized = false
    private var hasTap = false
    private var generation = 0
    private var recognitionGeneration = 0
    private var failures = 0
    private var prefix = ""
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
        transcript = ""; prefix = ""; failures = 0; lastError = nil
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)
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
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
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
        guard speechAuthorized, let recognizer, recognizer.isAvailable, recognizer.supportsOnDeviceRecognition,
              failures < 3 else {
            lastError = "Original audio is recording. Live transcription is unavailable; you can replay and correct it later."
            return
        }
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
                    let words = result.bestTranscription.formattedString
                    self.transcript = self.prefix + (self.prefix.isEmpty || words.isEmpty ? "" : "\n\n") + words
                }
                if error != nil || (result?.isFinal ?? false) {
                    self.recognitionGeneration += 1 // ignore late callbacks from this attempt
                    self.prefix = self.transcript
                    self.relay.set(nil)
                    self.task?.cancel(); self.task = nil
                    self.failures = error == nil ? 0 : self.failures + 1
                    // The engine and raw sink KEEP RUNNING during this restart.
                    try? await Task.sleep(for: .milliseconds(150))
                    guard self.isRecording, self.generation == stamp else { return }
                    self.startRecognition()
                }
            }
        }
    }

    private func drainAudio() {
        guard let sink else { return }
        let result = sink.drain()
        if !result.segments.isEmpty { deliverSegments?(result.segments) }
        if result.error != nil {
            lastError = "Recording stopped because the audio file could not be written. Earlier audio is kept."
            stop()
        }
    }

    func stop() {
        generation += 1
        timer?.invalidate(); timer = nil
        if let interruption { NotificationCenter.default.removeObserver(interruption); self.interruption = nil }
        let wasActive = hasTap || isRecording || engine.isRunning
        engine.stop()
        if hasTap { engine.inputNode.removeTap(onBus: 0); hasTap = false }
        relay.set(nil)
        task?.cancel(); task = nil
        if let sink {
            let result = sink.drain(close: true)
            if !result.segments.isEmpty { deliverSegments?(result.segments) }
            if result.error != nil { lastError = "Some audio could not be finalized. Earlier files are kept." }
        }
        if wasActive, !transcript.isEmpty { deliverTranscript?(transcript) }
        sink = nil; deliverSegments = nil; deliverTranscript = nil
        isRecording = false
        if wasActive { try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation) }
    }
}
