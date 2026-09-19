import SwiftUI

struct TalkView: View {
    @Environment(AppStore.self) private var store
    @AppStorage("alicia.dialogueDraft") private var draft = ""
    @AppStorage("alicia.dialogueRecordingID") private var recordingID = ""
    @State private var inspectedMessage: Message?
    @State private var speech = SpeechTranscriber()
    @FocusState private var focused: Bool
    @Environment(\.scenePhase) private var scenePhase
    @State private var showRecordings = false
    @State private var selectedRecordingID: String?
    @State private var microphoneError = ""
    @State private var microphoneGeneration = 0
    @State private var microphoneStarting = false
    @State private var lastSavedRecordingID = ""
    @State private var visible = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(title: "Dialogue", kicker: "STAY WITH THE QUESTION")
                    if let episode = store.episodeDay?.episode {
                        HStack(alignment: .top) {
                            Text(episode.title.strippedEmojis).font(.subheadline).italic()
                            Spacer()
                            Button { focused = false; store.openWalk() } label: {
                                Text("THINK ALOUD")
                                    .font(.system(size: 10, design: .monospaced)).tracking(1)
                                    .frame(minHeight: 44).contentShape(Rectangle())
                            }
                            .accessibilityIdentifier("episode.talkFromDialogue")
                        }
                    }
                    if store.episodeChoiceSyncing {
                        Button("Syncing your episode choice · tap to retry") { store.retryEpisodeSync() }
                            .font(.caption).foregroundStyle(Theme.inkSoft)
                    }
                    Button("OUR SHARED FOCUS") {
                        cancelMicrophoneStart(); speech.stop(); focused = false
                        store.collaboration.route = CollaborationRoute()
                    }.font(.system(size: 10, design: .monospaced)).frame(minHeight: 44)
                    EpisodeErrorLine()
                    Button("RECORDINGS") { cancelMicrophoneStart(); speech.stop(); focused = false; selectedRecordingID = nil; showRecordings = true }
                        .font(.system(size: 10, design: .monospaced)).tracking(1)
                        .frame(minHeight: 44).accessibilityIdentifier("voice.recordings")
                }.padding(.horizontal, 18).padding(.bottom, 12)
                messageList
            }
            // Sister field to Us: calmer, sparser — quiet water under words.
            .presenceBackground(.dialogue, store: store)
            .toolbar(.hidden, for: .navigationBar)
            .animation(.easeOut(duration: 0.2), value: focused)
            .onChange(of: focused) { _, now in store.composerFocused = now }
            .sheet(item: $inspectedMessage) { message in
                DialogueReviewView(message: message)
                    .presentationDetents([.large])
            }
            .sheet(isPresented: $showRecordings) { VoiceRecordingsView(recordingID: selectedRecordingID) }
            .onAppear { visible = true }
            .onDisappear { visible = false; cancelMicrophoneStart(); speech.stop() }
            .onChange(of: scenePhase) { _, phase in if phase != .active { cancelMicrophoneStart(); speech.stop() } }
        }
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(store.composerSection == .body ? store.privateBodyMessages : store.messages) { message in
                        MessageBubble(message: message, inspect: { inspectedMessage = $0 }).id(message.id)
                        if let context = message.workContext {
                            Button("RETURN TO · " + context.goalTitle) {
                                cancelMicrophoneStart(); speech.stop(); focused = false
                                store.collaboration.route = CollaborationRoute(goalID: context.goal_id, resultID: context.result_id, sectionID: context.section_id, originalQuote: context.quote)
                            }.font(.caption.monospaced()).frame(minHeight: 44)
                        }
                        if let id = message.recordingID {
                            Button("REVIEW ORIGINAL RECORDING") { cancelMicrophoneStart(); speech.stop(); focused = false; selectedRecordingID = id; showRecordings = true }
                                .font(.system(size: 10, design: .monospaced)).frame(minHeight: 44)
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

    private func cancelMicrophoneStart() { microphoneGeneration += 1; microphoneStarting = false }
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
    var inspect: (Message) -> Void = { _ in }
    private var isMe: Bool { message.sender == .me }

    // Reactions render as words in her register (InkReactions); the emoji
    // strings still travel to the backend, where the loops key on them.

    private var displayText: String {
        isMe ? message.text : message.conversationalPreview.strippedEmojis
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
                if !isMe, !message.text.isEmpty {
                    Button("BEHIND THIS REPLY") { inspect(message) }
                        .font(.system(size: 10, design: .monospaced).weight(.semibold))
                        .tracking(1.2)
                        .foregroundStyle(Theme.accentSoft)
                        .frame(minHeight: 44)
                        .buttonStyle(.plain)
                }
            }

            if let voiceURL = message.voiceURL {
                Button {
                    if isMe { store.playVoiceNote(voiceURL) }
                    else { store.readAloud(Readable(title: "", body: message.text, kind: "dialogue",
                        speechChunks: [SpeechChunk(url: voiceURL, duration: 0)],
                        stableID: message.replyID.map { "voice-reply:" + $0 })) }
                } label: {
                    InkPlayPause(playing: false, size: 24,
                                 color: Theme.accentSoft,
                                 seed: message.text.count, ringed: true)
                }
                .accessibilityLabel("Play voice note")
                .frame(minWidth: 44, minHeight: 44)
            } else if !isMe, message.canReadVoiceReply, !message.text.isEmpty {
                Button {
                    store.readAloud(Readable(title: "", body: message.text, kind: "dialogue",
                        stableID: message.replyID.map { "voice-reply:" + $0 }))
                } label: {
                    VStack(spacing: 4) {
                        InkPlayPause(playing: false, size: 24, color: Theme.accentSoft,
                                     seed: message.text.count, ringed: true)
                        Text("READ").font(.system(size: 9, design: .monospaced))
                    }.frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel("Read reply aloud")
                .accessibilityHint("The original reply audio was not recovered. Read these saved words aloud.")
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
            if !isMe, !message.text.isEmpty {
                Button("Behind this reply") { inspect(message) }
            }
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
        .preferredColorScheme(.light)
}
