# Morning briefing on Us

This component gives Hector a small, deliberate way to begin: a dated morning
reading, its actual audio length, and one Listen/Pause control. It belongs above
episode selection on Us, including when no episode has been chosen. Studio keeps
the existing playlist library. Opening the card or reading its text starts no
audio, generation, conversation, notification, or learning event.

This branch supplies the model and view only. AppStore, service, playback and
Us/Studio integration belong to the receiving change. It is not a released app
or evidence that a real morning recording has been generated.

## Data contract

`GET /api/morning_briefing` returns a read-only prepared snapshot:

| Field | Type | Meaning |
| --- | --- | --- |
| `id` | String | Stable briefing identity |
| `day` | String | Briefing day as `YYYY-MM-DD` |
| `title`, `text` | String | Display title and full prepared reading |
| `status` | String | `ready`, `preparing`, or `unavailable` |
| `audio_url` | String | Prepared media path; `/api/speech/...` is valid |
| `duration` | Double | Measured rendered audio seconds |
| `playlist_id` | String | Existing Studio playlist target |
| `error` | String | Optional availability detail, shown inside inspection |
| `sources` | Array | Supplied provenance entries |

Each source can have optional `id`, `title`, `path`, and `excerpt` strings.
Unknown JSON attributes are ignored. Missing or null top-level fields receive
empty defaults, including zero duration and an unavailable status. An unknown
status does not unlock playback. Wrongly typed fields fail normal decoding;
the owner should preserve its previous snapshot on a failed read.

`MorningBriefing.hasPlayableAudio` requires `ready`, a nonempty identity, a
usable HTTP(S) or relative media path, and positive finite measured duration.
The view does not invent a five-minute duration from a word count. It displays
the actual length, rounded to the nearest second, and an expanded spoken value
for VoiceOver. Preparing text remains readable while audio is unavailable.

Dates stay visible in every state. Earlier/later/invalid dates are labelled;
an older ready briefing can still be played by a deliberate tap. Day comparison
uses the phone's current calendar/timezone. A minute-based, nonanimated clock
keeps an open card honest across midnight.

## Integration seam

The two new Swift files are included by the project's synchronized groups;
there is no project-file change or new dependency.

```swift
MorningBriefingView(
    briefing: store.morningBriefing,
    playingBriefingID: store.playingMorningBriefingID,
    isRefreshing: store.isRefreshingMorningBriefing,
    onTogglePlayback: { briefing in store.toggleMorningBriefing(briefing) },
    onOpenPlaylist: { id in store.openMorningPlaylist(id) },
    onRefresh: { Task { await store.refreshMorningBriefing() } }
)
```

The AppStore names in that example are proposed owner-side wiring, not methods
introduced by this branch. `onRefresh` is optional; no callback means no refresh
button. The owner supplies `isRefreshing` to prevent duplicate check requests.

Required owner behavior:

- Fetch through AliciaService, with a mock/default implementation. GET must
  read existing work without triggering a model or audio generation.
- Keep a last-known snapshot after a failed GET; clear the refresh state when
  the request ends. Keep any transport/playback failure visible in the owning
  surface. The card's optional `error` is the backend snapshot's detail.
- Resolve relative media paths through the configured private service and its
  existing authenticated-media helper. Reuse the existing player/audio-session
  behavior. Opening Us or the inspection sheet must not start playback.
- `playingBriefingID` names a briefing that is actually playing. Set it to nil
  on pause/end/failure or playback of other content. A paused/preparing request
  is not already playing. Do not optimistically claim playback during loading.
- The playback callback receives the exact inspected `MorningBriefing`, not
  an unqualified "play latest" action. The reading sheet retains its captured
  text/sources across refreshes. Stop/pause must remain bound to that identity.
- Navigate to the exact nonempty `playlist_id` in the existing Studio flow.
  The callback is navigation only; it must not start the playlist. Handle a
  missing/deleted playlist explicitly. Dismissing the reading sheet precedes
  its Studio navigation callback.
- A briefing is not an episode selection or proof of listening to an episode.
  Keep playback evidence attributable to its actual playlist item. Do not
  fabricate episode/day observations, reflections or human commitments.

## Inspection and accessibility

Read the briefing opens a scrollable full-text sheet. Sources expands the
supplied passages and paths only; there is no direct file/network lookup and no
claim that an omitted source was supplied. Empty source metadata is labelled.
Opening sources does not call a model. Display text follows the existing
emoji-stripping convention; the decoded model retains the original strings.

The card uses paper/ink colors, dynamic serif type and the existing custom ink
play/pause glyph. All controls have at least 44-point labels; the audio control
has a 48-point minimum. The glyph is decorative for VoiceOver, while its button
names the action, exact briefing, playing state, and measured duration. Controls
carry stable `morningBriefing.*` accessibility identifiers. Text inspection is
selectable, scrollable and unlimited in length. This component adds no animated
visualization, spinner, autoplay, or microphone state.

## Validation and remaining integration checks

Component evidence is under
`/Users/alicia/Documents/Alicia-development/tasks/A2-013/evidence/ios/morning/`.
The isolated Swift harness tests real model source, including nullable/unknown
fields, relative media URLs, finite duration, and local-day rollover: **32 checks
passed**. Five actual XCUITest flows passed on iPhone 17/iOS 26.5, covering card
and sheet playback callbacks, supplied text/sources, exact playlist target,
preparing/missing/incomplete audio, earlier-day refresh, and accessibility XXXL.
Eight screenshots are in `screenshots/manifest.json`; ready, preparing, reading,
and large-type captures were visually inspected. The full app simulator build
passed. The build command is:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -scheme Alicia \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -derivedDataPath /tmp/alicia-morning-briefing-build \
  CODE_SIGNING_ALLOWED=NO build
```

The UI harness creates a temporary copy and replaces only that copy's app entry
with an inert fixture. It constructs no AppStore/service, omits Secrets.plist,
and records callback identities instead of playing audio. Repository app entry,
project file, signing/version and existing screens are unchanged. Its generated
project is a test artifact, not a shipping source.

The UI pass caught and fixed an accessibility wrapper that moved the play
button's name away from the actionable button. Card and sheet playback/playlist
controls now have distinct identifiers. No new motion is present; a physical
Reduce Motion/VoiceOver interaction pass was not performed.

The receiving integration must verify actual loading/failed reads, relative-URL
authentication, player pause/end/failure state, exact Studio navigation, no
episode-selection side effect, and reading-sheet identity during refresh. It
must capture the integrated Us screen before any episode is selected, both ready
and preparing. Audio routing, measured file length, background/lock playback,
VoiceOver gestures and final typography need physical-device evidence. Simulator
callback tests do not prove those behaviors or a real morning's content quality.
