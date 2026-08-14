import SwiftUI

/// A crossed-out mark in her hand — the only way to end a reading outright.
/// v28's lesson about the global player was "then I have to close it": a bar
/// that owns the bottom of the screen has to be dismissible in one tap.
struct InkCross: View {
    var size: CGFloat = 16
    var color: Color = Theme.paper.opacity(0.7)
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
    private var isPreparing: Bool { isCurrent && store.reader.isPreparing }

    /// Her voice takes ~10–15s to start when a piece hasn't been
    /// pre-rendered, so the word has to admit that rather than sit there
    /// looking like a tap that missed.
    private var word: String {
        if isPreparing { return "WARMING UP" }
        if isReading { return "READING" }
        if isCurrent { return "PAUSED" }
        return label
    }

    var body: some View {
        Button {
            store.readAloud(item)
        } label: {
            HStack(spacing: 6) {
                if isReading {
                    InkWaveBars(size: 13, color: tint, seed: item.title.inkSeed)
                } else if isPreparing {
                    InkSpark(size: 11, color: tint, seed: item.title.inkSeed)
                }
                VStack(spacing: 2) {
                    Text(word)
                        .font(.system(size: 10, design: .monospaced).weight(.bold))
                        .tracking(1.6)
                        .foregroundStyle(tint.opacity(isPreparing ? 0.7 : 1))
                    InkUnderline(color: tint, seed: item.title.inkSeed,
                                 lineWidth: 1.1)
                        .frame(width: isCurrent ? 52 : 38, height: 4)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isReading ? "Pause reading" : "Read this to me")
    }
}

/// Hold a synthesis on the home screen so it survives the shelf rotating.
///
/// The same mark and the same server-side store as pinned cards and
/// thinkers, so a pin is still also an interest signal — she records that
/// he's holding this idea (`home_context.pin_item` → hector_learnings).
struct SynthesisPin: View {
    @Environment(AppStore.self) private var store
    let syn: FeaturedSynthesis
    var size: CGFloat = 22

    var body: some View {
        Button {
            store.togglePin(id: syn.pinID, kind: "synthesis",
                            title: syn.title, body: syn.body,
                            source: syn.date)
        } label: {
            InkPinMark(pinned: store.isPinned(syn.pinID), size: size,
                       seed: syn.title.inkSeed)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(store.isPinned(syn.pinID)
                            ? "Let this synthesis go" : "Keep this synthesis")
    }
}

/// A held synthesis on the Us page — reads and plays like the real thing,
/// because the backend keeps a pinned synthesis's whole text (not the
/// 1000-char card excerpt).
struct HeldSynthesisCard: View {
    @Environment(AppStore.self) private var store
    let card: HomeContext.Card
    @State private var reading = false

    private var syn: FeaturedSynthesis { FeaturedSynthesis(pinned: card) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("HELD SYNTHESIS")
                        .font(.system(size: 9, design: .monospaced).weight(.semibold))
                        .tracking(1.6)
                        .foregroundStyle(Theme.inkSoft)
                    Spacer()
                    SynthesisPin(syn: syn, size: 20)
                }
                Text(syn.title.strippedEmojis)
                    .font(.system(.headline, design: .serif))
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(syn.excerpt.strippedEmojis)
                    .font(.system(.footnote, design: .serif))
                    .foregroundStyle(Theme.ink.opacity(0.75))
                    .lineLimit(3)
            }
            .contentShape(Rectangle())
            .onTapGesture { reading = true }
            HStack {
                Text("READ")
                    .font(.system(size: 10, design: .monospaced).weight(.semibold))
                    .tracking(1.4)
                    .underline()
                    .foregroundStyle(Theme.accent)
                    .onTapGesture { reading = true }
                Spacer()
                ListenLine(item: syn.readable)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 14, radius: 20)
        .sheet(isPresented: $reading) { SynthesisReader(featured: syn) }
    }
}

/// The reading bar — the top storey of the bottom bar.
///
/// It is a hard sibling above `EditorialTabBar` (never a `safeAreaInset`;
/// that mechanism failed three ways on device) and shares its ink ground, so
/// while something is playing the dark band simply grows upward to take the
/// player in: one slab, one edge, no floating card.
struct ReadingBar: View {
    @Environment(AppStore.self) private var store

    private var rateLabel: String {
        store.reader.rate == 1.0 ? "1×" :
        store.reader.rate == 1.5 ? "1.5×" : "2×"
    }

    /// What she's doing, said plainly. The stand-in is never dressed up as
    /// her — if you're hearing the phone, the bar tells you so.
    private var status: String {
        let reader = store.reader
        // In a queue, where-am-I matters more than which-engine — that's the
        // line he reads at a red light.
        if let name = reader.playlistName, reader.queueItems.count > 1 {
            let place = "\(name.uppercased()) · \(reader.queuePosition + 1)/\(reader.queueItems.count)"
            return reader.isPreparing ? place + " · WARMING UP" : place
        }
        if reader.voice == .device { return "STAND-IN VOICE · SHE'S OFFLINE" }
        if reader.isPreparing { return "HER VOICE · WARMING UP" }
        if reader.isStreaming { return "HER VOICE · STILL ARRIVING" }
        return "HER VOICE"
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
                            .foregroundStyle(Theme.paper)
                        HStack(spacing: 5) {
                            if reader.isPreparing {
                                // Her own mark, breathing, instead of a
                                // system spinner.
                                InkSpark(size: 9, color: Theme.paper.opacity(0.7),
                                         seed: 7)
                            }
                            Text(status)
                                .font(.system(size: 9, design: .monospaced).weight(.semibold))
                                .tracking(1.5)
                                .foregroundStyle(Theme.paper.opacity(0.6))
                        }
                    }
                    Spacer(minLength: 4)
                    Button { reader.cycleRate() } label: {
                        Text(rateLabel)
                            .font(.caption2.weight(.bold).monospacedDigit())
                            .foregroundStyle(Theme.paper.opacity(0.85))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .overlay(Capsule()
                                .strokeBorder(Theme.paper.opacity(0.25)))
                    }
                    .buttonStyle(.plain)
                    // In a queue the outer arrows move between PIECES, and
                    // ±15s lives on the lock screen and the scrub bar. One
                    // piece alone, they're ±15s as before.
                    Button {
                        reader.queueItems.count > 1 ? reader.previous()
                                                    : reader.skip(-15)
                    } label: {
                        InkSkip(forward: false, size: 24, color: Theme.paper, seed: 5)
                    }
                    .buttonStyle(.plain)
                    Button { reader.toggle() } label: {
                        InkPlayPause(playing: reader.isSpeaking, size: 28,
                                     color: Theme.paper, seed: 19)
                    }
                    .buttonStyle(.plain)
                    Button {
                        reader.hasNext ? reader.next() : reader.skip(15)
                    } label: {
                        InkSkip(forward: true, size: 24, color: Theme.paper, seed: 11)
                    }
                    .buttonStyle(.plain)
                    Button { reader.stop() } label: {
                        InkCross(size: 17, color: Theme.paper.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Stop reading")
                }

                HStack(spacing: 8) {
                    Text(reader.elapsed.asClock)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(Theme.paper.opacity(0.55))
                    Slider(
                        value: Binding(get: { reader.progress },
                                       set: { reader.scrub(to: $0) }),
                        in: 0...1,
                        onEditingChanged: { editing in
                            if !editing { reader.commitScrub() }
                        })
                        .tint(Theme.paper.opacity(0.85))
                    Text("−" + max(0, reader.duration - reader.elapsed).asClock)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(Theme.paper.opacity(0.55))
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .padding(.bottom, 10)
            // Same ink as the tab bar below, edge to edge — the two read as
            // one dark band, and a hairline marks the storey without
            // breaking it into a separate object.
            .background(alignment: .top) {
                ZStack(alignment: .top) {
                    Theme.ink
                    Theme.paper.opacity(0.13).frame(height: 0.7)
                }
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}
