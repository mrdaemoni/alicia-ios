#if DEBUG
import SwiftUI

/// The briefing room twice, side by side, for choosing (CL-20261018-organic-field).
///
/// Left is the field as it ships in TestFlight 49: the walk's listening pose,
/// her level polled every 66 ms from `BriefingPlanner.voiceLevel`, 15 frames a
/// second. Right is the organic candidate with its six toggles. Both hear the
/// same voice: her real speaking rhythm (`OrganicVoiceFixture`), on one clock.
/// Nothing here reaches a product surface.
struct OrganicRoomCompare: View {
    @Environment(\.dismiss) private var dismiss
    @State private var shipped = PresenceField()
    @State private var organic = PresenceField()
    @State private var style = OrganicStyle.all
    @State private var started = Date.now
    @State private var reduceMotion = ProcessInfo.processInfo.arguments.contains("--presence-reduce-motion")
    @State private var auditReport: String?
    private let cues = OrganicVoiceFixture.cues()
    private let showsControls = !ProcessInfo.processInfo.arguments.contains("--organic-compare-clean")

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                pane("AS SHIPPED", field: shipped, style: nil)
                pane("ORGANIC", field: organic, style: style)
            }
            .padding(.horizontal, 8)
            if showsControls { controls }
        }
        .padding(.vertical, 8)
        .background(Theme.paper.ignoresSafeArea())
        .onAppear(perform: start)
        // The shipped room's driver, reproduced: a 66 ms poll of the per-word level.
        .task {
            let chunk = SpeechChunk(url: URL(string: "https://fixture.invalid/voice.m4a")!, duration: 1e6,
                cues: cues.map { NarrationCue(start: $0.start, end: $0.end, text: "", start_char: 0, end_char: 0) })
            while !Task.isCancelled {
                let t = Date.now.timeIntervalSince(started)
                shipped.voiceLevel = BriefingPlanner.voiceLevel([chunk], at: (0, t), speaking: true,
                                                                clock: Date().timeIntervalSinceReferenceDate)
                try? await Task.sleep(for: .milliseconds(66))
            }
        }
    }

    private func start() {
        started = .now
        shipped.screen = .zero
        shipped.setListening(true)                 // what the room does today
        organic.setSpeaking(true)                  // E: her own pose
        organic.setVoice(cues: cues)
        organic.syncPlayback(seconds: 0, running: true, now: started)
        if ProcessInfo.processInfo.arguments.contains("--presence-audit") { auditReport = Self.audit() }
    }

    private func pane(_ label: String, field: PresenceField, style: OrganicStyle?) -> some View {
        GeometryReader { geo in
            ZStack {
                Theme.backdrop
                Theme.timeTint
                // Placed as PresenceLayer places her in the room: 1.45× the screen, centred.
                AliciaPresence(isActive: true, previewsReduceMotion: reduceMotion, field: field, organic: style)
                    .frame(width: geo.size.width * 1.45, height: geo.size.height * 1.45)
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)
                    .opacity(0.72)
                PaperGrain()
                VStack {
                    Text(label).font(.system(size: 9, design: .monospaced).weight(.semibold)).tracking(1.4)
                        .foregroundStyle(Theme.inkSoft).padding(.top, 8)
                    Spacer()
                }
            }
            .clipped()
        }
        .aspectRatio(402.0 / 874.0, contentMode: .fit)
        .accessibilityIdentifier("organic.pane." + label.lowercased())
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                toggle("A TIME", \.smoothTime)
                toggle("B BREATH", \.twoTimescales)
                toggle("C LIFE", \.particleLife)
            }
            HStack(spacing: 10) {
                toggle("D DOTS", \.organicDots)
                toggle("E POSE", \.speakingPose)
                toggle("F FRAME", \.roomFraming)
            }
            HStack(spacing: 14) {
                button(style.framesPerSecond == 60 ? "60 FPS" : "30 FPS") {
                    style.framesPerSecond = style.framesPerSecond == 60 ? 30 : 60
                }
                button("HIGHER") { organic.gesture(higher: true) }
                button("LOWER") { organic.gesture(higher: false) }
                button(organic.speakingSettled ? "RESUME" : "PAUSE") {
                    let pausing = !organic.speakingSettled
                    let t = Date.now.timeIntervalSince(started)
                    organic.setSpeakingSettled(pausing)
                    organic.syncPlayback(seconds: t, running: !pausing)
                }
                button(reduceMotion ? "MOTION" : "STILL") { reduceMotion.toggle() }
                button("AUDIT") { auditReport = Self.audit() }
                button("CLOSE") { dismiss() }
            }
            if let auditReport {
                Text(auditReport).font(.system(size: 9, design: .monospaced)).foregroundStyle(Theme.inkSoft)
                    .accessibilityIdentifier("organic.audit")
            }
        }
        .padding(.horizontal, 16)
    }

    private func toggle(_ label: String, _ key: WritableKeyPath<OrganicStyle, Bool>) -> some View {
        Button { style[keyPath: key].toggle() } label: {
            Text(label).font(.system(size: 10, design: .monospaced).weight(.bold)).tracking(1.2)
                .foregroundStyle(style[keyPath: key] ? Theme.ink : Theme.inkSoft.opacity(0.5))
                .frame(minHeight: 32)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("organic.toggle." + label.split(separator: " ")[0].lowercased())
    }

    private func button(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label).font(.system(size: 10, design: .monospaced).weight(.semibold)).tracking(1.2)
                .foregroundStyle(Theme.ink).frame(minHeight: 32)
        }
        .buttonStyle(.plain)
    }

    /// Every form pair, pose and phrase level at representative phases:
    /// finite, and enough of her visible.
    static func audit() -> String {
        let size = CGSize(width: 402 * 1.45, height: 874 * 1.45)
        var checked = 0, failures = 0, lowest = 1.0
        for primary in PresenceForm.allCases.indices {
            for secondary in PresenceForm.allCases.indices {
                for (speaking, listening) in [(true, false), (false, true), (false, false)] {
                    for phase in [0.0, 1.7, 3.4, 5.1] {
                        for voice in [0.0, 1.0] {
                            var frame = PresenceFrame(primary: primary, secondary: secondary, mix: 0.3, phase: phase,
                                                      energy: 0.56, openness: 0.72, coherence: 0.84,
                                                      focus: CGPoint(x: 0.5, y: 0.42))
                            frame.speaking = speaking; frame.listening = listening
                            frame.word = voice; frame.phraseTrail = Array(repeating: voice, count: 8)
                            frame.gesture = voice == 1 ? 1 : -1
                            let placed = OrganicField.points(frame: frame, size: size, style: .all,
                                                             source: PresenceGeometry.sourcePoint)
                            let first = Double(PresenceForm.allCases[primary].basePoints)
                            let second = Double(PresenceForm.allCases[secondary].basePoints)
                            let blended: Double = (first * 0.7 + second * 0.3) * (0.92 + 0.56 * 0.55)
                            let budget = Double(min(3_000, max(950, Int(blended))))
                            let visible = Double(placed.dots.count) / budget
                            checked += 1
                            lowest = min(lowest, visible)
                            let finite = placed.dots.allSatisfy { $0.point.x.isFinite && $0.point.y.isFinite }
                            if !finite || visible < 0.35 { failures += 1 }
                        }
                    }
                }
            }
        }
        return String(format: "AUDIT %d frames · %d failures · lowest visible %.0f%%", checked, failures, lowest * 100)
    }
}
#endif
