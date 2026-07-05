import SwiftUI

/// Alicia's own space — how she is doing, what she is thinking about.
struct MindView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        SectionHeader(title: "Alicia", kicker: "her inner weather")
                        // Build tag — so the phone build is identifiable at a
                        // glance. Bumped on every shipped app change.
                        Text("\(AppVersion.tag) · \(AppVersion.date)")
                            .font(.caption2.monospaced())
                            .foregroundStyle(Theme.inkSoft.opacity(0.8))
                            .padding(.top, -6)
                        stateHeader
                        if !store.proactiveFeed.isEmpty {
                            Text("What she's been saying")
                                .font(.headline)
                                .padding(.top, 4)
                            ForEach(store.proactiveFeed) { item in
                                SaidCard(item: item).id(item.id)
                            }
                        }
                        Text("Recent thinking")
                            .font(.headline)
                            .padding(.top, 4)
                        ForEach(store.thoughts) { ThoughtCard(thought: $0) }
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
            .waveBackground(.mind(mood: store.waveMood))
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

    private var stateHeader: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                // Her mark — the rabbit silhouette on the sea-slate circle.
                ZStack {
                    Circle().fill(Theme.accentGradient).frame(width: 56, height: 56)
                    Image("RabbitMark")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 32, height: 32)
                        .foregroundStyle(.white)
                }
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
