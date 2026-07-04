import SwiftUI

/// The landing tab: a morning-style welcome, the latest thing she said,
/// what her day has looked like, and a glanceable status strip.
struct HomeView: View {
    @Environment(AppStore.self) private var store

    private var greeting: String {
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
            .sectionBackground()
            .navigationTitle("Home")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(greeting)
                .font(.largeTitle.weight(.bold))
            if let season = seasonThought {
                Text(season.body)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text(Date.now.formatted(date: .complete, time: .omitted))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 8)
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
                Text(track.mood).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
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
                        .foregroundStyle(.tertiary)
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
                            .foregroundStyle(.secondary)
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
