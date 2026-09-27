import SwiftUI

struct BodyView: View {
    @Environment(AppStore.self) private var store
    @State private var segment = 0
    @State private var editor: BodyEvent?
    @State private var search = ""
    @State private var ask = false

    private var conflicted: [BodyEvent] {
        store.bodyStore.local.filter { store.bodyStore.conflictedIDs.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    SectionHeader(title: "Body", kicker: "a healthy body · a clearer mind")
                    Text("Your measurements, your rituals, your direction.")
                        .font(.system(size: 22, design: .serif))
                    InkTabs(items: ["Today", "Goals", "Evidence"], selection: $segment)
                    BodyStatus()
                    // Conflicts and captures waiting to sync belong to the
                    // whole surface, not to one segment: one section, at the
                    // top, instead of captions trailing every segment.
                    if !conflicted.isEmpty || !store.bodyStore.pendingIDs.isEmpty {
                        InkSection(kicker: "Needs attention", rule: false) {
                            ForEach(conflicted) { event in
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Not accepted by Alicia: " + (event.text.isEmpty ? event.ritual : event.text)).font(.subheadline)
                                    Text("Discard this rejected edit to edit the current version. The original capture remains in your local files.")
                                        .font(.caption).foregroundStyle(Theme.inkSoft)
                                    Button("Discard rejected edit") { store.bodyStore.discardRejected(event) }
                                        .buttonStyle(.inkDestructiveCompact)
                                }
                                .card(padding: 16, radius: 16)
                            }
                            if !store.bodyStore.pendingIDs.isEmpty {
                                InkNotice(text: "\(store.bodyStore.pendingIDs.count) capture(s) saved on this phone, awaiting Alicia.")
                            }
                        }
                    }
                    Button { ask = true } label: {
                        InkLinkLabel(title: "Ask Alicia about my wellbeing", detail: "A private answer, from your Mac")
                    }
                    .buttonStyle(.inkLink)
                    if segment == 0 {
                        InkSection(kicker: "Daily rituals") { RitualCaptureView() }
                        // Only a bridge the backend actually accepted draws
                        // measurements. A refused one used to render this whole
                        // block anyway — "OURA · AS OF unknown" over an empty
                        // grid — which is the shape of data where there is
                        // none. BodyStatus above says what happened instead.
                        if let overview = store.bodyStore.overview, overview.status == "ready" {
                            InkSection(kicker: "Oura · as of " + (overview.as_of ?? "unknown")) {
                                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], alignment: .leading, spacing: 12) {
                                    ForEach(overview.metrics) { metric in
                                        NavigationLink {
                                            MetricHistory(metric: metric)
                                        } label: {
                                            // Each measurement opens its
                                            // history: a card with her chevron.
                                            HStack(alignment: .center, spacing: 6) {
                                                VStack(alignment: .leading, spacing: 6) {
                                                    Text(metric.label).font(.subheadline).foregroundStyle(Theme.ink)
                                                    Text(metric.display(metric.value)).font(.system(size: 20, design: .serif))
                                                        .foregroundStyle(Theme.ink)
                                                    Text(metric.date ?? "No measurement").font(.caption).foregroundStyle(Theme.inkSoft)
                                                }
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                                InkChevron(pointing: .right, size: 12, color: Theme.inkSoft, seed: metric.id.inkSeed)
                                            }
                                            .frame(maxWidth: .infinity, minHeight: 84, alignment: .leading)
                                            .card(padding: 14, radius: 16)
                                        }
                                        .buttonStyle(.inkLink)
                                        .accessibilityHint("View history")
                                    }
                                }
                            }
                        }
                        goalSection
                    } else if segment == 1 { goalSection }
                    else {
                        InkSection(kicker: "Past evidence") {
                            Text("Reports retain their original source. An unknown date stays unknown.")
                                .font(.subheadline).foregroundStyle(Theme.inkSoft)
                            TextField("Find a report", text: $search).inkField()
                            let sources = (store.bodyStore.overview?.sources ?? []).filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) }
                            ForEach(Array(sources.enumerated()), id: \.element.id) { index, source in
                                if index > 0 { InkRule(opacity: 0.6) }
                                NavigationLink { BodySourceView(source: source) } label: {
                                    InkLinkLabel(title: source.title,
                                                 detail: source.category + " · " + (source.report_date ?? "Report date unknown"))
                                }
                                .buttonStyle(.inkLink)
                            }
                        }
                    }
                }.padding(22)
            }
            // v40: Body was the one room she never walked into. Every other
            // section carries the same field — the time-of-day tint and her
            // body moving behind the page — and Body alone was flat paper, so
            // stepping into it felt like leaving the app rather than moving
            // through it. Hector: "it should feel like there's a continuity of
            // her moving from one place to the other."
            .presenceBackground(.body, store: store)
            .toolbar(.hidden, for: .navigationBar)
            .task { await store.bodyStore.refresh() }
            .refreshable { await store.bodyStore.refresh() }
            .sheet(isPresented: $ask) { BodyQuestionView() }
            .sheet(item: $editor) { event in BodyGoalEditor(original: event) }
        }
    }
    private var goalSection: some View {
        InkSection(kicker: "Wellness goals", spacing: 14) {
            Text("Choose what better means. Measurements inform the work; you decide whether the outcome is achieved.")
                .font(.subheadline).foregroundStyle(Theme.inkSoft)
            if store.bodyStore.goals.isEmpty {
                Text("No wellness goals chosen yet.").font(InkType.body).italic().foregroundStyle(Theme.inkSoft)
            }
            // A goal and everything that belongs to it — its state, its
            // measurement, its sources, its notes — sit in one card.
            ForEach(store.bodyStore.goals.filter { $0.status != "archived" }) { goal in
                VStack(alignment: .leading, spacing: 10) {
                    Text(goal.text).font(InkType.subhead)
                    Text(goal.criterion).font(.subheadline)
                    Text(goal.status.capitalized + (store.bodyStore.pendingIDs.contains(goal.id) ? " · Waiting to sync" : " · Saved with Alicia"))
                        .font(.caption).foregroundStyle(Theme.inkSoft)
                    if let metric = store.bodyStore.overview?.metrics.first(where: { $0.id == goal.metric }) {
                        Text(metric.label + ": " + metric.display(metric.value) + " · " + (metric.date ?? "date unknown"))
                            .font(.caption)
                    }
                    let notes = store.bodyStore.events.filter { $0.kind == "reflection" && $0.goal_id == goal.goal_id }
                    ForEach(notes.suffix(3)) { note in
                        Text(note.local_day + " · " + note.text).font(.subheadline).italic()
                    }
                    if !goal.source_ids.isEmpty {
                        InkKicker(text: "\(goal.source_ids.count) source(s)").padding(.top, 4)
                    }
                    ForEach(goal.source_ids, id: \.self) { id in
                        if let source = store.bodyStore.overview?.sources.first(where: { $0.id == id }) {
                            NavigationLink { BodySourceView(source: source) } label: {
                                InkLinkLabel(title: source.title, small: true)
                            }
                            .buttonStyle(.inkLink)
                        }
                    }
                    InkRule(opacity: 0.6)
                    Button { editor = goal } label: { InkLinkLabel(title: "Review or edit", small: true) }
                        .buttonStyle(.inkLink)
                        .disabled(store.bodyStore.pendingIDs.contains(goal.id))
                        .opacity(store.bodyStore.pendingIDs.contains(goal.id) ? 0.45 : 1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .card(padding: 16, radius: 16)
            }
            // The same secondary compact as "Add a goal" in CollaborationSummary.
            Button("Add goal") { editor = BodyEvent(kind: "goal", goal_id: UUID().uuidString) }
                .buttonStyle(.inkSecondaryCompact).accessibilityIdentifier("body.addGoal")
        }
    }
}

struct BodyStatus: View {
    @Environment(AppStore.self) private var store
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(store.isMock ? "Preview · synthetic data, not your health record" : "Private · your Mac and phone").font(.caption).foregroundStyle(Theme.inkSoft)
            if let message = store.bodyStore.error { InkNotice(text: message, kind: .error) }
            if let overview = store.bodyStore.overview, overview.status != "ready" {
                // v39. This used to read "Oura evidence is stale" — true, and
                // useless: it did not say how stale, why, or what would fix
                // it, so Hector read it as the app being broken. The backend
                // now reports when the bridge was last built even when it
                // refuses to trust it, and the refusal is stated in full.
                VStack(alignment: .leading, spacing: 4) {
                    Text(overview.refusal)
                        .font(.subheadline).fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("body.staleness")
                    Text("Nothing here is being guessed at in the meantime: no measurement is shown and no interpretation is inferred.")
                        .font(.caption).foregroundStyle(Theme.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                    if let built = overview.last_built {
                        Text("Bridge last built " + bodyDateLabel(built))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(Theme.inkSoft)
                    }
                    Text("Your Mac rebuilds it every morning. If this stays, the Oura sign-in on the Mac probably needs renewing — Alicia cannot do that for you.")
                        .font(.caption).foregroundStyle(Theme.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else if store.bodyStore.overview == nil {
                Text(store.bodyStore.refreshing ? "Reading your private evidence…" : "Connect to your Mac to load Body.").font(.subheadline)
            }
            if store.bodyStore.error != nil || store.bodyStore.overview?.status != "ready" {
                Button("Refresh Body") { Task { await store.bodyStore.refresh() } }.buttonStyle(.inkQuiet)
            }
        }
    }
}

struct RitualCaptureView: View {
    @Environment(AppStore.self) private var store
    @State private var saving = false
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("A small record of what you did today.")
                .font(.caption).foregroundStyle(Theme.inkSoft)
            ForEach(Array(BodyCapture.rituals.enumerated()), id: \.element.0) { index, ritual in
                let done = BodyCapture.completed(ritual.0, events: store.bodyStore.events)
                if index > 0 { InkRule(opacity: 0.6) }
                HStack {
                    Text(ritual.1).font(InkType.body)
                    Spacer()
                    // Recording is an action: a mono word in an outline. The
                    // done state keeps the same shape and says so in words.
                    Button(done ? "Recorded · undo" : "Log it") {
                        var event = BodyEvent(kind: "ritual")
                        event.ritual = ritual.0; event.completed = !done
                        saving = true
                        Task { await store.bodyStore.capture(event); saving = false }
                    }
                    .buttonStyle(.inkSecondaryCompact).disabled(saving)
                    .accessibilityIdentifier("body.ritual." + ritual.0)
                }
            }
        }
    }
}

private struct MetricHistory: View {
    @Environment(AppStore.self) private var store
    let metric: BodyOverview.Metric
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(metric.label).font(.largeTitle)
                Text("Most recent: " + metric.display(metric.value))
                Text(metric.date ?? "Measurement date unavailable").foregroundStyle(Theme.inkSoft)
                Text("Baseline: " + metric.display(metric.baseline))
                Text("\(metric.baseline_days ?? 0) recorded days · \(metric.baseline_from ?? "unknown") to \(metric.baseline_to ?? "unknown")").font(.caption)
                InkSection(kicker: "Every measurement", spacing: 8) {
                    ForEach(metric.series.reversed(), id: \.date) { point in
                        HStack { Text(point.date); Spacer(); Text(metric.display(point.value)) }
                    }
                }
                Text("Oura observations. Differences can have several causes; these values alone do not establish one.")
                    .font(.caption).foregroundStyle(Theme.inkSoft)
            }.padding(22)
        }
        .presenceBackground(.body, store: store)
        .inkPushedPage("History")
    }
}

struct BodyGoalEditor: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let original: BodyEvent
    @State private var text = ""
    @State private var criterion = ""
    @State private var metric = ""
    @State private var status = "active"
    @State private var selected: Set<String> = []
    @State private var saving = false

    private var canSave: Bool {
        !(saving || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || criterion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || text.count > 4000 || criterion.count > 1000)
    }

    private func save() {
        var event = BodyEvent(kind: "goal", goal_id: original.goal_id)
        event.previous_id = original.text.isEmpty ? "" : original.id
        event.text = text; event.criterion = criterion; event.metric = metric
        event.status = status; event.source_ids = selected.sorted()
        saving = true
        Task { let kept = await store.bodyStore.capture(event); saving = false; if kept { dismiss() } }
    }

    // One page in the app's grammar instead of a system Form: sections with
    // kickers, fields in ink, choices as chips (the system Picker and Toggle
    // drew their own glyphs), Save as the one primary.
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    InkSection(kicker: "What do you want to improve?", rule: false) {
                        TextEditor(text: $text).scrollContentBackground(.hidden)
                            .inkField(minHeight: 100).accessibilityIdentifier("body.goalIntention")
                    }
                    InkSection(kicker: "How will you recognize progress?") {
                        TextEditor(text: $criterion).scrollContentBackground(.hidden)
                            .inkField(minHeight: 100).accessibilityIdentifier("body.goalCriterion")
                        Text("Use your own words. No score or streak completes a goal for you.")
                            .font(.caption).foregroundStyle(Theme.inkSoft)
                    }
                    InkSection(kicker: "Evidence to follow") {
                        Text("Daily signal").font(.subheadline)
                        FlexWrap(spacing: 8) {
                            WorkReviewChoice(title: "My own observations", selected: metric.isEmpty) { metric = "" }
                            ForEach(store.bodyStore.overview?.metrics ?? []) { item in
                                WorkReviewChoice(title: item.label, selected: metric == item.id) { metric = item.id }
                            }
                        }
                        InkDisclosure("Historical sources (\(selected.count))") {
                            ForEach(store.bodyStore.overview?.sources ?? []) { source in
                                let on = selected.contains(source.id)
                                WorkReviewChoice(title: source.title, selected: on) {
                                    if on { selected.remove(source.id) } else { selected.insert(source.id) }
                                }
                                .disabled(!on && selected.count >= 20)
                            }
                        }
                    }
                    InkSection(kicker: "Your assessment") {
                        FlexWrap(spacing: 8) {
                            ForEach([("active", "Active"), ("paused", "Paused"), ("achieved", "Achieved — I confirm"), ("archived", "Archived")], id: \.0) { option in
                                WorkReviewChoice(title: option.1, selected: status == option.0) { status = option.0 }
                            }
                        }
                    }
                    InkSection(kicker: "Keeping it") {
                        Text("Private wellness work stays separate from cloud goal agents. Your previous versions are retained.")
                            .font(.caption).foregroundStyle(Theme.inkSoft)
                        if let error = store.bodyStore.error { InkNotice(text: error, kind: .error) }
                        Button(saving ? "Saving…" : "Save", action: save)
                            .buttonStyle(.inkPrimary).disabled(!canSave)
                        Button("Cancel") { dismiss() }
                            .buttonStyle(.inkQuiet).disabled(saving)
                            .accessibilityLabel("Cancel")
                    }
                }
                .padding(22)
            }
            .background(Theme.paper)
            .inkSheetPage("Wellness goal", close: { if !saving { dismiss() } })
            .onAppear { text = original.text; criterion = original.criterion; metric = original.metric; status = original.status; selected = Set(original.source_ids) }
            .interactiveDismissDisabled()
        }
        .tint(Theme.ink)
    }
}

struct BodySourceView: View {
    @Environment(AppStore.self) private var store
    let source: BodyOverview.Source
    @State private var page: BodySourcePage?
    @State private var offset = 0
    @State private var loading = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(source.title).font(.title)
                Text("Report date: " + (source.report_date ?? "Unknown")).font(.caption)
                Text("Measurement date: " + (source.measurement_date ?? "Unknown")).font(.caption)
                if let page, page.status == "ready" {
                    ForEach(page.passages ?? []) { passage in Text(passage.excerpt).textSelection(.enabled) }
                    HStack {
                        if offset > 0 { Button("Previous passages") { offset = max(0, offset - 5) }.buttonStyle(.inkQuiet) }
                        Spacer()
                        if let next = page.next_offset { Button("More passages") { offset = next }.buttonStyle(.inkQuiet) }
                    }.frame(minHeight: 44)
                    if page.passages?.isEmpty == true { Text("No extracted text is available for this source.") }
                } else {
                    Text(loading ? "Reading the local report…" : "Report text unavailable. The original source remains on your Mac.")
                    Button("Retry") { Task { await load() } }.buttonStyle(.inkQuiet)
                }
                InkRule()
                Text("Local evidence · extracted text may contain errors. Historical findings are not automatically current findings.").font(.caption)
                Text(source.source_path).font(.caption2).textSelection(.enabled)
                if let hash = source.sha256 { Text("SHA256 " + hash).font(.caption2).textSelection(.enabled) }
            }.padding(22)
        }
        .presenceBackground(.body, store: store)
        .inkPushedPage("Evidence")
        .task(id: offset) { await load() }
    }
    private func load() async { loading = true; page = await store.bodyStore.source(source.id, offset: offset, expectedHash: source.sha256 ?? ""); loading = false }
}


private struct BodyQuestionView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var question = ""
    @State private var answer: BodyAnswer?
    @State private var working = false
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Your goals, recent private reflections, and available Oura evidence inform this answer. It runs on your Mac.").font(.subheadline)
                    TextField("What would you like to understand?", text: $question, axis: .vertical)
                        .lineLimit(3...8).inkField().disabled(working)
                    Button(working ? "Thinking on your Mac…" : "Ask privately") {
                        working = true
                        Task { answer = await store.bodyStore.ask(question) ?? .init(status: "unavailable", text: "Cannot reach your private answer. Please retry."); working = false }
                    }.buttonStyle(.inkPrimary).disabled(working || question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || question.count > 4000)
                    if let answer {
                        Text(answer.text).font(.system(size: 20, design: .serif)).textSelection(.enabled)
                        if let model = answer.model { Text("Local model · " + model).font(.caption) }
                        if let asOf = answer.as_of { Text("Oura through " + asOf).font(.caption) }
                    }
                    Text("This exchange is not saved or used for training. Keep what matters as a private reflection in Us. Private audio is not available yet.").font(.caption).foregroundStyle(Theme.inkSoft)
                }.padding(22)
            }.background(Theme.paper)
                .inkSheetPage("With Alicia", close: { if !working { dismiss() } })
                .interactiveDismissDisabled(working || !question.isEmpty)
        }
        .tint(Theme.ink)
    }
}

/// A bridge timestamp as a day he recognises, falling back to the raw value
/// rather than inventing one when it cannot be parsed.
func bodyDateLabel(_ timestamp: String) -> String {
    let iso = ISO8601DateFormatter()
    iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let plain = ISO8601DateFormatter()
    plain.formatOptions = [.withInternetDateTime]
    guard let date = iso.date(from: timestamp) ?? plain.date(from: timestamp) else { return timestamp }
    let out = DateFormatter()
    out.dateFormat = "EEEE d MMMM, HH:mm"
    return out.string(from: date)
}
