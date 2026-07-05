# CLAUDE.md — Alicia iOS

Context handoff for continuing this project in Claude Code. Everything below
reflects the app as of **v11 (2026-07-04)** — verify against the code, this
doc has drifted before.

## What this is

A native **pure-SwiftUI** iOS app for "Alicia," Hector's personal AI agent.
The backend is the separate Python service in the `alicia` repo
(github.com/mrdaemoni/alicia — also reachable via Telegram; one relationship,
two surfaces). Target **iOS 17.0**, Swift 5.9+, Xcode 16, **zero third-party
dependencies**. Runs live against the backend on a real iPhone; falls back to
mock data so the repo stays runnable for anyone who clones it.

## The five tabs

Defined in `Alicia/App/RootView.swift` as `enum AppSection` → `TabView`
(kept at five so iOS never folds tabs into "More"):

1. **Us** (`Features/Home/HomeView.swift`) — landing page: her live greeting
   (`/api/greeting`), latest proactive message with an inline reply field
   (`ProactiveReplyCard`), a day-thought card, now-playing chip, and a status
   strip that pushes **Health** (`Features/Health/HealthView.swift` — vitals
   gauges; deliberately no NavigationStack of its own).
2. **Dialogue** (`Features/Talk/TalkView.swift`) — chat. SSE token streaming,
   emoji reactions, optional voice-note replies, mic dictation in the
   composer, and a **Walk** toolbar button (same session as Telegram's
   `/walk`: while walking, input is accumulated, not answered). Her proactive
   messages appear as left-aligned "whisper" chips that deep-link to the
   exact card on the Alicia tab (`pendingMindFocusID` + ScrollViewReader).
3. **Alicia** (`Features/Mind/MindView.swift`) — her space: mode/state header
   with her rabbit mark, the version tag, her recent proactive messages
   ("What she's been saying"), and thought cards. Timeline opens seeded from
   the proactive feed. Tab icon is `TabRabbit` (Hector's rabbit silhouette,
   template-tinted), not an SF Symbol.
4. **Studio** (`Features/Studio/StudioView.swift`) — podcast library grouped
   by season, episode detail pages with shownotes (`/api/episode/<label>`),
   player bar with scrubbing, ±15s skip, and 1×/1.5×/2× rate — mounted as a
   `safeAreaInset` on the NavigationStack so it survives detail pushes.
5. **Canvas** (`Features/Canvas/CanvasView.swift` + `PencilCanvas.swift`) —
   segmented **My Canvas** / **Alicia's Gallery**. **Co-creation**: "Alicia
   continues" sends the flattened canvas + where the pencil stopped
   (`/api/cocreate`); her returned stroke layers render *under* the live
   PencilKit layer, so you draw on top of her and she on top of you.

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
to Telegram by the backend. Endpoints in use:

| Endpoint | For |
|---|---|
| `POST /api/chat` (SSE `{"t": token}` … `{"done": …, "message_id"}`) | Dialogue streaming; optional `voice: true` adds a voice-note URL |
| `GET /api/thoughts` · `/api/tracks` · `/api/gallery` · `/api/health` | tab data |
| `GET /api/proactive?limit=` | her proactive messages (feed + notifications + timeline seed) |
| `POST /api/react` | emoji reactions, by `message_id` or `proactive_id` |
| `POST /api/reply` | reply to a proactive message (lands in capture/history/memory) |
| `GET /api/greeting` | Us-page greeting |
| `GET/POST /api/mode` | walk/drive thinking-mode state + start/end |
| `GET /api/episode/<label>` | shownotes markdown |
| `POST /api/cocreate` (base64 PNG + size + anchor, 120 s timeout) | canvas co-creation: she draws from where the pencil stopped, returns an overlay layer + caption |
| `POST /api/complement` (base64 PNG, 120 s timeout) | drawing reply w/ vision — superseded by cocreate in the UI; `requestComplement` is currently unused |

All fetches degrade gracefully — errors return empty/nil, never throw to views.

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
- **Voice input** (`Core/SpeechTranscriber.swift`) — on-device SFSpeech
  dictation straight into the Dialogue composer.

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
- Tab icons are line-art SF Symbols (never filled) to match the ink identity —
  except the Alicia tab, which uses the `TabRabbit` template image.

## Version tag

`AppVersion.tag` (DesignSystem/ContourWaves.swift) shows on the Alicia tab so
Hector can tell which build his phone runs. **Bump it (v8 → v9 → …) and its
date in every change that ships.** Current: v11 (2026-07-04).

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
