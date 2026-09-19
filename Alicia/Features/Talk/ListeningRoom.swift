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
    /// When set, the transcript becomes an editable private-review field bound to
    /// these words — so on-device mistakes can be corrected, or typed when live
    /// recognition was unavailable, before sending. The mic is not restarted.
    var editableWords: Binding<String>? = nil
    /// Visible character budget for the editable review (no silent truncation).
    var characterLimit: Int? = nil
    var close: () -> Void
    @ViewBuilder var controls: () -> Controls

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
            GeometryReader { geo in
                AliciaPresence(voice: voice,
                               state: isRecording ? .listening : isStarting ? .thinking : .resting,
                               attention: attention,
                               isActive: scenePhase == .active)
                    .frame(width: geo.size.width * 1.9, height: geo.size.height * 1.9)
                    .position(x: geo.size.width * 0.5, y: geo.size.height * 0.46)
                    // Denser than a section's 0.30: here she IS the subject,
                    // and his words are the only thing above her.
                    .opacity(0.42)
            }
            .ignoresSafeArea()
            .accessibilityHidden(true)
            PaperGrain().ignoresSafeArea()
            VStack(alignment: .leading, spacing: 0) {
                head
                transcript
                Text(note)
                    .font(.caption).foregroundStyle(Theme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 24).padding(.bottom, 12)
                controls()
                    .padding(.horizontal, 24)
                    .padding(.bottom, 28)
            }
        }
        .foregroundStyle(Theme.ink)
        .fontDesign(.serif)
    }

    private var head: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text(kicker)
                    .font(.system(size: 9, design: .monospaced)).tracking(1.2)
                    .foregroundStyle(Theme.inkSoft)
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
            Button(action: close) {
                Text("CLOSE")
                    .font(.system(size: 10, design: .monospaced)).tracking(1.2)
                    .foregroundStyle(Theme.inkSoft)
                    .frame(minWidth: 56, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("listening.close")
        }
        .padding(.horizontal, 24).padding(.top, 18)
    }

    /// His own words, as large as they can be and still hold a paragraph, and
    /// pinned to the bottom so the newest line is where his eye already is. In
    /// the private review it becomes an editor with the same visual language.
    @ViewBuilder private var transcript: some View {
        if let editable = editableWords {
            reviewEditor(editable)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Spacer(minLength: 0)
                        Text(words.isEmpty ? placeholder : words)
                            .font(.system(size: words.count > 420 ? 24 : words.count > 160 ? 30 : 38,
                                          design: .serif))
                            .foregroundStyle(words.isEmpty ? Theme.inkSoft : Theme.ink)
                            .lineSpacing(4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .animation(.easeOut(duration: 0.18), value: words.count > 160)
                            .id("words")
                            .accessibilityIdentifier("listening.transcript")
                    }
                    .frame(maxWidth: .infinity, minHeight: 320, alignment: .bottomLeading)
                    .padding(.horizontal, 24).padding(.vertical, 18)
                }
                .onChange(of: words) { _, _ in
                    withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("words", anchor: .bottom) }
                }
            }
        }
    }

    /// The editable private review: same serif field, correctable on-device, with
    /// a visible character count against the private Body limit. No mic restart.
    private func reviewEditor(_ text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            TextEditor(text: text)
                .font(.system(size: text.wrappedValue.count > 420 ? 24 : text.wrappedValue.count > 160 ? 30 : 38,
                              design: .serif))
                .foregroundStyle(Theme.ink)
                .lineSpacing(4)
                .scrollContentBackground(.hidden)
                .frame(maxWidth: .infinity, minHeight: 300, alignment: .topLeading)
                .accessibilityIdentifier("listening.reviewEditor")
                .accessibilityLabel("Your private reflection")
            if let limit = characterLimit {
                Text("\(text.wrappedValue.count) / \(limit)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(text.wrappedValue.count > limit ? Theme.rose : Theme.inkSoft)
                    .accessibilityIdentifier("listening.reviewCount")
            }
        }
        .padding(.horizontal, 24).padding(.vertical, 18)
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
