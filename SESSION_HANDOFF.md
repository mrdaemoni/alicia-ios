# Session Handoff — Alicia iOS + Backend (as of v19, 2026-07-05)

Continuation doc for iterating on the iPhone app (`~/AliciaApp`) and its
backend surface (`~/alicia`, `skills/ios_api.py`). Written at the close of the
July 3–5 build marathon (v1 → v19). Read this, then `CLAUDE.md`, then go.

## The two repos, one feature loop

| | App | Backend |
|---|---|---|
| Path | `~/AliciaApp` | `~/alicia` |
| Repo | github.com/mrdaemoni/alicia-ios | github.com/mrdaemoni/alicia |
| Rules | this file + CLAUDE.md | **alicia-dev skill is MANDATORY** (smoke_test gate, wiring rules, push protocol, touchpoint parity Rule 14) |
| Test gate | `xcodebuild -scheme Alicia -destination 'platform=iOS Simulator,name=iPhone 17' build` | `python3 tests/smoke_test.py` — capture exit code directly, NEVER through a pipe (a red test once shipped hidden behind `\| tail`) |

**Every new feature is usually both sides:** a payload builder + route in
`skills/ios_api.py` (+ smoke test, + restart via `alicia-restart`), then a
method in `Core/AliciaService.swift` protocol (+ Mock + Live impls), state in
`Core/AppStore.swift`, and a view. Media URLs carry `?token=` (AVPlayer/
AsyncImage can't set headers); everything else uses `Authorization: Bearer`.

## Current app shape (v19)

Five tabs — `AppSection` in `App/RootView.swift`: **Us · Dialogue · Alicia ·
Studio · Knowledge** (Canvas lives INSIDE Studio as a segmented mode;
Health is pushed from Us's status strip).

- **Us**: her live greeting (tap the "Us" title → THE ARC timeline sheet since
  her birth), proactive reply card, featured synthesis (reader sheet with
  thinker chips), quote of the moment (copy button), her best drawing, voice
  of the moment, today's listening (deep-links to Studio), thinkers
  in-your-ears strip, "what she knows about me" loops card, status strip.
- **Dialogue**: SSE chat + dictation mic + walk mode + voice-note replies +
  emoji reactions; her impulses render as editorial interludes (hairlines +
  emblem + serif italic) that deep-link to the exact card on the Alicia tab.
- **Alicia**: THE VOICES gallery ranked by the real loop (`/api/archetypes`),
  custom ink emblems per voice (`ArchetypeEmblem`), manifesto sheets, recent
  thinking cards, version tag.
- **Studio**: podcast library by season wearing Hector's art tiles, editorial
  episode plates with shownotes, persistent player (scrub/±15s/rate,
  Dynamic Island artwork), co-creation canvas mode (she draws from where the
  pencil stopped — `/api/cocreate`).
- **Knowledge**: fresh syntheses shelf + 318-thinker network (Wikipedia
  portraits in duotone, theme filters, `ThinkersPage` subpage).
- **Widget** (`AliciaWidgets/` target): greeting + today's synthesis from the
  app-group cache (`group.com.myalicia.app`) — no network of its own.

## Backend surface (skills/ios_api.py, :8766)

chat (SSE+voice) · react (message/proactive) · reply · proactive · greeting ·
featured · quote · archetypes · timeline · knowing · thinkers · syntheses ·
tracks/audio/episode · mode (walk) · cocreate · complement · gallery/drawing ·
health · healthz. All payload builders are pure + defensive; harness callables
arrive via `start_ios_api(deps=...)` — skills never import alicia.py.

## Ship loop (memorize)

1. Bump `AppVersion.tag` in `DesignSystem/ContourWaves.swift` — Hector reads
   it on the Alicia tab to know he's on the latest build. EVERY shipped change.
2. Simulator build green → verify visually (`simctl launch` + screenshot;
   pixel-diff two frames when claiming something animates).
3. Backend: smoke green (unmasked exit) → commit → push → `alicia-restart`.
4. App: commit → push → `xcodebuild -destination 'generic/platform=iOS'
   -allowProvisioningUpdates build` → `xcrun devicectl device install app
   --device FE4F87D0-38E4-54AC-B5EA-AD68FF4EEE76 …/Debug-iphoneos/Alicia.app`
   (needs `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`, phone on
   USB — check `ioreg -p IOUSB | grep -i iphone`; empty `system_profiler
   SPUSBDataType` means the Mac's USB stack is wedged → reboot the Mac mini).

## Design language (he will reject deviations)

Ink-on-bone from his drawings: `Theme.paper`/`Theme.ink`; **no warm gray
anywhere** (inkSoft is ink at 78%); serif display + mono-caps tracked kickers
(Co-Star register); alternating alignments; everything decorative is
procedural Canvas — `ContourWaves` (per-tab sister fields, time-of-day tint +
ink weight, seasonal reseed, her-mood seed), `StippleIllustration` (breathing
engraved forms, heartbeat pulse), `ArchetypeEmblem` (six hand-drawn glyphs),
`InkStroke` (trembling bars). The bottom bar is a HARD VStack sibling
(`RootView`) — **`.safeAreaInset` is banned** (failed 3× on device). The
composer lives inside the ink frame.

## Known gaps / natural next steps

- Vault-only thinkers (282 of 318) mostly lack `#theme/` tags → invisible to
  theme filters until a vault tagging pass; regeneration script documented in
  backend commit 60af452.
- No in-app settings for baseURL/token (Secrets.plist only).
- Canvas drawings don't persist between launches (`PKDrawing` in `@State`).
- THE ARC milestones come from diary growth lines only; "moments we built
  together" (git/HANDOFF events) could join as a second node kind.
- Deep link from the widget into the app (tap → Us) not wired.
- Proactive polling is 60s foreground + best-effort BGAppRefresh; true push
  would need APNs (paid dev account).

## Context pointers

- Memory: `aliciaapp-ios-lessons` (ship loop + gotchas), `alicia-drawing-aesthetic`.
- Her side of the story: `~/alicia/ARCHITECTURE_MAP.md` (canonical),
  vault `Alicia/Bridge/HANDOFF.md` 2026-07-05 entry ("you have a third body").
- Device: iPhone Air "Pandaiux", iOS 26.5, Tailscale IP backend
  (`http://100.81.90.92:8766` in gitignored `Alicia/Secrets.plist`).
