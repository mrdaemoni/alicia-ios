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
            if busy {
                Text(privateBody ? "Thinking privately on your Mac…" : "Alicia is thinking…")
                    .font(.caption).foregroundStyle(Theme.paper.opacity(0.7))
            } else if let latestReply, draft.isEmpty {
                Button { store.openConversation() } label: {
                    Text(latestReply.text)
                        .font(.system(size: 14, design: .serif))
                        .foregroundStyle(Theme.paper.opacity(0.72))
                        .lineLimit(2).multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }.accessibilityIdentifier("composer.lastReply")
            }
            HStack(spacing: 10) {
                field
                talkButton
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
            if let episode {
                Button { store.openListening(episode: true) } label: {
                    Text("TALK ABOUT " + episode.id)
                        .font(.system(size: 9, design: .monospaced)).tracking(0.8)
                        .foregroundStyle(Theme.paper.opacity(0.78))
                        .lineLimit(1)
                        .padding(.horizontal, 9).padding(.vertical, 5)
                        .overlay(RoundedRectangle(cornerRadius: 9)
                            .stroke(Theme.paper.opacity(0.28), lineWidth: 0.8))
                }
                .accessibilityLabel("Talk about " + episode.id)
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

    private var talkButton: some View {
        Button { store.openListening(episode: false) } label: {
            Text("TALK")
                .font(.system(size: 10, design: .monospaced).weight(.semibold)).tracking(1)
                .foregroundStyle(Theme.ink)
                .frame(minWidth: 58, minHeight: 44)
                .background(Theme.paper, in: RoundedRectangle(cornerRadius: 12))
        }
        .accessibilityLabel("Talk to Alicia about " + section.title)
        .accessibilityIdentifier("composer.microphone")
    }
}
