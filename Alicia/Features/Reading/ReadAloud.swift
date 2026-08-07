import SwiftUI

/// A crossed-out mark in her hand — the only way to end a reading outright.
/// v28's lesson about the global player was "then I have to close it": a bar
/// that owns the bottom of the screen has to be dismissible in one tap.
struct InkCross: View {
    var size: CGFloat = 16
    var color: Color = Theme.inkSoft
    var seed: Int = 23

    var body: some View {
        Canvas { ctx, s in
            var rand = InkRand(seed)
            let w = s.width, h = s.height
            let strokes = [
                (CGPoint(x: w * 0.28, y: h * 0.28), CGPoint(x: w * 0.72, y: h * 0.72)),
                (CGPoint(x: w * 0.72, y: h * 0.28), CGPoint(x: w * 0.28, y: h * 0.72)),
            ]
            for (a, b) in strokes {
                let line = InkPen.stroke(from: a, to: b, rand: &rand,
                                         overshoot: 1.25, bow: 0.8,
                                         wobble: 0.4, segments: 6)
                ctx.stroke(line, with: .color(color),
                           style: StrokeStyle(lineWidth: 1.3, lineCap: .round))
            }
        }
        .frame(width: size, height: size)
    }
}

/// Press play on this piece — a word with her underline, never a widget
/// glyph. Shows LISTEN when idle, wave bars + READING when this is the
/// piece she's on, PAUSED when it's this piece but stopped.
struct ListenLine: View {
    @Environment(AppStore.self) private var store
    let item: Readable
    /// The resting word. "LISTEN" everywhere except where a shorter one
    /// reads better in a dense row.
    var label: String = "LISTEN"
    var tint: Color = Theme.accent

    private var isCurrent: Bool { store.reader.current?.id == item.id }
    private var isReading: Bool { isCurrent && store.reader.isSpeaking }

    var body: some View {
        Button {
            store.readAloud(item)
        } label: {
            HStack(spacing: 6) {
                if isReading {
                    InkWaveBars(size: 13, color: tint, seed: item.title.inkSeed)
                }
                VStack(spacing: 2) {
                    Text(isReading ? "READING" : (isCurrent ? "PAUSED" : label))
                        .font(.system(size: 10, design: .monospaced).weight(.bold))
                        .tracking(1.6)
                        .foregroundStyle(tint)
                    InkUnderline(color: tint, seed: item.title.inkSeed,
                                 lineWidth: 1.1)
                        .frame(width: isReading ? 46 : 38, height: 4)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isReading ? "Pause reading" : "Read this to me")
    }
}

/// The reading bar — a hard sibling above the tab bar (never a
/// `safeAreaInset`; that mechanism failed three ways on device), visible
/// only while something is being read.
struct ReadingBar: View {
    @Environment(AppStore.self) private var store

    private var rateLabel: String {
        store.reader.rate == 1.0 ? "1×" :
        store.reader.rate == 1.5 ? "1.5×" : "2×"
    }

    var body: some View {
        let reader = store.reader
        if let item = reader.current {
            VStack(spacing: 7) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title.strippedEmojis.isEmpty
                             ? "A reading" : item.title.strippedEmojis)
                            .font(.system(size: 13, design: .serif).weight(.semibold))
                            .lineLimit(1)
                            .foregroundStyle(Theme.ink)
                        // Never dress the stand-in up as her — the bar says
                        // plainly which voice is in your ears.
                        Text(reader.voice == .her ? "HER VOICE"
                             : (reader.herVoiceRendering ? "READING ALOUD · SHE'S CATCHING UP"
                                                         : "READING ALOUD"))
                            .font(.system(size: 9, design: .monospaced).weight(.semibold))
                            .tracking(1.5)
                            .foregroundStyle(Theme.inkSoft)
                    }
                    Spacer(minLength: 4)
                    Button { reader.cycleRate() } label: {
                        Text(rateLabel)
                            .font(.caption2.weight(.bold).monospacedDigit())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Theme.card, in: Capsule())
                            .overlay(Capsule().strokeBorder(Theme.stroke))
                    }
                    .buttonStyle(.plain)
                    Button { reader.skip(-15) } label: {
                        InkSkip(forward: false, size: 24, seed: 5)
                    }
                    .buttonStyle(.plain)
                    Button { reader.toggle() } label: {
                        InkPlayPause(playing: reader.isSpeaking, size: 28, seed: 19)
                    }
                    .buttonStyle(.plain)
                    Button { reader.skip(15) } label: {
                        InkSkip(forward: true, size: 24, seed: 11)
                    }
                    .buttonStyle(.plain)
                    Button { reader.stop() } label: {
                        InkCross(size: 17)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Stop reading")
                }

                HStack(spacing: 8) {
                    Text(reader.elapsed.asClock)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(Theme.inkSoft)
                    Slider(
                        value: Binding(get: { reader.progress },
                                       set: { reader.scrub(to: $0) }),
                        in: 0...1,
                        onEditingChanged: { editing in
                            if !editing { reader.commitScrub() }
                        })
                        .tint(Theme.accent)
                    Text("−" + max(0, reader.duration - reader.elapsed).asClock)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(Theme.inkSoft)
                }

                // Her render landed while the stand-in was reading. Offered,
                // never forced: swapping narrator mid-sentence unasked is
                // more jarring than finishing in the voice you started with.
                if reader.herVoiceReady {
                    Button { reader.switchToHerVoice() } label: {
                        HStack(spacing: 6) {
                            InkSpark(size: 10, color: Theme.accent, seed: 7)
                            Text("HER VOICE IS READY — SWITCH")
                                .font(.system(size: 9, design: .monospaced).weight(.bold))
                                .tracking(1.4)
                                .foregroundStyle(Theme.accent)
                            InkUnderline(color: Theme.accent, seed: 9,
                                         lineWidth: 1.0)
                                .frame(width: 22, height: 4)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .transition(.opacity)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Theme.paper.opacity(0.96),
                        in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Theme.stroke))
            .overlay(HandDrawnBorder())
            .shadow(color: Theme.ink.opacity(0.08), radius: 8, y: 2)
            .padding(.horizontal, 12)
            .padding(.bottom, 4)
            .animation(.easeInOut(duration: 0.2), value: reader.herVoiceReady)
        }
    }
}
