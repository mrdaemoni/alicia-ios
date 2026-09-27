import SwiftUI

struct TalkView: View {
    @Environment(AppStore.self) private var store
    @State private var inspectedMessage: Message?
    @State private var speech = SpeechTranscriber()
    @FocusState private var focused: Bool
    @Environment(\.scenePhase) private var scenePhase
    @State private var showRecordings = false
    @State private var selectedRecordingID: String?
    @State private var microphoneGeneration = 0
    @State private var microphoneStarting = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(title: "Dialogue", kicker: "STAY WITH THE QUESTION")
                    // One block: the episode and its walk, the sync state with
                    // its one quiet retry, then where he can go from here.
                    InkSection(kicker: "Around this dialogue", rule: false, spacing: 2) {
                        if let episode = store.episodeDay?.episode {
                            HStack(alignment: .center, spacing: 12) {
                                Text(episode.title.strippedEmojis).font(.subheadline).italic()
                                    .foregroundStyle(Theme.inkSoft)
                                Spacer(minLength: 8)
                                Button("Walk") { focused = false; store.openWalk() }
                                    .buttonStyle(.inkSecondaryCompact)
                                    .accessibilityIdentifier("episode.talkFromDialogue")
                            }
                        }
                        if store.episodeChoiceSyncing {
                            HStack(alignment: .firstTextBaseline, spacing: 12) {
                                Text("Syncing your episode choice").font(InkType.meta).foregroundStyle(Theme.inkSoft)
                                Spacer(minLength: 8)
                                Button("Try again") { store.retryEpisodeSync() }.buttonStyle(.inkQuiet)
                            }
                        }
                        Button {
                            cancelMicrophoneStart(); speech.stop(); focused = false
                            store.collaboration.route = CollaborationRoute()
                        } label: { InkLinkLabel(title: "Our shared focus", small: true) }
                            .buttonStyle(.inkLink)
                        InkRule(opacity: 0.6)
                        Button { cancelMicrophoneStart(); speech.stop(); focused = false; selectedRecordingID = nil; showRecordings = true } label: {
                            InkLinkLabel(title: "Original recordings", small: true)
                        }
                        .buttonStyle(.inkLink)
                        .accessibilityIdentifier("voice.recordings")
                        EpisodeErrorLine()
                    }
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
            .onDisappear { cancelMicrophoneStart(); speech.stop() }
            .onChange(of: scenePhase) { _, phase in if phase != .active { cancelMicrophoneStart(); speech.stop() } }
        }
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(store.composerSection == .body ? store.privateBodyMessages : store.messages) { message in
                        VStack(spacing: 0) {
                            MessageBubble(message: message, inspect: { inspectedMessage = $0 })
                            // What belongs to this message hangs under its
                            // bubble, on the bubble's side.
                            if let context = message.workContext {
                                MessageAttachment(isMe: message.sender == .me) {
                                    Button {
                                        cancelMicrophoneStart(); speech.stop(); focused = false
                                        store.collaboration.route = CollaborationRoute(goalID: context.goal_id, resultID: context.result_id, sectionID: context.section_id, originalQuote: context.quote)
                                    } label: { InkLinkLabel(title: context.goalTitle, detail: "Return to our goal", small: true) }
                                        .buttonStyle(.inkLink)
                                }
                            }
                            if let id = message.recordingID {
                                MessageAttachment(isMe: message.sender == .me) {
                                    Button { cancelMicrophoneStart(); speech.stop(); focused = false; selectedRecordingID = id; showRecordings = true } label: {
                                        InkLinkLabel(title: "Original recording", small: true)
                                    }
                                    .buttonStyle(.inkLink)
                                }
                            }
                        }.id(message.id)
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

/// A link that belongs to one message, set under its bubble on the bubble's
/// side and inset to the bubble's text.
struct MessageAttachment<Content: View>: View {
    var isMe: Bool
    @ViewBuilder var content: () -> Content
    var body: some View {
        HStack(spacing: 0) {
            if isMe { Spacer(minLength: 40) }
            content().padding(.horizontal, 14)
            if !isMe { Spacer(minLength: 40) }
        }
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
                    // An action (it sets reply mode), not a place: quiet.
                    Button(store.answeringAskID == message.proactiveID ? "Answering…" : "Answer her") {
                        store.beginAnswering(message)
                    }
                    .buttonStyle(.inkQuiet)
                    .padding(.leading, 14)
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
                    // Goes somewhere (the review sheet): her small link,
                    // hugging its words so the bubble keeps its width.
                    Button { inspect(message) } label: {
                        HStack(spacing: 6) {
                            Text("Behind this reply").font(InkType.linkSmall).foregroundStyle(Theme.ink)
                            InkChevron(pointing: .right, size: 12, color: Theme.inkSoft, seed: 61)
                        }
                        .frame(minHeight: 44).contentShape(Rectangle())
                    }
                    .buttonStyle(.inkLink)
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
