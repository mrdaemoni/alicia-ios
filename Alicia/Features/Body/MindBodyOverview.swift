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
    private var status: String {
        let finished = store.collaboration.state?.finishedGoals.count ?? 0
        let mind = mindGoals.isEmpty
            ? (finished > 0 ? "Mind: ready for a next goal" : "Mind: no shared goal yet")
            : "Mind: \(mindGoals.count) shared goal\(mindGoals.count == 1 ? "" : "s")"
        let body = recorded.isEmpty ? "Body: nothing logged today" : "Body: " + recorded.joined(separator: ", ")
        return mind + " · " + body
    }

    var body: some View {
        InkSection(kicker: "A clear mind · a healthy body", spacing: 12) {
            // The tab bar already goes to Mind and Body; what this section adds
            // is where each stands today, in one line (2026-09-27, real estate).
            Text(status).font(InkType.meta).foregroundStyle(Theme.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
            if let observation { Text(observation).font(.subheadline).foregroundStyle(Theme.inkSoft) }
            if let error = store.bodyStore.error { InkNotice(text: error, kind: .error) }
            Text(question).font(InkType.subhead)
                .fixedSize(horizontal: false, vertical: true)
            InkDisclosureToggle(title: "Connect this to my day", open: expanded) { expanded.toggle(); saved = false }
                .accessibilityIdentifier("body.connectDay")
            if expanded {
                HStack(alignment: .top, spacing: 12) {
                    Rectangle().fill(Theme.stroke).frame(width: 0.7)
                    VStack(alignment: .leading, spacing: 14) { reflection }
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .foregroundStyle(Theme.ink)
        .accessibilityElement(children: .contain)
    }

    /// The private reflection: which goals it bears on, whether the
    /// connection fits (chips — choosing, not doing), his words, and keep.
    @ViewBuilder private var reflection: some View {
        VStack(alignment: .leading, spacing: 8) {
            InkKicker(text: "Mind goal")
            choiceRow {
                WorkReviewChoice(title: "Today's episode / open reflection", selected: mindGoalID.isEmpty, compact: true) { mindGoalID = "" }
                ForEach(mindGoals) { goal in
                    WorkReviewChoice(title: goal.title.strippedEmojis, selected: mindGoalID == goal.id, compact: true) { mindGoalID = goal.id }
                }
            }
        }
        VStack(alignment: .leading, spacing: 8) {
            InkKicker(text: "Wellness goal")
            choiceRow {
                WorkReviewChoice(title: "My general wellbeing", selected: wellnessGoalID.isEmpty, compact: true) { wellnessGoalID = "" }
                ForEach(bodyGoals) { goal in
                    WorkReviewChoice(title: goal.text, selected: wellnessGoalID == goal.goal_id, compact: true) { wellnessGoalID = goal.goal_id }
                }
            }
        }
        VStack(alignment: .leading, spacing: 8) {
            InkKicker(text: "Does this connection fit?")
            // Tapping the chosen answer again returns to "not chosen", as
            // the old segmented control's "Choose" did.
            HStack(spacing: 8) {
                ForEach(["Fits", "Not sure", "Doesn't fit"], id: \.self) { option in
                    WorkReviewChoice(title: option, selected: verdict == option, compact: true) {
                        verdict = verdict == option ? "" : option
                    }
                }
            }
        }
        VStack(alignment: .leading, spacing: 8) {
            InkKicker(text: "What did you notice? (optional)")
            TextEditor(text: $note)
                .scrollContentBackground(.hidden)
                .inkField(minHeight: 110)
                .accessibilityLabel("What did you notice?")
                .accessibilityIdentifier("body.reflection")
        }
        Button(saving ? "Saving…" : "Keep this reflection") {
            var event = BodyEvent(kind: "reflection")
            event.text = [verdict, note].filter { !$0.isEmpty }.joined(separator: " — ")
            event.criterion = [observation, question].compactMap { $0 }.joined(separator: "\n")
            event.goal_id = wellnessGoalID; event.mind_goal_id = mindGoalID
            event.episode_id = store.episodeDay?.episode?.id ?? ""
            saving = true
            Task { saved = await store.bodyStore.capture(event); saving = false; if saved { note = ""; verdict = "" } }
        }
        .buttonStyle(.inkPrimary)
        .disabled(saving || (verdict.isEmpty && note.isEmpty) || note.count > 3900)
        if saved {
            InkNotice(text: "Saved on this phone" + (store.bodyStore.pendingIDs.isEmpty ? " and with Alicia." : "; waiting to sync."), kind: .success)
        }
        Text("This reflection stays in your private Body record, linked to the selected goals and episode.")
            .font(.caption).foregroundStyle(Theme.inkSoft)
    }

    private func choiceRow<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) { content() }
        }
    }
}
