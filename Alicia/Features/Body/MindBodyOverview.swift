import SwiftUI

/// This invitation combines observed evidence with the chosen episode/goal on
/// the phone. It asks Hector about the relationship; it does not infer causation.
struct MindBodyOverview: View {
    @Environment(AppStore.self) private var store
    @State private var expanded = false
    @State private var note = ""
    @State private var wellnessGoalID = ""
    @State private var mindGoalID = ""
    @State private var verdict = ""
    @State private var saving = false
    @State private var saved = false
    private var mindGoals: [CollaborationState.Goal] { store.collaboration.state?.activeGoals ?? [] }
    private var bodyGoals: [BodyEvent] { store.bodyStore.goals.filter { $0.status == "active" } }
    private var recorded: [String] {
        BodyCapture.rituals.filter { BodyCapture.completed($0.0, events: store.bodyStore.events) }.map(\.1)
    }
    private var observation: String? {
        guard let overview = store.bodyStore.overview, overview.status == "ready",
              let sleep = overview.metrics.first(where: { $0.id == "sleep_hours" }),
              let value = sleep.value, let date = sleep.date else { return nil }
        var line = "Oura recorded " + sleep.display(value) + " of sleep on " + date + "."
        if let baseline = sleep.baseline { line += " Your available baseline is " + sleep.display(baseline) + "." }
        return line
    }
    private var question: String {
        if let goal = mindGoals.first(where: { $0.id == mindGoalID }) {
            return "What do you notice in your body as you work toward ‘" + goal.title + "’? What would help you think clearly about it?"
        }
        if let episode = store.episodeDay?.episode {
            return "As you return to ‘" + episode.title.strippedEmojis + "’, what do you notice about your energy and attention?"
        }
        return "What is helping your body feel well and your mind feel clear today?"
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("A CLEAR MIND · A HEALTHY BODY").font(.system(size: 10, design: .monospaced)).tracking(1.2)
            HStack(alignment: .top, spacing: 20) {
                Button { store.selectedSection = .knowledge } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Mind").font(.title2)
                        Text("\(mindGoals.count) active shared goal(s)").font(.caption)
                        Text(mindGoals.first?.title ?? "Explore your knowledge").font(.subheadline).lineLimit(3)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                Button { store.selectedSection = .body } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Body").font(.title2)
                        Text("\(bodyGoals.count) active wellness goal(s)").font(.caption)
                        Text(recorded.isEmpty ? "Log your daily rituals" : recorded.joined(separator: " · ")).font(.subheadline).lineLimit(3)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }.buttonStyle(.plain)
            Divider()
            if let observation { Text(observation).font(.subheadline).foregroundStyle(Theme.inkSoft) }
            if let error = store.bodyStore.error { Text(error).font(.caption).foregroundStyle(Theme.inkSoft) }
            Text(question).font(.system(size: 21, design: .serif))
            Text("A connection to explore · your experience tells us whether it fits.").font(.caption).foregroundStyle(Theme.inkSoft)
            Button(expanded ? "Close reflection" : "Connect this to my day") { expanded.toggle(); saved = false }
                .inkAction().accessibilityIdentifier("body.connectDay")
            if expanded {
                // These two read the tint the same way a bare Button does,
                // and were the last sea-slate left on the surface. The
                // segmented control below is deliberately not tinted: ink
                // behind its selected segment would swallow the label.
                Picker("Mind goal", selection: $mindGoalID) {
                    Text("Today's episode / open reflection").tag("")
                    ForEach(mindGoals) { goal in Text(goal.title).tag(goal.id) }
                }.tint(Theme.ink)
                Picker("Wellness goal", selection: $wellnessGoalID) {
                    Text("My general wellbeing").tag("")
                    ForEach(bodyGoals) { goal in Text(goal.text).tag(goal.goal_id) }
                }.tint(Theme.ink)
                Picker("Does this connection fit?", selection: $verdict) {
                    Text("Choose").tag(""); Text("Fits").tag("Fits")
                    Text("Not sure").tag("Not sure"); Text("Doesn't fit").tag("Doesn't fit")
                }.pickerStyle(.segmented)
                Text("What did you notice? (optional)").font(.caption)
                TextEditor(text: $note)
                    .frame(minHeight: 110)
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(Theme.stroke, lineWidth: 0.7))
                    .accessibilityLabel("What did you notice?")
                    .accessibilityIdentifier("body.reflection")
                Button(saving ? "Saving…" : "Keep this reflection") {
                    var event = BodyEvent(kind: "reflection")
                    event.text = [verdict, note].filter { !$0.isEmpty }.joined(separator: " — ")
                    event.criterion = [observation, question].compactMap { $0 }.joined(separator: "\n")
                    event.goal_id = wellnessGoalID; event.mind_goal_id = mindGoalID
                    event.episode_id = store.episodeDay?.episode?.id ?? ""
                    saving = true
                    Task { saved = await store.bodyStore.capture(event); saving = false; if saved { note = ""; verdict = "" } }
                }.inkAction().disabled(saving || (verdict.isEmpty && note.isEmpty) || note.count > 3900)
                if saved { Text("Saved on this phone" + (store.bodyStore.pendingIDs.isEmpty ? " and with Alicia." : "; waiting to sync.")).font(.caption) }
                Text("This reflection stays in your private Body record, linked to the selected goals and episode.").font(.caption)
            }
        }
        .foregroundStyle(Theme.ink)
        .accessibilityElement(children: .contain)
    }
}
