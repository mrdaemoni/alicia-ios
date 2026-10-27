## Current state — October 26, 2026 (read this first)

The latest TestFlight build is **1.0 (53)**, from `1c14936`, tagged **v43
(Oct 24)**. iOS `main` has since moved to `410d19f` (#50 and #60, merged
2026-10-26). No TestFlight build carries those yet; see the next-to-last item.
It pairs with backend production `1e8b40c`, which has run on the
Mac Studio since 2026-10-07 (the mini is kept as the rollback). Feature notes
follow this block and also close the file, where the newest ones are
(steering, the study note, presence). Stable architecture starts at
"CLAUDE.md — Alicia iOS". `SESSION_HANDOFF.md` lists each release.

- **Sections.** Us · Mind · Body · Alicia · Studio. Dialogue is a shared action
  through the band above the tab bar, not a tab.
- **Her presence.** One continuous particle field sits behind every section
  and replaced the contour waves (`DesignSystem/TabPresence.swift`,
  `AliciaPresence.swift`). `GET /api/presence` drives its stance from her
  awareness. Since TF52, `GET/POST /api/presence/live` also makes it listen,
  think and speak only while recording, reply preparation or audio playback
  is actually happening, on the phone and on the room's Nest display
  (`Core/LivePresence.swift`, `docs/LIVE_PRESENCE.md`).
- **Walks.** Audio keeps uploading after lock and while the app is closed
  (`Core/BackgroundVoiceSync.swift`). The Mac transcribes it in English, and a
  walk of eight words or more sends itself (backend `walk_autosend.py`).
  Opening and correcting it afterwards is optional. Dialogue voice still needs
  an explicit Send.
- **Morning briefing.** Higher · Lower · Again while it plays, inside a
  full-screen particle room (`Features/Reading/BriefingStage.swift`, TF49).
  The four-week steering study runs Oct 18 – Nov 14, and from Oct 31 a weekly
  note card appears on Us (TF53). See `docs/STEERABLE_BRIEFING.md`.
- **Delivery.** A typed send has a durable identity and recovers through
  `GET /api/chat_receipt` without resending (`Core/ChatDelivery.swift`, TF50).
  One shared recovery task clears the connection banner (TF51,
  `docs/CONNECTION_RECOVERY.md`).
- **Network.** Since backend #102, the iOS API on :8766 accepts only loopback
  and tailnet clients. The phone reaches it over Tailscale, not a home-Wi-Fi
  address.
- **In `main` since 2026-10-26, but in no TestFlight build yet.** The phone
  still behaves as TF53 until a build ships, so being in `main` is not phone
  state.
  - iOS #50 (`b4fd6f4`): a second widget tap undoes the first.
  - iOS #60 (`410d19f`):
    - A2-045's exact `243ab83`: `reply()` now posts `surface_context`.
    - A2-045's exact `05c030a`: `VoiceArchive.begin` resumes a section walk
      when only time or place changed, and still refuses a different section
      or episode.
    - #48's episode guard: a Body, Mind or Alicia walk stays about that
      section.
- **Reviewed, but not in `main`:**
  - The rest of iOS #48: the real input field, TALK/keyboard layout on every
    section, and the unconditional dark widget plate. It shipped only as the
    TF42 branch build, and is unreleased pending a deliberate re-port.
  - iOS #54 (the phone half of the walk-delivery repair). Its exact head is
    inside iOS #59, which passes its tests but is not yet approved or
    merged.

## CL-20260926-goal-closure — Finished together

Hector closed two goals on a walk ("We close those two goals … so I can start
finding a new goal") and asked for the finished work to stay reachable. The
backend now hears that and freezes a record (`skills/goal_closure.py`). Here:
`Core/GoalClosure.swift` (summaries, proposals, the record), and
`Talk/FinishedTogetherView.swift`: `FinishedTogetherRoom` (every finished goal),
`FinishedGoalView` (how he closed it, her labelled reading, where the work
landed, his words along the way with originals, the steps, sources, what was
left open with "Start a goal from this", Reopen), `CloseGoalView` (close from
the app in his words) and `GoalClosureNotices` (her acknowledgement and "did
you mean to close this?"), mounted in `CollaborationSummary` and at the top of
Together. A goal with a record leaves the Together cards. Fixture:
`--collaboration-preview --finished-goals-preview` plus `--open-together`,
`--open-finished` or `--open-finished-record` (invented text; this repo is public).

## CL-20260926-walk-sync — walk audio keeps moving when the phone locks

Hector: "make sure that it runs in the background, even if the app is closed."
The archive synced only in the foreground, and every file was `.complete`
data protection, which iOS makes unreadable ~10 s after lock. A walk ends with
the phone pocketed, so the tail segments and the seal waited on the phone until
the next open (the 9/19 walk: 82 minutes).

`Core/BackgroundVoiceSync.swift`: on every background transition it holds a
`beginBackgroundTask` until the archive is drained; anything still pending
submits a network-requiring `BGProcessingTask` (`com.alicia.app.voicesync`,
`processing` background mode) that re-arms itself until
`VoiceArchive.hasPendingSync` is false; the notification refresh drains it
too. Walk/Dialogue files are now `completeUntilFirstUserAuthentication`
(migrated at archive open); private Body audio keeps the strict class and
never syncs. A swipe-up force-quit still stops everything until the next open.

## A2-060 — a link means she has it

**The state machine was reading the wrong signal.** `VoiceRecording.stage` only
consulted `submission`, the receipt the PHONE writes when the phone sends.
Since the Mac started sending on its own (A2-057), ten walks that had genuinely
arrived kept reading "Sending to Alicia" forever, because the phone was
watching for a receipt it would never write. `stage` now returns `.sent` when
`links` is non-empty — a link is what the backend writes when words are
attached to the episode and the conversation, whoever sent them.

**`readyForYou` no longer means "you".** Its words are done and on their way;
it groups with the in-flight states. `Stage.needsYou` is now exactly
`.needsAttention` — `saved` came off it because leaving a walk seals it
(A2-059) and the Mac sends it. One meaning everywhere: nothing happens to this
unless he acts.

**Opening a past session shows it.** It used to hand unfinished ones back to
`WalkReflectionView`, whose `.task` starts recording when there is no
finalization — so tapping an eleven-day-old walk began appending today's audio
to it. That read as "it opened the wrong recording" and was worse than it read.

Every stage detail now answers one question — do I need to do anything — and
for all but `needsAttention` the answer is no.

Evidence: `--mac-sent-preview` reproduces the exact archive shape (link, no
submission) and `test_sessions_ui.py` fails if it reads as anything but arrived.

## A2-059 — the Sessions list scrolls, and a walk seals itself

**The scroll bug was mine.** A2-058 hung a `DragGesture` on every row to get a
swipe; it ate the vertical drag. `WorkSessionsView` is a `List` now — scrolling
and `swipeActions` both come from the platform, nothing competes. Proved by
`scripts/test_sessions_ui.py` against `--sessions-preview`, a fixture with
enough rows to actually scroll (the old 2-row fixture could not show the bug).

**"NEEDS YOU 13" was thirteen accidents.** Every real walk had reached her;
the thirteen were 1-15 second stubs, empty or Whisper hallucinations
("Thanks for watching!"). Misfires are their own group, last, named for what
they are, with one tap to clear all. The Alicia-tab count ignores them too.

**Leaving a walk seals it.** Closing without FINISH left the recording
unfinalized, so the Mac never transcribed it and auto-send never saw it — a
walk he walked away from silently never happened. `pause()` now finalizes any
recording over 20 seconds. Under that it does not, because sealing a
one-second press queues the Mac to transcribe silence.

**The connection banner heals itself.** While it is up, and only while it is
up, the app re-probes every ten seconds; the first success clears it.

## A2-058 — Sessions after walks send themselves

`VoiceRecording.Stage.readyForYou` no longer counts as `needsYou`. Since the
Mac auto-sends (backend A2-057), a ready transcript goes on its own within two
minutes; listing it as needing him is the lie that let five walks sit unsent for
eleven days. It reads "Sending to Alicia", and the WAITING group became NEEDS
YOU — the short list of things that genuinely stalled.

Rows in `WorkSessionsView` swipe left to discard, with resistance past the
threshold so a scroll flick cannot throw a recording away, and a VoiceOver
action for the same thing. It deletes the **audio**; a reflection already sent
keeps its words, because deleting a recording is not a way to unsay something.

## A2-056 — a lost route retries instead of accusing her

Reads through `LiveAliciaService.fetchOne` attempt three times over ~2.4s
(400ms, then 2s) before reporting `.unreachable`. A 401/403 never retries —
the same token will be rejected three times — and a decode failure never
retries either, because she answered and the shape disagreed. `ConnectionState`
gained `.reaching`, drawn in ink rather than rose: still trying is not bad news.
A success always outranks a concurrent failure, so one slow call finishing late
cannot put the banner back over a screen already full of her.

Why: on 2026-09-18 the phone left the Wi-Fi, Tailscale fell from a direct route
to a relay (34ms → 400ms), and the single request lost to that transition left
"she's unreachable" on screen until Hector pulled to refresh.

Evidence: `scripts/test_reconnect_ui.py`, driven against a dead endpoint
through the UserDefaults override, so the app runs live and every read fails.

## A2-055 — the polish pass from the first device build

First real evidence from Pandaiux (TestFlight 19), and five things it showed.

**The band is one height everywhere.** It used to grow a two-line preview of
her last reply, so it was short in Body and tall in Mind and Studio — and on
the phone that reply was a fragment of an internal instruction set in her
voice, parked across the bottom of every screen. `composer.lastReply` is gone.

**Every screen is a room.** `PlaylistDetailView` and `VoiceRecordingsView` were
flat bone paper with no tint and no field; they now carry Studio's and Mind's
respectively. `VoiceProcessingView` forces `.buttonStyle(.plain)` and ink — its
controls were all system-blue links, which broke the one hard rule the app has
on the screen he sees most after speaking.

**The Us title opens `OurArcView` again** — what she's holding about him now,
then every day since she began, with a key happening and where he was beside
the date. The endpoints never stopped working; the surface had been unmounted
with the old orbit. Days before the phone reported a place show none.

## A2-052 — she walks through every room

Body carries `.presenceBackground(.body, store:)` like every other section, so
the time-of-day tint and her body behind the page are continuous across the
five tabs. `ListeningStage` is composed the same way — backdrop, `Theme.timeTint`,
the oversized field, `PaperGrain` — at 0.42 rather than 0.30, because there she
is the subject. The walk's listening phase is the only phase without the padded
paper ground, so the room reaches every edge while its controls stay in the
safe area.

`PlaceTracker` resolves a **named place**: locality, sub-locality and a point of
interest when there is one. Still no coordinate. Home is Palo Alto, office is
Seattle, stated by Hector. Fine-grained updates run only while the app is in the
foreground; significant-change monitoring continues either way.

## A2-050 — where he is

`Core/PlaceTracker.swift` gives Alicia a **place, not a position**: significant-
change monitoring, on-device reverse geocoding, and only a locality, region and
`home | office | travelling` ever published. Coordinates never leave the class.
`NSLocationWhenInUseUsageDescription` explains that in his words, and the
permission is requested from `PlaceAwareness` on the Alicia tab — where the
prompt arrives attached to a reason and he can read back exactly what she is
told. A refused permission is an ordinary state; everything else works.

The place travels two ways: one `place` presence event when the city changes,
and inside `SurfaceContext`, so a reflection recorded in Seattle is filed as one.

## A2-047 — the home screen Hector actually uses

Hector's build-18 field report, built on Codex's preserved A2-045 composer.

**The conversation is a layer, not a place.** `ConversationComposer` is a
permanent band directly above `EditorialTabBar`, on the same ink ground; it
never takes the keyboard and nothing collapses for it any more. Tapping it
raises `ConversationSheet` over the current section, carrying that section's
name and its own per-section draft; closing it returns him to the page he was
on. `TalkView` (Dialogue) still exists and keeps shared history.

**The microphone is the page.** `ListeningRoom` and the shared `ListeningStage`
put `AliciaPresence` full-bleed behind his own words in large serif, in the
voice of the section he spoke from. "Talk about this episode" opens the same
room through `WalkReflectionView`, whose lifecycle is unchanged: original audio
kept, Mac transcript, explicit review before anything is sent. Both paths ask
for speech authorization so live text can be read back, falling back to
microphone-only and saying so.

**A reflection has one address.** `VoiceRecording.stage` is the single
vocabulary — Saved / Your Mac is writing it / Waiting for you to read / Sending
/ Alicia has it / Needs your attention — used by the band, the recordings list
and `VoiceProcessingView`. Anything waiting on him surfaces on the band from
wherever he is.

**Body says what is wrong.** A refused bridge now reports `last_built`,
`last_measurement` and `stale_days`, and `BodyOverview.refusal` states them;
no measurement block is drawn for a bridge the backend did not accept. The
bridge itself is rebuilt by a scheduled task on the Mac (backend A2-046).

Evidence: `scripts/test_home_conversation_ui.py`.

## A2-043 — mind and body (released 2026-09-13, TestFlight 18)

Read [MIND_BODY.md](docs/MIND_BODY.md). Five visible tabs: Us, Mind, Body, Alicia, Studio; Dialogue is a shared action through the persistent bottom band. The band names the active section, keeps separate durable drafts and freezes that section into every send. Voice opens the full-screen shared particle field and states whether the microphone is opening, listening or paused. Body is private Mac/phone evidence and explicit wellness goals. The Daily rituals widget saves offline, shows the latest tap's local/synced state and keeps tinted white labels on a dark contrast plate. Drawing is removed from Studio navigation; files remain. Release status belongs to the current shared task record.

## A2-037 — natural immersive reading and voice interpretation review

Current branch adds [IMMERSIVE_READING.md](docs/IMMERSIVE_READING.md): shared
natural narration with exact text and measured cues, an honest unavailable/retry
state, next episode from observed playback in Us/Studio, and A2-036's reviewable
voice findings. Device read-aloud is removed. Podcast read-along uses a labelled
machine transcript from the original audio, never shownotes as a script. Backend
A2-036/A2-038 deploy first; task RELEASE.md owns actual shipping status.

## CL-20260919-context-arrangement — the day arranged around his nodes

"In the middle of" now renders `GET /api/context_graph/arrangement`: under each
node line, the items that bear on it today — question · thinker · passage ·
goal · finding · your words · place — as `ArrangedItemLine`s with their why.
The separate "For where you are" strip is gone; its items sit under their
nodes. The room opens with "Arranged today"; a node shows "Around this today"
with the evidence line and source. When the arrangement is not ready the plain
node lines show and nothing waits. Fixtures under the same preview flags.

## CL-20260918-context-graph-behaviours — "In the middle of"

Us gains one section between the mind/body overview and the goals summary:
two to three lines of Hector's context graph (`WhereYouAreSection`), each with
its mark — `STATED · PROJECT`, `UNCONFIRMED READING · TENSION` — and a hand-drawn
underline seeded by the node id. The kicker opens `ContextGraphRoom` (the whole
graph grouped by kind, unconfirmed readings first, the day's elevation with its
reason when it refused); a node opens `ContextNodeView` with body, receipts,
vault links, related nodes and the three acts — **Keep**, **Correct** (his
words, becomes stated), **Let go** (asked once) — as `ContextGraphMutation`s
kept verbatim on the phone until confirmed, one receipt id per unchanged
payload. Under the episode's questions, `ForWhereYouAreSection` renders what
was elevated and names the node it came from; nothing renders when nothing
cleared the threshold. The Alicia tab links into the same room next to "About
you"; a reply's inspector lists the nodes it drew on ("DREW ON YOUR CONTEXT").
The kicker is not "Where you are" — that name belongs to place awareness.
`--episode-day-preview` (or any `--context-graph-*` flag) serves fixtures.

# CLAUDE.md — Alicia iOS

Current task coordination: `/Users/alicia/alicia/docs/DEVELOPMENT_PROTOCOL.md` and
`/Users/alicia/Documents/Alicia-development/README.md`. Read the assigned brief,
claim its branch/worktree, and leave committed work plus test evidence in the
shared task folder for Codex review. Register self-initiated work there too.

**Read `AGENTS.md` before doing anything.** It is the repository-wide contract
for Codex–Opus coordination, worktrees, file ownership, review handoffs, Git,
and the Motion Lab promotion gate.

Read `SESSION_HANDOFF.md` for the release record and known limits. This file
carries stable architecture. The current product is the Alicia 2.0 episode/day
experience at `main` `1c14936` / TestFlight 53 (see "Current state" at the top),
including immersive natural reading (`docs/IMMERSIVE_READING.md`), shared work
review (`docs/WORK_REVIEW.md`) and Mac voice processing. Each shared task's
RELEASE.md records actual deployment and upload. Full cross-repository context is in
`/Users/alicia/alicia/docs/ALICIA_2_0.md`; feature detail is in `docs/EPISODE_DAY.md`.
Us and Alicia use the actually played episode and explicit human responses.
The older orbit/cards and archetype gallery are unmounted.

## What this is

A native **pure-SwiftUI** iOS app for "Alicia," Hector's personal AI agent.
The backend is the separate Python service in the `alicia` repo
(github.com/mrdaemoni/alicia). Hector builds with her in Cowork. Her outbound
Telegram has been off since 2026-09-18 (Telegram now carries only the Alicia
Labs bot), so the app and the web dashboard are where she reaches him. Target **iOS 17.0**, Swift 5.9+, the installed Xcode, **zero third-party
dependencies**. Runs live against the backend on a real iPhone; falls back to
mock data so the repo stays runnable for anyone who clones it.

## The five tabs and shared conversation

`AppSection.tabs` in `Alicia/App/RootView.swift` defines the five visible tabs.
The internal `.knowledge` case is labelled Mind; `.mind` is labelled Alicia.
Dialogue retains `.dialogue` for existing routes, rendered outside the five-tab
view and opened through the shared conversation affordance.

1. **Us** (`EpisodeHomeView`) — morning briefing, current episode and grounded
   probes, Together work, and the mind/body overview with private reflection.
2. **Mind** (`KnowledgeView`) — knowledge, syntheses, thinkers and existing pins.
3. **Body** (`BodyView`) — explicit wellness goals and progress criteria,
   daily ritual capture, dated Oura observations/history and private report
   reading. Its optional answer runs on the Mac's local model.
4. **Alicia** (`EpisodeMindView`) — her tentative reading, Hector's words,
   corrections, explicit learnings and existing archetype traces.
5. **Studio** (`StudioView`) — episodes, morning playlist and consumption
   artifacts with the shared immersive reader. Drawing is no longer mounted.
   Actual continuous playback remains distinct from selection or download.

**Dialogue** (`TalkView`) keeps shared history, reviewed voice input and goal
passage context. Mind goal work continues through the existing cloud pipeline;
private Body records do not enter it. See `docs/MIND_BODY.md` for the private
API and offline WidgetKit capture contract.

`WalkReflectionView` is a dedicated full-screen recording and review surface. It
pauses playback and retains original microphone audio. Pause or leaving the
foreground keeps an unfinished recording; Finish seals its complete ordered
manifest, and leaving a walk over 20 seconds seals it too (A2-059). Upload
continues after lock and while closed (CL-20260926-walk-sync), and the Mac
prepares a separate English machine transcript. A walk with at least eight
words is then sent by the Mac itself, recorded as `auto_sent` (backend
`walk_autosend.py`). Private Body walks are never sent this way. Hector can
still open, correct and resend it from Dialogue and Recordings; Dialogue voice
input keeps its explicit reviewed Send. Legacy Apple Speech code remains for existing compatibility paths;
new Mac-mode capture needs microphone permission only. Automatic screen sleep is
disabled while the walk is visible and active, including paused editing, and the
prior idle setting is restored on exit. No background recording is promised. See `docs/MAC_VOICE_PROCESSING.md` for recovery and provenance.

## Architecture

```
Alicia/
  App/            AliciaApp (@main) · RootView (TabView, AppSection)
  DesignSystem/   Theme · InkDrawn · InkUI · Editorial · TabPresence · AliciaPresence
                  · ListeningPresence · RelationalPresence/Geometry
                  · ContourWaves (Motion Lab neighbours + AppVersion)
  Core/           Models · AliciaService (protocol + mock) · LiveAliciaService
                  · Config · AppStore · BodyStore · Collaboration · ContextGraph
                  · GoalClosure · EpisodeDay · MorningBriefing · BriefingSteering*
                  · StudyNote · PresenceField · LivePresence · ChatDelivery
                  · VoiceEvidence · VoiceProcessing · BackgroundVoiceSync
                  · SurfaceContext · PlaceTracker · SpeechReader · … · SampleData
  Features/       Home · Talk · Mind · Body · Knowledge · Studio · Reading · Health
                  · MotionLab (DEBUG) (Canvas retained, unmounted)
  Assets.xcassets AppIcon · AccentColor · Art* (Hector's drawings)
AliciaWidgets/    the Daily rituals widget
Shared/           code shared by the app and the widget (BodyCapture, ritual intent)
```

- **State:** single `@MainActor @Observable final class AppStore`
  (`Core/AppStore.swift`), injected via `.environment(store)`. Holds the
  timeline, proactive feed, tracks, gallery, health, walk-mode state, and the
  real audio player. `scenePhase → .active` refetches everything.
- **Design — ink on paper:** `DesignSystem/Theme.swift`. The language comes
  from Hector's own drawings (bundled as `Art*` assets): warm bone paper,
  near-black ink, one sea-slate accent, serif type everywhere
  (`.fontDesign(.serif)` + UINavigationBar appearance), frameless
  translucent cards. The app forces **`.preferredColorScheme(.light)`** —
  paper wants light.
- **Her presence:** every product surface sits on one continuous particle
  field (`TabPresence.swift` `PresenceLayer`, `AliciaPresence.swift`); a
  section only nudges its shape. Its motion comes from `GET /api/presence`
  (local signals plus an optional rate-limited Jev reading) and from
  `GET /api/presence/live` (listening, thinking and speaking only while that
  is actually happening). The walk and conversation microphones open into
  her listening room (`ListeningRoom`, `ListeningStage`). This replaced the
  `ContourWaves` contour fields (`.waveBackground`), which now remain only as
  Motion Lab neighbours. The older `.artBackground()` washes are unused.

## The networking seam — LIVE

Everything flows through one protocol, `Core/AliciaService.swift`.
`Core/LiveAliciaService.swift` implements it against the backend's iOS API
(`skills/ios_api.py` in the `alicia` repo), a token-authed HTTP/SSE server on
port **8766** on the Mac Studio. Since backend #102 it serves only loopback
and tailnet clients, so the phone uses its Tailscale address. Auth is
`Authorization: Bearer <token>`; media URLs carry `?token=` instead
(AVPlayer/AsyncImage can't set headers). The backend refuses L4-classified
messages on the phone and points to the Telegram passphrase flow. Telegram is
no longer one of her surfaces, so that pointer is a known gap rather than a
working route. Endpoint inventory (current and retained compatibility surfaces):

| Endpoint | For |
|---|---|
| `GET /healthz` | unauthenticated liveness; every `/api/*` route needs the bearer token |
| `POST /api/morning_briefing/feedback` | explicit Useful / Missed (with optional words) on the whole script, or Landed / Didn't land bound to the heard steering path |
| `POST /api/chat` (SSE `{"t": token}` … `{"done": …, "message_id"}`) | Dialogue streaming; optional `voice: true` adds tap-to-play media. Reviewed Mac voice adds `client_request_id`, `recording_id`, machine source IDs and captured `episode_id`. |
| `GET /api/chat_receipt?request_id=<UUID>` | Read-only typed-send outcome. Recovery never resubmits the original model/tool action; the protected phone outbox retains its frozen words/context until acknowledgment. Private Body/health and reviewed voice retain their separate receipts. |
| `GET /api/body` · `POST /api/body` | Private overview and explicit wellness/ritual receipts |
| `GET /api/body/source` · `POST /api/body/ask` | Exact private report passages and optional local health answer |
| `GET /api/thoughts` · `/api/tracks` · `/api/gallery` · `/api/health` | tab data |
| `GET /api/proactive?limit=` | retained proactive feed and best-effort local notifications; never seeds Dialogue history |
| `POST /api/react` | emoji reactions, by `message_id` or `proactive_id` |
| `POST /api/reply` | reply to a proactive message; reviewed Mac voice adds the same receipt/source IDs and retains original `proactive_id` and `episode_id`, without requesting new reply audio |
| `GET /api/greeting` | legacy greeting endpoint; not loaded by the current Us screen |
| `GET /api/context` · `/api/context/<id>` | retained orbit/receipt API; old Us orbit is unmounted |
| `GET /api/context_graph?q=&kind=` · `GET /api/context_graph/<id>` · `POST /api/context_graph` | Hector's context graph — his situation as typed, ranked nodes (stated is his, inferred is unconfirmed); node body + receipts + related; acts `confirm` / `correct` / `retire` / `propose` / `worth`, and `translate` (text → the one node it bears on). Rendered on Us as "In the middle of" (`ContextGraphViews.swift`) |
| `GET /api/context_graph/arrangement` | The day arranged around his active nodes: per node, the episode's questions, validated elevation, mind/body findings, wellness goals, his place and his own words that bear on it, each with the line it was drawn from; `status` preparing/ready/refreshing, and incompatible episode/day groups are withheld while refreshing. Rendered under each node of "In the middle of" (CL-20260919-context-arrangement) |
| `GET /api/context_graph/elevate` · `GET /api/context_graph/translate?title=` | What Us elevates for his situation (thinkers, passages, goals with the line each was drawn from; `status` preparing/ready/refreshing) and a vault note translated into the one node it bears on |
| `GET /api/presence` | Her current motion-driving awareness: deterministic local signals plus an optional rate-limited Jev reading; the app ignores timestamp-only refreshes |
| `GET /api/presence/live` | Live presence: expiring activity facts plus attributed awareness; no text or audio |
| `POST /api/presence/live` | Live presence: bounded ephemeral capture/playback reports; Body excluded |
| `GET/POST /api/intelligence` | Global model-spend boundary shown at the top of Us: `local_first` makes Qwen the ordinary lane, keeps compatible heavy work on the signed-in Claude desktop subscription, and refuses paid Anthropic, OpenAI and general Gemini model APIs. Jev, Gemini full-audio enrichment and Gemini natural voice remain narrow paid exceptions; switching back to `balanced` is explicitly confirmed |
| `GET /api/home` | retained home/library context; no longer the Us framing source |
| `GET /api/timeline` | every lived day since she began (Timeline sheet) |
| `GET /api/featured` · `/api/syntheses` · `/api/quote` | the day's synthesis, the shelf, the rotating quote |
| `GET /api/knowing` · `/api/thinkers` · `/api/archetypes` | Mind library + her archetype balance |
| `POST /api/pin` · `/api/card_feedback` | hold a card on the home screen; 👍/👎 on a card |
| `POST /api/events` | **presence telemetry** — batch `{events:[{kind, ref, ms, meta}]}`. Kinds: `app_open`, `screen_view`, `section_dwell`, `episode_play`, `episode_progress`, `episode_finish`, `card_view`, `place` (named place only, never coordinates). This is the one endpoint that reports what he *did* rather than what he deliberately tapped; without it a day spent listening reads to her as silence. Fire-and-forget — never block UI on it, and batch on background/foreground transitions. Episode playback now comes from the player via `/api/episode_day`; an audio GET is not listening evidence. |
| `GET /api/reflections` | her morning/evening self-reflections, text + a playable reading when rendered |
| `GET /api/mind` | on-demand reading of the current episode, corrections and explicit keeps; Sunday push paused. Current Us/Alicia use `/api/episode_day`. Missing evidence can correctly return `has_note: false`. |
| `GET/POST /api/mode` | walk/drive state; finish accepts `text`, `episode_id`, `request_id` and acknowledges durable save. Reviewed Mac voice also supplies `recording_id`, `transcription_request_id`, `transcript_id`. |
| `GET/POST /api/voice_evidence` | raw voice metadata/versions; additive `finalize` with an ordered expected segment manifest and explicit `retry_transcription`; GET includes separate optional `transcription.draft` |
| `PUT/GET /api/voice_evidence/audio/<recording>/<segment>` | exact original CAF upload/replay, checked by byte count and SHA-256 |
| `GET /api/voice_submission?request_id=<UUID>` | durable Dialogue/proactive voice send status; only definite404 permits reposting the identical pending request |
| `GET /api/episode_day?day=YYYY-MM-DD` | current or historical frame, probes, reactions, corrections, explicit keeps |
| `POST /api/episode_day` | playing/progress/finished observations; reaction, feedback, correction, learning, refresh actions |
| `GET/POST /api/episode_reading` | original podcast read-along: GET returns cached machine transcript and measured word cues; explicit POST prepares the complete catalog episode locally on the Mac. No listening evidence or model call from GET. |
| `GET /api/history` | last 120 actual shared conversation turns with stable receipts and optional reply_id; no proactive feed |
| `GET /api/context_enrichment` | current working picture and captured reply context; optional reply_id; item_id opens captured source |
| `POST /api/context_enrichment` | UUID-receipted attention priority, correction, explicit note or follow-up setting |
| `GET /api/dialogue_review?reply_id=<UUID>` | public context for one saved reply; read-only |
| `POST /api/dialogue_review` | explicit feedback, requested opposite-model comparison, or contextual preference; UUID receipt |
| `GET /api/collaboration` · `POST /api/collaboration` · `GET /api/collaboration/source` | shared goals, connections, prepared work, project revisions and closures; UUID-receipted actions; bounded reads of an exact source or frozen capture (`docs/COLLABORATION.md`) |
| `GET /api/goal_closure?closure_id=` | a finished goal's frozen record: goal, his closing words and whole input, her labelled reflection and next-goal seeds, his words along the way, steps, final artifact, sources, open questions. `GET /api/collaboration` adds `closures` / `closure_proposals`; POST actions `close_goal`, `reopen_goal`, `closure_decision` |
| `GET /api/episode/<label>` | shownotes markdown |
| `POST /api/speak` · `GET /api/speech/<name>` | read-aloud: her voice rendered in ramped chunks (`skills/reading_voice.py`), returned as an ordered chunk list — `ready` / `streaming` / `rendering`, never blocking |
| `GET /api/morning_briefing` (`segments[]`, `steering`) · `POST /api/morning_briefing/steer` · `POST /api/morning_briefing/receipt` · `GET /api/morning_briefing/audio/<id>/<file>.m4a` | the steerable morning briefing (CL-20261015-steerable-briefing): per-segment L+1/L0/L−1 variants with ledger-tagged sentences and measured cues; Higher · Lower · Again returns a deterministic interpretation; the phone posts opportunity, consequence and session-end receipts. Landed / Didn't land goes to `POST /api/morning_briefing/feedback` with the heard path. Study records, never training. See `docs/STEERABLE_BRIEFING.md` |
| `GET /api/study_note` · `POST /api/study_note` | the steering study's weekly note (CL-20261023-study-note-card): whether Us shows the card today (a study week's last day, or the next day if that note is missing; same in both arms; no note text), and saving the template's answers verbatim with a UUID receipt to the study's own notes, which Alicia never reads |
| `GET /api/playlists` · `POST /api/playlist` | Studio's listening queues (create/rename/delete/add/remove/reorder); adding also renders that piece's audio so a queue is warm before he drives |
| `GET /api/stories/<id>.m4a` | the Scaleofus original scored stories in Studio's story queue (allowlisted ids, Range playback) |
| `GET /api/morning_briefing/audio/<id>.m4a` | the briefing's legacy single-track audio (Range) |
| `GET /api/audio/<file>` · `/api/voice/<file>` · `/api/drawing/<file>` | media byte-servers for episode audio, her voice notes and drawings (`?token=`) |
| `POST /api/cocreate` (base64 PNG + size + anchor, 120 s timeout) | canvas co-creation: she draws from where the pencil stopped, returns an overlay layer + caption |
| `POST /api/complement` (base64 PNG, 120 s timeout) | drawing reply w/ vision — superseded by cocreate in the UI; `requestComplement` is currently unused |

Fetches return typed optional/error results through the service seam. AppStore preserves last-known data on failed reads where supported; a real empty payload is different from an unavailable backend. Mutation failures retain explicit error/receipt state for retry.

## Config / secrets

Service selection is config-driven (`Core/Config.swift`), first hit wins:

1. UserDefaults `alicia.baseURL` / `alicia.token` (debugger-set; no settings UI yet).
2. Bundled `Secrets.plist` — **gitignored**; copy `Secrets.example.plist` and fill in.
3. Neither → **silent fallback to `MockAliciaService`** + SampleData. If the
   app looks alive but ignores the backend, check this first.

ATS: root `Info.plist` allows plain HTTP (backend is private-network only).

## Audio & notifications

- **Audio is real** — `AppStore` drives AVPlayer for http-URL tracks (backend
  serves wavs with Range support), publishes `MPNowPlayingInfo` with spiral
  artwork + full metadata + remote commands, so the lock screen / Dynamic
  Island shows a real now-playing card (`audio` background mode). Long
  episodes over the tailnet get a 60 s forward buffer and a
  `playbackStalledNotification` observer that nudges playback back after a
  network dip. The old simulated ticker survives only as the fallback for
  sample tracks. Voice notes use a separate AVPlayer so they never steal the
  podcast position.
- **Notifications** (`Core/ProactiveNotifier.swift`) — no APNs; a
  `BGAppRefreshTask` (`com.alicia.app.refresh`) polls `/api/proactive` and
  posts **local** notifications for unseen messages. iOS controls the timing,
  so it's best-effort. Seen-tracking is shared with the foreground load path.
- **Voice input** (`Core/SpeechTranscriber.swift`, `Core/VoiceEvidence.swift`,
  `Core/VoiceProcessing.swift`) — new Walk/Dialogue input captures original audio
  without starting Apple Speech. The Mac transcribes the finalized recording;
  `Talk/VoiceProcessingView.swift` offers durable review, Done editing and explicit
  Send. The independently typed Dialogue draft remains unchanged. Apple Speech
  recognition is retained as legacy code, not the new capture requirement.
  `docs/MAC_VOICE_PROCESSING.md` documents offline recovery and the exact receipts.

## How to build / run

- Open `Alicia.xcodeproj` in Xcode 16+. Signing Team needed only for a
  physical device (already set up for Hector's iPhone).
- Scheme "Alicia", iPhone simulator destination, Run. Or CLI:
  `xcodebuild -scheme Alicia -destination 'platform=iOS Simulator,name=iPhone 17' build`

## Conventions

- Pure SwiftUI, iOS 17 APIs (`@Observable`, `Gauge`, `symbolEffect`,
  two-param `onChange`, `TextField(axis:)`). No third-party packages.
- Keep the `AliciaService` seam clean — views never touch the network, only
  `AppStore`.
- The section enum is `AppSection` (not `Section`) to avoid SwiftUI's `Section`.
- **HARD RULE: no stock SF Symbols and no emoji anywhere in the app** (v21–v25,
  enforced repeatedly). No rendered screen uses `systemName:`. The four left
  sit in legacy code nothing draws: the unused `statusStrip` in
  `Home/HomeView.swift`, whose body is `EpisodeHomeView()`, and the unmounted
  `Canvas/CanvasView.swift`. Delete them rather than copy them. Every glyph is
  hand-drawn Canvas from `DesignSystem/InkDrawn.swift` (InkPlayPause, InkSkip,
  InkChevron, InkWaveBars, InkSpark, InkSubmitArrow, InkBackButton, InkTabs,
  InkUnderline, HandDrawnBorder, PortraitTrace, InkReactionTag), with
  deterministic seeds — never `@State`-seeded, or the ink re-scribbles every
  frame and reads as noise. The Alicia tab uses the `TabRabbit` template image.
  Her text renders through `String.strippedEmojis` on every surface; reactions
  display as words (LOVE/FIRE/MIND/YES/HMM/NO) while the emoji strings still
  travel to the backend, which keys `reaction_scorer` on them — never change
  that wire format.

## Version tag

`AppVersion.tag` (DesignSystem/ContourWaves.swift) shows on the Alicia tab so
Hector can tell which build his phone runs. Bump `AppVersion.baseTag` and its
date when an app change is promoted. TestFlight branch archives append their
branch automatically through `ship.sh`. Current base: **v43 (Oct 24)**, TestFlight 1.0 (53). TestFlight build numbers are allocated separately; do not bump the tag for documentation or backend-only edits.

## Actually pending

- In-app settings screen for `alicia.baseURL`/`alicia.token` (today:
  debugger or Secrets.plist only).
- Canvas drawings and co-creation overlays aren't persisted between launches
  (`PKDrawing` in `@State`, overlays in `AppStore`).
- Dead code candidates: `.artBackground()` (Theme.swift),
  `AppStore.requestComplement` and `HomeView.statusStrip` — superseded
  (presence field / cocreate / Us) and no longer called.
- The reviewed iOS changes not yet in `main` (see "Current state" at the top).
- `docs/RESEARCH.md` (library research from the scaffold session) is
  historical — the zero-dependency approach won; consult it only if a real
  need for a chat/markdown/image library appears.


## A2-006: brief Dialogue with inspection

This branch adds `Core/DialogueReview.swift` and `Talk/DialogueReviewView.swift`.
**Behind this reply** opens from the short message or its long-press menu. It
shows a saved public reading, lens and supplied context, with granular feedback
and optional labelled comparison; only unchanged-input pairs qualify for training review. `ChatEvent.details` and history `reply_id`
keep the inspection bound to the exact reply. View requests go through AppStore
and AliciaService. Legacy replies keep their original text but have no invented
context. See `docs/DIALOGUE_REVIEW.md` for draft/retry and training boundaries.
The preceding v38 / 1.0 (5) entry is historical. Exact branch build and Apple
processing status are recorded in the shared A2-006 `RELEASE.md` receipt.


## A2-007 — context enrichment (released 2026-09-06)

Dialogue owns its inspector sheet outside LazyVStack rows; each text field has a
separate focus identity. `ContextEnrichmentView` uses AppStore/AliciaService for
frozen context, tentative personal readings, source drill-in and durable edits.
`ListeningPresence` reuses the selected home motion tied to actual microphone
state. `ThoughtReturnNotifier` schedules the backend's optional prepared return
with one local-day reservation, quiet hours and immediate stop/cancellation.
No APNs, training, new Telegram stream or new animation family. Feature contract:
`/Users/alicia/alicia/docs/CONTEXT_ENRICHMENT.md`. Release evidence belongs to
`/Users/alicia/Documents/Alicia-development/tasks/A2-007/RELEASE.md`.

## Original voice archive (A2-009)

`Core/VoiceEvidence.swift` owns original CAF files, capture metadata, text versions,
and the durable upload/deletion outbox. New Mac-mode recordings also retain capture
order, an immutable final manifest, separate machine draft, authored review and
send receipts. Backgrounding or closing pauses recording without finalizing it.
The legacy Apple Speech mode can restart recognition while the raw sink continues;
new Mac capture does not run that recognizer or depend on its permission.
`Talk/VoiceRecordingsView.swift` offers replay, corrections, context and deletion.
AppStore/AliciaService use GET/POST `/api/voice_evidence` and PUT/GET
`/api/voice_evidence/audio/<recording>/<segment>`. The original stays on phone and
private Mac until explicit deletion; no automatic training. Mac processing uses
the paired backend's local transcription worker. The machine draft never
replaces the original. It reaches her only when sent: by Hector after review,
or, for a walk of eight words or more, by the Mac's auto-send, recorded as
`auto_sent` (it is never presented as words he reviewed).
See `docs/MAC_VOICE_PROCESSING.md` for the additive service contract and limits.

## A2-010 — collaborative partner

Read docs/COLLABORATION.md. Core/Collaboration.swift owns the shared goals,
connections, agreements, outcomes and exact pending receipts. CollaborationView
is reached through compact Us/Alicia summaries, Dialogue and Context enrichment;
there is no sixth tab. CollaborationNotifier consumes the shared backend's
purposeful return and preserves its exact navigation target. Its policy has no
daily reservation and supersedes the old ThoughtReturn policy when supported.
The new state uses AliciaService GET/POST /api/collaboration and bounded source
reads; views do not issue HTTP. --collaboration-preview is mock-only.

Morning exercise briefing: `GET /api/morning_briefing` (read-only dated snapshot)
and `GET /api/morning_briefing/audio/<id>.m4a` (authenticated Range audio).
See docs/MORNING_BRIEFING.md. It never selects a podcast episode or manufactures listening evidence.

October 4 health repairs: `POST /api/morning_briefing/feedback` stores explicit script-scoped Useful/Missed feedback and exact optional words with idempotent receipts. `GET /api/stories/<allowlisted-id>.m4a` serves completed Scaleofus original scored audio with Range support; the normal Studio playlist/player carries Book One v17 and Count Love v15. `/api/health` exposes actual briefing/voice/goal availability and sparse-feedback uncertainty. Goal work reviews queue independently by result/section and saved drafts resume explicitly. No on-device speech fallback or inferred listening/learning is introduced.

## CL-20261015-steerable-briefing — steering the briefing while it plays

`Core/BriefingSteering.swift` (payload models and the pure `BriefingPlanner`,
which mirrors the backend's interpretation rules), `Core/BriefingSteeringController.swift`
(session, stretches, outbox, verified audio cache, remote-command mapping) and
`Features/Reading/BriefingSteerControls.swift` add Higher · Lower · Again to the
morning briefing. `SpeechReader` plays a path of clipped pieces and changes only
what follows the sounding piece (`replaceFuture`). The arm comes from the
payload; Landed / Didn't land is bound to the heard path; pause is never a
signal. Fixture: `--morning-briefing-steer-preview` (invented text). See
`docs/STEERABLE_BRIEFING.md`.

Two study-time changes shipped on top (both recorded as dated study
deviations):
- **TF48, faded commands.** Higher and Lower fade when a press would change
  nothing.
- **TF49, the room.** Starting the briefing opens `Features/Reading/BriefingStage.swift`.
  It is a full-screen room of her particle field breathing with her voice, with
  no text, and the phone stays awake. That build was the study build from day
  one.

Backend #98–#100 carry the segments, steering and the per-segment L0 check.
Preparation starts at 04:30 during the study.


## CL-20261023-study-note-card — the study's weekly note on Us

`Core/StudyNote.swift` (status, draft with its receipt, protected per-week draft
files, response mapping) and `Features/Home/StudyNoteCard.swift`.
- **The card.** A quiet line sits at the top of Us only when
  `GET /api/study_note` says so: a study week's last day, or the next day if
  that week's note is missing. It reads "Week N note · two minutes, your own
  words".
- **The sheet.** It opens the template's six prompts plus "Mornings I played
  it", and blank is valid. Every keystroke is kept on the phone.
- **Saving.** SAVE posts the words verbatim with a UUID receipt. A retry of the
  same words reuses it; changed words get a new one. Only a confirmed save
  clears the draft. The card then reads "Week N note saved" for the rest of
  the day.
- **Fixture:** `--study-note-preview` (`--study-note-fail-once` for the retry
  path). Logic is in `scripts/test_study_note.py`, UI in
  `scripts/test_study_note_ui.py`.


## Her presence — the field as her awareness, then as what is happening

Three releases built the one field that now sits behind every section.
- **Awareness (CL-20260926-presence; in `main` since TF39).**
  - `Core/PresenceField.swift` decodes `GET /api/presence`. The backend
    (`skills/presence_awareness.py`) reads her own signals: whether he is
    speaking, whether goal work is running or a question is waiting, and the
    time of day. A rate-limited, typed Jev reading adds a stance (witness, ask,
    offer, hold, celebrate).
  - The stance chooses the form she leans into, and a section only nudges it.
  - Timestamp-only refreshes are ignored.
- **One continuous body (CL-20260927-presence-home, TF40).**
  - `TabPresence.swift` `PresenceLayer` replaced `.waveBackground` on the
    product surfaces.
  - The walk and conversation microphones open `ListeningRoom` and
    `ListeningStage`: her particles listening rather than his transcript.
  - Back from "Play in Studio" returns to Us.
- **Live presence (CL-20261024-live-presence, TF52; in `main` with TF53).**
  - `Core/LivePresence.swift` posts `POST /api/presence/live` from actual
    audio-engine capture and actual `.playing` playback, never from opening a
    screen.
  - Each post carries only a UUID, sequence, surface, state, a normalized meter
    and a timestamp. Capture holds an eight-second expiring lease.
  - The backend adds reply preparation from real non-private jobs and serves
    `GET /api/presence/live` to the phone and to the room's Nest display. The
    stance stays attributed to the awareness reading.
  - Private Body capture and narration are excluded.
  - The DEBUG Motion Lab entry is `--motion-lab --live-presence-lab`. See
    `docs/LIVE_PRESENCE.md`.

The organic-field prototype (CL-20261018-organic-field) is a DEBUG Motion Lab
candidate on its own branch, not in `main`. Nothing from it ships before the
study ends and Hector picks one.
