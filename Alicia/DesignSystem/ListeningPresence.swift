import SwiftUI

/// Reuses the home's existing Musubi motion, driven by the microphone engine.
struct ListeningPresence: View {
    let isRecording: Bool
    let isStarting: Bool
    var seconds: Double = 0
    var level: Double = 0
    var microphoneName: String = "Microphone"
    var liveTextAvailable: Bool = true
    var transcribesOnMac = false
    var voice: AliciaPresence.Voice = .musubi
    @Environment(\.scenePhase) private var scenePhase

    private var previewReduction: Bool {
#if DEBUG
        return ProcessInfo.processInfo.arguments.contains("--episode-day-preview") && ProcessInfo.processInfo.arguments.contains("--reduce-motion-preview")
#else
        return false
#endif
    }

    var body: some View {
        HStack(spacing: 16) {
            AliciaPresence(voice: voice, state: isRecording ? .listening : isStarting ? .thinking : .resting,
                attention: isRecording ? 0.55 + 0.3 * (level.isFinite ? min(1, max(0, level)) : 0) : 0.45,
                isActive: isRecording && scenePhase == .active, previewsReduceMotion: previewReduction)
                .frame(width: 110, height: 90)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(isRecording ? "MICROPHONE ON" : isStarting ? "OPENING MICROPHONE…" : "MICROPHONE PAUSED")
                    .font(.system(size: 10, design: .monospaced).weight(.semibold)).tracking(1.2)
                Text(isRecording ? microphoneName : "Nothing is being recorded.")
                    .font(.callout).foregroundStyle(Theme.inkSoft)
                if isRecording {
                    HStack(spacing: 10) {
                        Text(String(format: "%d:%02d recorded", Int(max(0, seconds)) / 60, Int(max(0, seconds)) % 60))
                            .font(.system(size: 11, design: .monospaced)).monospacedDigit()
                    }
                    Text(transcribesOnMac ? "Your Mac transcribes after Finish." : liveTextAvailable ? "Private audio and speech recognition stay on this phone." : "Live text paused. Audio is still recording.")
                        .font(.caption).foregroundStyle(Theme.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("walk.microphoneState")
    }
}
