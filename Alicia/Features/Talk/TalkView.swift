import SwiftUI

struct TalkView: View {
    @Environment(AppStore.self) private var store
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                messageList
                composer
            }
            .sectionBackground()
            .navigationTitle("Talk")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
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
                        MessageBubble(message: message)
                            .id(message.id)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .refreshable { await store.load() }
            .onChange(of: store.messages.last?.text) {
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(store.messages.last?.id, anchor: .bottom)
                }
            }
        }
    }

    private var composer: some View {
        HStack(spacing: 10) {
            TextField("Message Alicia…", text: $draft, axis: .vertical)
                .lineLimit(1...5)
                .focused($focused)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Theme.card, in: Capsule())
                .overlay(Capsule().strokeBorder(Theme.stroke))

            Button {
                store.send(draft)
                draft = ""
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(Theme.accentGradient, in: Circle())
            }
            .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
            .opacity(draft.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }
}

struct MessageBubble: View {
    @Environment(AppStore.self) private var store
    let message: Message
    private var isMe: Bool { message.sender == .me }

    /// Emoji palette mirroring what her reaction loop scores on Telegram.
    private static let reactions = ["❤️", "🔥", "🧠", "👍", "🤔", "👎"]

    /// Markdown-rendered body (falls back to plain text on parse failure).
    private var rendered: AttributedString {
        (try? AttributedString(
            markdown: message.text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
        ?? AttributedString(message.text)
    }

    var body: some View {
        HStack {
            if isMe { Spacer(minLength: 40) }
            VStack(alignment: isMe ? .trailing : .leading, spacing: 4) {
                if let label = message.proactiveLabel, !label.isEmpty {
                    Label(label, systemImage: "sparkles")
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
            Text(message.text.isEmpty ? AttributedString("…") : rendered)
                .foregroundStyle(isMe ? .white : .primary)

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
        .background {
            if isMe {
                Theme.accentGradient
            } else {
                Theme.card
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(isMe ? .clear : Theme.stroke)
        )
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
            // React to her replies only — reactions are her learning signal.
            if !isMe, message.messageID != nil {
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
