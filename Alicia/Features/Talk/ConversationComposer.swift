import SwiftUI

/// The way to reach her, as a permanent band directly above the navigation.
///
/// Codex's A2-045 version made this the single input owner so a section change
/// could never reparent the microphone or leak a Body draft into Mind. What it
/// still did was behave like a state: it took the keyboard in place, and the
/// tab bar folded away underneath it.
///
/// Hector's build-18 note: *"the interface to talking to Alicia is broken. It
/// should always be present right above the bottom bar of navigation. It should
/// be with black background matching the same style as the navigation."*
///
/// So this band is furniture. It is always on screen, it is drawn on the same
/// ink ground as `EditorialTabBar`, and its field is real: Hector can type and
/// send without first leaving the room. The reply layer opens after the send,
/// carrying the section that accepted those words. TALK raises the full-screen
/// particle `ListeningRoom` with the same frozen section.
struct ConversationComposer: View {
    @Environment(AppStore.self) private var store
    @FocusState private var focused: Bool

    private var section: SurfaceContext { store.surfaceContext() }
    private var privateBody: Bool { section.section == "body" }
    private var busy: Bool { privateBody ? store.privateBodySending : store.isStreaming }

    /// What he last typed here, per section. Shown as the field's own text so
    /// an unsent draft is visible from the outside, not hidden in the sheet.
    private var draft: Binding<String> {
        Binding(get: { store.composerDrafts.text(for: section.section) },
                set: { store.composerDrafts.set($0, for: section.section) })
    }

    private var canSend: Bool {
        !busy && !store.episodeChoiceSyncing
            && !draft.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// An episode is part of the visible room only on Us and Studio. A chosen
    /// episode must never silently turn a Body or Mind conversation into an
    /// episode conversation.
    private var episode: EpisodeDay.Episode? {
        section.episode_id.isEmpty ? nil : store.episodeDay?.episode
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            context
            reflectionLine
            // v40: one height, everywhere. This used to grow a two-line
            // preview of her last reply, so the band was short in Body and
            // tall in Mind and Studio depending on what she had last said —
            // and on a real phone that reply was a fragment of an internal
            // instruction, set in her voice, permanently across the bottom of
            // the screen. Hector: "The input box should always be like in the
            // body section (small)." Her reply belongs in the conversation,
            // which is one tap away.
            if busy {
                Text(privateBody ? "Thinking privately on your Mac…" : "Alicia is thinking…")
                    .font(.caption).foregroundStyle(Theme.paper.opacity(0.7))
                    .lineLimit(1)
            }
            HStack(spacing: 10) {
                field
                walkButton
            }
            if let error = store.composerDrafts.error {
                // An error reads in seal red, even on the ink ground.
                Text(error.strippedEmojis).font(.caption).foregroundStyle(Theme.rose)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .padding(.bottom, 10)
        .background(Theme.ink)
        .overlay(alignment: .top) { Rectangle().fill(Theme.paper.opacity(0.12)).frame(height: 0.7) }
        .buttonStyle(.plain)
        .onChange(of: focused) { _, now in store.composerFocused = now }
    }

    /// Where his last spoken reflection is, in one tappable line.
    ///
    /// Hector's build-18 note: *"when I talk about an episode and I submit
    /// something, I don't know where it is … I don't know if I already viewed
    /// it or if I already sent it."* The answer used to live only inside a
    /// screen he had to already know to open. Now it follows him: anything
    /// waiting on him is stated here, and for a short while after it lands,
    /// so is the fact that she has it.
    @ViewBuilder private var reflectionLine: some View {
        if let waiting = store.reflectionNeedingYou {
            Button { openReflection(waiting) } label: {
                // Goes somewhere: InkLinkLabel's shape (serif line, her
                // chevron trailing), composed in paper for the ink ground.
                HStack(spacing: 8) {
                    Circle().fill(Theme.amber).frame(width: 6, height: 6)
                    Text(reflectionSubject(waiting) + " · " + waiting.stage.label.lowercased())
                        .font(.system(size: 14, design: .serif))
                        .foregroundStyle(Theme.paper)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    InkChevron(pointing: .right, size: 12, color: Theme.paper.opacity(0.75), seed: 53)
                }
                .frame(maxWidth: .infinity, minHeight: 28)
                .contentShape(Rectangle())
            }
            .accessibilityLabel(reflectionSubject(waiting) + ", " + waiting.stage.detail)
            .accessibilityIdentifier("composer.reflectionWaiting")
        } else if let sent = store.recentlySentReflection, recentlySent(sent) {
            HStack(spacing: 8) {
                Circle().fill(Theme.mint).frame(width: 6, height: 6)
                Text(reflectionSubject(sent) + " · Alicia has it")
                    .font(.system(size: 12, design: .serif))
                    .foregroundStyle(Theme.paper.opacity(0.7))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .frame(minHeight: 28)
            .accessibilityIdentifier("composer.reflectionSent")
        }
    }

    private func reflectionSubject(_ record: VoiceRecording) -> String {
        let episode = record.context.episode_id
        return episode.isEmpty ? "Your spoken thought" : "Your " + episode + " reflection"
    }

    /// Six hours: long enough that he sees it the next time he picks up the
    /// phone, short enough that the band does not become a permanent receipt.
    private func recentlySent(_ record: VoiceRecording) -> Bool {
        Date().timeIntervalSince(voiceDate(record.context.started_at)) < 6 * 3600
    }

    /// Show it; never reopen the walk. Handing an unfinished recording back to
    /// WalkReflectionView starts recording into it, which edits an original he
    /// cannot get back.
    private func openReflection(_ record: VoiceRecording) {
        store.reviewRecording = AppStore.ReviewedRecording(id: record.id)
    }

    /// One line that names what she would be hearing about. When an episode is
    /// playing it says so, because "talk about this episode" was the entry
    /// point Hector actually used and it must not disappear into a tab.
    private var context: some View {
        HStack(spacing: 10) {
            // Plain meta, not controls: sentence-case serif, soft paper.
            Text("About " + section.title)
                .font(.system(size: 12, design: .serif)).italic()
                .foregroundStyle(Theme.paper.opacity(0.6))
                .lineLimit(1)
                .accessibilityIdentifier("composer.context")
            Spacer(minLength: 8)
            // When something is playing, TALK is about that; the chip says so
            // rather than offering a second button that does the same thing.
            if let episode {
                Text("Talk is about " + episode.id)
                    .font(.system(size: 12, design: .serif)).italic()
                    .foregroundStyle(Theme.paper.opacity(0.6))
                    .lineLimit(1)
                    .accessibilityIdentifier("episode.talkAnywhere")
            }
        }
    }

    /// One real field in every room. Draft storage remains per section, so a
    /// half-written Body question never follows Hector into Mind.
    private var field: some View {
        HStack(spacing: 8) {
            TextField("", text: draft,
                      prompt: Text("Talk or type to Alicia about " + section.title + "…")
                        .foregroundColor(Theme.paper.opacity(0.52)),
                      axis: .vertical)
                .lineLimit(1...3)
                .font(.system(size: 16, design: .serif))
                .foregroundStyle(Theme.paper)
                .tint(Theme.paper)
                .focused($focused)
                .submitLabel(.send)
                .onSubmit(send)
                .accessibilityIdentifier("conversation.fieldInline")
            Button(action: send) {
                InkSubmitArrow(size: 24,
                               color: canSend ? Theme.paper : Theme.paper.opacity(0.32),
                               seed: 29)
                    .frame(width: 36, height: 36)
            }
            .disabled(!canSend)
            .accessibilityLabel("Send to Alicia about " + section.title)
            .accessibilityIdentifier("conversation.sendInline")
        }
        .padding(.leading, 13).padding(.trailing, 5).padding(.vertical, 4)
        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
        .background(Theme.paper.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.paper.opacity(focused ? 0.42 : 0.16), lineWidth: 0.7))
        .accessibilityHint("Your message carries the context of this section.")
    }

    /// There is one spoken path now, and it is the walk.
    ///
    /// Hector: *"let's remove the voice input and only have the arrow up to
    /// submit, and next to it, let's have a button that says walk … where I
    /// can just probably speak for a long time in an open-ended manner."*
    ///
    /// The short-remark microphone is gone. A walk started here is the same
    /// kind of thing as one started from an episode or the morning — original
    /// audio kept, Mac transcript, his review before anything is sent — and it
    /// carries the section he started it from as its subject.
    private var walkButton: some View {
        Button {
            focused = false
            store.openWalk(surface: section)
        } label: {
            Text("TALK")
                .font(.system(size: 10, design: .monospaced).weight(.semibold)).tracking(1)
                .foregroundStyle(Theme.ink)
                .frame(minWidth: 58, minHeight: 44)
                .background(Theme.paper, in: RoundedRectangle(cornerRadius: 12))
        }
        .accessibilityLabel(episode == nil
            ? "Talk to Alicia about " + section.title
            : "Talk to Alicia about " + (episode?.id ?? ""))
        .accessibilityIdentifier("composer.walk")
    }

    private func send() {
        let text = draft.wrappedValue
        guard canSend else { return }
        // Freeze before either the keyboard or the reply layer changes the
        // view hierarchy. This exact value travels in `/api/chat`.
        let sendingContext = section
        if privateBody {
            store.sendPrivateBody(text)
        } else {
            store.send(text, surfaceContext: sendingContext)
        }
        draft.wrappedValue = ""
        focused = false
        store.openConversation(context: sendingContext)
    }
}
