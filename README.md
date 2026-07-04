# Alicia — iOS starter

A runnable pure-SwiftUI scaffold for the Alicia app. Five sections, native look, **zero external dependencies** — it builds and runs on the simulator as-is. Everything talks to a mock backend through one seam (`AliciaService`), so "start networking" means implementing that one protocol.

## Run it

1. Open `Alicia.xcodeproj` in Xcode 16+.
2. Set your Team under **Signing & Capabilities** (only needed for a physical device; the simulator runs without it).
3. Select an iPhone simulator and press Run. Deployment target is **iOS 17.0**.

## The five sections

| Tab | File | What it is | Status in scaffold |
|-----|------|-----------|--------------------|
| **Talk** | `Features/Talk/TalkView.swift` | You messaging Alicia | Native bubbles + composer; replies stream in token-by-token |
| **Alicia** | `Features/Mind/MindView.swift` | Her introspection — mood, focus, recent thinking | State header + live "thinking" dot + thought cards |
| **Studio** | `Features/Studio/StudioView.swift` | Spotify-style player for the audio she makes | Playlist + tappable tracks + persistent now-playing bar |
| **Canvas** | `Features/Canvas/CanvasView.swift` | You draw; her gallery of drawings for you | Segmented: **My Canvas** (PencilKit) / **Alicia's Gallery** (grid) |
| **Health** | `Features/Health/HealthView.swift` | Her vitals dashboard | Status banner + metric tiles with gauges |

Canvas is kept as one tab with a segmented control (My Canvas / Alicia's Gallery). If you'd rather have two separate tabs, split `CanvasView` into `DrawView` and `GalleryView` and add both cases to `AppSection` in `App/RootView.swift`.

## Architecture

```
App/            AliciaApp (entry) · RootView (TabView)
DesignSystem/   Theme (palette, card style, backdrop)
Core/           Models · AliciaService (the seam) · AppStore (@Observable state) · SampleData
Features/       Talk · Mind · Studio · Canvas · Health
```

State is a single `@MainActor @Observable` `AppStore`, injected via `.environment(store)` and read with `@Environment(AppStore.self)`. This mirrors the central-`AppState` pattern from `nalexn/clean-architecture-swiftui` recommended in the research doc.

## The networking seam — this is where you plug in the real Alicia

Everything the UI needs comes through `Core/AliciaService.swift`:

```swift
protocol AliciaService {
    func stream(_ prompt: String) -> AsyncStream<String>   // token stream (LLM/SSE)
    func thoughts() async -> [Thought]
    func tracks() async -> [Track]
    func gallery() async -> [Artwork]
    func health() async -> [HealthMetric]
    func complement(_ title: String) async -> Artwork
}
```

`MockAliciaService` returns `SampleData` and fakes streaming. To go live, write a `LiveAliciaService` that hits your backend (URLSession; `stream` maps naturally onto Server-Sent Events / chunked responses), then change one line in `App/AliciaApp.swift`:

```swift
@State private var store = AppStore(service: LiveAliciaService(baseURL: ...))
```

No view changes required.

## Where the recommended open-source libraries drop in

The scaffold is native-only so it runs immediately. When you want more, add these via **File ▸ Add Package Dependencies** (all in the research doc/spreadsheet):

- **Talk:** `exyte/Chat` to replace the hand-rolled message list; `microsoft/SwiftStreamingMarkdown` to render streamed AI markdown in bubbles (wrap where `MessageBubble` renders `message.text`); `swift-markdown-ui` for markdown theming; `kitlangton/OmenTextField` for the composer.
- **Studio:** `Nuke` (`LazyImage`) once tracks have real cover art. Wire real audio by replacing the simulated ticker in `AppStore.startTicker()` with `AVAudioPlayer`/`AVPlayer` driving `progress` (set `Track.fileName` and load from bundle or a URL).
- **Canvas gallery:** `Nuke`/`Kingfisher` for loading her rendered images; native `.navigationTransition(.zoom)` (iOS 18) + `ZoomImageViewer`'s interaction for full-screen viewing.
- **Health:** native `Gauge` is already in use; `Charts` (Apple) if you want trend history.

## Notes

- Forces dark mode for the cosmic look (`.preferredColorScheme(.dark)` in `AliciaApp`). Remove that line to follow the system.
- Audio playback is **simulated** (a timer advances the progress bar) so the app runs without bundled media. See the Studio note above to wire real files.
- SF Symbol names are placeholders for artwork/metrics — swap freely.
- Built and reviewed for iOS 17 / Swift 5.9 / Xcode 16 with default concurrency settings. If you enable strict/Swift 6 concurrency, the `@State` store initializer in `AliciaApp` may need a small adjustment.
