import SwiftUI

/// Afternoon and Evening with Alicia on Us, under the morning briefing
/// (CL-20261126-us-day-episodes). Shaped like the morning card: the title is
/// the play control, "Read it" opens the words, "Its playlist" opens Studio's.
/// The owner supplies playback identity and callbacks; this view never
/// fetches, renders or autoplays, and a tap is not a listening receipt.
struct DayEpisodeView: View {
    let episode: DayEpisode
    var playingEpisodeID: String? = nil
    var loadingEpisodeID: String? = nil
    var failedEpisodeID: String? = nil
    var playbackError: String? = nil
    let onTogglePlayback: (DayEpisode) -> Void
    let onOpenPlaylist: (String) -> Void

    @State private var inspected: DayEpisode?

    var body: some View {
        InkSection(kicker: episode.slotName, rule: false, spacing: 10) {
            if episode.hasPlayableAudio {
                DayEpisodePlayButton(episode: episode, isPlaying: playingEpisodeID == episode.id,
                                     isLoading: loadingEpisodeID == episode.id, hasFailed: failedEpisodeID == episode.id,
                                     accessibilityID: "dayEpisode.\(episode.slot).play",
                                     action: { onTogglePlayback(episode) })
                if loadingEpisodeID == episode.id { InkNotice(text: "Loading audio…") }
                if failedEpisodeID == episode.id, let playbackError { InkNotice(text: playbackError, kind: .error) }
            } else {
                if !episode.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(episode.displayTitle.strippedEmojis)
                        .font(.system(size: 19, design: .serif))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                }
                Text(episode.availabilityText()).font(.subheadline).fontDesign(.serif)
                    .foregroundStyle(Theme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("dayEpisode.\(episode.slot).status")
            }
            if episode.hasText {
                HStack(spacing: 18) {
                    Button { inspected = episode } label: {
                        InkLinkLabel(title: "Read it", small: true)
                    }
                    .buttonStyle(.inkLink)
                    .accessibilityIdentifier("dayEpisode.\(episode.slot).read")
                    .accessibilityHint("Opens the full text and its supplied sources. Does not start audio.")
                    if episode.hasPlayableAudio && episode.hasPlaylist {
                        Button { onOpenPlaylist(episode.playlist_id) } label: {
                            InkLinkLabel(title: "Its playlist", small: true)
                        }
                        .buttonStyle(.inkLink)
                        .accessibilityLabel("Open the \(episode.slotName) playlist")
                        .accessibilityIdentifier("dayEpisode.\(episode.slot).playlist")
                    }
                }
            }
        }
        .foregroundStyle(Theme.ink)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sheet(item: $inspected) { item in
            DayEpisodeReading(episode: item, playingEpisodeID: playingEpisodeID, loadingEpisodeID: loadingEpisodeID,
                              failedEpisodeID: failedEpisodeID, playbackError: playbackError,
                              onTogglePlayback: onTogglePlayback, onOpenPlaylist: onOpenPlaylist)
        }
    }
}

private struct DayEpisodePlayButton: View {
    let episode: DayEpisode
    let isPlaying: Bool
    var isLoading = false
    var hasFailed = false
    let accessibilityID: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 13) {
                InkPlayPause(playing: isPlaying, size: 34, color: Theme.ink, ringed: true)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(episode.displayTitle.strippedEmojis)
                        .font(.system(size: 19, design: .serif))
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Text([hasFailed ? "Retry" : isPlaying ? "Pause" : "Listen", episode.durationLabel]
                            .compactMap { $0 }.joined(separator: " · "))
                        .font(InkType.meta.monospacedDigit()).foregroundStyle(Theme.inkSoft)
                }
                Spacer(minLength: 0)
            }
            .frame(minHeight: 48).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(hasFailed ? "Retry" : isPlaying ? "Pause" : "Listen to") \(episode.displayTitle.strippedEmojis)")
        .accessibilityValue("\(hasFailed ? "Audio unavailable" : isLoading ? "Loading audio" : isPlaying ? "Playing" : "Ready"), \(episode.spokenDuration ?? "duration unavailable")")
        .accessibilityHint(isPlaying ? "Pauses this episode." : "Plays the prepared recording when you tap.")
        .accessibilityIdentifier(accessibilityID)
    }
}

private struct DayEpisodeReading: View {
    @Environment(\.dismiss) private var dismiss
    let episode: DayEpisode
    let playingEpisodeID: String?
    let loadingEpisodeID: String?
    let failedEpisodeID: String?
    let playbackError: String?
    let onTogglePlayback: (DayEpisode) -> Void
    let onOpenPlaylist: (String) -> Void
    @State private var showSources = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if episode.hasPlayableAudio {
                        // The title is the play control, as on Us.
                        DayEpisodePlayButton(episode: episode, isPlaying: playingEpisodeID == episode.id,
                                             isLoading: loadingEpisodeID == episode.id,
                                             hasFailed: failedEpisodeID == episode.id,
                                             accessibilityID: "dayEpisode.reading.play",
                                             action: { onTogglePlayback(episode) })
                        if loadingEpisodeID == episode.id { InkNotice(text: "Loading audio…") }
                        if failedEpisodeID == episode.id, let playbackError { InkNotice(text: playbackError, kind: .error) }
                    } else {
                        Text(episode.displayTitle.strippedEmojis).font(.title2).fontDesign(.serif)
                            .accessibilityAddTraits(.isHeader)
                        Text(episode.availabilityText()).font(.subheadline).foregroundStyle(Theme.inkSoft)
                    }
                    Text(episode.text.strippedEmojis).font(.body).fontDesign(.serif)
                        .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("dayEpisode.fullText")
                    if !episode.error.isEmpty {
                        InkNotice(text: episode.error, kind: .error).textSelection(.enabled)
                    }
                    InkDisclosureToggle(title: "Sources · \(episode.sources.count)", open: showSources) { showSources.toggle() }
                        .accessibilityIdentifier("dayEpisode.sources")
                    if showSources {
                        HStack(alignment: .top, spacing: 12) {
                            Rectangle().fill(Theme.stroke).frame(width: 0.7)
                            VStack(alignment: .leading, spacing: 12) {
                                if episode.sources.isEmpty {
                                    InkNotice(text: "No source passages were supplied with this episode.")
                                }
                                ForEach(Array(episode.sources.enumerated()), id: \.offset) { index, source in
                                    if index > 0 { InkRule(opacity: 0.6) }
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
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    if episode.hasPlayableAudio && episode.hasPlaylist {
                        Button {
                            dismiss()
                            onOpenPlaylist(episode.playlist_id)
                        } label: {
                            InkLinkLabel(title: "Its playlist", small: true)
                        }
                        .buttonStyle(.inkLink).accessibilityIdentifier("dayEpisode.reading.playlist")
                    }
                }
                .padding(22)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Theme.paper.ignoresSafeArea()).foregroundStyle(Theme.ink)
            .inkSheetPage(episode.slotName)
        }
    }
}
