import SwiftUI

/// Scale of Us behavior: measured word focus, tap-to-seek, and following
/// that yields as soon as Hector scrolls. Opening this view never starts audio.
struct ImmersiveReadingView: View {
    var previewReduceMotion = false
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var follow = true
    @State private var document = NarrationDocument(text: "", chunks: [])
    private func refreshDocument() {
        document = NarrationDocument(text: store.reader.narrationText, chunks: store.reader.narrationChunks)
    }
    private var focusedParagraph: Int? {
        let elapsed = store.reader.elapsed
        return document.paragraphs.first { p in
            if !p.spans.isEmpty { return p.spans.contains { elapsed >= $0.start && elapsed < $0.end } }
            return p.chunkStart.map { elapsed >= $0 && elapsed < (p.chunkEnd ?? $0) } ?? false
        }?.id
    }
    private func attributed(_ paragraph: NarrationDocument.Paragraph) -> AttributedString {
        var value = AttributedString(paragraph.text)
        for span in paragraph.spans {
            let a = paragraph.text.unicodeScalars.index(paragraph.text.startIndex, offsetBy: span.lower)
            let b = paragraph.text.unicodeScalars.index(paragraph.text.startIndex, offsetBy: span.upper)
            guard let lower = AttributedString.Index(a, within: value), let upper = AttributedString.Index(b, within: value) else { continue }
            value[lower..<upper].link = URL(string: "alicia-reading://seek/\(span.start)")
            value[lower..<upper].foregroundColor = Theme.ink
            if store.reader.elapsed >= span.start && store.reader.elapsed < span.end {
                value[lower..<upper].backgroundColor = Theme.accent.opacity(0.18)
            }
        }
        return value
    }
    var body: some View {
        let focused = focusedParagraph
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 28) {
                        Text(store.reader.current?.title ?? "A reading")
                            .font(.system(size: 32, design: .serif)).accessibilityAddTraits(.isHeader)
                        if store.reader.current?.textSource == "machine_audio_transcript" {
                            Text("Transcript from the original recording. Words may contain recognition errors.")
                                .font(.caption).foregroundStyle(Theme.inkSoft)
                        }
                        Text(document.hasWordTiming ? "Tap a word to listen from there." : "Word timing is unavailable. Read the full text while listening.")
                            .font(.caption).foregroundStyle(Theme.inkSoft)
                        ForEach(document.paragraphs) { paragraph in
                            Text(attributed(paragraph)).font(.system(size: 23, design: .serif)).lineSpacing(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .fixedSize(horizontal: false, vertical: true).padding(.leading, 12)
                                .overlay(alignment: .leading) {
                                    if focused == paragraph.id {
                                        Rectangle().fill(Theme.accent.opacity(0.5)).frame(width: 2)
                                    }
                                }.id(paragraph.id)
                        }
                    }.padding(24)
                }
                .simultaneousGesture(DragGesture(minimumDistance: 8).onChanged { _ in follow = false })
                .onChange(of: focused) { _, target in
                    guard follow, store.reader.isSpeaking, let target else { return }
                    withAnimation((reduceMotion || previewReduceMotion) ? nil : .easeInOut(duration: 0.35)) { proxy.scrollTo(target, anchor: .center) }
                }
                .environment(\.openURL, OpenURLAction { url in
                    guard url.scheme == "alicia-reading", let seconds = Double(url.lastPathComponent) else { return .systemAction }
                    store.reader.seekToNarration(seconds: seconds); follow = true
                    return .handled
                })
            }
            .onChange(of: store.reader.narrationChunks, initial: true) { _, _ in refreshDocument() }
            .onChange(of: store.reader.narrationText) { _, _ in refreshDocument() }
            .background(Theme.paper).safeAreaInset(edge: .bottom) { controls }
            .inkSheetPage("Read along")
            .toolbar {
                // Following is a switch he flips, not a place: a quiet action
                // whose words say its state. The labels are what the UI tests
                // (and VoiceOver) read, so they stay sentence case.
                ToolbarItem(placement: .topBarLeading) {
                    Button(follow ? "Following" : "Follow voice") { follow.toggle() }
                        .buttonStyle(.inkQuiet)
                        .accessibilityLabel(follow ? "Following" : "Follow voice")
                        .accessibilityValue(follow ? "On" : "Off")
                }
            }.toolbarBackground(Theme.paper, for: .navigationBar)
        }
    }
    private var controls: some View {
        VStack(spacing: 10) {
            if let error = store.reader.failure {
                // Seal red like every error; a plain Text so the UI test still
                // finds it as static text.
                Text(error).font(.callout).foregroundStyle(Theme.rose)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("reading.failure")
            } else if store.reader.isPreparing || store.reader.isLoadingMedia {
                InkNotice(text: store.reader.isPreparing ? "Preparing her voice…" : "Loading recording…")
            }
            // Transport in her hand, like the reading bar: back, play/pause,
            // forward, the rate, and — apart, in seal red — the one control
            // that ends the reading.
            HStack(spacing: 22) {
                Button { store.reader.skip(-15) } label: {
                    InkSkip(forward: false, size: 30, color: Theme.ink, seed: 5)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.plain).accessibilityLabel("Back 15 seconds")
                Button { store.reader.toggle() } label: {
                    InkPlayPause(playing: store.reader.isSpeaking, size: 40, color: Theme.ink, seed: 19)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.plain)
                .disabled(store.reader.isPreparing)
                .opacity(store.reader.isPreparing ? 0.4 : 1)
                .accessibilityLabel(store.reader.failure != nil ? "Retry voice" : store.reader.isSpeaking ? "Pause" : "Listen")
                .accessibilityIdentifier("reading.play")
                Button { store.reader.skip(15) } label: {
                    InkSkip(forward: true, size: 30, color: Theme.ink, seed: 11)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.plain).accessibilityLabel("Forward 15 seconds")
                Button(String(format: "%g×", store.reader.rate)) { store.reader.cycleRate() }
                    .buttonStyle(.inkQuiet)
                    .accessibilityLabel("Speed " + String(format: "%g", store.reader.rate))
                Spacer(minLength: 8)
                Button { store.reader.stop(); dismiss() } label: {
                    InkCross(size: 20, color: Theme.rose, seed: 23)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.plain).accessibilityLabel("Stop")
            }
            Slider(value: Binding(get: { store.reader.progress }, set: { store.reader.scrub(to: $0) }), in: 0...1,
                   onEditingChanged: { if !$0 { store.reader.commitScrub() } })
                .disabled(store.reader.duration <= 0).accessibilityLabel("Reading position")
            HStack {
                Text(store.reader.elapsed.asClock); Spacer(); Text(store.reader.duration.asClock)
            }.font(.caption.monospacedDigit()).foregroundStyle(Theme.inkSoft)
        }.padding(20).background(Theme.paper).tint(Theme.ink)
    }
}
