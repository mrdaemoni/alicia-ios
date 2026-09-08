# A2-013 — morning briefing and long voice capture

Current work builds on TestFlight 1.0 (12), source3932615. Us places the dated
morning briefing above shared goals and the selected episode. Its full reading,
sources and measured audio remain available; Studio opens the same playlist and
stable record identity. Service refresh is read-only and audio uses the configured
private media route. It neither chooses an episode nor manufactures listening.

Walk and Dialogue show microphone state, actual input route, elapsed audio and
level. A saved confirmation distinguishes words received by Alicia from audio
retained locally and upload progress. Review/correction preserves the original.
The full Sept7 recording survived (333.3seconds,35segments); only13 transcript
characters reached the backend. Full local ASR recovery remains unconfirmed.

Read docs/MORNING_BRIEFING.md, docs/VOICE_CAPTURE.md and shared A2-013 HANDOFF.md/
RELEASE.md for source, checks and Apple receipts. Prior sections below are history.

# Session handoff — Alicia 2.0

Current task: A2-011 concurrent goals, stacked on build 11 source 712cd62.
Us and Alicia expose three active goal rows, their total count and a direct Add
goal action; Together keeps all goals and moves Add goal above existing details.
There is no three-goal storage cap. The paired backend corrects compact local
context so at least three active goals survive alongside corrections/agreements.
Read docs/COLLABORATION.md and the shared A2-011 HANDOFF.md/RELEASE.md for current
commit and TestFlight receipts. The A2-010 records below are the earlier release.

Current task: A2-010 collaborative Alicia, September 7, 2026. This candidate
builds on A2-009 source 55798db. Read docs/COLLABORATION.md for the current iOS
implementation; Apple release status is recorded only in the shared A2-010
RELEASE.md. Historical release sections below are retained as history.

Earlier product baseline: September 5, 2026. Read `AGENTS.md` first, then this
file and `CLAUDE.md`. The complete cross-repository handoff is
`/Users/alicia/alicia/docs/ALICIA_2_0.md`.

## September 5 release baseline (historical)

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

- **Us:** shared goal/current connection, then the exact played episode and two or three probes with source passages,
  This helps / Go deeper / Missed me on the exact question, and Walk with this.
- **Dialogue:** actual persisted conversation from `/api/history`, a small
  episode header, dictation, optional voice replies, and Think aloud. A proactive
  feed does not seed the transcript.
- **Alicia:** shared goals and agreements, tentative understanding, Hector's words, corrections and explicit
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

## A2-008 — episode continuity

Built on shipped cc05703 (TestFlight 7), not canonical main. AppStore chooses a
shared topic on explicit episode play; a durable selected receipt shares its
local-day identity with the backend. RootView's quiet Talk about this episode
bar is a hard VStack sibling in every tab. Studio playback controls remain in
Studio. Automatic advancement does not choose a topic. Us/Alicia headings
separate choice from observed playback. Dialogue waits for choice sync, while
walks save their explicit episode identity. Snapshot revisions reject old HTTP
results. Local drafts are kept per episode; an uncertain save stays immutable.
Finish during live dictation first exposes editable words, then Save & reflect.

Feature contract: backend docs/EPISODE_DAY.md. Actual audit/release evidence:
`/Users/alicia/Documents/Alicia-development/tasks/A2-008/`. Tests use inert
Swift harnesses and mock-only XCUITest; no production inputs are manufactured.

## A2-009 — retain original iOS voice

Walk and Dialogue now retain original CAF microphone segments in a protected,
file-backed VoiceArchive, independently of live speech recognition. Raw files,
capture time/timezone/episode/frame/question context, original on-device text,
submitted words and explicit corrections remain distinguishable. Closed audio
segments retry to the private Mac by UUID/checksum; empty recognition still keeps
valid audio. Recordings opens from Dialogue or the paused walk, with original
playback, text versions, exact message links, nearby messages and Delete audio.
Deletion keeps a tombstone and text/context; an offline Mac deletion remains
visibly pending. No raw-audio cloud provider or automatic training was added.

The implementation is stacked on TestFlight 1.0 (9), source 0de4440. Its own
release status is `/Users/alicia/Documents/Alicia-development/tasks/A2-009/RELEASE.md`.
Backend behavior: `docs/VOICE_CAPTURE.md` in the paired backend worktree.
Physical microphone/headset completeness remains a device check, separate from
simulator file/buffer/UI evidence. Earlier missing recordings cannot be recovered.

## A2-010 — shared focus across episodes

Us and Alicia now show a compact shared goal/current connection independently of
playback. Dialogue and Context enrichment open the same collaboration review.
Explicit edits distinguish use, clarification, commitment, reported outcomes and
change of course. Source and original voice drill-down reuse existing surfaces;
long reviews offer explicitly labelled local read-aloud. Shared state uses a
monotonic revision and durable exact mutation receipts; drafts retain the entity
revision they originally edited.
Alicia's internal research can also appear directly under a saved goal, labelled
prepared work. It does not create a human agreement or report an achieved outcome.

Purposeful local returns supersede the earlier daily-slot ThoughtReturn policy
when the collaboration API is available. Quiet hours and immediate Stop remain;
unrelated conversation does not cancel an agreement. Notification targets open
the exact connection/agreement. The backend owns candidate relevance and work;
iOS neither generates a result nor claims a scheduled notification was delivered.

No release, live input, microphone call, model request or send is part of the iOS
fixture checks. docs/COLLABORATION.md and shared A2-010 evidence describe the
current candidate. Preserve the existing voice archive and comparison consent.
