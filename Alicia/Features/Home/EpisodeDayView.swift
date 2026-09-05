import SwiftUI

struct EpisodeHomeView: View {
    @Environment(AppStore.self) private var store
    @State private var showHistory = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    SectionHeader(title: "Us", kicker: Date.now.formatted(date: .complete, time: .omitted))
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
                            Text("STAY WITH THIS")
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
                        InkTitle(text: "Begin with what you hear", size: 32)
                        Text("Play an episode in Studio. Its ideas will be here, ready for your reaction.")
                            .font(.system(size: 20, design: .serif))
                        Button("OPEN STUDIO") { store.selectedSection = .studio }
                            .buttonStyle(EpisodeButtonStyle())
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
            .refreshable { await store.refreshEpisodeDay() }
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
        VStack(alignment: .leading, spacing: 10) {
            Button(expanded ? "HIDE THE PASSAGE" : "FROM THE EPISODE") { expanded.toggle() }
                .font(.system(size: 9, design: .monospaced)).tracking(1)
                .accessibilityValue(expanded ? "Expanded" : "Collapsed")
            if expanded {
                Text(probe.anchor.strippedEmojis).font(.subheadline).italic()
                Text(probe.source_path).font(.caption2).foregroundStyle(Theme.inkSoft)
                ListenLine(item: Readable(title: "From the episode", body: probe.anchor, kind: "thought"))
            }
        }
    }
}

struct EpisodeHeading: View {
    let episode: EpisodeDay.Episode
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("IN OUR EARS · " + episode.id)
                .font(.system(size: 10, design: .monospaced)).tracking(1.7)
                .foregroundStyle(Theme.accent)
            Text(episode.title.strippedEmojis)
                .font(.system(size: 17, design: .serif)).italic()
        }
        .accessibilityElement(children: .combine)
    }
}

struct WalkInvitation: View {
    @Environment(AppStore.self) private var store
    var body: some View {
        Button { store.openWalk() } label: {
            VStack(alignment: .leading, spacing: 9) {
                Text(store.walkDraft.isEmpty ? "Walk with this" : "Return to your reflection")
                    .font(.system(size: 25, design: .serif))
                Text("TAP AND THINK ALOUD")
                    .font(.system(size: 10, design: .monospaced)).tracking(1.5)
                Text("I'll listen. We can reflect when you're ready.")
                    .font(.system(size: 15, design: .serif)).italic()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(22)
            .foregroundStyle(Theme.paper)
            .background(Theme.ink)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("episode.walk")
    }
}

struct EpisodeButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, design: .monospaced).weight(.semibold))
            .tracking(1.2)
            .frame(maxWidth: .infinity, minHeight: 48)
            .padding(.horizontal, 12)
            .foregroundStyle(Theme.paper)
            .background(Theme.ink.opacity(configuration.isPressed ? 0.75 : 1))
    }
}

struct FrameStatus: View {
    @Environment(AppStore.self) private var store
    @State private var retrying = false
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(store.episodeDay?.frame_status == "unavailable"
                 ? "I couldn't prepare the questions. Your words are saved; you can try again."
                 : "The episode is in our frame. The questions are being updated from it and your words.")
                .font(.subheadline).italic().foregroundStyle(Theme.inkSoft)
            Button(retrying ? "PREPARING…" : "REFRESH QUESTIONS") {
                retrying = true
                Task {
                    _ = await store.episodeAction("refresh")
                    retrying = false
                }
            }
            .font(.system(size: 9, design: .monospaced)).tracking(1)
            .disabled(retrying)
        }
    }
}

struct EpisodeErrorLine: View {
    @Environment(AppStore.self) private var store
    var body: some View {
        if !store.episodeError.isEmpty {
            Text(store.episodeError).font(.subheadline).foregroundStyle(Theme.rose)
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
    @State private var saving = false
    @State private var confirmed = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 22) {
                feedback("THIS HELPS", value: "good")
                feedback("GO DEEPER", value: "deeper")
                feedback("MISSED ME", value: "miss")
            }
            .font(.system(size: 9, design: .monospaced).weight(.semibold)).tracking(0.7)
            if canCorrect {
                Button("LET ME CORRECT THAT") { showCorrection = true }
                    .font(.system(size: 9, design: .monospaced)).tracking(1)
            }
            if !confirmed.isEmpty { Text(confirmed).font(.caption).italic() }
        }
        .disabled(saving)
        .sheet(isPresented: $showCorrection) {
            NavigationStack {
                VStack(alignment: .leading, spacing: 20) {
                    Text("What should I understand differently?").font(.title2)
                    TextEditor(text: $correction).frame(minHeight: 150)
                        .scrollContentBackground(.hidden)
                    EpisodeErrorLine()
                    Button(saving ? "SAVING…" : "SAVE MY CORRECTION") {
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
                    .buttonStyle(EpisodeButtonStyle())
                    .disabled(correction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || saving)
                }
                .padding(22).background(Theme.paper)
                .toolbar { Button("Close") { showCorrection = false } }
            }
        }
    }

    private func feedback(_ label: String, value: String) -> some View {
        Button(label) {
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
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .underline(verdict == value)
    }
}

struct EpisodeMindView: View {
    @Environment(AppStore.self) private var store
    @AppStorage("alicia.learningDraft") private var learning = ""
    @State private var receiptID = UUID().uuidString
    @State private var saving = false
    @State private var showHistory = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    SectionHeader(title: "Alicia", kicker: "WHAT I'M HOLDING WITH YOU")
                    if let day = store.episodeDay, let episode = day.episode {
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
                        if let last = day.reactions.last {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("YOUR WORDS").font(.system(size: 10, design: .monospaced)).tracking(2)
                                Text(last.text.strippedEmojis).font(.body)
                                ListenLine(item: Readable(title: "Your reflection", body: last.text, kind: "thought"))
                            }
                        } else {
                            WalkInvitation()
                        }
                        ForEach(day.corrections) { entry in
                            VStack(alignment: .leading, spacing: 8) {
                                Text("YOU CORRECTED").font(.system(size: 10, design: .monospaced)).tracking(2)
                                Text(entry.text.strippedEmojis)
                            }
                        }
                        Rectangle().fill(Theme.stroke).frame(height: 0.7)
                        Text("What do you want to keep?").font(.system(size: 23, design: .serif))
                        Text("A learning becomes yours here when you choose it.")
                            .font(.subheadline).italic().foregroundStyle(Theme.inkSoft)
                        TextField("In your own words…", text: $learning, axis: .vertical)
                            .lineLimit(3...8).padding(14).background(Theme.paper.opacity(0.85))
                        Button(saving ? "SAVING…" : "KEEP THIS LEARNING") {
                            saving = true
                            Task {
                                if await store.episodeAction("learning", text: learning, eventID: receiptID) {
                                    learning = ""
                                    receiptID = UUID().uuidString
                                }
                                saving = false
                            }
                        }
                        .buttonStyle(EpisodeButtonStyle())
                        .disabled(saving || learning.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        ForEach(day.learnings) { entry in
                            Text(entry.text.strippedEmojis).font(.body)
                            ListenLine(item: Readable(title: "What you kept", body: entry.text, kind: "thought"))
                        }
                        Button("CONTINUE TOGETHER") { store.selectedSection = .dialogue }
                            .font(.system(size: 10, design: .monospaced)).tracking(1.2)
                    } else {
                        Text("Once you've listened, this is where we'll hold your reaction and what you want to keep.")
                            .font(.system(size: 23, design: .serif))
                        Button("OPEN STUDIO") { store.selectedSection = .studio }
                            .buttonStyle(EpisodeButtonStyle())
                    }
                    EpisodeErrorLine()
                    Button("YOUR DAYS & LEARNINGS") { showHistory = true }
                        .font(.system(size: 10, design: .monospaced)).tracking(1.3)
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
