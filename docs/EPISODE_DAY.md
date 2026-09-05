# Episode day — iOS implementation handoff

Branch `codex/episode-day`, base `790f093`; paired backend branch with base
`98f65c3`. Owner: Codex. No competing open PRs touched these files at the start.
No version bump, TestFlight upload, device install, or production promotion.

Hector approved an iOS-first loop around the morning episode and his reaction.
Us, Dialogue, and Alicia are focused on that moment; Studio and Knowledge keep
their library roles. The app presents two or three source-grounded questions,
a large Walk with this action, a correctable reading, and explicit learning keeps.

## Decisions and implementation

- Actual continuous player progress, including episode playlists, identifies
  the episode. The persisted outbox carries UUID/time receipts. A download,
  seek, pause, or tab visit is not listening/learning evidence.
- Us uses `EpisodeHomeView`; Alicia uses `EpisodeMindView`. Old galleries/cards
  remain unmounted; the startup load no longer requests their generated greeting,
  mind note, orbit, or reflections. The widget cache follows the episode frame.
- Dialogue restores actual conversation history through `/api/history`; refreshing
  cannot overwrite a conversation changed since the request began. Proactive
  sends are not seeded as chat turns. Voice replies and composer dictation remain.
- `WalkReflectionView` pauses playback, starts on-device dictation, shows a local
  draft, restarts completed recognition segments, and acknowledges a durable
  server receipt before clearing. Failed saves preserve words. Closing/backgrounding
  pauses; reopening can continue. It is a foreground reflection surface.
- Feedback sits beside its exact question/reading. Corrections and learning keeps
  preserve the user's words; episode ideas are not automatically declared learned.
- `EpisodeDay` DTOs, `AliciaService`, `LiveAliciaService`, and `AppStore` own the
  network seam; views never call the network directly. New routes are listed in
  `CLAUDE.md`. The backend contract is in its `docs/EPISODE_DAY.md`.
- Ink on bone, existing presence backgrounds, pure SwiftUI, no dependencies,
  SF Symbols, emoji, new motion, or generated version values. Existing DEBUG
  Motion Lab entry remains accessible through the Alicia title long press.

## Validation

Build with:

```
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -scheme Alicia -destination 'platform=iOS Simulator,name=iPhone 17' \
  -derivedDataPath .derived build
```

Simulator: iPhone 17, iOS 26.5. Explicit DEBUG `--episode-day-preview` chooses
MockAliciaService, displays labelled fixture content, and does not schedule live
background fetches. `--tab us|alicia|dialogue`, `--episode-empty`,
`--episode-failed`, and `--episode-walk-preview` expose representative states.
The walk preview does not start the microphone. No model-quality claim is made
from these fixtures. Screenshots are under `docs/episode-day-preview/`.

Reduce Motion uses the existing presence component's intentional static rendering;
no new motion is introduced. Pandaiux speech, headset interruptions, lock/unlock,
fonts, touch targets, and real morning playback/feedback need device verification.
On-device dictation intentionally pauses in the background. There is no claim
of background/lock-screen recording, outbound calling, or a new full voice agent.

## Integration and next action

Review the committed paired branches. Backend must be promoted and deployed before
an iOS build that depends on the new routes can be field-tested. A branch backend
against live state remains prohibited by `docs/SHIPPING.md`; no such sidecar ran.
Promote only after the product/device choice. Rollback is the prior build; the
server's additive journal and daily vault notes remain available. Authentication
and higher-tier confirmation still use the established backend boundaries.

## Cross-review revisions

An immutable pending walk payload is persisted before the request; uncertain
saves offer Retry save and prevent editing that submission. Controls are locked
during an active save, and a successful receipt cannot erase newer text. Changed
feedback is a distinct action/receipt; identical retries retain their receipt.
Microphone starts check a view generation after backend/permission waits; old
recognition callbacks cannot touch a newer segment. Segment final text is kept
before restarting. The presented question survives alongside the draft and is
stored separately from Hector's own words. Backend retry repairs the daily note
and conversation history idempotently.

`python3 scripts/test_walk_save.py` compiles AppStore's actual save method with
inert UI/network/storage dependencies. It verifies successful save, immutable
retry/relaunch, definite rejection becoming editable, the size bound, and newer
words surviving a delayed save. It failed on the rejected-pending bug before
the correction and passes afterward. This does not exercise the microphone.
