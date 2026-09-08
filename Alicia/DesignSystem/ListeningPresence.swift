import SwiftUI

/// Reuses the home's existing Musubi motion, driven by the microphone engine.
struct ListeningPresence: View {
    let isRecording: Bool
    let isStarting: Bool
    var seconds: Double = 0
    var level: Double = 0
    var microphoneName: String = "Microphone"
    var liveTextAvailable: Bool = true
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
            ZStack {
                AliciaPresence(voice: .musubi, state: isRecording ? .listening : .resting,
                    attention: isRecording ? 0.8 : 0.45,
                    isActive: isRecording && scenePhase == .active, previewsReduceMotion: previewReduction)
                    .frame(width: 96, height: 78).opacity(0.65)
                MicrophoneMark().stroke(Theme.ink, style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
                    .frame(width: 21, height: 32)
                    .padding(12).background(Theme.paper.opacity(0.8), in: Circle())
            }.accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(isRecording ? "MICROPHONE ON" : isStarting ? "OPENING MICROPHONE…" : "MICROPHONE PAUSED")
                    .font(.system(size: 10, design: .monospaced).weight(.semibold)).tracking(1.2)
                Text(isRecording ? microphoneName : "Nothing is being recorded.")
                    .font(.callout).foregroundStyle(Theme.inkSoft)
                if isRecording {
                    HStack(spacing: 10) {
                        Text(String(format: "%d:%02d recorded", Int(max(0, seconds)) / 60, Int(max(0, seconds)) % 60))
                            .font(.system(size: 11, design: .monospaced)).monospacedDigit()
                        HStack(alignment: .bottom, spacing: 3) {
                            ForEach(0..<6) { step in
                                RoundedRectangle(cornerRadius: 1)
                                    .fill(Theme.ink.opacity(level > Double(step) / 6 ? 0.8 : 0.12))
                                    .frame(width: 3, height: CGFloat(5 + step * 2))
                            }
                        }.accessibilityLabel("Microphone input level")
                    }
                    Text(liveTextAvailable ? "Audio is being saved on this phone." : "Live text paused. Audio is still recording.")
                        .font(.caption).foregroundStyle(Theme.inkSoft)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("walk.microphoneState")
    }
}

private struct MicrophoneMark: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path(roundedRect: CGRect(x: rect.width * 0.28, y: 0,
            width: rect.width * 0.44, height: rect.height * 0.62), cornerRadius: rect.width * 0.22)
        path.move(to: CGPoint(x: rect.width * 0.08, y: rect.height * 0.38))
        path.addQuadCurve(to: CGPoint(x: rect.width * 0.92, y: rect.height * 0.38),
                         control: CGPoint(x: rect.width * 0.5, y: rect.height * 1.12))
        path.move(to: CGPoint(x: rect.midX, y: rect.height * 0.78))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.move(to: CGPoint(x: rect.width * 0.24, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.width * 0.76, y: rect.maxY))
        return path
    }
}
