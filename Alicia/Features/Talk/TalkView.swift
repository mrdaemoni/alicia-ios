import SwiftUI

struct TalkView: View {
    @Environment(AppStore.self) private var store
    @State private var draft = ""
    @State private var speech = SpeechTranscriber()
    @State private var dictationBase = ""
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                messageList
                composer
            }
            // The bone-carving lines run the whole page behind the words.
            // Sister field to Us: calmer, sparser — quiet water under words.
            .waveBackground(.dialogue(mood: store.waveMood))
            .navigationTitle("Dialogue")
            .navigationBarTitleDisplayMode(.inline)
            // While typing, the keyboard owns the bottom edge — hide the
            // tab bar so it can't float over / collide with the keyboard.
            .toolbar(focused ? .hidden : .visible, for: .tabBar)
            .animation(.easeOut(duration: 0.2), value: focused)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    // Walk mode — same session as Telegram's /walk. While
                    // active, everything typed is kept, not answered.
                    Button {
                        store.toggleWalk()
                    } label: {
                        Label(store.isWalking ? "\(store.walkWords)w" : "Walk",
                              systemImage: "figure.walk")
                            .labelStyle(.titleAndIcon)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(store.isWalking ? Theme.accentSoft : Theme.inkSoft)
                    }
                    .accessibilityLabel(store.isWalking ? "End walk" : "Start walk")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        store.voiceReplies.toggle()
                    } label: {
                        Image(systemName: store.voiceReplies
                              ? "speaker.wave.2.fill" : "speaker.slash")
                            .symbolEffect(.bounce, value: store.voiceReplies)
                    }
                    .accessibilityLabel(store.voiceReplies
                                        ? "Voice replies on" : "Voice replies off")
                }
            }
        }
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(store.messages) { message in
                        // Her proactive life stays a whisper here — one
                        // tappable line that opens the Alicia tab. The
                        // Dialogue page belongs to the dialogue.
                        if message.proactiveLabel != nil {
                            ProactiveWhisper(message: message)
                                .id(message.id)
                        } else {
                            MessageBubble(message: message)
                                .id(message.id)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            // Drag down through the messages pulls the keyboard away with
            // the gesture; a tap anywhere outside the composer dismisses it.
            .scrollDismissesKeyboard(.interactively)
            .onTapGesture { focused = false }
            .refreshable { await store.load() }
            .onChange(of: store.messages.last?.text) {
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(store.messages.last?.id, anchor: .bottom)
                }
            }
        }
    }

    private var composer: some View {
        HStack(spacing: 8) {
            TextField(speech.isRecording ? "Listening…"
                      : store.isWalking ? "Walking — talk or type…"
                                        : "Message Alicia…",
                      text: $draft, axis: .vertical)
                .font(.subheadline)
                .lineLimit(1...5)
                .focused($focused)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.30), in: Capsule())

            // Voice in — live on-device transcription into the draft.
            // Works the same in walk mode (accumulates) and regular chat.
            Button {
                toggleDictation()
            } label: {
                Image(systemName: speech.isRecording ? "waveform.circle.fill" : "mic")
                    .font(.system(size: speech.isRecording ? 26 : 17, weight: .semibold))
                    .symbolEffect(.variableColor.iterative, isActive: speech.isRecording)
                    .foregroundStyle(speech.isRecording ? Theme.rose : Theme.accentSoft)
                    .frame(width: 34, height: 34)
            }
            .accessibilityLabel(speech.isRecording ? "Stop dictation" : "Dictate")

            Button {
                store.send(draft)
                draft = ""
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(Theme.accentGradient, in: Circle())
            }
            .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
            .opacity(draft.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Theme.paper.opacity(0.55))
        .onChange(of: speech.transcript) { _, new in
            if speech.isRecording || !new.isEmpty {
                draft = dictationBase.isEmpty ? new
                      : dictationBase + (new.isEmpty ? "" : " " + new)
            }
        }
    }

    private func toggleDictation() {
        if speech.isRecording {
            speech.stop()
            return
        }
        focused = false
        dictationBase = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            guard await speech.requestAuthorization() else { return }
            try? speech.start()
        }
    }
}

/// A proactive message reduced to one quiet line. Tapping it opens the
/// Alicia tab, where her thinking lives in full.
struct ProactiveWhisper: View {
    @Environment(AppStore.self) private var store
    let message: Message

    var body: some View {
        Button {
            store.pendingMindFocusID = message.proactiveID
            store.selectedSection = .mind
        } label: {
            HStack(spacing: 7) {
                Image("RabbitMark")
                    .resizable().scaledToFit()
                    .frame(width: 14, height: 14)
                    .foregroundStyle(Theme.accentSoft)
                Text(message.proactiveLabel ?? "from her")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.accentSoft)
                Text(message.text)
                    .font(.caption)
                    .foregroundStyle(Theme.inkSoft)
                    .lineLimit(1)
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.inkSoft.opacity(0.6))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.16), in: Capsule())
            // Left-aligned with her bubbles — impulses come from her side.
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
    }
}

struct MessageBubble: View {
    @Environment(AppStore.self) private var store
    let message: Message
    @State private var expanded = false
    private var isMe: Bool { message.sender == .me }

    /// Emoji palette mirroring what her reaction loop scores on Telegram.
    private static let reactions = ["❤️", "🔥", "🧠", "👍", "🤔", "👎"]

    /// A long message from her that isn't asking or answering directly —
    /// a report. Reports open folded to their first breath; direct speech
    /// (anything that ends in a question, or short) stays full-size.
    private var isReport: Bool {
        guard !isMe, message.text.count > 350 else { return false }
        let tail = message.text.suffix(120)
        return !tail.contains("?")
    }

    private var displayText: String {
        guard isReport, !expanded else { return message.text }
        // Fold at the first paragraph break past a minimum, else hard-cut.
        if let cut = message.text.range(of: "\n\n", range:
                message.text.index(message.text.startIndex, offsetBy: 120)..<message.text.endIndex) {
            return String(message.text[..<cut.lowerBound])
        }
        return String(message.text.prefix(220)) + "…"
    }

    /// Markdown-rendered body (falls back to plain text on parse failure).
    private var rendered: AttributedString {
        (try? AttributedString(
            markdown: displayText,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
        ?? AttributedString(displayText)
    }

    var body: some View {
        HStack {
            if isMe { Spacer(minLength: 40) }
            VStack(alignment: isMe ? .trailing : .leading, spacing: 4) {
                if let label = message.proactiveLabel, !label.isEmpty {
                    HStack(spacing: 5) {
                        Image("RabbitMark")
                            .resizable()
                            .scaledToFill()
                            .frame(width: 15, height: 15)
                            .clipShape(Circle())
                        Text(label)
                    }
                    .font(.caption2)
                    .foregroundStyle(Theme.accentSoft)
                }
                bubble
            }
            if !isMe { Spacer(minLength: 40) }
        }
    }

    private var bubble: some View {
        HStack(alignment: .bottom, spacing: 8) {
            VStack(alignment: .leading, spacing: 6) {
                Text(message.text.isEmpty ? AttributedString("…") : rendered)
                    .foregroundStyle(Theme.ink)
                if isReport {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
                    } label: {
                        Label(expanded ? "less" : "the rest",
                              systemImage: expanded ? "chevron.up" : "text.alignleft")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.accentSoft)
                    }
                    .buttonStyle(.plain)
                }
            }

            if let voiceURL = message.voiceURL {
                Button {
                    store.playVoiceNote(voiceURL)
                } label: {
                    Image(systemName: "play.circle.fill")
                        .font(.title3)
                        .foregroundStyle(Theme.accentSoft)
                }
                .accessibilityLabel("Play voice note")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        // Transparent washes — the drawing stays visible through the words.
        .background {
            if isMe {
                Theme.accent.opacity(0.16)
            } else {
                Color.white.opacity(0.22)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(alignment: isMe ? .bottomLeading : .bottomTrailing) {
            if let reaction = message.reaction {
                Text(reaction)
                    .font(.footnote)
                    .padding(5)
                    .background(.ultraThinMaterial, in: Circle())
                    .offset(x: isMe ? -10 : 10, y: 12)
            }
        }
        .contextMenu {
            // React to her messages — chat replies feed the archetype loop,
            // proactive messages feed their circulation entry.
            if !isMe, message.messageID != nil || message.proactiveID != nil {
                ForEach(Self.reactions, id: \.self) { emoji in
                    Button {
                        store.react(to: message, with: emoji)
                    } label: {
                        Text(emoji)
                    }
                }
            }
        }
    }
}

#Preview {
    TalkView()
        .environment(AppStore(service: MockAliciaService()))
        .tint(Theme.accent)
        .preferredColorScheme(.dark)
}
