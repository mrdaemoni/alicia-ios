# CLAUDE.md — Alicia iOS

**Read `AGENTS.md` before doing anything.** It is the repository-wide contract
for Codex–Opus coordination, worktrees, file ownership, review handoffs, Git,
and the Motion Lab promotion gate.

Read `SESSION_HANDOFF.md` for the current release and known limits. This file
carries stable architecture. The current product is the Alicia 2.0 episode/day
experience; this branch adds A2-033 shared work review on released source
207279e / TestFlight 15, including Mac voice processing. Read `docs/WORK_REVIEW.md`;
the shared task RELEASE.md records actual deployment and upload. Full cross-repository context is in
`/Users/alicia/alicia/docs/ALICIA_2_0.md`; feature detail is in `docs/EPISODE_DAY.md`.
Us and Alicia use the actually played episode and explicit human responses.
The older orbit/cards and archetype gallery are unmounted.

## What this is

A native **pure-SwiftUI** iOS app for "Alicia," Hector's personal AI agent.
The backend is the separate Python service in the `alicia` repo
(github.com/mrdaemoni/alicia — also reachable via Telegram and Cowork; one
relationship, three touchpoints). Target **iOS 17.0**, Swift 5.9+, the installed Xcode, **zero third-party
dependencies**. Runs live against the backend on a real iPhone; falls back to
mock data so the repo stays runnable for anyone who clones it.

## The five tabs

Defined in `Alicia/App/RootView.swift` as `enum AppSection` → `TabView`
(kept at five so iOS never folds tabs into "More"):

1. **Us** (`EpisodeHomeView`) — the episode actually played today, two or three
   precise questions with inspectable passages, and a large **Walk with this**
   action. Questions carry This helps / Go deeper / Missed me. Connection and
   dated history remain available. The old orbit/cards are unmounted.
2. **Dialogue** (`TalkView`) — the real shared conversation restored from
   `/api/history`, a small current-episode header, reviewed voice input, optional voice
   replies, and Think aloud. The backend uses the same retrieval/model/tool
   routing boundary as Telegram. Proactive feed items do not seed the transcript.
3. **Alicia** (`EpisodeMindView`) — her tentative reading, Hector's words,
   corrections, and explicit learnings. He can correct her and keep something
   in his own words. A prior rejected reading remains labelled while updating.
4. **Studio** (`StudioView`) — the podcast and playlist library, shownotes,
   playback, scrubbing, skips, and rate controls. AppStore reports actual
   continuous playback; file downloads establish no listening evidence.
5. **Knowledge** (`KnowledgeView`) — the passive synthesis/notes library and
   existing pins. Studio and Knowledge retain their library roles.

`WalkReflectionView` is a dedicated full-screen recording and review surface. It
pauses playback and retains original microphone audio. Pause or leaving the
foreground keeps an unfinished recording; Finish seals its complete ordered
manifest. Foreground sync uploads the audio, and the Mac prepares a separate
machine transcript. Hector reviews and edits it, then explicitly sends those
words with a durable receipt. The same review is reachable from Dialogue and
Recordings. Legacy Apple Speech code remains for existing compatibility paths;
new Mac-mode capture needs microphone permission only. Automatic screen sleep is
disabled while the walk is visible and active, including paused editing, and the
prior idle setting is restored on exit. No background recording or locked-phone
upload is promised. See `docs/MAC_VOICE_PROCESSING.md` for recovery and provenance.

## Architecture

```
Alicia/
  App/            AliciaApp (@main) · RootView (TabView, AppSection)
  DesignSystem/   Theme.swift · ContourWaves.swift (animated home bg + AppVersion)
  Core/           Models · AliciaService (protocol + mock) · LiveAliciaService
                  · Config · AppStore · SpeechTranscriber · ProactiveNotifier
                  · SampleData
  Features/       Home · Talk · Mind · Studio · Canvas · Health
  Assets.xcassets AppIcon · AccentColor · Art* (Hector's drawings)
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
- **The living water:** every main page breathes under `ContourWaves`
  (the fromfutureself.com contour field, marching squares at 12 fps).
  Each tab gets a sister field via `.waveBackground(config)` — Us full,
  Dialogue sparse, Alicia slow/dense, Studio a horizontal current. The
  fields modulate with **time of day** (speed + ink weight, darker at
  night), **season** (density + monthly re-seed), and **her mood**
  (`AppStore.waveMood`, seeded from the latest proactive archetype). The
  older `.artBackground()` drawing washes were replaced by the fields and
  the modifier is currently unused.

## The networking seam — LIVE

Everything flows through one protocol, `Core/AliciaService.swift`.
`Core/LiveAliciaService.swift` implements it against the backend's iOS API
(`skills/ios_api.py` in the `alicia` repo), a token-authed HTTP/SSE server on
port **8766** (Mac Mini; home Wi-Fi or Tailscale). Auth is
`Authorization: Bearer <token>`; media URLs carry `?token=` instead
(AVPlayer/AsyncImage can't set headers). L4-classified messages are redirected
to Telegram by the backend. Endpoint inventory (current and retained compatibility surfaces):

| Endpoint | For |
|---|---|
| `POST /api/chat` (SSE `{"t": token}` … `{"done": …, "message_id"}`) | Dialogue streaming; optional `voice: true` adds tap-to-play media. Reviewed Mac voice adds `client_request_id`, `recording_id`, machine source IDs and captured `episode_id`. |
| `GET /api/thoughts` · `/api/tracks` · `/api/gallery` · `/api/health` | tab data |
| `GET /api/proactive?limit=` | retained proactive feed and best-effort local notifications; never seeds Dialogue history |
| `POST /api/react` | emoji reactions, by `message_id` or `proactive_id` |
| `POST /api/reply` | reply to a proactive message; reviewed Mac voice adds the same receipt/source IDs and retains original `proactive_id` and `episode_id`, without requesting new reply audio |
| `GET /api/greeting` | legacy greeting endpoint; not loaded by the current Us screen |
| `GET /api/context` · `/api/context/<id>` | retained orbit/receipt API; old Us orbit is unmounted |
| `GET /api/home` | retained home/library context; no longer the Us framing source |
| `GET /api/timeline` | every lived day since she began (Timeline sheet) |
| `GET /api/featured` · `/api/syntheses` · `/api/quote` | the day's synthesis, the shelf, the rotating quote |
| `GET /api/knowing` · `/api/thinkers` · `/api/archetypes` | Knowledge tab + her archetype balance |
| `POST /api/speak` | render arbitrary text in her voice (read-aloud fallback when nothing is cached) |
| `POST /api/pin` · `/api/card_feedback` | hold a card on the home screen; 👍/👎 on a card |
| `POST /api/events` | **presence telemetry** — batch `{events:[{kind, ref, ms, meta}]}`. Kinds: `app_open`, `screen_view`, `section_dwell`, `episode_play`, `episode_progress`, `episode_finish`, `card_view`. This is the one endpoint that reports what he *did* rather than what he deliberately tapped; without it a day spent listening reads to her as silence. Fire-and-forget — never block UI on it, and batch on background/foreground transitions. Episode playback now comes from the player via `/api/episode_day`; an audio GET is not listening evidence. |
| `GET /api/reflections` | her morning/evening self-reflections, text + a playable reading when rendered |
| `GET /api/mind` | on-demand reading of the current episode, corrections and explicit keeps; Sunday push paused. Current Us/Alicia use `/api/episode_day`. Missing evidence can correctly return `has_note: false`. |
| `GET/POST /api/mode` | walk/drive state; finish accepts `text`, `episode_id`, `request_id` and acknowledges durable save. Reviewed Mac voice also supplies `recording_id`, `transcription_request_id`, `transcript_id`. |
| `GET/POST /api/voice_evidence` | raw voice metadata/versions; additive `finalize` with an ordered expected segment manifest and explicit `retry_transcription`; GET includes separate optional `transcription.draft` |
| `PUT/GET /api/voice_evidence/audio/<recording>/<segment>` | exact original CAF upload/replay, checked by byte count and SHA-256 |
| `GET /api/voice_submission?request_id=<UUID>` | durable Dialogue/proactive voice send status; only definite404 permits reposting the identical pending request |
| `GET /api/episode_day?day=YYYY-MM-DD` | current or historical frame, probes, reactions, corrections, explicit keeps |
| `POST /api/episode_day` | playing/progress/finished observations; reaction, feedback, correction, learning, refresh actions |
| `GET /api/history` | last 120 actual shared conversation turns with stable receipts and optional reply_id; no proactive feed |
| `GET /api/context_enrichment` | current working picture and captured reply context; optional reply_id; item_id opens captured source |
| `POST /api/context_enrichment` | UUID-receipted attention priority, correction, explicit note or follow-up setting |
| `GET /api/dialogue_review?reply_id=<UUID>` | public context for one saved reply; read-only |
| `POST /api/dialogue_review` | explicit feedback, requested opposite-model comparison, or contextual preference; UUID receipt |
| `GET /api/episode/<label>` | shownotes markdown |
| `POST /api/speak` · `GET /api/speech/<name>` | read-aloud: her voice rendered in ramped chunks (`skills/reading_voice.py`), returned as an ordered chunk list — `ready` / `streaming` / `rendering`, never blocking |
| `GET /api/playlists` · `POST /api/playlist` | Studio's listening queues (create/rename/delete/add/remove/reorder); adding also renders that piece's audio so a queue is warm before he drives |
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
  enforced repeatedly). Verified: zero `systemName:` in `Alicia/`. Every glyph is
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
branch automatically through `ship.sh`. Current base: **v38 (2026-09-05)**. TestFlight build numbers are allocated separately; do not bump the tag for documentation or backend-only edits.

## Actually pending

- In-app settings screen for `alicia.baseURL`/`alicia.token` (today:
  debugger or Secrets.plist only).
- Canvas drawings and co-creation overlays aren't persisted between launches
  (`PKDrawing` in `@State`, overlays in `AppStore`).
- Dead code candidates: `.artBackground()` (Theme.swift) and
  `AppStore.requestComplement` — both superseded (wave fields / cocreate)
  and no longer called.
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


## A2-007 — context enrichment candidate

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
the paired backend's local transcription worker. The new machine draft never
replaces the original or becomes a human statement until explicit reviewed Send.
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
