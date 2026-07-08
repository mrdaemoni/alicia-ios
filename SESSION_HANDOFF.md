# Session Handoff — Alicia iOS + Backend (as of v27, 2026-07-07)

Continuation doc for iterating on the iPhone app (`~/AliciaApp`) and its
backend surface (`~/alicia`, `skills/ios_api.py`). Written at the close of the
July 3–5 build marathon (v1 → v19); v20 (2026-07-07) added the
loop-architecture home; v21 (same day) the hand-drawn chrome. Read this,
then `CLAUDE.md`, then go.

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

## Current app shape (v20)

Five tabs — `AppSection` in `App/RootView.swift`: **Us · Dialogue · Alicia ·
Studio · Knowledge** (Canvas lives INSIDE Studio as a segmented mode;
Health is pushed from Us's status strip).

- **Us (v20 — the loop architecture)**: her live greeting, proactive reply
  card, then three concentric loops from `/api/home` (`skills/home_context.py`):
  **SeasonArcCard** (season theme + episode-node spine + current movement) →
  **TrailCard** (previous days' episodes) → **TodayEpisodeCard** (today's
  pick, focus claim, one-tap LISTEN into Studio) → **knowledge cards** mined
  from today's shownotes (quote / thinkers / ideas), each with a feedback row
  (RELEVANT · GREAT · NOT TODAY + a why-note follow-up → POST
  /api/card_feedback → evidence-shrunk card-ordering weights + daily signal;
  loop 10 in the backend map). Tap the "Us" title → **UsSheet**: TODAY (the
  context line — what she thinks you two are talking about today — episode,
  season, trail, what she's surfacing) with THE ARC timeline one segment
  away. Below the loops: featured synthesis, quote, drawing, voice of the
  moment, knowing card, thinkers-in-your-ears strip, status strip.
  (EpisodeAskCard renders only when /api/home has no active episode.)
- **Dialogue**: SSE chat + dictation mic + walk mode + voice-note replies +
  emoji reactions; her impulses render as editorial interludes (hairlines +
  emblem + serif italic) that deep-link to the exact card on the Alicia tab.
  v23: sends the backend flags `is_ask` (kind tokens — Rule-11 word-boundary,
  💭 rider glyph, tail "?") arrive as FULL bubbles with ANSWER HER → —
  answering-mode composer routes the reply through /api/reply (Tier-3
  capture + circulation attribution, same as answering on Telegram).
- **Alicia**: THE VOICES gallery ranked by the real loop (`/api/archetypes`),
  custom ink emblems per voice (`ArchetypeEmblem`), manifesto sheets, recent
  thinking cards, version tag.
- **Studio**: podcast library by season wearing Hector's art tiles, editorial
  episode plates with shownotes, persistent player (scrub/±15s/rate,
  Dynamic Island artwork), co-creation canvas mode (she draws from where the
  pencil stopped — `/api/cocreate`).
- **Knowledge (v21: two rooms)**: `InkTabs` KNOWLEDGE | THINKERS — the
  syntheses shelf in one, the full 313-thinker network inline in the other
  (ThinkersPage subpage folded in; deep-links set `store.knowledgeSegment`).
  `ThinkerSheet` ends in **MINDS LIKE THIS ONE**, now a hand-stitched
  **ThinkerConstellation** — staggered faces joined by bowed ink threads +
  knot rings; why-they-connect lines from vault co-citation + theme overlap
  (`skills/data/thinker_links.json` ← `scripts/build_thinker_links.py`);
  tapping hops the sheet (breadcrumb + back), so the graph walks end to end.
- **Hand-drawn chrome (v21–v22)** — `DesignSystem/InkDrawn.swift`, all
  deterministic-seeded Canvas (no @State — nothing shimmers on scroll):
  `HandDrawnBorder` on every `.card()` (subtle since v22),
  `InkUnderline` under the selected tab-bar word, `InkTabs` replacing every
  segmented picker, `InkSubmitArrow` for every send affordance,
  `PortraitTrace` (her pen circling every thinker photograph). v22 finished
  the de-widgeting: `InkPlayPause`/`InkSkip`/`InkWaveBars`/`InkChevron`/
  `InkSpark`/`InkBackButton` replaced every stock play/pause/±15/waveform/
  chevron/back glyph across Home, Studio (incl. the DRAW|LISTEN word
  toggle), Knowledge, and Health; the Alicia tab strips message emojis in
  favor of ink sparks. Home knowledge-card feedback is hidden until the
  card is tapped (three resting dots mark the spot).
- **THE ARC is legible (v22)** — `/api/timeline` rows now carry `learned`
  (hector_learnings bucketed by local day), `thread` (the day's circulated
  idea, hash-ids filtered), and `goal`; the sheet renders them per day.
- **Badge (v22)** — local notifications set `content.badge` from an own
  counter (`ProactiveNotifier`), cleared on scenePhase.active.
- **No emoji, anywhere (v24–v25, HARD RULE)** — Hector enforced this twice:
  her displayed text passes through `String.strippedEmojis` on every
  surface (bubbles, whispers, SaidCards, Us proactive card, greeting,
  thoughts, knowing claims, timeline lines, synthesis reader, quote card,
  shownotes, notifications, widget cache). Reactions are WORDS
  (LOVE/FIRE/MIND/YES/HMM/NO via `InkReactions`) + `InkReactionTag` badge;
  the emoji strings still travel to the backend unchanged (loops key on
  them). Dialogue's last stock glyphs went too: WALK/VOICE/MIC words,
  THE REST → fold, ink ring on voice notes.
- **Pins (v26)** — `InkPinMark` (dot → her asterisk) top-right of every
  knowledge card + on thinker sheets. Pinned items persist server-side
  (`memory/pinned_items.json`, POST `/api/pin`, in the `/api/home` payload)
  and render in a HELD · STILL TALKING ABOUT section atop Us until
  released. A pin is ALSO an interest signal: `home_context.pin_item`
  appends a hector_learnings row (source=ios_pin) — loop-4 fuel. Unpin is
  quiet (no negative signal).
- **v26 aesthetics** — `ContextOnion` (TODAY sheet: the day as three
  hand-pulled concentric rings, in→out); THE ARC wears archetype emblems
  per day (`timeline` rows carry `archetype`), a trembling/curling spine
  (`InkSpineSegment`), milestone underlines; `InkTitleLine`/`InkTitle`
  hand-set display type (per-glyph lean + baseline drift) on the greeting,
  all SectionHeaders, episode plates/rows/nav; Studio's background is the
  `.soundwave` ContourWaves pattern — stacked waveforms, not sonar.
- **Widget** (`AliciaWidgets/` target): greeting + today's synthesis from the
  app-group cache (`group.com.myalicia.app`) — no network of its own.

## Backend surface (skills/ios_api.py, :8766)

chat (SSE+voice) · react (message/proactive) · reply · proactive · greeting ·
featured · quote · archetypes · timeline · knowing · thinkers (now with
per-thinker `related` edges) · syntheses · tracks/audio/episode · mode (walk) ·
cocreate · complement · gallery/drawing · health · **home** (the loop payload;
capability in `skills/home_context.py`) · **card_feedback** (POST; writes the
contracted `card_feedback.jsonl` + `home_card_weights.json`) · healthz. All
payload builders are pure + defensive; harness callables arrive via
`start_ios_api(deps=...)` — skills never import alicia.py.

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
anywhere** (inkSoft is ink at 78%); **no SF Symbols and no emojis anywhere**
(InkDrawn glyphs + strippedEmojis — see the v24–v25 bullet above);
serif display + mono-caps tracked kickers
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

## v27 addenda (2026-07-07, late)

- **Her hand is TRUE CURSIVE now** — `InkTitleLine`/`InkTitle` use Snell
  Roundhand (system script) with per-WORD lean/baseline drift. NEVER go
  back to per-glyph jitter: it breaks script ligatures and Hector called
  it "sloppy type". Scale script sizes ~1.22× (small x-height).
- **Widget**: systemSmall/Medium/Large; paper tint follows the hour
  (night = bone on ink); cache keys now include widget.todayLabel/
  todayTitle/context/carry (written by AppStore.publishWidgetCache).
- **Knowledge background** = `.particles` pattern (idea-nodes + faint
  threads); Studio = `.soundwave`; Us/Dialogue contour; Alicia ripples.
- **PlayerBar is global** (RootView hard sibling above the word-bar,
  hidden while the Dialogue composer is up). Do not mount it per-tab.
- **Thinkers open in place** via `store.showThinker(named:)` /
  `presentThinker` (falls back to Knowledge deep-link pre-load).
  ThinkerSheet: cursive name, `InkAnnotatedText` (underlined key words +
  dashed connecting thread), `InkDividerCurl` between sections.

## v28 addenda (2026-07-07, night)

- **Her hand = Zapfino** (0.82× in `InkTitleLine`; widget 12–16pt). The
  brief: "a smart notepad that is alive"; squiggle over polish. **The
  iOS 26 SIM substitutes ALL Font.custom with New York serif — judge
  scripts on device or a macOS PIL proof, never the sim.**
- Global player reverted — PlayerBar is Studio-only again (inset on the
  NavigationStack). Tab bar spaces by equal gaps, not equal columns.
- Alicia tab field = sparse contour (calm); Knowledge = particles.
- `InkSquiggle` + `InkHighlightedText` (FlexWrap now takes `trailing:`)
  underline the recurring shelf words (computed client-side from
  syntheses titles+excerpts, ≥5 letters, ≥3 occurrences, top 8).
