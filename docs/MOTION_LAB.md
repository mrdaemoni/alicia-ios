# Alicia Motion Lab

The Motion Lab is a `DEBUG`-only tuning room for Alicia's mathematical,
animated representation. Experiments remain separate from the five product
tabs until they are deliberately promoted.

## Open it

1. Run the Alicia scheme with the Debug configuration.
2. Open the Alicia tab.
3. Tap `HER INNER WEATHER · v34` beneath her name.

The entry point and the lab controls are removed from Release builds.

For repeatable simulator capture, the Debug build also accepts a direct launch
argument:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcrun simctl launch booted com.myalicia.app --motion-lab
```

## Review an experiment

- Compare RESTING, LISTENING, and THINKING at the same settings.
- Pause, then use PHASE to compare exact moments instead of judging two
  different animation frames.
- Drag on the figure to test how attention deforms the body. RESET clears it.
- Use SHOW THE MATH to reveal the center axes and attention vector.
- Check 5 and 20 lines to expose density or performance problems.
- Check 0.2 and 2.0 speed before choosing the intended rhythm.
- Turn on Reduce Motion in iOS Accessibility settings. The representation
  must settle into a meaningful still rather than disappear.

For an animation claim, capture two simulator frames at different phases and
pixel-compare them. For typography, rhythm, touch, and final scale, judge on
the real device; the iOS 26 simulator substitutes custom fonts.

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
