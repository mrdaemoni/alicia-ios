import SwiftUI

/// The steering study's weekly note, impossible to miss (CL-20261023-study-note-card).
///
/// A quiet line at the top of Us, only on a study week's last day (and the next
/// day if that week's note is still missing), the same in both arms. It opens
/// the template's prompts. Once the Mac confirms the save, the line says so for
/// the rest of the day. Ink and words only: no SF Symbols, no emoji.
struct StudyNoteCard: View {
    @Environment(AppStore.self) private var store
    @State private var writing = false

    var body: some View {
        if let note = store.studyNote, note.show {
            Button { if !note.saved { writing = true } } label: {
                VStack(alignment: .leading, spacing: 6) {
                    InkKicker(text: note.late ? "Study note · from yesterday" : "Study note")
                    Text(note.line.isEmpty ? note.title : note.line)
                        .font(.system(size: 19, design: .serif))
                        .foregroundStyle(note.saved ? Theme.inkSoft : Theme.ink)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    if !note.saved {
                        InkUnderline(color: Theme.ink.opacity(0.55), seed: 41 + note.week, lineWidth: 1)
                            .frame(width: 120, height: 4)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(note.saved)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(note.saved ? "Week \(note.week) note saved"
                                           : "Week \(note.week) study note, two minutes, your own words")
            .accessibilityIdentifier("studyNote.card")
            .sheet(isPresented: $writing) { StudyNoteSheet(status: note) }
        }
    }
}

/// The template's prompts, one field each. Blank is valid; the words stay on
/// the phone until the Mac confirms them.
struct StudyNoteSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let status: StudyNoteStatus
    @State private var draft: StudyNoteDraft
    @State private var saving = false
    @State private var notice = ""

    init(status: StudyNoteStatus) {
        self.status = status
        _draft = State(initialValue: StudyNoteDrafts.load(week: status.week) ?? StudyNoteDraft(week: status.week))
    }

    private var armLine: String {
        switch status.arm {
        case "during": "a week to steer while it plays"
        case "after": "a week to steer when it ends"
        default: ""
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        InkKicker(text: "Study note · week \(status.week)")
                        Text("Two minutes, your own words.")
                            .font(.system(size: 22, design: .serif))
                        Text([status.dates, armLine].filter { !$0.isEmpty }.joined(separator: " · ")
                             + ". A blank answer is a valid answer. Alicia never reads these.")
                            .font(.system(size: 13, design: .serif))
                            .foregroundStyle(Theme.inkSoft)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    InkCloseButton(identifier: "studyNote.close")
                }
                field(status.mornings_prompt.isEmpty ? "Mornings I played it (roughly)" : status.mornings_prompt,
                      hint: "", text: $draft.mornings, id: "mornings", lines: 1...2)
                ForEach(status.prompts) { prompt in
                    field(prompt.heading, hint: prompt.hint, text: answer(prompt.id), id: prompt.id, lines: 3...10)
                }
                if !notice.isEmpty {
                    Text(notice)
                        .font(.system(size: 13, design: .serif))
                        .foregroundStyle(Theme.rose)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("studyNote.notice")
                }
                Button(action: save) {
                    Text(saving ? "SAVING" : "SAVE")
                        .font(.system(size: 12, design: .monospaced).weight(.semibold)).tracking(1.8)
                        .foregroundStyle(Theme.paper)
                        .padding(.horizontal, 28).padding(.vertical, 12)
                        .background(Capsule().fill(Theme.ink.opacity(saving ? 0.5 : 1)))
                }
                .buttonStyle(.plain)
                .disabled(saving)
                .accessibilityIdentifier("studyNote.save")
            }
            .padding(24)
        }
        .background(Theme.paper.ignoresSafeArea())
        .foregroundStyle(Theme.ink)
        .fontDesign(.serif)
        // Every keystroke is kept on the phone, so closing the sheet loses nothing.
        .onChange(of: draft) { _, value in
            if !StudyNoteDrafts.store(value) { notice = "These words aren't kept on the phone yet. Save before closing." }
        }
    }

    private func answer(_ id: String) -> Binding<String> {
        Binding(get: { draft.answers[id] ?? "" }, set: { draft.answers[id] = $0 })
    }

    private func field(_ title: String, hint: String, text: Binding<String>, id: String,
                       lines: ClosedRange<Int>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 17, design: .serif).weight(.semibold))
            if !hint.isEmpty {
                Text(hint).font(.system(size: 13, design: .serif)).foregroundStyle(Theme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            TextField("", text: text, axis: .vertical)
                .lineLimit(lines)
                .font(.system(size: 16, design: .serif))
                .padding(10)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.ink.opacity(0.18), lineWidth: 0.8))
                .accessibilityLabel(title)
                .accessibilityIdentifier("studyNote.field." + id)
        }
    }

    private func save() {
        saving = true
        notice = ""
        Task {
            var attempt = draft
            let result = await store.saveStudyNote(&attempt)
            saving = false
            switch result {
            case .saved:
                dismiss()
            case .rejected(let message):
                draft = attempt
                notice = message
            case .unreachable:
                draft = attempt
                notice = "Not saved yet. Your words stay here; try again."
            }
        }
    }
}

#if DEBUG
/// Invented fixture for `--study-note-preview` (this repo is public). The
/// prompts are the study template's own.
@MainActor enum StudyNotePreview {
    static var saved = false
    static var failNext = ProcessInfo.processInfo.arguments.contains("--study-note-fail-once")

    static let prompts = [
        StudyNotePrompt(id: "cost", heading: "1. What did the controls cost?",
                        hint: "Did having Higher · Lower · Again there (or waiting for them at the end) take attention away from the exercise or the briefing? When?"),
        StudyNotePrompt(id: "not_steered", heading: "2. When I didn't steer",
                        hint: "Think of a moment you could have pressed something and didn't. Why not?"),
        StudyNotePrompt(id: "steered", heading: "3. When I did steer",
                        hint: "Did what came next match what you meant by the press?"),
        StudyNotePrompt(id: "landed", heading: "4. Landed / Didn't land",
                        hint: "What did \"landed\" mean to you this week?"),
        StudyNotePrompt(id: "wrong", heading: "5. Anything that felt wrong", hint: "A claim that seemed lost or added, a seam, a repeat."),
        StudyNotePrompt(id: "else", heading: "6. Anything else", hint: ""),
    ]

    static func status() -> StudyNoteStatus {
        var s = StudyNoteStatus()
        s.show = true; s.week = 2; s.arm = "after"; s.dates = "Oct 25 – Oct 31"
        s.prompts = prompts; s.mornings_prompt = "Mornings I played it (roughly)"
        s.saved = saved; s.saved_today = saved; s.title = "Week 2 note"
        s.line = saved ? "Week 2 note saved" : "Week 2 note · two minutes, your own words"
        return s
    }

    static func save(_ body: Data) -> StudyNoteSave {
        if failNext { failNext = false; return .unreachable }
        saved = true
        return .saved(savedAt: "2026-10-31T16:00:00+00:00")
    }
}
#endif
