import SwiftUI

/// Elevated on Us before episode selection. The owner supplies exact playback
/// identity and callbacks; this component never fetches, renders or autoplays.
struct MorningBriefingView: View {
    let briefing: MorningBriefing?
    var playingBriefingID: String? = nil
    var isRefreshing = false
    let onTogglePlayback: (MorningBriefing) -> Void
    let onOpenPlaylist: (String) -> Void
    var onRefresh: (() -> Void)? = nil

    @State private var inspectedBriefing: MorningBriefing?

    var body: some View {
        // Date honesty survives leaving Us visible through midnight. This is a
        // clock update, with no animation or activity indicator.
        TimelineView(.periodic(from: .now, by: 60)) { clock in
            VStack(alignment: .leading, spacing: 14) {
                Text("MORNING BRIEFING")
                    .font(.caption.monospaced()).tracking(1.5)
                    .foregroundStyle(Theme.accent)
                if let briefing {
                    MorningBriefingDate(briefing: briefing, now: clock.date)
                    Text(briefing.displayTitle.strippedEmojis)
                        .font(.title2).fontDesign(.serif)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    if briefing.hasPlayableAudio {
                        playbackButton(briefing)
                    } else {
                        Text(briefing.availabilityText).font(.body).fontDesign(.serif)
                            .foregroundStyle(Theme.inkSoft)
                            .accessibilityIdentifier("morningBriefing.status")
                    }
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 18) { inspectButton(briefing); playlistButton(briefing) }
                        VStack(alignment: .leading, spacing: 0) { inspectButton(briefing); playlistButton(briefing) }
                    }
                    if !briefing.hasPlayableAudio || briefing.dayRelation(to: clock.date) != .today {
                        refreshButton
                    }
                } else {
                    Text(clock.date.formatted(date: .complete, time: .omitted))
                        .font(.caption).foregroundStyle(Theme.inkSoft)
                    Text("Your morning briefing")
                        .font(.title2).fontDesign(.serif).accessibilityAddTraits(.isHeader)
                    Text("The briefing hasn't loaded yet.")
                        .font(.body).fontDesign(.serif).foregroundStyle(Theme.inkSoft)
                        .accessibilityIdentifier("morningBriefing.status")
                    refreshButton
                }
            }
        }
        .foregroundStyle(Theme.ink)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 18)
        .overlay(alignment: .top) { Rectangle().fill(Theme.stroke).frame(height: 0.7) }
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.stroke).frame(height: 0.7) }
        .sheet(item: $inspectedBriefing) { inspected in
            MorningBriefingReading(briefing: inspected, playingBriefingID: playingBriefingID,
                                   onTogglePlayback: onTogglePlayback, onOpenPlaylist: onOpenPlaylist)
        }
    }

    private func playbackButton(_ item: MorningBriefing) -> some View {
        MorningBriefingPlayButton(briefing: item, isPlaying: playingBriefingID == item.id,
                                 action: { onTogglePlayback(item) })
    }

    private func inspectButton(_ item: MorningBriefing) -> some View {
        Button { inspectedBriefing = item } label: {
            Text(item.hasText ? "READ THE BRIEFING" : "VIEW DETAILS")
                .font(.caption.monospaced()).tracking(0.5)
                .frame(minHeight: 44, alignment: .leading).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("morningBriefing.read")
        .accessibilityHint("Opens the full text and its supplied sources. Does not start audio.")
    }

    @ViewBuilder private func playlistButton(_ item: MorningBriefing) -> some View {
        if item.hasPlaylist {
            Button { onOpenPlaylist(item.playlist_id) } label: {
                Text("IN STUDIO").font(.caption.monospaced()).tracking(0.5)
                    .frame(minHeight: 44, alignment: .leading).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open this briefing's playlist in Studio")
            .accessibilityIdentifier("morningBriefing.playlist")
        }
    }

    @ViewBuilder private var refreshButton: some View {
        if let onRefresh {
            Button(action: onRefresh) {
                Text(isRefreshing ? "CHECKING…" : "CHECK AGAIN")
                    .font(.caption.monospaced()).tracking(0.5)
                    .frame(minHeight: 44, alignment: .leading).contentShape(Rectangle())
            }
            .buttonStyle(.plain).disabled(isRefreshing)
            .accessibilityIdentifier("morningBriefing.refresh")
            .accessibilityHint("Checks for an already prepared briefing.")
        }
    }
}

private struct MorningBriefingDate: View {
    let briefing: MorningBriefing
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(briefing.dateLabel()).font(.caption)
                .accessibilityIdentifier("morningBriefing.date")
            switch briefing.dayRelation(to: now) {
            case .earlier:
                Text("From an earlier day.")
                    .font(.caption).italic().accessibilityIdentifier("morningBriefing.stale")
            case .later:
                Text("Dated for a later day.").font(.caption).italic()
                    .accessibilityIdentifier("morningBriefing.stale")
            case .unknown:
                Text("This briefing's day couldn't be verified.").font(.caption).italic()
            case .today: EmptyView()
            }
        }
        .foregroundStyle(Theme.inkSoft)
    }
}

private struct MorningBriefingPlayButton: View {
    let briefing: MorningBriefing
    let isPlaying: Bool
    var accessibilityID = "morningBriefing.play"
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 13) {
                InkPlayPause(playing: isPlaying, size: 34, color: Theme.ink, ringed: true)
                    .accessibilityHidden(true)
                Text(isPlaying ? "Pause" : "Listen")
                    .font(.title3).fontDesign(.serif)
                Spacer(minLength: 8)
                if let duration = briefing.durationLabel {
                    Text(duration).font(.body.monospacedDigit())
                }
            }
            .frame(minHeight: 48).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(isPlaying ? "Pause" : "Listen to") \(briefing.displayTitle.strippedEmojis)")
        .accessibilityValue("\(isPlaying ? "Playing" : "Ready"), \(briefing.spokenDuration ?? "duration unavailable")")
        .accessibilityHint(isPlaying ? "Pauses this briefing." : "Plays the prepared recording when you tap.")
        .accessibilityIdentifier(accessibilityID)
    }
}

private struct MorningBriefingReading: View {
    @Environment(\.dismiss) private var dismiss
    let briefing: MorningBriefing
    let playingBriefingID: String?
    let onTogglePlayback: (MorningBriefing) -> Void
    let onOpenPlaylist: (String) -> Void
    @State private var showSources = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    TimelineView(.periodic(from: .now, by: 60)) { clock in
                        MorningBriefingDate(briefing: briefing, now: clock.date)
                    }
                    Text(briefing.displayTitle.strippedEmojis).font(.title2).fontDesign(.serif)
                        .accessibilityAddTraits(.isHeader)
                    if briefing.hasPlayableAudio {
                        MorningBriefingPlayButton(briefing: briefing, isPlaying: playingBriefingID == briefing.id,
                                                 accessibilityID: "morningBriefing.reading.play",
                                                 action: { onTogglePlayback(briefing) })
                    } else {
                        Text(briefing.availabilityText).font(.subheadline).foregroundStyle(Theme.inkSoft)
                    }
                    if briefing.hasText {
                        Text(briefing.text.strippedEmojis).font(.body).fontDesign(.serif)
                            .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("morningBriefing.fullText")
                    } else {
                        Text("The text isn't available yet.").font(.body).italic()
                    }
                    Button { showSources.toggle() } label: {
                        Text(showSources ? "HIDE SOURCES" : "SOURCES · \(briefing.sources.count)")
                            .font(.caption.monospaced()).frame(minHeight: 44).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityValue(showSources ? "Expanded" : "Collapsed")
                    .accessibilityIdentifier("morningBriefing.sources")
                    if showSources {
                        if briefing.sources.isEmpty {
                            Text("No source passages were supplied with this briefing.")
                                .font(.subheadline).foregroundStyle(Theme.inkSoft)
                        }
                        ForEach(Array(briefing.sources.enumerated()), id: \.offset) { _, source in
                            VStack(alignment: .leading, spacing: 8) {
                                if let title = source.title, !title.isEmpty {
                                    Text(title.strippedEmojis).font(.headline).fontDesign(.serif)
                                }
                                if let excerpt = source.excerpt, !excerpt.isEmpty {
                                    Text(excerpt.strippedEmojis).font(.body).fontDesign(.serif).textSelection(.enabled)
                                }
                                if let path = source.path, !path.isEmpty {
                                    Text(path).font(.caption).foregroundStyle(Theme.inkSoft).textSelection(.enabled)
                                }
                                if [source.title, source.excerpt, source.path].allSatisfy({ ($0 ?? "").isEmpty }) {
                                    Text("Source details weren't supplied.").font(.subheadline)
                                        .foregroundStyle(Theme.inkSoft)
                                }
                            }
                        }
                    }
                    if !briefing.error.isEmpty {
                        Text(briefing.error.strippedEmojis).font(.caption).foregroundStyle(Theme.inkSoft)
                            .textSelection(.enabled)
                    }
                    if briefing.hasPlaylist {
                        Button {
                            dismiss()
                            onOpenPlaylist(briefing.playlist_id)
                        } label: {
                            Text("OPEN PLAYLIST IN STUDIO").font(.caption.monospaced())
                                .frame(minHeight: 44).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain).accessibilityIdentifier("morningBriefing.reading.playlist")
                    }
                }
                .padding(22)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Theme.paper.ignoresSafeArea()).foregroundStyle(Theme.ink)
            .navigationTitle("Morning briefing").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Close") { dismiss() }.frame(minWidth: 44, minHeight: 44)
                }
            }
        }
    }
}
