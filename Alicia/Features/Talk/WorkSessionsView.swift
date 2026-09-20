import SwiftUI

/// Every spoken session, and exactly where each one is.
///
/// Hector's note after the first pass: *"there's a bug there that I don't know
/// how to go back to all the things that are yet to be validated and all the
/// things that have been sent. Maybe we should create an entry point in the
/// Alicia section to have the state of the work sessions, the ones that have
/// been on device and the ones that have been sent for processing and the ones
/// that have been processed."*
///
/// The first pass gave the states one vocabulary and surfaced the single most
/// recent one on the composer band. That is not the same as being able to go
/// and look. This is the place to look: one screen, reachable from Alicia,
/// where the sessions are grouped by what is true of them rather than listed
/// by date, and the group that needs him is first and cannot be missed.
struct WorkSessionsView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var opened: AppStore.ReviewedRecording?

    /// The three questions he was actually asking, in order.
    private enum Group: String, CaseIterable, Identifiable {
        case needsYou = "NEEDS YOU"
        case working = "ON YOUR MAC"
        case done = "ALICIA HAS THEM"
        var id: String { rawValue }

        var blurb: String {
            switch self {
            // Since A2-057 a finished walk sends itself, so this group is no
            // longer the queue his thinking waits in — it is the short list of
            // things that genuinely stalled.
            case .needsYou: "These stalled. Everything else sends itself."
            case .working:  "Being transcribed, then sent on their own."
            case .done:     "Sent, with the original recording still here."
            }
        }

        func holds(_ stage: VoiceRecording.Stage) -> Bool {
            switch self {
            case .needsYou: stage.needsYou
            case .working:  stage == .transcribing || stage == .sending || stage == .capturing
            case .done:     stage == .sent
            }
        }
    }

    /// Private Body originals never appear here. They are not work sessions and
    /// they never leave the phone on their own.
    private var sessions: [VoiceRecording] {
        store.voiceArchive.recordings
            .filter { !$0.deleted && !$0.isPrivateBody }
            .sorted { voiceDate($0.context.started_at) > voiceDate($1.context.started_at) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    SectionHeader(title: "Sessions", kicker: "WHAT YOU SAID, AND WHERE IT IS")
                    if sessions.isEmpty {
                        Text("Nothing spoken yet. A walk, or the microphone on any section, appears here with its state.")
                            .font(.system(size: 20, design: .serif))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    ForEach(Group.allCases) { group in
                        let rows = sessions.filter { group.holds($0.stage) }
                        if !rows.isEmpty {
                            VStack(alignment: .leading, spacing: 14) {
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    Text(group.rawValue)
                                        .font(.system(size: 10, design: .monospaced)).tracking(1.6)
                                    Text("\(rows.count)")
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(Theme.inkSoft)
                                }
                                Text(group.blurb)
                                    .font(.caption).foregroundStyle(Theme.inkSoft)
                                ForEach(rows) { record in
                                    row(record, urgent: group == .needsYou)
                                        .swipeToDelete { discard(record) }
                                }
                            }
                            .accessibilityIdentifier("sessions.group." + group.rawValue)
                        }
                    }
                    if !store.voiceArchive.lastError.isEmpty {
                        Text(store.voiceArchive.lastError)
                            .font(.caption).fixedSize(horizontal: false, vertical: true)
                    }
                    Button(store.voiceArchive.processing || store.voiceArchive.syncing
                           ? "CHECKING YOUR MAC…" : "CHECK YOUR MAC") {
                        Task { await store.refreshVoiceArchive() }
                    }
                    .font(.system(size: 10, design: .monospaced)).tracking(1)
                    .foregroundStyle(Theme.inkSoft).frame(minHeight: 44)
                    .disabled(store.voiceArchive.processing || store.voiceArchive.syncing)
                }
                .padding(22)
            }
            .background(Theme.paper)
            .foregroundStyle(Theme.ink)
            .buttonStyle(.plain)
            .toolbar(.hidden, for: .navigationBar)
            .task { await store.refreshVoiceArchive() }
            .refreshable { await store.refreshVoiceArchive() }
            .sheet(item: $opened) { target in
                VoiceRecordingsView(recordingID: target.id)
            }
        }
    }

    private func row(_ record: VoiceRecording, urgent: Bool) -> some View {
        Button { open(record) } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text(subject(record))
                    .font(.system(size: 19, design: .serif))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(record.stage.label.uppercased())
                    .font(.system(size: 9, design: .monospaced)).tracking(1)
                    .foregroundStyle(urgent ? Theme.ink : Theme.inkSoft)
                Text(record.stage.detail)
                    .font(.caption).foregroundStyle(Theme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(voiceDateLabel(record.context) + " · " + length(record))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Theme.inkSoft)
            }
            .padding(.vertical, 12)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.stroke).frame(height: 0.7) }
        }
        .accessibilityIdentifier("sessions.row")
        .accessibilityLabel(subject(record) + ", " + record.stage.label + ". " + record.stage.detail)
    }

    /// What it was about: the episode when there was one, otherwise the section
    /// he spoke from. Never "a recording" when the app knows better.
    private func subject(_ record: VoiceRecording) -> String {
        let episode = record.context.episode_id
        if !episode.isEmpty {
            let title = record.context.episode_title.strippedEmojis
            return title.isEmpty || title == episode ? episode : episode + " · " + title
        }
        if let surface = record.context.surface_context?.title, !surface.isEmpty {
            return "From " + surface
        }
        return "A spoken thought"
    }

    private func length(_ record: VoiceRecording) -> String {
        let whole = Int(record.duration)
        return whole <= 0 ? "no audio yet" : "\(whole / 60)m \(whole % 60)s"
    }

    /// Throw one away. Hector asked for this after his list filled with
    /// one-second entries from pressing the button by accident:
    /// *"my ability to quickly delete the ones that are bad, like maybe
    /// swiping to the left."*
    ///
    /// This deletes the audio, which is the thing taking up room and the thing
    /// he means by "bad". A reflection already sent to Alicia keeps its words
    /// — deleting a recording is not a way to unsay something, and pretending
    /// otherwise would be worse than not offering it.
    private func discard(_ record: VoiceRecording) {
        Task { await store.deleteOriginalVoice(record.id) }
    }

    /// A session that still needs reviewing reopens where the reviewing
    /// happens; anything else opens its own record.
    private func open(_ record: VoiceRecording) {
        if record.stage.needsYou, record.context.source == "ios_walk" {
            dismiss()
            store.walkRecordingID = record.id
            store.walkEpisodeID = record.context.episode_id
            store.showWalk = true
        } else {
            opened = AppStore.ReviewedRecording(id: record.id)
        }
    }
}

private extension View {
    /// Leading-edge swipe to discard, on a row that is a Button rather than a
    /// List cell. `swipeActions` needs a List; these rows are a VStack, so the
    /// gesture is drawn here — a drag that reveals a word, never a bare icon.
    func swipeToDelete(_ discard: @escaping () -> Void) -> some View {
        modifier(SwipeToDelete(discard: discard))
    }
}

private struct SwipeToDelete: ViewModifier {
    let discard: () -> Void
    @State private var offset: CGFloat = 0
    @State private var gone = false

    private let threshold: CGFloat = -72

    func body(content: Content) -> some View {
        if gone { EmptyView() } else {
            content
                .offset(x: offset)
                .background(alignment: .trailing) {
                    Text("DELETE")
                        .font(.system(size: 10, design: .monospaced)).tracking(1.4)
                        .foregroundStyle(Theme.rose)
                        .opacity(Double(min(1, max(0, offset / threshold))))
                        .padding(.trailing, 6)
                }
                .gesture(
                    DragGesture(minimumDistance: 18)
                        .onChanged { value in
                            // Left only, and it resists past the threshold so
                            // a scroll flick cannot throw a recording away.
                            let raw = min(0, value.translation.width)
                            offset = raw < threshold ? threshold + (raw - threshold) / 4 : raw
                        }
                        .onEnded { _ in
                            if offset <= threshold {
                                withAnimation(.easeIn(duration: 0.18)) { offset = -600; gone = true }
                                discard()
                            } else {
                                withAnimation(.spring(response: 0.3)) { offset = 0 }
                            }
                        }
                )
                .accessibilityAction(named: "Delete this recording") { gone = true; discard() }
        }
    }
}
