# Alicia Motion Lab

The Motion Lab is a `DEBUG`-only tuning room for Alicia's mathematical,
animated representation. Experiments remain separate from the five product
tabs until they are deliberately promoted.

## Open it

1. Run the Alicia scheme with the Debug configuration.
2. Open the Alicia tab.
3. Tap `HER INNER WEATHER · v35` beneath her name.

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
