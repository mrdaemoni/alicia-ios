# Alicia for iOS

A native SwiftUI app for Hector's thought partner. The current experience follows
the episode he actually plays, his reaction, a correctable reading, and the ideas
he explicitly chooses to keep. iOS is the first entry point; Telegram continues
the same relationship more quietly.

Read [AGENTS.md](AGENTS.md), [SESSION_HANDOFF.md](SESSION_HANDOFF.md), and
[CLAUDE.md](CLAUDE.md) before changing the app.

## Five tabs

| Tab | Current surface |
|---|---|
| Us | Played episode, two or three source-grounded probes, prominent Walk with this |
| Dialogue | Actual shared conversation, dictation, optional voice replies |
| Alicia | Tentative reading, Hector's words, corrections and explicit learning keeps |
| Studio | Podcast and playlist library, playback, shownotes, retained canvas tools |
| Knowledge | Synthesis and thinker library |

Walk with this pauses playback, keeps the screen awake while the reflection
screen is visible and active, and saves the inspected transcript with a durable
receipt. A failed/uncertain save retains the local draft for retry. Manual lock
or backgrounding pauses dictation; leaving restores normal idle behavior.

## Run and connect

Open `Alicia.xcodeproj` with the installed Xcode and use the Alicia scheme.
Deployment target is iOS 17.0. Pure SwiftUI, zero third-party dependencies,
ink-on-bone light theme, custom ink controls; no stock SF Symbols or emoji in
product UI. All networking flows through `AppStore` and `AliciaService`.

`LiveAliciaService` calls the Python backend on port 8766 over the configured
private network. Provision the gitignored `Alicia/Secrets.plist` privately;
`./scripts/provision-worktree.sh` links the canonical configuration for trusted
local worktrees. No credentials belong in docs or commits. With no configuration,
the app uses `MockAliciaService`; a working mock is not a backend health check.

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -scheme Alicia -destination 'platform=iOS Simulator,name=iPhone 17' build
```

## Release baseline

v38 / marketing version 1.0 / TestFlight build 5 was reported VALID and
IN_BETA_TESTING on September 5, 2026. Product source: PR #6, merge `9b353f5`.
Backend episode/day and focused messages shipped in backend PRs #12 and #13.
A later documentation commit can change HEAD without changing the installed app.

[Episode contracts and validation](docs/EPISODE_DAY.md) ·
[Shipping and build allocation](docs/SHIPPING.md) ·
[Motion Lab](docs/MOTION_LAB.md)

The earlier scaffold and tab history are preserved in `docs/history/`. Their
suggestions about mock-only networking, dark mode or adding stock icons do not
apply to the current product.
