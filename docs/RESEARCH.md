# Alicia iOS — Open-Source Reuse Research

**Scope:** Pure SwiftUI, native and beautiful. Three sections — messaging, media/photos, drawing/rendering. Any OSS license acceptable (with license flagged per project). Compiled July 2026.

All project details (stars, licenses, maintenance) are also in the companion spreadsheet, `Alicia_iOS_OpenSource_Research.xlsx`, which is sortable/filterable by section, license, and pick.

---

## The short version

You do not need to build any of the three sections from scratch. There is a mature SwiftUI project for every piece, and Apple's own frameworks cover more than you'd expect — especially the media and drawing tabs.

My recommended pure-SwiftUI stack:

- **Shell/architecture:** copy the skeleton from `nalexn/clean-architecture-swiftui` (MIT), and study `Ice Cubes` for how a real multi-tab app splits features into Swift packages — one package per tab maps almost exactly onto your messaging/media/drawing split.
- **Messaging:** `exyte/Chat` for the chat surface, `microsoft/SwiftStreamingMarkdown` for flicker-free streaming of AI responses, `swift-markdown-ui` for markdown theming inside bubbles, `OmenTextField` for the composer.
- **Media:** lean on Apple first-party — `PhotosPicker` to import, `LazyVGrid` + `.navigationTransition(.zoom)` for the Photos-style grid and hero animation, `Nuke` for thumbnail caching, `VideoPlayer` for video. Add `ZoomImageViewer`'s interaction model for the fullscreen viewer.
- **Drawing:** `PencilKit` for freehand/handwriting, `swifty-creatives` (Metal) plus SwiftUI shader effects for the generative/rendering side, and Apple's "Constructing PencilKit Drawings" sample as the bridge for AI-drawn strokes.

The one licensing caveat worth remembering: **Ice Cubes is AGPL-3.0** and **Stream is a commercial license** — study them, don't fork-and-ship them into a closed app. Everything else in the recommended stack is MIT or Apache-2.0.

---

## 1. App shell & architecture

The biggest reuse win isn't a widget — it's the skeleton. Two projects matter most.

`nalexn/clean-architecture-swiftui` (MIT, ~6.6k stars, refreshed Dec 2024) is the cleanest MIT-licensed template for the app shell: a central `AppState` as single source of truth, dependency injection through `@Environment`, programmatic navigation with deep linking, and real test coverage. It ships both a Clean-Architecture and an MVVM branch so you can compare. This is the safest thing to copy code from directly.

`Ice Cubes` (AGPL-3.0, ~7k stars, very active into 2026) is the best real-world reference for an app shaped like Alicia. It's a Mastodon client built entirely in SwiftUI, and critically it's split into independent Swift packages — one per feature (timeline, direct-messages/chat, explore, media composer), with OpenAI wired in as its own package. That modular layout is exactly how you'd want to separate Alicia's messaging, media, and drawing tabs. Because it's AGPL, treat it as an architecture reference to learn from, not a base to fork into a closed product.

Supporting references: `MovieSwiftUI` (media grids + a Redux/Flux state pattern), `isowords` by Point-Free (the canonical production example if you choose The Composable Architecture), `alfianlosari/ChatGPTSwiftUI` + `ChatGPTUI` (the closest existing *AI-assistant* app — streaming responses, markdown/code rendering, model plumbing), and `calda/SwiftUI-Notes` (clean SwiftUI + Core Data + CloudKit sync if Alicia's data should follow the user across devices).

**Architecture recommendation:** copy the clean-architecture skeleton, adopt the SPM-per-feature layout from Ice Cubes, and decide early between plain MVVM (simpler, fine here) and TCA (more structure and testability, heavier). Given Alicia is a personal app, MVVM with a central app state is likely the pragmatic call.

---

## 2. Messaging section

Your messaging tab is a conversation between the user and an AI: bubbles, timestamps, media attachments, a typing indicator, and — the part generic chat kits don't solve — **streaming markdown** as the model generates.

**Chat surface.** `exyte/Chat` (SwiftUI, MIT, ~1.8k stars, very active) is the strongest all-in-one. Its `ChatView` gives you the message list, user/AI bubbles, timestamps, and a built-in media picker, and the cells are fully customizable so you can inject markdown-rendered AI bubbles and a custom typing indicator. It's commonly paired with an LLM backend, so it's the fastest path to Alicia's chat. Requires iOS 16+. If you'd rather fork something smaller, `SwiftyChat` (Apache-2.0) is a lighter kit with themeable message types.

**AI response rendering — the part that actually matters.** Generic chat kits render plain text; AI responses are markdown that arrives token by token. Two libraries solve this:

- `microsoft/SwiftStreamingMarkdown` (SwiftUI, MIT) incrementally parses and renders markdown *as it streams*, without re-parsing the whole string or flickering. This is purpose-built for exactly your case and is the strongest match for streaming AI bubbles.
- `swift-markdown-ui` (MIT, ~3.9k stars) is the default for the markdown *look* — tables, code blocks with syntax styling, lists, blockquotes — and is fully themeable so AI bubbles match your design. Note it's in maintenance mode (successor project: Textual). If you want an actively developed alternative with LaTeX math and SVG support, use `LiYanan2004/MarkdownView` (MIT) instead.

**Composer.** `kitlangton/OmenTextField` (SwiftUI, MIT) is a growing, multiline, auto-focusing text field — it fixes the classic pain where native `TextField` handles multiline input poorly. Pair it with send and attachment buttons.

**Polish.** `jasudev/AnimateText` (MIT) gives a typewriter/reveal effect for non-streaming messages. For the typing indicator, exyte has one built in, or roll a small animated-dots view.

**Things to reference but probably not adopt:** `GetStream/stream-chat-swiftui` is a polished production chat UI, but it's tied to Stream's hosted backend and a non-standard commercial license — only worth it if you want their backend. `MessageKit` (UIKit, MIT, ~6.3k stars) is the most battle-tested chat kit overall; keep it in your back pocket only if the SwiftUI kits hit performance limits on very long conversations.

---

## 3. Media / photos section

Here the surprise is how much Apple gives you for free. A Photos-like experience is now mostly first-party SwiftUI, with two or three community libraries filling gaps.

**Import:** Apple's native `PhotosPicker` (PhotosUI, iOS 16+) is the modern SwiftUI photo/video picker and the correct default — the older community wrappers only matter if you must support iOS 14/15.

**Grid:** `LazyVGrid` gives the uniform, Apple-Photos-style grid with zero dependencies. If you want the variable-height Pinterest/masonry look for mixed aspect ratios, `WaterfallGrid` (MIT, ~2.7k stars) is the primary choice, with `SwiftUIMasonry` (MIT) as a lighter alternative that supports column/row spanning for hero photos.

**Thumbnail loading & caching:** this is the one place a library is essential for smooth scrolling. `Nuke` with `NukeUI` (MIT, ~8.6k stars, very active) gives you `LazyImage` for async thumbnails, an LRU memory+disk cache, and — critically — prefetching, which keeps a large grid buttery. `NukeVideo` even plays short clips inline. `Kingfisher` (MIT, ~24k stars) is the equally strong, more popular alternative; its `DownsamplingImageProcessor` is ideal for generating right-sized thumbnails from full-res originals. Use `SDWebImageSwiftUI` only if you specifically need animated GIF/APNG/WebP/AVIF in the grid.

**Fullscreen viewer with zoom & swipe-to-dismiss:** no library perfectly packages the Apple Photos experience, so combine native + community. For the grid-to-fullscreen *hero animation*, use Apple's official zoom transition: `.matchedTransitionSource(id:in:)` on the thumbnail plus `.navigationTransition(.zoom(sourceID:in:))` on the destination (iOS 18+); fall back to `matchedGeometryEffect` on iOS 17. For the *interaction* inside the viewer (bouncy pinch/double-tap zoom, swipe-down-to-dismiss), `ZoomImageViewer` (MIT) is the closest single-file match — fork its interaction model since it's pre-release. `Jake-Short/swiftui-image-viewer` (MIT, ~499 stars) is the most-starred SwiftUI viewer and a good source for the drag-to-dismiss overlay pattern, though it's stale (2021) so validate on current iOS.

**Video:** Apple's native `VideoPlayer` (AVKit) is the default for standard library formats (H.264/HEVC). Add `VLCUI` (MIT) only as a fallback for exotic codecs/containers (MKV, network streams) that AVKit won't play.

---

## 4. Drawing / rendering section

You described this as both freehand drawing and programmatic rendering, so it's really two engines behind one tab. Apple's frameworks anchor the freehand side; Metal and SwiftUI's own Canvas anchor the generative side.

**Freehand / handwriting:** `PencilKit` (`PKCanvasView`) is the default backbone — Apple's low-latency, Metal-backed ink engine with pressure, tilt, palm rejection, the system tool picker, and undo for free. You access `canvasView.drawing` (a `PKDrawing`) to serialize strokes and call `drawing.image(from:scale:)` for handwriting-to-image export. Wrap it in `UIViewRepresentable`; `GGCIRILLO/PencilKit-App-SwiftData` is a small, readable reference for that bridge plus persistence.

**AI-drawn strokes (the interesting bit for Alicia):** Apple's sample "Inspecting, Modifying, and Constructing PencilKit Drawings" shows how to *build* a `PKDrawing` from code and *read* individual `PKStroke`/`PKStrokePoint` data. That's the seam where Alicia can draw responses programmatically and where you can feed the user's strokes back to the AI — it bridges the freehand and generative sides.

**Custom ink (if you want strokes prettier than or independent of PencilKit):** `perfect-freehand` (MIT, ~5.6k stars) is the reference pressure-sensitive stroke algorithm — variable-width, tapered, natural ink. There's no Swift port yet, but the core (`getStrokePoints` + `getStrokeOutlinePoints`) is a few hundred lines of pure math; porting it to Swift and rendering into SwiftUI's `Canvas` gives you beautiful ink without depending on PencilKit's closed engine, plus a ready SVG-export recipe. (The port would itself be a nice OSS contribution.)

**Shapes, text, markup:** `Asana/Drawsana` (MIT) is the most complete MIT toolbox — pen, eraser, shapes, text, selection, undo/redo — with `Codable` serialization and image export. Wrap its `DrawsanaView` for SwiftUI.

**Generative / high-performance rendering:** `swifty-creatives` (Apache-2.0) is the best fit — a Processing-style creative-coding framework built directly on Metal, with a `SketchView` that drops into SwiftUI and even audio-reactive FFT input for algorithmic art. For lighter generative pieces without a full Metal pipeline, SwiftUI's own `Canvas` + `TimelineView` handles animated procedural drawing, and iOS 17+ shader effects (`.colorEffect`/`.layerEffect`) run `.metal` fragment shaders on any SwiftUI view. If your generative output should be vector/SVG rather than pixels, `emorydunn/SwiftGraphics` is the niche pick.

**Reference only:** `gahntpo/DrawingApp` is the cleanest pure-SwiftUI stroke loop (DragGesture → points → `GraphicsContext`), but it has no LICENSE file, so learn from it rather than copying. `Awalz/SwiftyDraw` (MIT, dormant) has a nice brush-model and pencil-angle-to-width idea worth borrowing.

---

## Licensing at a glance

Since you said any OSS is fine, the practical question is just: which of these force *your* app open if you ship them. MIT, Apache-2.0, and Apple's own frameworks are all safe to ship in a closed app. The two to keep at arm's length are **Ice Cubes (AGPL-3.0)** — network-copyleft, so forking it forces your whole app open — and **Stream (commercial license)**. A handful of smaller repos (MovieSwiftUI "Other", plus a few with no clear LICENSE file like `gahntpo/DrawingApp`) should be verified before you copy code. The License Notes tab in the spreadsheet spells each of these out.

---

## Suggested next step

If you want, I can turn this into a starter Xcode project scaffold — a three-tab SwiftUI app shell wired to placeholder Messaging / Media / Drawing views using the recommended libraries — so you have something running to iterate on rather than a blank project.
