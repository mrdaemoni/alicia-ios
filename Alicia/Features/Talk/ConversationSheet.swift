import SwiftUI

/// Writing to her, as a layer over the page he is already on.
///
/// Hector's build-18 note: *"when I open the text field to talk to Alicia, it
/// should be rendered like a sheet on top of everything else because it's a
/// contextual layer that I'm talking to her on top of any of the sections."*
///
/// That is the whole design. Before this, typing meant leaving — the app swapped
/// to the Dialogue tab, and whatever he had been reading in Mind or looking at
/// in Body went away underneath him. Now the section stays where it was, this
/// comes up over it carrying that section's name and its own saved draft, and
/// closing it puts him back exactly where he was standing.
///
/// Body keeps its own everything: its own draft, its own message list, and a
/// send that goes to the Mac's local model rather than the cloud lane.
struct ConversationSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool
    @State private var inspected: Message?
    @State private var sent = false

    /// Frozen by `openConversation()` before this view ever renders. Deriving
    /// it here — even into `@State` on appear — let a dismissing sheet write
    /// one last time under whatever section the app had already moved to.
    private var section: SurfaceContext { store.conversationContext }
    private var privateBody: Bool { section.section == "body" }
    private var busy: Bool { privateBody ? store.privateBodySending : store.isStreaming }
    private var messages: [Message] { privateBody ? store.privateBodyMessages : store.messages }

    private var draft: Binding<String> {
        Binding(get: { store.composerDrafts.text(for: section.section) },
                set: { value in
                    store.composerDrafts.set(value, for: section.section)
                    if privateBody, value.isEmpty {
                        UserDefaults.standard.removeObject(forKey: "alicia.bodyDraftRecordingID")
                    }
                })
    }

    private var canSend: Bool {
        !busy && !store.episodeChoiceSyncing
            && !draft.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(Theme.stroke)
            conversation
            composer
        }
        .background(Theme.backdrop.ignoresSafeArea())
        .foregroundStyle(Theme.ink)
        .fontDesign(.serif)
        .onAppear { focused = true }
        .sheet(item: $inspected) { message in
            DialogueReviewView(message: message).presentationDetents([.large])
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("WRITING TO ALICIA")
                        .font(.system(size: 9, design: .monospaced)).tracking(1.2)
                        .foregroundStyle(Theme.inkSoft)
                    Text("about " + section.title)
                        .font(.system(size: 22, design: .serif))
                        .accessibilityIdentifier("conversation.context")
                }
                Spacer()
                Button("CLOSE") { focused = false; dismiss() }
                    .font(.system(size: 10, design: .monospaced)).tracking(1)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("conversation.close")
            }
            if privateBody {
                Text("Private · this stays between your phone and your Mac.")
                    .font(.caption).foregroundStyle(Theme.inkSoft)
            }
            // Context he attached elsewhere travels in with him rather than
            // being silently dropped by the change of surface.
            if !privateBody, let work = store.collaboration.dialogueContext {
                HStack {
                    Text("Passage · " + work.sectionTitle).font(.caption).lineLimit(1)
                    Spacer()
                    Button("Clear") { store.collaboration.dialogueContext = nil }.font(.caption)
                }.accessibilityIdentifier("workReview.dialogueContext")
            }
            if !privateBody, store.answeringAskID != nil {
                HStack {
                    Text("Replying to · " + store.answeringAskExcerpt).font(.caption).lineLimit(1)
                    Spacer()
                    Button("Cancel") { store.cancelAnswering() }.font(.caption)
                }
            }
            EpisodeErrorLine()
        }
        .padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 10)
        .buttonStyle(.plain)
    }

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    if messages.isEmpty {
                        Text(privateBody
                             ? "Nothing asked here yet. Your body questions stay on your Mac."
                             : "Nothing here yet. Say what you're actually thinking.")
                            .font(.subheadline).italic().foregroundStyle(Theme.inkSoft)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 24)
                    }
                    ForEach(messages) { message in
                        MessageBubble(message: message, inspect: { inspected = $0 }).id(message.id)
                    }
                    if busy {
                        Text(privateBody ? "Thinking privately on your Mac…" : "Alicia is thinking…")
                            .font(.caption).foregroundStyle(Theme.inkSoft)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id("thinking")
                    }
                }
                .padding(.horizontal, 20).padding(.vertical, 12)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: messages.count) { _, _ in
                guard let last = messages.last else { return }
                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(last.id, anchor: .bottom) }
            }
            .task { if let last = messages.last { proxy.scrollTo(last.id, anchor: .bottom) } }
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if sent {
                Text(privateBody ? "Asked. Her answer appears above."
                                 : "Sent. Her reply appears above, and stays in Dialogue.")
                    .font(.caption).foregroundStyle(Theme.inkSoft)
            }
            HStack(spacing: 10) {
                TextField("Say what you're thinking…", text: draft, axis: .vertical)
                    .lineLimit(1...6)
                    .font(.system(size: 17, design: .serif))
                    .focused($focused)
                    .padding(.horizontal, 13).padding(.vertical, 11)
                    .background(Theme.ink.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityIdentifier("conversation.field")
                Button { send() } label: {
                    InkSubmitArrow(size: 27, color: canSend ? Theme.ink : Theme.inkSoft.opacity(0.4), seed: 23)
                        .frame(width: 44, height: 44)
                }
                .disabled(!canSend)
                .accessibilityLabel("Send to Alicia")
                .accessibilityIdentifier("conversation.send")
                // Speaking is the walk, and only the walk. Leaving here keeps
                // the draft exactly as it stands; the two are separate records.
                Button {
                    focused = false
                    dismiss()
                    store.openWalk(surface: section)
                } label: {
                    Text("WALK")
                        .font(.system(size: 10, design: .monospaced).weight(.semibold)).tracking(1)
                        .foregroundStyle(Theme.paper)
                        .frame(minWidth: 58, minHeight: 44)
                        .background(Theme.ink, in: RoundedRectangle(cornerRadius: 12))
                }
                .accessibilityLabel("Walk and think aloud about " + section.title)
                .accessibilityIdentifier("conversation.walk")
            }

        }
        .padding(.horizontal, 20).padding(.top, 10).padding(.bottom, 14)
        .background(Theme.paper)
        .overlay(alignment: .top) { Rectangle().fill(Theme.stroke).frame(height: 0.7) }
        .buttonStyle(.plain)
    }

    private func send() {
        let text = draft.wrappedValue
        guard canSend else { return }
        if privateBody {
            store.sendPrivateBody(text, recordingID: UserDefaults.standard
                .string(forKey: "alicia.bodyDraftRecordingID") ?? "")
        } else {
            store.send(text, surfaceContext: section)
        }
        draft.wrappedValue = ""
        sent = true
    }
}
