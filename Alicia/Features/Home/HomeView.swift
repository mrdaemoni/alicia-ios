import SwiftUI

/// Us — the landing page. Hector's `memories` drawing (the figure before
/// the sea) washes down from the top of the page; beneath it: her greeting,
/// the latest thing she said, what her day held, and a quiet status strip.
struct HomeView: View {
    @Environment(AppStore.self) private var store

    /// Her line, when the backend has one — grounded in what you two are
    /// actually talking about. Time-of-day only as the offline fallback.
    private var greeting: String {
        if let live = store.greeting, !live.isEmpty { return live }
        switch Calendar.current.component(.hour, from: .now) {
        case 5..<12:  return "Good morning, Hector"
        case 12..<18: return "Good afternoon, Hector"
        default:      return "Good evening, Hector"
        }
    }

    /// Her most recent proactive message (the timeline seeds oldest-first).
    private var latestWord: Message? {
        store.messages.last(where: { $0.proactiveLabel != nil })
    }

    private var seasonThought: Thought? {
        store.thoughts.first(where: { $0.tag == "emergence" })
    }

    private var dayThought: Thought? {
        store.thoughts.first(where: { $0.tag != "emergence" })
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header

                    if let track = store.nowPlaying {
                        nowPlayingChip(track)
                    }

                    if let word = latestWord {
                        card(icon: "quote.opening",
                             title: word.proactiveLabel ?? "from Alicia",
                             body: word.text)
                    }

                    if let day = dayThought {
                        card(icon: "sun.horizon.fill",
                             title: day.title,
                             body: day.body)
                    }

                    statusStrip
                }
                .padding(16)
                .padding(.bottom, 24)
            }
            .refreshable { await store.load() }
            .artBackground("ArtMemories", drift: true)
            .navigationTitle("Us")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(greeting)
                .font(.system(.largeTitle, design: .serif, weight: .semibold))
                .foregroundStyle(Theme.ink)
            if let season = seasonThought {
                Text(season.body)
                    .font(.system(.subheadline, design: .serif))
                    .italic()
                    .foregroundStyle(Theme.ink.opacity(0.65))
            } else {
                Text(Date.now.formatted(date: .complete, time: .omitted))
                    .font(.system(.subheadline, design: .serif))
                    .italic()
                    .foregroundStyle(Theme.ink.opacity(0.65))
            }
        }
        // Clear the drawing's focal band before the content begins.
        .padding(.top, 148)
    }

    private func nowPlayingChip(_ track: Track) -> some View {
        HStack(spacing: 10) {
            Image(systemName: store.isPlaying ? "waveform" : "pause.fill")
                .symbolEffect(.variableColor.iterative, isActive: store.isPlaying)
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(Theme.accentGradient, in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(track.title).font(.footnote.weight(.semibold)).lineLimit(1)
                Text(track.mood).font(.caption2).foregroundStyle(Theme.inkSoft).lineLimit(1)
            }
            Spacer()
            Button { store.togglePlay() } label: {
                Image(systemName: store.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.title2)
                    .foregroundStyle(Theme.accentSoft)
            }
        }
        .card(padding: 10, radius: 18)
    }

    private func card(icon: String, title: String, body text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.accentSoft)
                .lineLimit(1)
            Text((try? AttributedString(
                    markdown: text,
                    options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
                 ?? AttributedString(text))
                .font(.subheadline)
                .lineLimit(8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 14, radius: 20)
    }

    private var statusStrip: some View {
        NavigationLink {
            HealthView()
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Status", systemImage: "waveform.path.ecg")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.accentSoft)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(Theme.inkSoft.opacity(0.75))
                }
                ForEach(store.health.prefix(4)) { metric in
                    HStack(spacing: 10) {
                        Image(systemName: metric.symbol)
                            .font(.caption)
                            .foregroundStyle(metric.color)
                            .frame(width: 18)
                        Text(metric.name).font(.caption)
                        Spacer()
                        Text(metric.display)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(Theme.inkSoft)
                        ProgressView(value: metric.value)
                            .tint(metric.color)
                            .frame(width: 64)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card(padding: 14, radius: 20)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    HomeView()
        .environment(AppStore(service: MockAliciaService()))
        .tint(Theme.accent)
        .preferredColorScheme(.dark)
}
