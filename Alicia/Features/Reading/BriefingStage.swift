import SwiftUI
import UIKit

/// The morning briefing as a room (Hector, 2026-10-17): "the phone should not
/// lock … a full screen experience in where I can see the particles dancing of
/// Alicia as she's narrating it. Then I don't need to have the text readout
/// anymore."
///
/// Composed exactly like `ListeningStage`: backdrop, time-of-day tint, her one
/// field full-bleed, grain. Here the field breathes with *her* voice: the
/// measured word cues of the piece being heard (`BriefingPlanner.voiceLevel`)
/// feed the same voice-reactive state the walk uses for his. There is no text.
/// The steering row and the end check are the same `BriefingSteeringPanel` the
/// reading bar carries, so the study's controls don't change with the surface.
/// The screen stays awake while this is open and the app is active; the prior
/// setting is restored when it closes or the app leaves the foreground.
/// Closing it leaves the briefing playing in the reading bar, whose title opens
/// it again.
struct BriefingStage: View {
    @Environment(AppStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss
    @State private var previousIdleTimerDisabled: Bool?
    /// Whether this room is holding the screen awake right now (the idle
    /// timer itself isn't observable, so the room keeps its own word).
    @State private var holdingAwake = false
#if DEBUG
    @State private var shownLevel = 0.0
#endif

    private var reader: SpeechReader { store.reader }

    /// Still this briefing: anything else being read, or nothing, closes the room.
    private var isBriefing: Bool { (reader.current?.stableID ?? "").hasPrefix("morning:") }

    private var clock: String {
        let left = max(0, reader.duration - reader.elapsed)
        return reader.elapsed.asClock + "  ·  −" + left.asClock
    }

    var body: some View {
        ZStack {
            Theme.backdrop.ignoresSafeArea()
            Theme.timeTint.ignoresSafeArea()
            if store.presenceField.enabled || LivePresenceClient.shared.enabled {
                PresenceLayer(isActive: scenePhase == .active, opacity: 0.72)
            } else {
                GeometryReader { geo in
                    AliciaPresence(voice: .forSurface("us"),
                                   state: reader.isSpeaking ? .listening : .resting,
                                   attention: reader.isSpeaking ? 0.8 : 0.42,
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
                Spacer(minLength: 0)
                    .overlay {
                        // She is the page; this names it for VoiceOver.
                        Color.clear
                            .accessibilityElement()
                            .accessibilityLabel(reader.isSpeaking ? "Alicia is reading the briefing" : "The briefing is paused")
                            .accessibilityIdentifier("briefingStage.presence")
                    }
                VStack(alignment: .leading, spacing: 14) {
                    BriefingSteeringPanel()
                    transport
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 28)
            }
        }
        .foregroundStyle(Theme.ink)
        .fontDesign(.serif)
        .onAppear { keepScreenAwake() }
        .onDisappear {
            store.presenceField.setListening(false)
            restoreScreenSleep()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { keepScreenAwake() } else { restoreScreenSleep() }
        }
        .onChange(of: isBriefing) { _, still in if !still { dismiss() } }
        // Her breath follows her words: about fifteen times a second while the
        // room is in front of him, never in the background.
        .task(id: scenePhase) {
            guard scenePhase == .active else { store.presenceField.setListening(false); return }
            while !Task.isCancelled {
                let speaking = reader.isSpeaking
                let level = BriefingPlanner.voiceLevel(reader.narrationChunks, at: reader.currentPosition(),
                                                       speaking: speaking, clock: Date().timeIntervalSinceReferenceDate)
                store.presenceField.setListening(speaking)
                store.presenceField.voiceLevel = level
#if DEBUG
                shownLevel = level
#endif
                try? await Task.sleep(for: .milliseconds(66))
            }
        }
    }

    private var head: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                InkKicker(text: "Morning briefing").lineLimit(1)
                Text((reader.current?.title.strippedEmojis).flatMap { $0.isEmpty ? nil : $0 } ?? "This morning")
                    .font(.system(size: 19, design: .serif)).italic()
                    .foregroundStyle(Theme.inkSoft)
                    .lineLimit(2)
                    .accessibilityIdentifier("briefingStage.title")
            }
            Spacer()
            // Closing the room leaves her reading in the bar below.
            InkCloseButton(identifier: "briefingStage.close")
        }
        .padding(.horizontal, 24).padding(.top, 18)
#if DEBUG
        .overlay(alignment: .topLeading) {
            // Test-only: what drives her breath, and whether the screen is held awake.
            if ProcessInfo.processInfo.arguments.contains("--steer-live-audio")
                || ProcessInfo.processInfo.arguments.contains("--briefing-stage-preview") {
                HStack(spacing: 8) {
                    Text(String(format: "%.2f", shownLevel)).accessibilityIdentifier("briefingStage.debug.level")
                    Text(holdingAwake && UIApplication.shared.isIdleTimerDisabled ? "awake" : "may sleep")
                        .accessibilityIdentifier("briefingStage.debug.awake")
                }
                .font(.system(size: 8, design: .monospaced)).foregroundStyle(Theme.inkSoft)
                .padding(.leading, 24).offset(y: 2)
            }
        }
#endif
    }

    private var transport: some View {
        HStack(spacing: 16) {
            Button { reader.toggle() } label: {
                InkPlayPause(playing: reader.isSpeaking, size: 30, color: Theme.ink, seed: 19, ringed: true)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(reader.isSpeaking ? "Pause the briefing" : "Play the briefing")
            .accessibilityIdentifier("briefingStage.play")
            Text(clock)
                .font(.system(size: 12, design: .monospaced)).monospacedDigit()
                .foregroundStyle(Theme.inkSoft)
                .accessibilityIdentifier("briefingStage.clock")
            Spacer(minLength: 0)
        }
    }

    private func keepScreenAwake() {
        guard scenePhase == .active else { return }
        if previousIdleTimerDisabled == nil {
            previousIdleTimerDisabled = UIApplication.shared.isIdleTimerDisabled
        }
        UIApplication.shared.isIdleTimerDisabled = true
        holdingAwake = true
    }

    private func restoreScreenSleep() {
        holdingAwake = false
        guard let previous = previousIdleTimerDisabled else { return }
        UIApplication.shared.isIdleTimerDisabled = previous
        previousIdleTimerDisabled = nil
    }
}
