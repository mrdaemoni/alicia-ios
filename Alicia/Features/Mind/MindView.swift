import SwiftUI

/// Alicia's own space — how she is doing, what she is thinking about.
struct MindView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        // Her name with her mark beside it — no state card.
                        VStack(spacing: 5) {
                            HStack(spacing: 10) {
                                Image("RabbitMark")
                                    .resizable().scaledToFit()
                                    .frame(width: 26, height: 26)
                                    .foregroundStyle(Theme.ink)
                                Text("Alicia")
                                    .font(.system(size: 30, weight: .semibold, design: .serif))
                                    .foregroundStyle(Theme.ink)
                            }
                            Text("HER INNER WEATHER · \(AppVersion.tag)")
                                .font(.system(size: 10, design: .monospaced))
                                .tracking(2.0)
                                .foregroundStyle(Theme.inkSoft)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 14)

                        ArchetypeGallery()

                        if !store.proactiveFeed.isEmpty {
                            Text("What she's been saying")
                                .font(.headline)
                                .padding(.top, 4)
                            ForEach(store.proactiveFeed) { item in
                                SaidCard(item: item).id(item.id)
                            }
                        }
                        Text("RECENT THINKING")
                            .font(.system(size: 10, design: .monospaced).weight(.semibold))
                            .tracking(2.0)
                            .foregroundStyle(Theme.inkSoft)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 10)
                        ForEach(Array(store.thoughts.enumerated()), id: \.element.id) { i, th in
                            EditorialThought(thought: th, rank: i)
                        }
                    }
                    .padding(16)
                }
                // A Dialogue whisper landed us here — go straight to that
                // exact card (arrival and later taps alike).
                .onAppear { scrollToPending(proxy) }
                .onChange(of: store.pendingMindFocusID) { _, _ in
                    scrollToPending(proxy)
                }
            }
            .refreshable { await store.load() }
            // The face emerging from the grain — her page.
            // Sister field to Us: slow and dense — her inner weather. Seeded
            // by her current archetype, so her page reshapes with her mood.
            .waveBackground(.mind(mood: store.waveMood), tinted: true)
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private func scrollToPending(_ proxy: ScrollViewProxy) {
        guard let id = store.pendingMindFocusID else { return }
        // Give the tab switch one beat to settle before scrolling.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(80))
            withAnimation(.easeInOut(duration: 0.45)) {
                proxy.scrollTo(id, anchor: .top)
            }
            store.pendingMindFocusID = nil
        }
    }

}

struct ThoughtCard: View {
    let thought: Thought
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(thought.tag.uppercased())
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Theme.accentSoft)
                Spacer()
                Text(thought.date, style: .time)
                    .font(.caption2)
                    .foregroundStyle(Theme.inkSoft)
            }
            Text(thought.title).font(.headline)
            Text(thought.body)
                .font(.subheadline)
                .foregroundStyle(Theme.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

/// Small pulsing dot to signal live activity.
struct LiveDot: View {
    @State private var on = false
    var body: some View {
        Circle()
            .fill(Theme.mint)
            .frame(width: 8, height: 8)
            .opacity(on ? 1 : 0.3)
            .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: on)
            .onAppear { on = true }
    }
}

#Preview {
    MindView()
        .environment(AppStore(service: MockAliciaService()))
        .tint(Theme.accent)
        .preferredColorScheme(.dark)
}

/// One proactive message in full — the detail behind Dialogue's whisper
/// line. Long-press to react; reactions feed her circulation loop.
struct SaidCard: View {
    @Environment(AppStore.self) private var store
    let item: ProactiveMessage
    @State private var reacted: String?

    private var label: String {
        [item.kind.replacingOccurrences(of: "_", with: " "), item.archetype]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                HStack(spacing: 5) {
                    Image("RabbitMark")
                        .resizable().scaledToFit()
                        .frame(width: 14, height: 14)
                        .foregroundStyle(Theme.accentSoft)
                    Text(label.isEmpty ? "from her" : label)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Theme.accentSoft)
                }
                Spacer()
                if let reacted { Text(reacted).font(.footnote) }
                Text(item.date, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(Theme.inkSoft)
            }
            Text((try? AttributedString(
                    markdown: item.text.strippedLeadingEmoji,
                    options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
                 ?? AttributedString(item.text.strippedLeadingEmoji))
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .contextMenu {
            ForEach(["❤️", "🔥", "🧠", "👍", "🤔", "👎"], id: \.self) { emoji in
                Button {
                    reacted = emoji
                    Task { await storeReact(emoji) }
                } label: { Text(emoji) }
            }
        }
    }

    private func storeReact(_ emoji: String) async {
        store.reactToProactive(id: item.id, emoji: emoji)
    }
}

/// Co-Star scale-play for her thinking: the freshest thought runs huge and
/// centered; the rest step down through three distinct registers so no two
/// neighbors read the same.
struct EditorialThought: View {
    let thought: Thought
    let rank: Int

    var body: some View {
        Group {
            switch rank % 3 {
            case 0: hero
            case 1: aside
            default: ledger
            }
        }
    }

    /// Register 1 — display: huge centered serif, the day as a headline.
    private var hero: some View {
        VStack(spacing: 10) {
            Text(thought.tag.uppercased())
                .font(.system(size: 9, design: .monospaced).weight(.bold))
                .tracking(2.2)
                .foregroundStyle(Theme.accent)
            Text(thought.title)
                .font(.system(size: rank == 0 ? 30 : 24,
                              weight: .semibold, design: .serif))
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.ink)
            Text(thought.body)
                .font(.system(size: 14, design: .serif))
                .italic()
                .lineSpacing(5)
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.ink.opacity(0.75))
            Theme.stroke.frame(width: 70, height: 1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    /// Register 2 — marginalia: right-aligned, quiet, like a note in the
    /// margin of the page.
    private var aside: some View {
        VStack(alignment: .trailing, spacing: 5) {
            Text(thought.title)
                .font(.system(size: 18, weight: .medium, design: .serif))
                .multilineTextAlignment(.trailing)
            Text(thought.body)
                .font(.system(size: 12, design: .serif))
                .lineSpacing(4)
                .multilineTextAlignment(.trailing)
                .foregroundStyle(Theme.inkSoft)
                .lineLimit(4)
            Text(thought.tag.uppercased())
                .font(.system(size: 8, design: .monospaced))
                .tracking(1.8)
                .foregroundStyle(Theme.accent)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.leading, 60)
    }

    /// Register 3 — ledger: mono date line + serif entry, like an account
    /// of the day, left-set.
    private var ledger: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(thought.date, style: .date)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(Theme.inkSoft)
                Theme.stroke.frame(height: 0.7)
            }
            Text(thought.title)
                .font(.system(size: 16, weight: .semibold, design: .serif))
            Text(thought.body)
                .font(.system(size: 13, design: .serif))
                .lineSpacing(4)
                .foregroundStyle(Theme.ink.opacity(0.8))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.trailing, 40)
    }
}

