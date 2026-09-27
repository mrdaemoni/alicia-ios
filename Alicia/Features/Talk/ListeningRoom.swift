import SwiftUI

/// The room a walk happens in.
///
/// This began as a short-remark microphone on the composer band. Hector
/// retired that on 2026-09-18 — *"let's remove the voice input … next to it,
/// let's have a button that says walk"* — so there is now exactly one spoken
/// path and `WalkReflectionView` owns its lifecycle. What survives is the
/// room: her particle body full-bleed behind his own words, set large enough
/// to read at arm's length while he is still speaking.

/// The room itself: her body behind, his words in front, the controls at the
/// bottom. Split out so `WalkReflectionView` presents an episode reflection in
/// exactly the same space rather than a second, smaller idea of listening.
struct ListeningStage<Controls: View>: View {
    var voice: AliciaPresence.Voice
    var isRecording: Bool
    var isStarting: Bool
    var level: Double
    var kicker: String
    var seconds: Double
    var words: String
    var placeholder: String
    var note: String
    /// A failure (the microphone, the recognizer) reads in seal red.
    var noteIsError = false
    var close: () -> Void
    @ViewBuilder var controls: () -> Controls

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AppStore.self) private var store

    /// Loud speech gathers her; silence lets her rest. Clamped because a NaN
    /// from the audio tap must never reach the drawing.
    private var attention: Double {
        guard isRecording else { return 0.42 }
        let clean = level.isFinite ? min(1, max(0, level)) : 0
        return 0.58 + 0.34 * clean
    }

    private var elapsed: String {
        let whole = Int(max(0, seconds))
        return String(format: "%d:%02d", whole / 60, whole % 60)
    }

    var body: some View {
        ZStack {
            // v40: composed exactly like a section's background, not merely
            // "also a presence". Same backdrop, same time-of-day tint, same
            // oversized field pushing the dense core off-canvas, same grain —
            // so opening the microphone reads as her turning toward him in the
            // room he is already in, rather than a different screen that also
            // has particles. Hector asked for that same animation here.
            Theme.backdrop.ignoresSafeArea()
            Theme.timeTint.ignoresSafeArea()
            if store.presenceField.enabled {
                // The same body as every room, turned toward him: opened wide
                // and breathing with his voice while the microphone is on.
                PresenceLayer(isActive: scenePhase == .active, opacity: 0.68)
            } else {
            GeometryReader { geo in
                AliciaPresence(voice: voice,
                               state: isRecording ? .listening : isStarting ? .thinking : .resting,
                               attention: attention,
                               isActive: scenePhase == .active)
                    .frame(width: geo.size.width * 1.9, height: geo.size.height * 1.9)
                    .position(x: geo.size.width * 0.5, y: geo.size.height * 0.46)
                    .opacity(0.42)
            }
            .ignoresSafeArea()
            .accessibilityHidden(true)
            }
            PaperGrain().ignoresSafeArea()
            VStack(alignment: .leading, spacing: 0) {
                head
                question
                Spacer(minLength: 0)
                Text(note)
                    .font(InkType.meta).foregroundStyle(noteIsError ? Theme.rose : Theme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 24).padding(.bottom, 12)
                controls()
                    .padding(.horizontal, 24)
                    .padding(.bottom, 28)
            }
        }
        .foregroundStyle(Theme.ink)
        .fontDesign(.serif)
        .onAppear { store.presenceField.setListening(isRecording) }
        .onChange(of: isRecording) { _, on in store.presenceField.setListening(on) }
        .onChange(of: level) { _, value in store.presenceField.voiceLevel = value }
        .onDisappear { store.presenceField.setListening(false) }
    }

    /// Build 35 on the phone, 2026-09-27: "On the walks, I don't need to see
    /// the text that I'm speaking. I just want to see Alicia listening to me."
    /// His words are still captured and kept (the Mac transcript is the record
    /// he reviews); the room shows only what he is answering, and her.
    private var question: some View {
        Text(placeholder)
            .font(.system(size: 19, design: .serif)).italic()
            .foregroundStyle(Theme.inkSoft)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 24).padding(.top, 14)
            .accessibilityIdentifier("listening.prompt")
            .overlay {
                // She is the page now; this names it for VoiceOver.
                Color.clear
                    .accessibilityElement()
                    .accessibilityLabel(isRecording ? "Alicia is listening" : "Alicia is waiting")
                    .accessibilityIdentifier("listening.presence")
            }
    }

    private var head: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                InkKicker(text: kicker)
                    .lineLimit(1)
                HStack(spacing: 10) {
                    // A drawn mark, not a level meter: it says "on" at a glance
                    // from across the room, which six tiny bars never did.
                    Circle()
                        .fill(isRecording ? Theme.rose : Theme.inkSoft.opacity(0.35))
                        .frame(width: 9, height: 9)
                        .opacity(isRecording && !reduceMotion ? 0.55 + 0.45 * attention : 1)
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: attention)
                    Text(elapsed)
                        .font(.system(size: 15, design: .monospaced)).monospacedDigit()
                        .foregroundStyle(Theme.inkSoft)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(isRecording
                    ? "Microphone on, \(Int(seconds)) seconds recorded"
                    : "Microphone paused, \(Int(seconds)) seconds recorded")
                .accessibilityIdentifier("walk.microphoneState")
            }
            Spacer()
            // The same CLOSE every sheet ends with. It still runs `close`,
            // which pauses and seals the walk — not a plain dismiss.
            InkCloseButton(action: close)
                .accessibilityIdentifier("listening.close")
        }
        .padding(.horizontal, 24).padding(.top, 18)
    }

}

extension AliciaPresence.Voice {
    /// Which of her six bodies belongs to a surface. The same mapping the tabs
    /// use, so the particles behind a reflection are continuous with the page
    /// he just left rather than a generic animation.
    static func forSurface(_ section: String) -> AliciaPresence.Voice {
        switch section {
        case "mind": .ariadne
        case "body", "dialogue": .psyche
        case "alicia": .beatrice
        case "studio": .muse
        default: .musubi
        }
    }
}
