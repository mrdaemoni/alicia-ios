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
                ZStack {
                    SectionHeader(
                        title: "Dialogue",
                        kicker: store.isWalking
                            ? "walking · \(store.walkWords) words kept"
                            : "one conversation · two doors")
                    HStack {
                        // Walk mode — same session as Telegram's /walk. While
                        // active, everything typed is kept, not answered.
                        Button {
                            store.toggleWalk()
                        } label: {
                            // Words with her underline, not widget glyphs
                            // (v24 — same treatment as Studio's DRAW).
                            VStack(spacing: 2) {
                                Text("WALK")
                                    .font(.system(size: 9, design: .monospaced)
                                        .weight(store.isWalking ? .bold : .semibold))
                                    .tracking(1.6)
                                    .foregroundStyle(store.isWalking
                                                     ? Theme.accent : Theme.inkSoft)
                                InkUnderline(color: Theme.accent, seed: 19,
                                             lineWidth: 1.1)
                                    .frame(width: 26, height: 4)
                                    .opacity(store.isWalking ? 1 : 0)
                            }
                        }
                        .accessibilityLabel(store.isWalking ? "End walk" : "Start walk")
                        Spacer()
                        Button {
                            store.voiceReplies.toggle()
                        } label: {
                            VStack(spacing: 2) {
                                Text("VOICE")
                                    .font(.system(size: 9, design: .monospaced)
                                        .weight(store.voiceReplies ? .bold : .semibold))
                                    .tracking(1.6)
                                    .foregroundStyle(store.voiceReplies
                                                     ? Theme.accent : Theme.inkSoft)
                                InkUnderline(color: Theme.accent, seed: 21,
                                             lineWidth: 1.1)
                                    .frame(width: 26, height: 4)
                                    .opacity(store.voiceReplies ? 1 : 0)
                            }
                        }
                        .accessibilityLabel(store.voiceReplies
                                            ? "Voice replies on" : "Voice replies off")
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 14)
                }
                messageList
                composer
            }
            // Sister field to Us: calmer, sparser — quiet water under words.
            .waveBackground(.dialogue(mood: store.waveMood), tinted: true)
            .toolbar(.hidden, for: .navigationBar)
            .animation(.easeOut(duration: 0.2), value: focused)
            .onChange(of: focused) { _, now in store.composerFocused = now }
        }
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(store.messages) { message in
                        // Her proactive life stays a whisper here — one
                        // tappable line that opens the Alicia tab. The
                        // Dialogue page belongs to the dialogue. EXCEPT
                        // her explicit asks (v23): those are conversation
                        // by construction, so they arrive as full bubbles
                        // he can answer in place.
                        if message.proactiveLabel != nil, !message.isAsk {
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
        VStack(spacing: 6) {
            // v23: answering one of her asks — the send routes to her
            // capture loops, and this strip says so.
            if store.answeringAskID != nil {
                HStack(spacing: 7) {
                    InkChevron(pointing: .right, size: 10,
                               color: Theme.paper.opacity(0.8), seed: 47)
                    Text("ANSWERING · " + store.answeringAskExcerpt.uppercased())
                        .font(.system(size: 8, design: .monospaced).weight(.semibold))
                        .tracking(1.2)
                        .foregroundStyle(Theme.paper.opacity(0.8))
                        .lineLimit(1)
                    Spacer()
                    Button { store.cancelAnswering() } label: {
                        Text("CANCEL")
                            .font(.system(size: 8, design: .monospaced).weight(.semibold))
                            .tracking(1.2)
                            .underline()
                            .foregroundStyle(Theme.paper.opacity(0.65))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 4)
            }
            composerRow
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 12)
        // One piece with the word-bar: the composer sits IN the ink frame.
        .background(Theme.ink)
        .onChange(of: speech.transcript) { _, new in
            if speech.isRecording || !new.isEmpty {
                draft = dictationBase.isEmpty ? new
                      : dictationBase + (new.isEmpty ? "" : " " + new)
            }
        }
        // Choosing an ask to answer pulls the keyboard up ready to write.
        .onChange(of: store.answeringAskID) { _, id in
            if id != nil { focused = true }
        }
    }

    private var composerRow: some View {
        HStack(spacing: 8) {
            TextField(speech.isRecording ? "Listening…"
                      : store.answeringAskID != nil ? "Answer her…"
                      : store.isWalking ? "Walking — talk or type…"
                                        : "Message Alicia…",
                      text: $draft, axis: .vertical)
                .font(.subheadline)
                .lineLimit(1...5)
                .focused($focused)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .foregroundStyle(Theme.ink)
                .background(Theme.paper, in: Capsule())

            // Voice in — live on-device transcription into the draft.
            // Works the same in walk mode (accumulates) and regular chat.
            Button {
                toggleDictation()
            } label: {
                // Dictation in her register: wave bars while listening,
                // the word at rest (v24).
                Group {
                    if speech.isRecording {
                        InkWaveBars(size: 24, color: Theme.rose, seed: 25)
                    } else {
                        Text("MIC")
                            .font(.system(size: 9, design: .monospaced).weight(.semibold))
                            .tracking(1.4)
                            .foregroundStyle(Theme.paper.opacity(0.85))
                    }
                }
                .frame(width: 34, height: 34)
            }
            .accessibilityLabel(speech.isRecording ? "Stop dictation" : "Dictate")

            Button {
                store.send(draft)
                draft = ""
            } label: {
                // Hand-drawn send — paper ink on the dark band (v21).
                InkSubmitArrow(size: 34, color: Theme.paper, seed: 23)
            }
            .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
            .opacity(draft.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1)
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

/// A proactive message as an editorial interlude — no bubble, no wash:
/// a mono-caps rule with her emblem, and the line itself in serif italic,
/// centered like a section break in a book. Tapping opens the Alicia tab.
struct ProactiveWhisper: View {
    @Environment(AppStore.self) private var store
    let message: Message

    private var archetypeID: String {
        let label = (message.proactiveLabel ?? "").lowercased()
        return Archetypes.order.first(where: { label.contains($0) }) ?? "musubi"
    }

    var body: some View {
        Button {
            store.pendingMindFocusID = message.proactiveID
            store.selectedSection = .mind
        } label: {
            VStack(spacing: 7) {
                HStack(spacing: 9) {
                    Theme.stroke.frame(height: 0.7)
                    ArchetypeEmblem(id: archetypeID, size: 15)
                    Text((message.proactiveLabel ?? "from her").uppercased())
                        .font(.system(size: 8.5, design: .monospaced).weight(.semibold))
                        .tracking(1.8)
                        .foregroundStyle(Theme.ink.opacity(0.65))
                        .fixedSize()
                    Theme.stroke.frame(height: 0.7)
                }
                Text("“" + message.text.strippedEmojis.prefix(90) + "”")
                    .font(.system(size: 13, design: .serif))
                    .italic()
                    .foregroundStyle(Theme.ink.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct MessageBubble: View {
    @Environment(AppStore.self) private var store
    let message: Message
    @State private var expanded = false
    private var isMe: Bool { message.sender == .me }

    // Reactions render as words in her register (InkReactions); the emoji
    // strings still travel to the backend, where the loops key on them.

    /// A long message from her that isn't asking or answering directly —
    /// a report. Reports open folded to their first breath; direct speech
    /// (anything that ends in a question, or short) stays full-size.
    private var isReport: Bool {
        guard !isMe, message.text.count > 350 else { return false }
        let tail = message.text.suffix(120)
        return !tail.contains("?")
    }

    /// Her text arrives with Telegram's inline emoji markers (💭/✨/🎙) —
    /// on paper, the ink chrome does that work, so they're shed (v24).
    private var cleanText: String {
        isMe ? message.text : message.text.strippedEmojis
    }

    private var displayText: String {
        let text = cleanText
        guard isReport, !expanded else { return text }
        // Fold at the first paragraph break past a minimum, else hard-cut.
        if text.count > 120,
           let cut = text.range(of: "\n\n", range:
                text.index(text.startIndex, offsetBy: 120)..<text.endIndex) {
            return String(text[..<cut.lowerBound])
        }
        return String(text.prefix(220)) + "…"
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
                        Text(message.isAsk ? label + " · she's asking" : label)
                    }
                    .font(.caption2)
                    .foregroundStyle(Theme.accentSoft)
                }
                bubble
                // v23: her explicit asks carry the door to answer them —
                // the reply lands in her capture loops, not a fresh chat.
                if message.isAsk, message.proactiveID != nil {
                    Button {
                        store.beginAnswering(message)
                    } label: {
                        HStack(spacing: 5) {
                            InkSpark(size: 9, seed: (message.proactiveID ?? "a").inkSeed)
                            Text(store.answeringAskID == message.proactiveID
                                 ? "ANSWERING…" : "ANSWER HER →")
                                .font(.system(size: 9, design: .monospaced).weight(.semibold))
                                .tracking(1.6)
                                .underline()
                        }
                        .foregroundStyle(Theme.accent)
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 4)
                }
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
                        Text(expanded ? "LESS" : "THE REST →")
                            .font(.system(size: 9, design: .monospaced).weight(.semibold))
                            .tracking(1.6)
                            .underline()
                            .foregroundStyle(Theme.accentSoft)
                    }
                    .buttonStyle(.plain)
                }
            }

            if let voiceURL = message.voiceURL {
                Button {
                    store.playVoiceNote(voiceURL)
                } label: {
                    InkPlayPause(playing: false, size: 24,
                                 color: Theme.accentSoft,
                                 seed: message.text.count, ringed: true)
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
                InkReactionTag(emoji: reaction)
                    .offset(x: isMe ? -8 : 8, y: 11)
            }
        }
        .contextMenu {
            // React to her messages — chat replies feed the archetype loop,
            // proactive messages feed their circulation entry. Words in
            // her register; the emoji rides underneath to the backend.
            if !isMe, message.messageID != nil || message.proactiveID != nil {
                ForEach(InkReactions.all, id: \.emoji) { reaction in
                    Button {
                        store.react(to: message, with: reaction.emoji)
                    } label: {
                        Text(reaction.word)
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
