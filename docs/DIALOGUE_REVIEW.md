# Dialogue response inspection — A2-006

Review candidate on `codex/dialogue-insight`; not a shipped version. The complete
backend contract is `alicia/docs/DIALOGUE_REVIEW.md` in the paired branch.

Normal Dialogue is conversational and brief. **Behind this reply** and the
long-press menu open a sheet for the exact saved answer. It contains Hector's
words, a tentative reading, optional public detail, archetype lens, supplied
context/source excerpts and granular feedback. Provider labels reflect the
actual route. Qwen runs on the Mac mini. No private thinking transcript is shown.

The second answer is requested explicitly and cached by the backend. Tool-based
answers and inputs that cannot fit unchanged are ineligible. Preferences are
original / alternative / both equally / neither plus a reason. Training-review
permission is off by default for each new reply; the draft can retain Hector's
choice. A selected pair enters a separate review queue, never automatic training
or the blind Labs scores.

## Ownership and recovery

`DialogueReview.swift` has Codable wire models and immutable mutation IDs.
`DialogueReviewView` owns its per-reply presentation and draft/outbox state;
AppStore and AliciaService own the networking seam. An uncertain save persists
its exact payload and UUID in UserDefaults. Retry sends that payload. Edit starts
a new event after refreshing the server view; the old receipt cannot change.

`ChatEvent.details(replyID)` arrives before text; `done` repeats it. `/api/history`
restores the same ID. A legacy message remains readable in full with an explicit
unavailable-context message. No new context is invented for old answers.

## Validation and promotion

`python3 scripts/test_dialogue_review.py` compiles the actual submit/retry methods
with fake IO and public wire types. It exercises lost acknowledgments, immutable
retry, malformed/rejected success, reentrancy, no implicit consent and legacy
folding. The paired backend has its own isolated acceptance suite, schema/
contract/loop wiring, and full smoke checks.

Build: iPhone 17 simulator. Fixtures and Reduce Motion captures live under
`docs/dialogue-review-preview/`. No new animation is introduced in the sheet.
Physical-device touch, VoiceOver, headset/dictation and model quality still need
real use. Do not label these screenshots as live data or device QA.

Deploy the reviewed backend first, then the reviewed app. Keep current release
metadata separate until an actual upload and device validation. The task handoff
contains exact commits, PR links and check evidence. Roll back the app before the
backend; retain journals and feedback. No noisy Telegram routines are restored.
