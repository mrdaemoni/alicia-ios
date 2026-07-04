import SwiftUI

/// Alicia's own space — how she is doing, what she is thinking about.
struct MindView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    stateHeader
                    if !store.proactiveFeed.isEmpty {
                        Text("What she's been saying")
                            .font(.headline)
                            .padding(.top, 4)
                        ForEach(store.proactiveFeed) { SaidCard(item: $0) }
                    }
                    Text("Recent thinking")
                        .font(.headline)
                        .padding(.top, 4)
                    ForEach(store.thoughts) { ThoughtCard(thought: $0) }
                }
                .padding(16)
            }
            .refreshable { await store.load() }
            // The face emerging from the grain — her page.
            .artBackground("ArtFace", opacity: 0.22)
            .navigationTitle("Alicia")
            .toolbarBackground(.hidden, for: .navigationBar)
        }
    }

    private var stateHeader: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image("ArtRabbit")
                    .resizable()
                    .scaledToFill()
                    .frame(width: 56, height: 56)
                    .clipShape(Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text("Present and warm")
                        .font(.title3.weight(.semibold))
                    Text("Working on a new composition")
                        .font(.subheadline)
                        .foregroundStyle(Theme.inkSoft)
                }
                Spacer()
            }
            HStack(spacing: 8) {
                LiveDot()
                Text("Thinking…")
                    .font(.footnote)
                    .foregroundStyle(Theme.inkSoft)
            }
        }
        .card(padding: 18)
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
                    Image("ArtRabbit")
                        .resizable().scaledToFill()
                        .frame(width: 14, height: 14)
                        .clipShape(Circle())
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
                    markdown: item.text,
                    options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
                 ?? AttributedString(item.text))
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
