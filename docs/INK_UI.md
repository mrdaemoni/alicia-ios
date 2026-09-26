# Ink UI — one grammar for the whole app (CL-20260926-ia-pass)

Hector, 2026-09-26: "the information hierarchy is difficult to get … links and
buttons … get lost with the amount of information — they're mixed with the
text … apply the right styling … so they all look coherent and clear … the
containment around information." Components: `Alicia/DesignSystem/InkUI.swift`.
Reference screen: the Alicia tab (`EpisodeMindView`) and `CollaborationSummary`.

## The five kinds of thing on a screen

| Kind | Looks like | Use |
|---|---|---|
| **Goes somewhere** (push, sheet, tab switch, open a record) | serif title (+ optional meta detail) with her `›` at the trailing edge | `NavigationLink`/`Button { route } label: { InkLinkLabel(title:detail:) }.buttonStyle(.inkLink)`; `small: true` inline; `external: true` for the web |
| **Does something** (save, send, play-less actions, retry, refresh) | a word in MONO CAPITALS | `.buttonStyle(.inkPrimary)` filled — the one thing this screen/section is for (max one per section); `.inkSecondary`/`.inkSecondaryCompact` outlined; `.inkQuiet` underlined — refresh, retry, fold, cancel |
| **Removes** (delete, discard, let go, clear, stop) | the same, in seal red | `.inkDestructive` / `.inkDestructiveCompact`; confirmation dialogs use `role: .destructive` |
| **Opens here** | quiet serif line + chevron pointing down (up when open) | `InkDisclosure("…") { … }` — never `DisclosureGroup` (system chevron) |
| **Chooses** | a chip, filled when chosen | `WorkReviewChoice(title:selected:compact:)`, `InkTabs` |

Listening keeps its own established control: `ListenLine` (and `NaturalReviewButton`). Transport keeps the ink glyphs (`InkPlayPause`, `InkSkip`, `InkCross`).

Labels are sentence case in code — the action styles draw them in small capitals (the words themselves are unchanged for VoiceOver and tests).

## Containment

- A **section** is `InkSection(kicker:) { … }`: hairline, kicker, and everything
  it owns until the next rule. `rule: false` for the first section under a page
  title. A trailing control (e.g. "CLEAR ALL") goes in the `trailing:` slot.
- Rows of a list are separated by `InkRule(opacity: 0.6)`.
- Things that belong to ONE item — a goal and its work, a recording and its
  state, a question for him, her acknowledgement — sit in one `.card(padding: 16, radius: 16)`.
- Status that is not a control: `InkNotice(text:kind:)` — `.error` is always
  rose (never ink caption), `.info` soft italic, `.success` ink.
- Inputs: `.inkField()` on every TextField/TextEditor.
- Kickers: `InkKicker` (mono 10, tracking 2, inkSoft) — never hand-rolled mono.

## Chrome

- Pushed page: `.inkPushedPage("Title")` (her BACK, script title; no system chevron).
- Sheet root: `.inkSheetPage("Title")` (script title, CLOSE trailing). Don't add a
  second in-page title that repeats it.
- Tab roots keep `SectionHeader`.

## Rules

- Nothing interactive is plain body text; nothing plain looks like a control.
- The same destination has the same words everywhere.
- No SF Symbols, no emoji, deterministic seeds (CLAUDE.md hard rule).
