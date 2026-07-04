# CLAUDE.md — Alicia iOS

Context handoff for continuing this project in Claude Code. This app was scaffolded in a Cowork session; everything below reflects that starting state.

## What this is

A native **pure-SwiftUI** iOS app for "Alicia," a personal AI agent (whose backend is a separate Python service — currently Telegram-based). The app is Hector's interface to Alicia. Target **iOS 17.0**, Swift 5.9+, Xcode 16. **Zero third-party dependencies** right now — it builds and runs on the simulator as-is. Runs on the iPhone 17 simulator; verified building and running with a working live preview.

## The five sections (tabs)

Defined in `Alicia/App/RootView.swift` as `enum AppSection` → `TabView`:

1. **Talk** (`Features/Talk/TalkView.swift`) — Hector messaging Alicia. Native bubbles + composer; Alicia's replies stream in token-by-token.
2. **Alicia** (`Features/Mind/MindView.swift`) — her introspection: mood/focus header, a live "thinking" pulse, cards of recent thoughts.
3. **Studio** (`Features/Studio/StudioView.swift`) — Spotify-style player for audio she makes (wav/mp3): playlist + tappable tracks + persistent now-playing bar.
4. **Canvas** (`Features/Canvas/CanvasView.swift` + `PencilCanvas.swift`) — one tab, segmented **My Canvas** (real PencilKit drawing) / **Alicia's Gallery** (grid of her + your drawings). "Ask Alicia to reply" seeds a gallery item.
5. **Health** (`Features/Health/HealthView.swift`) — her vitals dashboard (presence, mood, memory, responsiveness…) as gauge tiles.

## Architecture

```
Alicia/
  App/            AliciaApp (@main entry) · RootView (TabView)
  DesignSystem/   Theme.swift  (palette, .card() modifier, backdrop gradient)
  Core/           Models.swift · AliciaService.swift · AppStore.swift · SampleData.swift
  Features/       Talk · Mind · Studio · Canvas · Health
  Assets.xcassets AppIcon + AccentColor
```

- **State:** single `@MainActor @Observable final class AppStore` (`Core/AppStore.swift`). Injected with `.environment(store)` in `AliciaApp`, read via `@Environment(AppStore.self)`. Holds messages, thoughts, tracks, gallery, health, and the (simulated) player state.
- **Design:** `Theme` enum centralizes colors and the frosted `.card()` look so all tabs feel like one app. Forces `.preferredColorScheme(.dark)` in `AliciaApp` (remove that line to follow the system).

## The networking seam — LIVE (wired 2026-07-03)

Everything the UI needs flows through **one protocol**, `Core/AliciaService.swift`.
`Core/LiveAliciaService.swift` implements it against the backend's iOS API —
`skills/ios_api.py` in the `alicia` repo (github.com/mrdaemoni/alicia), a
token-authed HTTP/SSE server on port **8766** started from `alicia.py:main()`.
Auth: `Authorization: Bearer <ALICIA_IOS_TOKEN>`; media URLs carry `?token=`
instead (AVPlayer/AsyncImage can't set headers). Chat is SSE (`{"t": token}`
events) and **shares conversation_history with Telegram** — one relationship,
two surfaces. L4-classified messages are redirected to Telegram by the backend.

Service selection is config-driven (`Core/Config.swift`): UserDefaults
(`alicia.baseURL`/`alicia.token`) → bundled `Secrets.plist` (gitignored; copy
`Secrets.example.plist`) → falls back to `MockAliciaService` + SampleData.

## Current state

- **Audio is real** — `AppStore` drives AVPlayer for tracks with http URLs
  (backend serves wavs with Range support); the old ticker remains the
  fallback for sample tracks.
- **Gallery renders real drawings** — `Artwork.imageURL` + `AsyncImage` in
  `ArtworkCell`; symbol placeholder when nil.
- **ATS**: root `Info.plist` (merged via `INFOPLIST_FILE`) allows plain-HTTP —
  backend is private-network only (tailnet/LAN).
- **Canvas is one tab** with a segmented control. Split `CanvasView` into
  `DrawView` + `GalleryView` and add cases to `AppSection` if you want two tabs.

## Recommended libraries to add (from the research pass)

See `docs/RESEARCH.md` for the full report + rationale. When ready, add via SPM:
- **Talk:** `exyte/Chat` (chat surface), `microsoft/SwiftStreamingMarkdown` (streamed AI markdown), `swift-markdown-ui` (markdown theme), `kitlangton/OmenTextField` (composer).
- **Studio / Canvas gallery:** `Nuke` (async image + caching) once there's real cover art / rendered images.
- Drawing generative side: `swifty-creatives` (Metal) + native SwiftUI shader effects.

## How to build / run

- Open `Alicia.xcodeproj` in Xcode 16+. Set a signing Team only for a physical device (simulator needs none).
- Scheme "Alicia", destination an iPhone simulator (e.g. iPhone 17), Run. Or CLI:
  `xcodebuild -scheme Alicia -destination 'platform=iOS Simulator,name=iPhone 17' build`

## Conventions

- Pure SwiftUI, iOS 17 APIs (`@Observable`, `Gauge`, `symbolEffect`, `onChange` two-param, `TextField(axis:)`).
- Keep the `AliciaService` seam clean — views should never call the network directly, only `AppStore`.
- The custom section enum is `AppSection` (not `Section`) to avoid colliding with SwiftUI's `Section`.

## Next steps (suggested order)

1. Commit is already made; push to `github.com/mrdaemoni/alicia-ios`.
2. Implement `LiveAliciaService` against Alicia's backend (start with `stream`).
3. Real audio playback in Studio.
4. Add `exyte/Chat` + streaming markdown to Talk.
5. Wire the Canvas "Ask Alicia to reply" to the backend and render returned images in the gallery (Nuke).
