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
/// ink ground as `EditorialTabBar`, and it never takes the keyboard itself —
/// tapping it raises `ConversationSheet` over the page he is on, and TALK
/// raises the full-screen `ListeningRoom`. Both carry this band's section with
/// them, which is what makes "about BODY" true rather than decorative.
struct ConversationComposer: View {
    @Environment(AppStore.self) private var store

    private var section: SurfaceContext { store.surfaceContext() }
    private var privateBody: Bool { section.section == "body" }
    private var busy: Bool { privateBody ? store.privateBodySending : store.isStreaming }

    /// What he last typed here, per section. Shown as the field's own text so
    /// an unsent draft is visible from the outside, not hidden in the sheet.
    private var draft: String { store.composerDrafts.text(for: section.section) }

    private var latestReply: Message? {
        (privateBody ? store.privateBodyMessages : store.messages)
            .last(where: { $0.sender == .alicia && !$0.text.isEmpty })
    }

    private var episode: EpisodeDay.Episode? { store.episodeDay?.episode }

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
                Text(error).font(.caption).foregroundStyle(Theme.paper.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .padding(.bottom, 10)
        .background(Theme.ink)
        .overlay(alignment: .top) { Rectangle().fill(Theme.paper.opacity(0.12)).frame(height: 0.7) }
        .buttonStyle(.plain)
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
                HStack(spacing: 8) {
                    Circle().fill(Theme.amber).frame(width: 6, height: 6)
                    Text(reflectionSubject(waiting) + " · " + waiting.stage.label.lowercased())
                        .font(.system(size: 12, design: .serif))
                        .foregroundStyle(Theme.paper.opacity(0.85))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text("OPEN")
                        .font(.system(size: 8, design: .monospaced)).tracking(1)
                        .foregroundStyle(Theme.paper.opacity(0.6))
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

    private func openReflection(_ record: VoiceRecording) {
        if record.context.source == "ios_walk" {
            store.walkRecordingID = record.id
            store.walkEpisodeID = record.context.episode_id
            store.showWalk = true
        } else {
            store.reviewRecording = AppStore.ReviewedRecording(id: record.id)
        }
    }

    /// One line that names what she would be hearing about. When an episode is
    /// playing it says so, because "talk about this episode" was the entry
    /// point Hector actually used and it must not disappear into a tab.
    private var context: some View {
        HStack(spacing: 10) {
            Text("ABOUT · " + section.title.uppercased())
                .font(.system(size: 9, design: .monospaced)).tracking(0.8)
                .foregroundStyle(Theme.paper.opacity(0.55))
                .accessibilityIdentifier("composer.context")
            Spacer(minLength: 8)
            // When something is playing, WALK is about that; the chip says so
            // rather than offering a second button that does the same thing.
            if let episode {
                Text("WALK IS ABOUT " + episode.id)
                    .font(.system(size: 9, design: .monospaced)).tracking(0.8)
                    .foregroundStyle(Theme.paper.opacity(0.6))
                    .lineLimit(1)
                    .accessibilityIdentifier("episode.talkAnywhere")
            }
        }
    }

    /// Not a `TextField`. Raising the sheet is the whole job, and a real field
    /// here would pull the keyboard up against the tab bar — the layout fight
    /// that made the old composer collapse everything around it.
    private var field: some View {
        Button { store.openConversation() } label: {
            HStack(spacing: 8) {
                Text(draft.isEmpty ? "Talk or type to Alicia…" : draft)
                    .font(.system(size: 16, design: .serif))
                    .foregroundStyle(draft.isEmpty ? Theme.paper.opacity(0.5) : Theme.paper)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if !draft.isEmpty {
                    Text("DRAFT")
                        .font(.system(size: 8, design: .monospaced)).tracking(0.8)
                        .foregroundStyle(Theme.paper.opacity(0.55))
                }
            }
            .padding(.horizontal, 13).padding(.vertical, 11)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(Theme.paper.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
            .contentShape(Rectangle())
        }
        .accessibilityLabel(draft.isEmpty
            ? "Write to Alicia about " + section.title
            : "Continue your draft about " + section.title)
        .accessibilityIdentifier("dialogue.composer")
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
        Button { store.openWalk(surface: section) } label: {
            Text("WALK")
                .font(.system(size: 10, design: .monospaced).weight(.semibold)).tracking(1)
                .foregroundStyle(Theme.ink)
                .frame(minWidth: 58, minHeight: 44)
                .background(Theme.paper, in: RoundedRectangle(cornerRadius: 12))
        }
        .accessibilityLabel(episode == nil
            ? "Walk and think aloud about " + section.title
            : "Walk and think aloud about " + (episode?.id ?? ""))
        .accessibilityIdentifier("composer.walk")
    }
}
