# Alicia Motion Lab

The Motion Lab is a `DEBUG`-only tuning room for Alicia's mathematical,
animated representation. Experiments remain separate from the five product
tabs until they are deliberately promoted.

## Open it

1. Run the Alicia scheme with the Debug configuration.
2. Open the Alicia tab.
3. Long-press the Alicia screen (`MindView` wraps `EpisodeMindView`).

The entry point and the lab controls are removed from Release builds.

For repeatable simulator capture, the Debug build also accepts a direct launch
argument:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcrun simctl launch booted com.myalicia.app --motion-lab
```

Repeatable DEBUG captures can also pass
`--presence-voice=beatrice|ariadne|psyche|daimon|muse|musubi`,
`--presence-state=resting|listening|thinking`,
`--presence-attention=0...1`, `--presence-reduce-motion`, and
`--presence-audit`. These inspection seams are not product settings.

## Review an experiment

- Compare all six voices at the same ATTENTION value. Each voice uses a
  different geometric family, not a small parameter variation: Beatrice
  drifts vertically, Ariadne weaves, Psyche folds a dimensional field, Daimon
  carries controlled singular edges, Muse blooms, and Musubi knots.
- Compare RESTING, LISTENING, and THINKING at the same voice and attention.
  State scales an archetype's native tempo; it does not replace its identity.
- ATTENTION is the semantic control. It increases point density and opacity,
  gathers the body, and strengthens its response to the dragged focus point.
- Family density is compensated inside `AliciaPresence`, so point count stays
  a performance budget rather than becoming a product-level opacity contract.
- Pause, then use PHASE to compare exact moments instead of judging two
  different animation frames. Phase is a lab inspection tool, not personality.
- Use SHOW MATH to reveal the center axes and attention vector.
- Use REDUCE MOTION to preview each voice's intentional deterministic still.
- AUDIT ALL checks every voice/state combination across representative phases
  for finite values and sufficient visible bounds at the current attention.
- The readout reports effective tempo, point budget, the fixed 15 FPS cadence,
  visible-point percentage, and finite-value status.

The point field is capped at 2,800 samples and 15 FPS, clips outliers before
adding them to one batched Canvas path, renders asynchronously, and pauses when
inactive, backgrounded, reduced-motion, or held at a lab phase. Browser
performance is not evidence of iOS performance.

For an animation claim, capture two simulator frames at different phases and
pixel-compare them. Capture representative voices plus the Reduce Motion still.
For typography, rhythm, touch, battery, and final scale, judge on the real
device; the iOS 26 simulator substitutes custom fonts.

## Promotion gate

An experiment moves into Alicia only after:

1. Its meaning is agreed: what visible behavior maps to resting, listening,
   thinking, or a real backend state.
2. It reads at the intended production size and does not compete with text.
3. Reduce Motion has a deliberate still state.
4. Simulator build is green and two frames prove motion where expected.
5. The device build is inspected on Pandaiux.

When promoted, reuse the design-system component, add only the production
state mapping and placement, bump `AppVersion.tag`, run the normal ship loop,
then commit and push.

## The briefing room, as shipped and organic (CL-20261018-organic-field)

Hector, 2026-10-18, on TestFlight 49: "the particles feel too forced. They
don't feel organic." The room's candidate is a lab-only toggle set.
Nothing in a product surface draws it before the steering study ends on
2026-11-14 and he picks it here.

- **Open it.** ROOM in the lab opens `OrganicRoomCompare`, or launch with
  `--organic-compare`; `--organic-compare-clean` hides the controls for
  recording.
  - **Left:** the room as shipped, driven exactly as TestFlight 49 does it
    (listening pose, 15 FPS, the per-word level polled every 66 ms).
  - **Right:** the candidate.
  - **Their voice:** both hear her real speaking rhythm,
    `OrganicVoiceFixture`: word times from a live shakedown, with no text.
- **Toggles,** one per cause, all in `OrganicStyle`:
  - **A TIME:** 30/60 FPS, with her voice read in each frame from the
    playback clock.
  - **B BREATH:** the phrase breathes ±4.5% outward from her centre; each
    word only stirs texture.
  - **C LIFE:** a per-particle lag, drift and rhythm.
  - **D DOTS:** round dots, in three sizes and three depths of ink.
  - **E POSE:** her speaking pose. PAUSE settles, and HIGHER / LOWER play the
    steering gestures.
  - **F FRAME:** she grows toward the screen height, with a sparse dust.
- **Readouts.** STILL previews Reduce Motion. AUDIT checks every form pair,
  pose, voice and gesture for finite points and visibility.
- **The math is shared.** `Alicia/DesignSystem/PresenceGeometry.swift` and
  `OrganicField.swift` hold it, Foundation only.
  - The formulas moved there verbatim; `AliciaPresence` keeps thin wrappers,
    and the shipped drawing is byte-for-byte the same placement.
  - `scripts/test_organic_field.py` checks:
    - with every toggle off, the candidate places exactly the shipped points;
    - bounds, the breath limit, envelope smoothness, gestures and
      determinism;
    - per-frame cost.
  - `scripts/render_organic_field.py OUT` renders the two side by side to an
    MP4 offline, from the same math. The paper grain is omitted.
- **Still required before promotion:** simulator recordings, measured device
  frame time and energy at 30/60 FPS, Hector's pick, and a check on Pandaiux.
