# Live presence

Released. TestFlight 1.0 (52) from source `6954a4e` (PR #56, v42) became
available on October 24, 2026 (Pacific), after the backend's
`/api/presence/live` (backend PR #109) and the Nest display went live the same
evening. PR #57 then brought this code into iOS main (`1c14936`, v43), which
shipped as TestFlight 1.0 (53). Official installation of build 52 or 53 on the
phone is not yet confirmed.

This release connects the four recovered mathematical fields to
observed listening, reply preparation and playback, with an attributed emotional
stance from the existing awareness reading. Deployment and installation status belong to the task release receipt.
The approved single-body jellyfish projection remains intact. No sensor is
opened by enabling the renderer or entering the lab.

## Review entry points

`--motion-lab --live-presence-lab` opens the live review room. Its switch enables
the live renderer for this DEBUG session; the usual phone recording/playback flows
supply facts. The backend companion must expose `/api/presence/live`. The regular app enables
this path by default with the live service. Mock fallback stays inert. The lab
and synthetic controls remain DEBUG-only. `--live-presence-preview` forces the
mock service while exercising the new renderer and observed local fixture audio.

`--motion-lab --live-presence-lab --live-presence-fixture` forces MockAliciaService
and synthetic review signals. It never publishes presence. It accepts
`--presence-state=resting|listening|thinking|speaking`,
`--presence-stance=witness|ask|offer|hold|celebrate|challenge`, and
`--presence-reduce-motion`. Fixture screenshots are visual evidence, not proof
of actual microphone or model activity.

## State and privacy

Actual audio-engine start, meter and stop callbacks author listening; merely
opening Dialogue does not. The optional telemetry path never waits on capture.
Capture uses an eight-second expiring lease and sends only a UUID, monotonic
sequence, surface, state, normalized meter and observation timestamp. No text,
audio or transcript is included. Private Body capture, including Body walks,
is excluded. Shared playback uses an explicit content-kind allowlist, excluding
private Body narration.

Reply preparation comes from actual non-private backend jobs, not an invented
thinking timer. Playback follows actual `.playing` player status and ready samples, not a pending
play request. Measured word cues can shape the phone at its audio clock; absent
measured cues produce no invented voice energy. Buffering clears speaking. Active local phone
capture/playback stays authoritative during transport failure. A delayed echo
of this phone cannot reopen stopped capture. Incoming leases lose request transit
time; cached activity expires. Missing/failed status produces unavailable/zero
voice energy. Telemetry is serialized, coalesced and never put in the durable
voice/chat outbox. Background polling stops unless actual capture/playback needs
its lease renewed. Disabling sends a final stop and restores the existing field.

Expression is an interpretation, not a measurement of an inner emotional state.
Witness/hold use the jellyfish, ask the folded depth, offer/celebrate the drift,
and challenge the singular edge. Energy/openness tune pace and openness; activity
tunes posture. Every transition retains point identity, integrates phase during
speed changes, and blends all active families. Both renderers use 2,400 fixed
samples and a 30 FPS ceiling. Reduce Motion uses fixed phases with zero meter
motion; inactive/offscreen views pause. No camera, facial analysis, phone motion
sensor or Nest microphone is integrated by this release.

## Evidence and promotion

`python3 scripts/test_live_presence_client.py` checks actual client cancellation,
rapid toggles, capture ownership, local stop authority and ordered reporting with
in-memory suspended service IO. `python3 scripts/test_live_presence.py` compiles the actual value types and
geometry, checks expiration, interrupted transition continuity, deterministic
Reduce Motion, finite/bounded point counts and the shared JavaScript equation
fixtures in `docs/live-presence-equations.json`.

The iPhone 17 simulator build and fixture screens are checked. Build 52 was
built on released build 51 (`e4546df`), preserving the study room, steering
controls and recent delivery/connection repairs. The companion
room renderer has authenticated proxy tests and a 1024x600 headless Chrome
fixture run, including connection failure and settled Reduce Motion. These are
not physical-device performance or network acceptance.

Hector explicitly authorized an early-release exception on October 24: “exception
because this will help with the study”. The study deviations log records the
visual interface change as a possible influence on study outcomes; the hypotheses,
arms, control rules and prior data are preserved. Independent committed review
and physical acceptance remain distinct from simulator tests and Apple availability.
The task RELEASE.md records actual backend/Nest activation, Apple build and phone
installation times. Build 52 was a branch build that included the already
released study and connection repairs. PR #57 later merged that whole lineage,
with the study-note card, into main.
Rollback is the prior released app build and prior display commit; the backend
channel is additive and process-local. Disabling the DEBUG switch remains a lab
comparison tool, not a new product setting.
