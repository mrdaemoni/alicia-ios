import SwiftUI

/// Elevated on Us before episode selection. The owner supplies exact playback
/// identity and callbacks; this component never fetches, renders or autoplays.
struct MorningBriefingView: View {
    let briefing: MorningBriefing?
    var playingBriefingID: String? = nil
    var loadingBriefingID: String? = nil
    var failedBriefingID: String? = nil
    var playbackError: String? = nil
    var isRefreshing = false
    let onTogglePlayback: (MorningBriefing) -> Void
    let onOpenPlaylist: (String) -> Void
    var onRefresh: (() -> Void)? = nil

    @State private var inspectedBriefing: MorningBriefing?

    var body: some View {
        // Date honesty survives leaving Us visible through midnight. This is a
        // clock update, with no animation or activity indicator.
        TimelineView(.periodic(from: .now, by: 60)) { clock in
            // Build 35 on the phone, 2026-09-27: the kicker said "Morning
            // briefing", then the date (already under the page title), then a
            // heading saying "morning briefing" again. One kicker, the title as
            // the thing you tap to listen, and the date only when it isn't today.
            InkSection(kicker: "Morning briefing", rule: false, spacing: 10) {
                if let briefing {
                    if briefing.dayRelation(to: clock.date) != .today {
                        MorningBriefingDate(briefing: briefing, now: clock.date)
                    }
                    if briefing.hasPlayableAudio {
                        playbackButton(briefing)
                        if loadingBriefingID == briefing.id { InkNotice(text: "Loading audio…") }
                        if failedBriefingID == briefing.id, let playbackError { InkNotice(text: playbackError, kind: .error) }
                    } else {
                        Text(briefing.displayTitle.strippedEmojis)
                            .font(.system(size: 19, design: .serif))
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)
                        Text(briefing.availabilityText).font(.subheadline).fontDesign(.serif)
                            .foregroundStyle(Theme.inkSoft)
                            .accessibilityIdentifier("morningBriefing.status")
                    }
                    HStack(spacing: 18) {
                        inspectButton(briefing)
                        playlistButton(briefing)
                    }
                    if !briefing.hasPlayableAudio || briefing.dayRelation(to: clock.date) != .today {
                        refreshButton
                    }
                } else {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Not ready yet.")
                            .font(.subheadline).italic().foregroundStyle(Theme.inkSoft)
                            .accessibilityIdentifier("morningBriefing.status")
                        Spacer(minLength: 8)
                        refreshButton
                    }
                }
            }
        }
        .foregroundStyle(Theme.ink)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sheet(item: $inspectedBriefing) { inspected in
            MorningBriefingReading(briefing: inspected, playingBriefingID: playingBriefingID,
                                   loadingBriefingID: loadingBriefingID, failedBriefingID: failedBriefingID, playbackError: playbackError,
                                   onTogglePlayback: onTogglePlayback, onOpenPlaylist: onOpenPlaylist)
        }
    }

    private func playbackButton(_ item: MorningBriefing) -> some View {
        MorningBriefingPlayButton(briefing: item, isPlaying: playingBriefingID == item.id,
                                 isLoading: loadingBriefingID == item.id, hasFailed: failedBriefingID == item.id,
                                 action: { onTogglePlayback(item) })
    }

    private func inspectButton(_ item: MorningBriefing) -> some View {
        Button { inspectedBriefing = item } label: {
            InkLinkLabel(title: item.hasText ? "Read it" : "Details", small: true)
        }
        .buttonStyle(.inkLink)
        .accessibilityIdentifier("morningBriefing.read")
        .accessibilityHint("Opens the full text and its supplied sources. Does not start audio.")
    }

    @ViewBuilder private func playlistButton(_ item: MorningBriefing) -> some View {
        if item.hasPlaylist {
            Button { onOpenPlaylist(item.playlist_id) } label: {
                InkLinkLabel(title: "Its playlist", small: true)
            }
            .buttonStyle(.inkLink)
            .accessibilityLabel("Open this briefing's playlist in Studio")
            .accessibilityIdentifier("morningBriefing.playlist")
        }
    }

    @ViewBuilder private var refreshButton: some View {
        if let onRefresh {
            Button(isRefreshing ? "Checking…" : "Check again", action: onRefresh)
            .buttonStyle(.inkQuiet).disabled(isRefreshing)
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
    var isLoading = false
    var hasFailed = false
    var accessibilityID = "morningBriefing.play"
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 13) {
                InkPlayPause(playing: isPlaying, size: 34, color: Theme.ink, ringed: true)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(briefing.displayTitle.strippedEmojis)
                        .font(.system(size: 19, design: .serif))
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Text([hasFailed ? "Retry" : isPlaying ? "Pause" : "Listen", briefing.durationLabel]
                            .compactMap { $0 }.joined(separator: " · "))
                        .font(InkType.meta.monospacedDigit()).foregroundStyle(Theme.inkSoft)
                }
                Spacer(minLength: 0)
            }
            .frame(minHeight: 48).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(hasFailed ? "Retry" : isPlaying ? "Pause" : "Listen to") \(briefing.displayTitle.strippedEmojis)")
        .accessibilityValue("\(hasFailed ? "Audio unavailable" : isLoading ? "Loading audio" : isPlaying ? "Playing" : "Ready"), \(briefing.spokenDuration ?? "duration unavailable")")
        .accessibilityHint(isPlaying ? "Pauses this briefing." : "Plays the prepared recording when you tap.")
        .accessibilityIdentifier(accessibilityID)
    }
}

private struct MorningBriefingReading: View {
    @Environment(\.dismiss) private var dismiss
    let briefing: MorningBriefing
    let playingBriefingID: String?
    let loadingBriefingID: String?
    let failedBriefingID: String?
    let playbackError: String?
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
                    if !briefing.hasPlayableAudio {
                        Text(briefing.displayTitle.strippedEmojis).font(.title2).fontDesign(.serif)
                            .accessibilityAddTraits(.isHeader)
                    }
                    if briefing.hasPlayableAudio {
                        // The title is the play control, as on Us.
                        MorningBriefingPlayButton(briefing: briefing, isPlaying: playingBriefingID == briefing.id,
                                                 isLoading: loadingBriefingID == briefing.id, hasFailed: failedBriefingID == briefing.id,
                                                 accessibilityID: "morningBriefing.reading.play",
                                                 action: { onTogglePlayback(briefing) })
                        if loadingBriefingID == briefing.id { InkNotice(text: "Loading audio…") }
                        if failedBriefingID == briefing.id, let playbackError { InkNotice(text: playbackError, kind: .error) }
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
                    if !briefing.error.isEmpty {
                        InkNotice(text: briefing.error, kind: .error)
                            .textSelection(.enabled)
                    }
                    InkDisclosureToggle(title: "Sources · \(briefing.sources.count)",
                                        open: showSources) { showSources.toggle() }
                        .accessibilityIdentifier("morningBriefing.sources")
                    if showSources {
                        HStack(alignment: .top, spacing: 12) {
                            Rectangle().fill(Theme.stroke).frame(width: 0.7)
                            VStack(alignment: .leading, spacing: 12) {
                                if briefing.sources.isEmpty {
                                    InkNotice(text: "No source passages were supplied with this briefing.")
                                }
                                ForEach(Array(briefing.sources.enumerated()), id: \.offset) { index, source in
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
                    if briefing.hasPlaylist {
                        Button {
                            dismiss()
                            onOpenPlaylist(briefing.playlist_id)
                        } label: {
                            InkLinkLabel(title: "Its playlist", small: true)
                        }
                        .buttonStyle(.inkLink).accessibilityIdentifier("morningBriefing.reading.playlist")
                    }
                }
                .padding(22)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Theme.paper.ignoresSafeArea()).foregroundStyle(Theme.ink)
            .inkSheetPage("Morning briefing")
        }
    }
}
