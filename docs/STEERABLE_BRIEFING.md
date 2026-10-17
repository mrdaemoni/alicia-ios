# Steering the morning briefing while it plays (iOS)

*CL-20261015-steerable-briefing. Backend contract:
`/Users/alicia/alicia/docs/STEERABLE_BRIEFING.md` (`GET /api/morning_briefing`
`segments[]` + `steering`, `POST /api/morning_briefing/steer`, `POST
/api/morning_briefing/receipt`, Landed / Didn't land on `.../feedback`). The
pre-registration, altitude definitions and event model are in the board task.*

## What he sees and hears

**The briefing is a room** (`Features/Reading/BriefingStage.swift`, Hector,
2026-10-17: "the phone should not lock … a full screen experience in where I
can see the particles dancing of Alicia as she's narrating it. Then I don't
need to have the text readout anymore").
- **Opening.** Starting the morning briefing from its card opens a
  full-screen cover, composed like the walk's `ListeningStage`: backdrop,
  time-of-day tint, her one field full-bleed, grain.
- **What's on it.** There is no text. At the bottom are the same
  `BriefingSteeringPanel` (Higher · Lower · Again, the interpretation line,
  Landed / Didn't land), play/pause and the clock.
- **Her breath.** The field breathes with her voice:
  `BriefingPlanner.voiceLevel` reads the measured word cues of the piece
  being heard, so each word swells and the gaps rest. It feeds the same
  voice-reactive state the walk uses for his voice.
  - Untimed audio breathes slowly and evenly, and nothing invents syllables.
  - Reduce Motion stills the field, as everywhere.
- **The screen stays awake** while the room is open and the app is active.
  The prior setting is restored on close or backgrounding, as in the walk.
- **Leaving and returning.** CLOSE leaves the briefing playing in the reading
  bar. For the briefing, the bar's title reads FULL SCREEN and opens the room
  again; other readings keep READ ALONG and the text reader.
- **Behind the room.** The tabs' field stops drawing while it is up.
- **Fixture:** `--morning-briefing-steer-preview --briefing-stage-preview`.

The briefing card and reading bar look as before. When the day's briefing is
steerable, the room, the reading bar and the immersive reader carry one quiet row:

**HIGHER · LOWER · AGAIN**, with the arm on the right ("STEER WHILE IT PLAYS ·
WEEK 1"). The commands are ink-drawn small caps with her underline: no SF
Symbols, no emoji.

- **Higher:** the rest from higher up, from the next sentence.
- **Lower:** the rest closer in, from the next sentence.
- **Again:** replay the sentence now, or the previous one if he pressed within
  1.5 s of a sentence's start.
- **A faded command can't be pressed.** Higher or Lower fades when its press
  would change nothing from here: the briefing is already at that altitude, or
  no part from here on has a version there. It stays open when a later part
  has one; that press changes from that part ("Changed where a version exists;
  this part has only one"). Again never fades. The panel asks the same
  planner, at the same position, that a press would ask
  (`BriefingSteeringController.available`, `BriefingPlanner.changes`), and
  redraws as playback moves. Hector asked for this on 2026-10-17, before the
  study started: a button that answers "Not changed" is confusing. The
  headphone mapping is unchanged: its spoken cue ("Staying here.") is the only
  answer a pocketed phone can give.
- One **interpretation line** says what Alicia took the press to mean ("From
  higher up, starting with the next sentence"), then fades after six seconds.
- A short prerendered **spoken cue** in her voice ("Higher.", "Lower.",
  "Again.", "Staying here.") confirms it at the seam, so he doesn't have to look.
- At the end: **DID IT LAND? Landed · Didn't land**, identical in both arms.
- **After weeks:** nothing to press while it plays. When it ends, the same three
  commands appear: Higher or Lower replays the whole briefing at that level,
  and Again replays the last sentence.
- **During weeks:** the commands disappear when it ends.

The card has a *Steering this briefing* disclosure: what the controls do this
week, the arm, and the v1.1 **headphone setting** (off by default). When it's
on, headphone or lock-screen next/previous track means Higher/Lower, in the
briefing only and only while the commands are showing. Everywhere else those
buttons keep their usual meaning.

A pause is a pause. Nothing records pausing, scrubbing, skipping, stopping or
silence as a signal.

## How playback works

| Piece | Role |
|---|---|
| `Core/BriefingSteering.swift` | Payload models; `BriefingPlanner`: the interpretation table and entry-sentence rule (mirrors `skills/briefing_steering.py`), path building, switch points, Again targets, narration text, and `consequence(...)`: what a reading does to the path, as data. Pure Foundation. |
| `Core/SpeechReader.swift` | Plays a path of **pieces**. A piece is a chunk file that may start (`clipStart`) and end (`clipEnd`, via `forwardPlaybackEndTime`) inside the file. Pieces that need their own seek start a new queue run at a seam. A seam fades the last 120 ms out and the next run in. `replaceFuture(after:current:tail:immediate:)` changes only what follows the sounding piece; the sounding piece may only end sooner, at a boundary still ahead of the playhead. |
| `Core/BriefingSteeringController.swift` | The session. It decides what a press means (server answer, or the identical local rule if the Mac doesn't answer within 1.5 s), applies the consequence, records stretches of what actually played, and keeps the receipt outbox. |
| `Features/Reading/BriefingSteerControls.swift` | `BriefingSteeringPanel`, `BriefingEndCheck`, `BriefingSteeringSettings`. |

**A steer.**

1. The press is placed at the sentence being heard. If less than 0.35 s of it
   is left, the change waits one more sentence.
2. The heard piece is cut in the gap after that sentence, the cue follows, then
   the new variant resumes at its first sentence that carries a ledger item
   not yet heard, so nothing unheard is skipped.
3. Later segments follow the new dial, falling back to L0 where a level failed
   validation.
4. An untimed sentence can only be entered at its chunk's start (a little may
   repeat), and a cut without timing waits for the chunk's end.
5. If the briefing finishes before a press made while it played is answered,
   the press is still delivered but changes nothing ("Not changed. That was
   the end"). It never becomes the whole-briefing replay of a press after the end.

**The text above the playhead never changes.** The reader's narration is
rebuilt from the path, one paragraph per segment. The heard pieces keep their
exact text and measured cues, so word following and tap-to-seek keep working.

**Records.**

| Record | When it's posted |
|---|---|
| `session_started` | When a steerable briefing starts playing (the opportunity) |
| `consequence` | Each time a new stretch actually starts. It names its event when a steer caused it; natural progression is `initial`, a scrub or skip is `seek`. |
| `session_ended` | Once per session, with measured seconds heard and the heard path: on stop or replace, after Landed / Didn't land, or when the next session starts |
| Landed / Didn't land | After every queued consequence has been delivered, so the server can confirm the path. Plain "Saved." only when the response's `validation.path_status` is `confirmed`. |

Everything goes through a durable outbox (Application Support,
`completeUntilFirstUserAuthentication`, so it still writes in a locked
pocket). Every body carries its UUID, so retries are no-ops on the server.

**Audio.** When a session starts, every variant chunk is downloaded once to
Caches. A copy is used only if its SHA-256 matches the validated variant.
Steers then switch from local files, and a run's dropouts don't stop the
briefing.

Older payloads, an unsegmented day, or arm `off` keep the legacy single track
exactly as before.

## Fixtures and checks

`--morning-briefing-steer-preview` builds an invented briefing (the plan's
talk-prep / book-edits example) with synthetic 0.3 s/word cues. URLs are never
loaded, and the mock service answers with the same local rules. Add
`--reading-bar-preview` or `--immersive-reading-preview` for those surfaces,
`--steer-after-arm` for an after week, `--steer-ended-preview` for the end
state, `--steer-line-preview` to show a line, and `--tab us` for the card.
`--steer-live-audio` instead plays for real: each variant is a local tone file
whose beeps sit at the fixture's word times. The real reader then plays and
steers, and a DEBUG label shows the heard path and seconds.

- `scripts/test_briefing_steering.py` compiles the real planner and
  NarrationDocument against `scripts/fixtures/steerable_briefing_payload.json`,
  which the backend test flow generated from invented text. It checks
  interpretation parity with the backend, path building, cuts and entries,
  every consequence branch, and narration alignment (46 checks).
- `scripts/test_briefing_steering_ui.py` has 10 tests: both arms, the end
  check, the immersive reader, the card setting, large type, and two
  live-audio tests. Those two observe the real seam: after Higher, the L0
  piece stops at the sentence boundary, the cue plays, and L+1 resumes at the
  unheard caveat. Again replays the sentence. Screenshots export to
  `steer-screenshots/`. Requires the iOS Simulator runtime (iPhone 17).

Simulator results are not phone evidence. Still to check on Pandaiux: how
the seams and fades sound, the lock screen and headphone mapping, Bluetooth
latency, and the after-arm replay.
