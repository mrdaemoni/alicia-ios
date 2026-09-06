# Session handoff — Alicia 2.0, iOS v38

Current task: A2-007, September 6, 2026. This branch builds on the last recorded
TestFlight 1.0 (6), v38 · codex/dialogue-insight at `0cd200e`. A2-007 is a
candidate until its shared RELEASE.md records Apple state. The build-5 release
section below is historical. Read `docs/CONTEXT_ENRICHMENT.md` for this change.

Earlier product baseline: September 5, 2026. Read `AGENTS.md` first, then this
file and `CLAUDE.md`. The complete cross-repository handoff is
`/Users/alicia/alicia/docs/ALICIA_2_0.md`.

## What is released

- iOS PR #6, merge `9b353f5`, implements episode/day focus and the foreground
  walk/reflection screen's keep-awake behavior.
- Backend PR #12 (`7ba1897`) implements observed playback, source-grounded frames,
  shared conversation routing/history, and durable reactions/corrections/keeps.
- Backend PR #13 (`44c8385`) pauses 18 standalone Telegram routines and aligns
  messaging and self-description to the same episode-day evidence.
- TestFlight v38 / 1.0 (5) was reported VALID and IN_BETA_TESTING on September 5.
  Later documentation-only commits are not new app builds. Check current Git
  and App Store Connect before asserting a newer release.

The iOS source is `/Users/alicia/AliciaApp`; the production backend is
`/Users/alicia/alicia`. Keep both canonical checkouts clean on main. Work in
separate task branches/worktrees, exchange committed diffs, and follow each
repository's AGENTS rules. No competing open PRs existed at the start of this
documentation reconciliation; verify again before future work.

## The current app

`RootView` has five tabs: **Us · Dialogue · Alicia · Studio · Knowledge**.
`HomeView` mounts `EpisodeHomeView`; `MindView` mounts `EpisodeMindView`. Both
current episode views are implemented in `Features/Home/EpisodeDayView.swift`.
Older orbit, card and voice-gallery implementations remain unmounted.

- **Us:** the exact played episode, two or three probes with source passages,
  This helps / Go deeper / Missed me on the exact question, and Walk with this.
- **Dialogue:** actual persisted conversation from `/api/history`, a small
  episode header, dictation, optional voice replies, and Think aloud. A proactive
  feed does not seed the transcript.
- **Alicia:** tentative understanding, Hector's words, corrections and explicit
  keeps. His correction is evidence; a generated interpretation is not his belief.
- **Studio / Knowledge:** the podcast, playlist, synthesis and thinker libraries
  remain available. Studio retains its canvas tools.

`Core/AppStore.swift` owns state, playback outbox and walk save lifecycle.
`Core/AliciaService.swift` is the protocol; `LiveAliciaService` and the mock are
its implementations. Views do not issue HTTP requests directly.

## Walk and playback semantics

Actual continuous player progress identifies listening, including episode
playlists. Seeks, downloads and selection alone do not. Queued observations
retain their original timestamps and stable IDs when retried.

`Features/Talk/WalkReflectionView.swift` pauses playback and shows dictation as
it arrives. It keeps automatic screen sleep disabled while visible and active,
including paused dictation/editing. It restores the prior setting when leaving
or becoming inactive. Manual lock/backgrounding pauses recognition. There is no
background microphone or new outbound call capability in this release.

A local draft remains until a durable server receipt. An uncertain submission
retains its exact payload for Retry save and cannot be edited into a different
request under the same ID. The presented probe is separate from human words.
No claim of real microphone correctness comes from mocked save tests.

## Messaging and learning

Telegram offers at most one optional 12:30 episode question before Hector has
responded, with no new generation at send time. Morning/evening broadcasts,
random discoveries/drawings, scorecards, surveys and portrait pushes are paused.
Background work remains. Requested conversation, email digest, committed
practices, unpack probes and service notices are separate.

One Alicia voice distinguishes observation, tentative interpretation and explicit
learning keeps. Playback, clicks, silence and likes are not agreement or learning.
The journal projects into vault `Alicia/Hector/Learnings/YYYY-MM-DD.md`; a keep
is not a promoted synthesis or proven lived practice. Labs and Qwen training
remain separate from ordinary app feedback.

## Design decisions to preserve

Ink-on-bone, `Theme.paper`/`Theme.ink`, no warm-gray redesign, no SF Symbols or
emoji in product UI. Custom deterministic ink glyphs and stripped display text
remain; reaction wire values stay compatible with the backend. Preserve Zapfino
word-level handwriting and the existing serif/mono hierarchy. Judge custom-font
rendering on device, not just the iOS 26 simulator.

The bottom word bar remains a hard VStack sibling; do not return it to
`.safeAreaInset`. The podcast player is Studio-only; the active reading bar is
global. Existing presence fields and Reduce Motion behavior remain. New motion
experiments start in the DEBUG Motion Lab; long-press the Alicia screen to open
it, or use the `--motion-lab` DEBUG launch argument.

## Verification and next checks

The v38 build passed iPhone 17/iOS 26.5 simulator compilation, labelled fixture
screens (Us, Alicia, Dialogue, walk, missing episode, unavailable frame, Reduce
Motion), and six Swift save-lifecycle scenarios. Focused backend messaging passed
1,244 smoke checks and 258 contract checks; its 23 acceptance cases used fake
transports/models and temporary state. Live health and authenticated endpoints
were checked after release. No test messages were sent to Hector.

Remaining: real morning listening, speech accuracy, headset/permission/interruption
behavior, lock/unlock, physical typography and touch targets on Pandaiux, and
whether the probes help. Do not declare these proven from simulator screenshots.
No need for a new TestFlight binary when only backend messaging or docs change.

## Integration

Follow `docs/SHIPPING.md`: reviewed PRs and fast-forward-only canonical updates;
backend first when contracts change; `ship.sh` allocates build numbers without
editing/pushing source. Do not run a branch backend against live state. No version
bump or device build is needed for a documentation-only change. If Python-loaded
help/catalog text changes, its backend PR owns the targeted restart.

Earlier app and handoff history remains in `docs/history/SESSION_HANDOFF-before-alicia-2.md`.
Do not restore the old orbit, voice gallery, daily broadcast arc or weekly survey
as a fix for missing UI or a retired assertion.


## A2-006 — brief Dialogue and quick feedback

`codex/dialogue-insight` adds brief Dialogue and **Behind this reply** (button or
long press). The paired backend branch uses that same name in `alicia`.
`docs/DIALOGUE_REVIEW.md` is the feature contract. Backend must deploy before
the dependent app. The v38 record above is historical; see the shared A2-006
`RELEASE.md` for the exact branch build and Apple processing evidence.

The sheet reveals saved public response metadata and supplied context, never a
private reasoning transcript. Feedback belongs to an exact response/reading/
source set/lens/length. Optional Qwen/Claude comparison starts from frozen input and
runs only on a deliberate tap. Qwen is on the Mac mini, not the phone. It is a
contextual preference with visible providers, separate from blind Labs trials.
A decisive choice, optional reason and explicit permission can enter a pending-review
export; saving feedback does not train or replace any model.

Pending mutations are persisted with immutable payload and UUID until confirmed;
retries cannot turn edited words into the same request. No automatic comparison
on expansion. Older replies have no invented saved context. The existing quiet
schedule, episode/day signals and explicit vault keeps remain separate.

Fixtures use `--dialogue-review-preview`, `--dialogue-review-sheet-preview`, and
optionally `--dialogue-review-comparison-preview`; any dialogue-review preview
flag forces MockAliciaService in DEBUG. All preview text is fixture content;
no production feedback, presence, model generation or vault writes occur.

### A2-006 feedback refinement

Every captured reply has provider tabs and answer-specific Helpful / Okay /
Missed me, with optional tone/depth/length and text feedback. Preferences save
in one tap; reason chips and free text follow optionally. Adapted tool-free
alternatives are labelled and excluded from training. Only unchanged-input
pairs expose explicit training review permission. Current evidence and Apple
release receipt live in `/Users/alicia/Documents/Alicia-development/tasks/A2-006/`.
