# Dialogue response inspection — A2-006

Released September 5, 2026: backend PR #16 and TestFlight 1.0 (6) from
`codex/dialogue-insight`; the interface is in iOS main. Exact backend
deployment and Apple processing status live in the shared
`Alicia-development/tasks/A2-006/RELEASE.md` receipt. The complete backend contract is `alicia/docs/DIALOGUE_REVIEW.md`.

Normal Dialogue is conversational and brief. **Behind this reply** and the
long-press menu open a sheet for the exact saved answer. It contains Hector's
words, a tentative reading, optional public detail, archetype lens, supplied
context/source excerpts and granular feedback. Provider labels reflect the
actual route. Qwen runs locally on the Mac. No private thinking transcript is shown.

The model tabs switch between the original and an automatically prepared alternative for each new iOS reply,
cached by the backend. Tapping Prefer Qwen / Prefer Claude / Tie / Neither saves
immediately. Add why is optional: reason chips plus a text box. Helpful / Okay /
Missed me and the Depth / Tone / Length menu rate the selected answer separately.
Original context retains reading, source and lens feedback.

Captured tool replies and long contexts can produce labelled adapted textual
alternatives without replaying tools. Those pairs never enter training exports.
Only unchanged-input pairs expose the separate training-review toggle, initially
off for each reply. Explicit consent selects a pending review candidate; no
automatic training and no contribution to blind Labs scores.

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
folding, quick votes without reasons, alternative attribution and old pending
mutation decoding. The paired backend has its own isolated acceptance suite, schema/
contract/loop wiring, and full smoke checks.

Build: iPhone 17 simulator. Fixtures and Reduce Motion captures live under
`docs/dialogue-review-preview/`. No new animation is introduced in the sheet.
Physical-device touch, VoiceOver, headset/dictation and model quality still need
real use. Do not label these screenshots as live data or device QA.

Deploy the reviewed backend first, then the reviewed app. Keep current release
metadata separate until an actual upload and device validation. The task handoff
contains exact commits, PR links and check evidence. Roll back the app before the
backend; retain journals and feedback. No noisy Telegram routines are restored.

## October 12 — recover the send without repeating the action

Shipped in TestFlight 1.0 (46) with backend PR #97 (October 12, 2026); in iOS
main since PR #57.

Typed shared conversation now binds `request_id` to its exact original packet
before effects. The existing review journal adds typed `chat_received`,
`chat_completed` and `chat_failed` events. Its file lock determines the one
execution owner, including competing processes. A repeated POST returns the
original public reply, an in-flight state, or an explicit unresolved outcome;
it never replays a model/tool call. A restarted process treats incomplete
receipts as uncertain. Changed words/context under the same identity are
rejected. Completed original passage replies remain recoverable after the
prepared work changes.

`GET /api/chat_receipt?request_id=<UUID>` is authenticated, read-only and exposes
only that send's public outcome. Body/private-health questions and reviewed
voice sends retain their existing isolated receipt paths. The app keeps an
immutable protected, backup-excluded outbox, checks matching completed receipts
after a transport failure, replaces partial output with the saved public reply,
and reuses its local message row on an explicit retry. Pending/unknown outcomes
keep the draft and never trigger automatic POST replay or training.

Startup diagnostics no longer gate the library/home/mode updates. The October
12 phone watchdog report resolved to BodyStore.events sorting and the
MindBodyOverview ritual status: timestamp parsers are now bounded/reused,
sorts parse once per event, and one render reads one ritual event list. Original
timestamps, timezone/day rules, capture bytes and clinical records are unchanged.

Verification uses isolated HTTP and storage, including cross-process claims,
socket loss after a completed action, current-passage mutation, private health
exclusion, exact outbox restoration and delayed startup diagnostics. The
sort benchmark compares the exact build-45 implementation with the candidate.
No synthetic conversation, feedback or health capture is sent to production.


## October 18 — early receipt and late draft reconciliation

Shipped in TestFlight 1.0 (50) (`c2f16ab`, PR #53); in iOS main since PR #57.
It uses the `accepted` event the backend added with PR #97.

A matching `accepted` SSE UUID proves that the Mac durably retained the typed
request. The original section's composer clears at that point, while the
protected send outbox retains the immutable request until the saved reply or
terminal event confirms completion. Failed sends without a receipt keep their
draft. A foreign receipt cannot clear it. Newer text and other sections' drafts
are never acknowledged by an older send.

Receipt GET recovery retries brief network failures without repeating the POST.
Reopening the conversation or refreshing history reconciles completed assistant
reply UUIDs against the outbox and clears any matching old draft, including
sends completed while the app was disconnected. No model or tool is replayed.
The private Body/health and reviewed voice lanes retain their separate handling.

## October 27 — keep recovering a late typed reply

Candidate `codex/late-chat-recovery-20261027`; release and phone acceptance
remain separate. After the stream's short recovery window, a foreground task
checks pending protected-outbox receipts every five seconds. It starts with
the existing foreground polling lifecycle and cancels on background. Empty
outboxes make no receipt requests. These are authenticated, uncached GETs;
no message, model call or tool action is automatically replayed.

A matching completed receipt replaces the original assistant row, clears its
transport warning and acknowledges only the originating draft. A relaunched
phone can recover directly from the outbox even when that reply has left the
history window. Uncertain outcomes say that completion could not be confirmed;
explicit rejection retains the original user bubble and restores an empty
originating draft. Newer words and private Body drafts are preserved.

Recovery defers during a live send, coalesces overlapping checks, and discards
results after cancellation. History reads compare the full message snapshot
before publishing so stale history cannot erase a reply recovered in place.
The Swift/HTTP harness exercises delayed completion beyond the short recovery
window, relaunch, foreign receipts, offline checks, reentrancy, cancellation,
draft preservation, rejection and zero recovery POSTs. The startup harness
also covers an older history read completing after an in-place reply update.
