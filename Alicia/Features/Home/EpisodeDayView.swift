import SwiftUI

struct EpisodeHomeView: View {
    @Environment(AppStore.self) private var store
    @State private var showHistory = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    // v40: the title is the way in again. Tapping it brings
                    // back what she is holding about him and the whole arc
                    // since she began — unmounted when the old orbit came out
                    // of Us, though both endpoints kept working the whole time.
                    Button { store.showArc = true } label: {
                        SectionHeader(title: "Us", kicker: Date.now.formatted(date: .complete, time: .omitted))
                            .frame(maxWidth: .infinity)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Us — open what she's holding and the whole arc")
                    .accessibilityIdentifier("us.openArc")
                    MorningBriefingView(briefing: store.morningBriefing,
                        playingBriefingID: store.playingMorningBriefingID,
                        loadingBriefingID: store.reader.isLoadingMedia ? store.currentMorningBriefingID : nil,
                        failedBriefingID: store.reader.failure != nil ? store.currentMorningBriefingID : nil,
                        playbackError: store.reader.failure,
                        isRefreshing: store.morningBriefingRefreshing,
                        onTogglePlayback: store.toggleMorningBriefing,
                        onOpenPlaylist: store.openMorningPlaylist,
                        onRefresh: { Task { await store.refreshMorningBriefing() } })
                    MindBodyOverview()
                    // Option A (CL-20260918-context-graph-behaviours): his situation,
                    // above the goals, opening into the room with the whole graph.
                    WhereYouAreSection()
                    NextEpisodeInvitation()
                    InkSection(kicker: "Our shared focus") { CollaborationSummary() }
                    if let day = store.episodeDay, let episode = day.episode {
                        EpisodeHeading(episode: episode)
                        if !day.focus.isEmpty {
                            Text(day.focus.strippedEmojis)
                                .font(.system(size: 25, design: .serif))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        WalkInvitation()
                        if day.frame_status != "ready" {
                            FrameStatus()
                        }
                        if !day.probes.isEmpty {
                            Text(day.frame_status == "ready" ? "STAY WITH THIS" : "EARLIER QUESTIONS")
                                .font(.system(size: 10, design: .monospaced)).tracking(2)
                                .foregroundStyle(Theme.inkSoft)
                            ForEach(day.probes) { probe in
                                VStack(alignment: .leading, spacing: 13) {
                                    Text(probe.question.strippedEmojis)
                                        .font(.system(size: 21, design: .serif))
                                        .fixedSize(horizontal: false, vertical: true)
                                    EpisodePassage(probe: probe)
                                    HStack {
                                        Button("TALK ABOUT THIS") { store.openWalk(probe: probe.question) }
                                            .font(.system(size: 10, design: .monospaced).weight(.semibold)).tracking(1)
                                        Spacer()
                                        ListenLine(item: Readable(title: "", body: probe.question, kind: "thought"))
                                    }
                                    EpisodeFeedback(target: probe.id, verdict: probe.verdict,
                                                    episodeID: episode.id, canCorrect: false)
                                }
                                .padding(.bottom, 18)
                                Rectangle().fill(Theme.stroke).frame(height: 0.7)
                            }
                        }
                        Button("CONTINUE IN DIALOGUE") { store.selectedSection = .dialogue }
                            .font(.system(size: 11, design: .monospaced)).tracking(1.3)
                    } else {
                        if store.collaboration.state?.goals.contains(where: { $0.status == "active" }) == true {
                            Text("An episode can add another perspective.").font(.subheadline).italic()
                            Button("BRING IN AN EPISODE") { store.selectedSection = .studio }
                                .font(.caption.monospaced()).frame(minHeight: 44)
                        } else {
                            InkTitle(text: "Begin with what you hear", size: 32)
                            Text("Play an episode in Studio. Its ideas will be here, ready for your reaction.")
                                .font(.system(size: 20, design: .serif))
                            Button("OPEN STUDIO") { store.selectedSection = .studio }
                                .buttonStyle(EpisodeButtonStyle())
                        }
                        if !store.walkDraft.isEmpty {
                            Button("RETURN TO YOUR REFLECTION") {
                                store.walkEpisodeID = UserDefaults.standard.string(forKey: "alicia.walkEpisodeID") ?? ""
                                store.showWalk = true
                            }
                        }
                    }
                    EpisodeErrorLine()
                    HStack {
                        Button("THE DAYS BEHIND") { showHistory = true }
                        Spacer()
                        NavigationLink("CONNECTION") { HealthView() }
                    }
                    .font(.system(size: 9, design: .monospaced)).tracking(1.4)
                    .foregroundStyle(Theme.inkSoft)
                }
                .padding(22)
                .padding(.bottom, 20)
            }
            .task { await store.refreshMorningBriefing(); await store.bodyStore.refresh() }
            // The graph and its elevation load on their own task so a slow body
            // refresh never holds the section back.
            .task { await store.refreshContextGraph(); await store.refreshContextArrangement(); await store.refreshContextElevation() }
            .refreshable { await store.refreshMorningBriefing(); await store.refreshEpisodeDay(); await store.bodyStore.refresh(); await store.refreshContextGraph(); await store.refreshContextArrangement(); await store.refreshContextElevation() }
            .presenceBackground(.us, store: store)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showHistory) { EpisodeHistoryView() }
        }
    }
}

struct EpisodePassage: View {
    let probe: EpisodeDay.Probe
    @State private var expanded = false
    var body: some View {
        InkDisclosure("From the episode") {
            Text(probe.anchor.strippedEmojis).font(.subheadline).italic()
            Text(probe.source_path).font(.caption2).foregroundStyle(Theme.inkSoft)
            ListenLine(item: Readable(title: "From the episode", body: probe.anchor, kind: "thought"))
        }
    }
}

struct EpisodeHeading: View {
    @Environment(AppStore.self) private var store
    let episode: EpisodeDay.Episode
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(episode.title.strippedEmojis)
                .font(.system(size: 17, design: .serif)).italic()
            Text((store.episodeDay?.has_playback == false ? "Chosen in Studio · " : "In our ears · ") + episode.id)
                .font(InkType.meta).foregroundStyle(Theme.inkSoft)
        }
        .accessibilityElement(children: .combine)
    }
}

struct WalkInvitation: View {
    @Environment(AppStore.self) private var store
    var body: some View {
        Button { store.openWalk() } label: {
            VStack(alignment: .leading, spacing: 9) {
                Text(store.walkDraft.isEmpty || store.walkEpisodeID != store.episodeDay?.episode?.id ? "Walk with this" : "Return to your reflection")
                    .font(.system(size: 23, design: .serif))
                HStack {
                    Text("I'll listen. We can reflect when you're ready.")
                        .font(.system(size: 15, design: .serif)).italic()
                    Spacer(minLength: 8)
                    InkChevron(pointing: .right, size: 14, color: Theme.inkSoft, seed: 17)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(Theme.ink)
            .card(padding: 18, radius: 16)
        }
        .buttonStyle(.inkLink)
        .accessibilityIdentifier("episode.walk")
    }
}

/// Kept as a name for older call sites; it is the primary action now.
struct EpisodeButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        InkButtonStyle(role: .primary).makeBody(configuration: configuration)
    }
}

struct FrameStatus: View {
    @Environment(AppStore.self) private var store
    @State private var retrying = false
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(store.episodeDay?.frame_status == "unavailable"
                 ? "I couldn't prepare the questions. You can still think aloud, or try again."
                 : "The episode is in our frame. The questions are being updated from it and your words.")
                .font(.subheadline).italic().foregroundStyle(Theme.inkSoft)
            Button(retrying ? "PREPARING…" : "REFRESH QUESTIONS") {
                retrying = true
                Task {
                    _ = await store.episodeAction("refresh")
                    retrying = false
                }
            }
            .buttonStyle(.inkQuiet)
            .disabled(retrying)
        }
    }
}

struct EpisodeErrorLine: View {
    @Environment(AppStore.self) private var store
    var body: some View {
        if !store.episodeError.isEmpty {
            InkNotice(text: store.episodeError, kind: .error)
                .accessibilityIdentifier("episode.error")
        }
    }
}

struct EpisodeFeedback: View {
    @Environment(AppStore.self) private var store
    let target: String
    let verdict: String
    let episodeID: String
    var canCorrect = true
    @State private var showCorrection = false
    @State private var correction = ""
    @State private var receiptID = UUID().uuidString
    @State private var receiptIdentity = ""
    @State private var saving = false
    @State private var confirmed = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                feedback("This helps", value: "good")
                feedback("Go deeper", value: "deeper")
                feedback("Missed me", value: "miss")
            }
            if canCorrect {
                Button { showCorrection = true } label: { InkLinkLabel(title: "Correct this reading", small: true) }
                    .buttonStyle(.inkLink)
            }
            InkNotice(text: confirmed, kind: .success)
        }
        .disabled(saving)
        .sheet(isPresented: $showCorrection) {
            NavigationStack {
                VStack(alignment: .leading, spacing: 20) {
                    Text("What should I understand differently?").font(.title2)
                    TextEditor(text: $correction).frame(minHeight: 150)
                        .scrollContentBackground(.hidden).disabled(saving).inkField()
                    EpisodeErrorLine()
                    Button(saving ? "SAVING…" : "SAVE MY CORRECTION") {
                        let identity = "correction|" + target + "|" + correction
                        if receiptIdentity != identity { receiptID = UUID().uuidString; receiptIdentity = identity }
                        saving = true
                        Task {
                            if await store.episodeAction("correction", text: correction, target: target,
                                                         verdict: "corrected", episodeID: episodeID, eventID: receiptID) {
                                confirmed = "Your correction is saved. It will shape the next response."
                                showCorrection = false
                                correction = ""
                                receiptID = UUID().uuidString
                            }
                            saving = false
                        }
                    }
                    .buttonStyle(.inkPrimary)
                    .disabled(correction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || saving)
                }
                .padding(22).background(Theme.paper)
                .inkSheetPage("Correct this reading") { showCorrection = false }
            }
        }
    }

    private func feedback(_ label: String, value: String) -> some View {
        WorkReviewChoice(title: label, selected: verdict == value, compact: true) {
            let identity = "feedback|" + target + "|" + value
            if receiptIdentity != identity { receiptID = UUID().uuidString; receiptIdentity = identity }
            saving = true
            Task {
                if await store.episodeAction("feedback", target: target, verdict: value,
                                             episodeID: episodeID, eventID: receiptID) {
                    confirmed = value == "miss" ? "I've kept that this missed you." : "Your feedback is saved."
                    receiptID = UUID().uuidString
                }
                saving = false
            }
        }
    }
}

struct EpisodeMindView: View {
    @Environment(AppStore.self) private var store
    @AppStorage("alicia.learningDraft") private var learning = ""
    @State private var receiptID = UUID().uuidString
    @State private var receiptIdentity = ""
    @State private var saving = false
    @State private var showHistory = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    SectionHeader(title: "Alicia", kicker: "WHAT I'M HOLDING WITH YOU")
                    InkSection(kicker: "Our shared focus", rule: false) { CollaborationSummary() }
                    if let day = store.episodeDay, let episode = day.episode {
                        InkSection(kicker: "What I'm holding") {
                            EpisodeHeading(episode: episode)
                            if !day.understanding.isEmpty {
                                Text(day.understanding.strippedEmojis)
                                    .font(.system(size: 23, design: .serif))
                                    .fixedSize(horizontal: false, vertical: true)
                                Text(["miss", "corrected"].contains(day.frame_verdict)
                                     ? "You corrected this reading. Your words take precedence while I update it."
                                     : day.reactions.isEmpty ? "A starting point, before your reaction." : "My reading of your words. You can change it.")
                                    .font(.caption).italic().foregroundStyle(Theme.inkSoft)
                                ListenLine(item: Readable(title: "What I'm holding", body: day.understanding, kind: "thought"))
                                EpisodeFeedback(target: day.frame_id, verdict: day.frame_verdict, episodeID: episode.id)
                            }
                            if day.frame_status != "ready" { FrameStatus() }
                        }
                        InkSection(kicker: "Your words") {
                            if let last = day.reactions.last {
                                Text(last.text.strippedEmojis).font(InkType.body)
                                ListenLine(item: Readable(title: "Your reflection", body: last.text, kind: "thought"))
                            } else {
                                WalkInvitation()
                            }
                            ForEach(day.corrections) { entry in
                                VStack(alignment: .leading, spacing: 6) {
                                    InkKicker(text: "You corrected")
                                    Text(entry.text.strippedEmojis).font(InkType.body)
                                }
                            }
                        }
                        InkSection(kicker: "What you keep") {
                            Text("What do you want to keep?").font(InkType.subhead)
                            Text("A learning becomes yours here when you choose it.")
                                .font(.subheadline).italic().foregroundStyle(Theme.inkSoft)
                            TextField("In your own words…", text: $learning, axis: .vertical)
                                .lineLimit(3...8).disabled(saving).inkField()
                            Button(saving ? "Saving…" : "Keep this learning") {
                                let identity = episode.id + "|" + learning
                                if receiptIdentity != identity { receiptID = UUID().uuidString; receiptIdentity = identity }
                                saving = true
                                Task {
                                    if await store.episodeAction("learning", text: learning, eventID: receiptID) {
                                        learning = ""
                                        receiptID = UUID().uuidString
                                    }
                                    saving = false
                                }
                            }
                            .buttonStyle(.inkPrimary)
                            .disabled(saving || learning.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            ForEach(day.learnings) { entry in
                                VStack(alignment: .leading, spacing: 8) {
                                    InkRule(opacity: 0.6)
                                    Text(entry.text.strippedEmojis).font(InkType.body)
                                    ListenLine(item: Readable(title: "What you kept", body: entry.text, kind: "thought"))
                                }
                            }
                        }
                    } else {
                        InkSection(kicker: "What I'm holding") {
                            Text("Once you've listened, this is where we'll hold your reaction and what you want to keep.")
                                .font(InkType.subhead)
                            Button { store.selectedSection = .studio } label: { InkLinkLabel(title: "Choose an episode in Studio") }
                                .buttonStyle(.inkLink)
                        }
                    }
                    EpisodeErrorLine()
                    InkSection(kicker: "Around you", spacing: 4) {
                        NavigationLink { ContextEnrichmentView() } label: {
                            InkLinkLabel(title: "About you", detail: "What she knows about you, open to your corrections")
                        }.buttonStyle(.inkLink)
                        InkRule(opacity: 0.6)
                        NavigationLink { ContextGraphRoom() } label: {
                            InkLinkLabel(title: "In the middle of", detail: "Your situation as she holds it today")
                        }.buttonStyle(.inkLink).accessibilityIdentifier("alicia.contextGraph.open")
                        InkRule(opacity: 0.6)
                        WorkSessionsEntry()
                        InkRule(opacity: 0.6)
                        Button { showHistory = true } label: {
                            InkLinkLabel(title: "Your days & learnings", detail: "Every day's reading, your words and what you kept")
                        }.buttonStyle(.inkLink)
                        InkRule(opacity: 0.6)
                        Button { store.selectedSection = .dialogue } label: {
                            InkLinkLabel(title: "Continue in Dialogue", detail: "Talk it through with her")
                        }.buttonStyle(.inkLink)
                    }
                    InkSection(kicker: "Where you are") { PlaceAwareness() }
                    Text(AppVersion.tag).font(.system(size: 9, design: .monospaced)).foregroundStyle(Theme.inkSoft)
                }
                .padding(22)
            }
            .refreshable { await store.refreshEpisodeDay() }
            .presenceBackground(.mind, store: store)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showHistory) { EpisodeHistoryView() }
        }
    }
}

struct EpisodeHistoryView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var selected: EpisodeDay?
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Your days").font(.largeTitle)
                    Text("The episodes, your reactions, and what you chose to keep.").font(.subheadline).italic()
                    ForEach(store.episodeDay?.days ?? [], id: \.self) { date in
                        Button(date) { Task { selected = await store.loadEpisodeDay(date) } }
                            .font(.system(size: 15, design: .monospaced))
                    }
                    if let day = selected {
                        Text(day.date).font(.title2)
                        Text(day.episodes.joined(separator: " · ")).font(.caption)
                        ForEach(day.reactions + day.learnings + day.corrections) { entry in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(entry.kind.uppercased()).font(.system(size: 9, design: .monospaced)).tracking(1.3)
                                Text(entry.text.strippedEmojis)
                                ListenLine(item: Readable(title: "", body: entry.text, kind: "thought"))
                            }
                        }
                    }
                }.padding(22)
            }
            .background(Theme.paper)
            .toolbar { Button("Close") { dismiss() } }
        }
    }
}

/// The way in to every spoken session and its state. It lives in Alicia
/// because that is where the work she is doing with his words belongs, and it
/// carries its own count so the number waiting on him is visible without
/// opening anything.
struct WorkSessionsEntry: View {
    @Environment(AppStore.self) private var store
    @State private var open = false

    /// Only real sessions count. A one-second misfire is not something
    /// waiting for him, and counting it here is what made a working pipeline
    /// read as thirteen lost walks.
    private var waiting: Int {
        store.voiceArchive.recordings
            .filter { !$0.deleted && !$0.isPrivateBody && $0.stage.needsYou && !$0.isMisfire }.count
    }
    private var total: Int {
        store.voiceArchive.recordings.filter { !$0.deleted && !$0.isPrivateBody }.count
    }

    var body: some View {
        Button { open = true } label: {
            HStack(spacing: 10) {
                if waiting > 0 { Circle().fill(Theme.amber).frame(width: 7, height: 7) }
                InkLinkLabel(title: "Your spoken sessions",
                             detail: waiting > 0 ? "\(waiting) waiting for you · \(total) in all"
                                : total > 0 ? "\(total) recorded · none waiting on you" : "Nothing spoken yet")
            }
        }
        .buttonStyle(.inkLink)
        .accessibilityIdentifier("sessions.open")
        .accessibilityLabel(waiting > 0
            ? "Your spoken sessions, \(waiting) waiting for you"
            : "Your spoken sessions")
        .sheet(isPresented: $open) { WorkSessionsView() }
    }
}

/// Where Alicia thinks he is, and the one place he grants or refuses it.
///
/// The permission prompt is raised from here rather than at launch, so the
/// system dialog arrives attached to a sentence explaining why. What she is
/// told is shown verbatim — a city and whether that is home, the office or
/// away — because a location feature he cannot inspect is one he cannot trust.
struct PlaceAwareness: View {
    @State private var tracker = PlaceTracker.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(tracker.summary)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("place.summary")
            switch tracker.authorization {
            case .notDetermined:
                Text("She's told the city and whether it's home, the office or away — never a coordinate.")
                    .font(.caption).foregroundStyle(Theme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Let Alicia know where I am") { tracker.requestAccess() }
                    .buttonStyle(.inkSecondaryCompact)
                    .padding(.top, 4)
                    .accessibilityIdentifier("place.grant")
            case .denied, .restricted:
                Text("Turn it on in Settings if you want her to know. Everything else works without it.")
                    .font(.caption).foregroundStyle(Theme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            default:
                EmptyView()
            }
        }
        .task { tracker.begin() }
    }
}
