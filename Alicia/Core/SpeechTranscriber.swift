import Foundation
import Speech
import AVFoundation

/// On-device live transcription for the Dialogue composer: tap the mic,
/// speak, and words land in the draft as you talk — in walk mode or
/// regular mode alike (the send path is the same either way).
@MainActor
@Observable
final class SpeechTranscriber {
    var isRecording = false
    var transcript = ""
    var authorized = false
    var lastError: String?
    private var hasTap = false

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private let engine = AVAudioEngine()

    func requestAuthorization() async -> Bool {
        let speech = await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0) }
        }
        let mic = await AVAudioApplication.requestRecordPermission()
        authorized = (speech == .authorized) && mic
        return authorized
    }

    func start() throws {
        stop()
        transcript = ""
        lastError = nil
        guard let recognizer, recognizer.isAvailable, recognizer.supportsOnDeviceRecognition else {
            throw NSError(domain: "AliciaSpeech", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "On-device speech is unavailable."])
        }
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        self.request = request

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }
        hasTap = true
        engine.prepare()
        do { try engine.start() }
        catch { stopEngineOnly(); throw error }
        isRecording = true

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }
                if let result {
                    self.transcript = result.bestTranscription.formattedString
                }
                self.lastError = error?.localizedDescription
                if error != nil || (result?.isFinal ?? false) {
                    self.stopEngineOnly()
                }
            }
        }
    }

    func stop() {
        stopEngineOnly()
        task?.cancel()
        task = nil
    }

    private func stopEngineOnly() {
        guard hasTap || isRecording || engine.isRunning else { return }
        engine.stop()
        if hasTap { engine.inputNode.removeTap(onBus: 0); hasTap = false }
        request?.endAudio()
        request = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
