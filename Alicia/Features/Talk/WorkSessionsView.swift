import SwiftUI

/// Every spoken session, and exactly where each one is.
///
/// Two corrections from Hector using it on 2026-09-20.
///
/// **It would not scroll.** A2-058 hung a `DragGesture` on every row to get a
/// swipe, and that gesture ate the vertical drag the ScrollView needed. The
/// rows are a `List` now: scrolling and `swipeActions` both come from the
/// platform, and nothing competes for the gesture.
///
/// **"NEEDS YOU 13" was thirteen accidents.** Every real walk had been sent —
/// verified against the Mac — and the thirteen were one-to-fifteen second
/// stubs from pressing the button by mistake. Presenting those as things that
/// need him is how a working pipeline reads as a broken one. They now have
/// their own group, last, named for what they are, with one tap to clear all
/// of them.
struct WorkSessionsView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var opened: AppStore.ReviewedRecording?
    @State private var confirmingSweep = false

    /// Under this a recording holds no thought. His real walks run three to six
    /// minutes; his misfires are a second or two of room noise, and some never
    /// reach the Mac at all.
    private static let misfireSeconds: Double = 20

    private enum Group: String, CaseIterable, Identifiable {
        case needsYou = "NEEDS YOU"
        case working = "ON YOUR MAC"
        case done = "ALICIA HAS THEM"
        case misfire = "NOTHING WAS SAID"
        var id: String { rawValue }

        var blurb: String {
            switch self {
            case .needsYou: "These stalled. Everything else sends itself."
            case .working:  "Being transcribed, then sent on their own."
            case .done:     "Sent, with the original recording still here."
            case .misfire:  "A second or two — the button, not a thought. Safe to clear."
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

    /// A misfire is short AND has no words. A short recording that did produce
    /// a transcript is a real short thought and stays where it belongs.
    private func isMisfire(_ record: VoiceRecording) -> Bool {
        guard record.stage != .sent else { return false }
        return record.duration < Self.misfireSeconds && record.latestWords.count < 200
    }

    private func group(for record: VoiceRecording) -> Group {
        if isMisfire(record) { return .misfire }
        switch record.stage {
        case .sent: return .done
        case .transcribing, .sending, .capturing: return .working
        default: return .needsYou
        }
    }

    private var misfires: [VoiceRecording] { sessions.filter { group(for: $0) == .misfire } }

    var body: some View {
        NavigationStack {
            List {
                header
                ForEach(Group.allCases) { group in
                    let rows = sessions.filter { self.group(for: $0) == group }
                    if !rows.isEmpty {
                        Section {
                            ForEach(rows) { record in
                                row(record, urgent: group == .needsYou)
                                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                        Button("Delete", role: .destructive) { discard(record) }
                                    }
                            }
                        } header: {
                            sectionHead(group, count: rows.count)
                        }
                    }
                }
                footer
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .presenceBackground(.mind, store: store)
            .foregroundStyle(Theme.ink)
            .toolbar(.hidden, for: .navigationBar)
            .task { await store.refreshVoiceArchive() }
            .refreshable { await store.refreshVoiceArchive() }
            .sheet(item: $opened) { target in
                VoiceRecordingsView(recordingID: target.id)
            }
            .confirmationDialog("Clear \(misfires.count) empty recording(s)?",
                                isPresented: $confirmingSweep, titleVisibility: .visible) {
                Button("Clear them", role: .destructive) { misfires.forEach(discard) }
                Button("Keep them", role: .cancel) { }
            } message: {
                Text("These are a second or two each with no words in them. Their audio is deleted; nothing you sent to Alicia is affected.")
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                InkTitleLine(text: "Sessions", size: 27)
                Text("WHAT YOU SAID, AND WHERE IT IS")
                    .font(.system(size: 10, design: .monospaced)).tracking(1.6)
                    .foregroundStyle(Theme.inkSoft)
            }
            Spacer()
            Button("CLOSE") { dismiss() }
                .font(.system(size: 10, design: .monospaced)).tracking(1)
                .frame(minHeight: 44)
                .accessibilityIdentifier("sessions.close")
        }
        .buttonStyle(.plain)
        .padding(.vertical, 8)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private func sectionHead(_ group: Group, count: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(group.rawValue)
                    .font(.system(size: 10, design: .monospaced)).tracking(1.6)
                Text("\(count)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Theme.inkSoft)
                Spacer(minLength: 0)
                if group == .misfire {
                    Button("CLEAR ALL") { confirmingSweep = true }
                        .font(.system(size: 9, design: .monospaced)).tracking(1)
                        .foregroundStyle(Theme.rose)
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("sessions.clearMisfires")
                }
            }
            Text(group.blurb).font(.caption).foregroundStyle(Theme.inkSoft)
        }
        .textCase(nil)
        .foregroundStyle(Theme.ink)
        .padding(.top, 14).padding(.bottom, 2)
        // Match the rows' own inset; a header flush to the screen edge while
        // every row is indented reads as a rendering fault.
        .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
    }

    @ViewBuilder private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
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
            .buttonStyle(.plain)
        }
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private func row(_ record: VoiceRecording, urgent: Bool) -> some View {
        Button { open(record) } label: {
            VStack(alignment: .leading, spacing: 5) {
                Text(subject(record))
                    .font(.system(size: 18, design: .serif))
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
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(Color.clear)
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

    /// Deletes the audio. A reflection already sent keeps its words — deleting
    /// a recording is not a way to unsay something.
    private func discard(_ record: VoiceRecording) {
        Task { await store.deleteOriginalVoice(record.id) }
    }

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
