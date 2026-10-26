# Fixture captures — September 5, 2026

All images use MockAliciaService, iPhone 17 simulator, iOS 26.5. These are
illustrative inputs and fake model replies, not production conversations or
model-quality evidence. Any `--dialogue-review-*` flag forces the mock in DEBUG.

- `dialogue.png`: short exchange and Behind this reply button.
- `inspection.png`: saved public reading and granular feedback controls.
- `comparison.png`: earlier comparison fixture, superseded by the captures below.
- `inspection-reduce-motion.png`: the inspection under simulator Reduce Motion.
  `com.apple.Accessibility ReduceMotionEnabled` was read as 1 before capture and
  restored to its prior 0 afterward. The feature introduces no custom animation.

Visual inspection: readable serif type, no overlapping feedback controls, full
width scrollable content, 44-point minimum feedback targets. The main conversation
retains the existing design; the detailed sheet uses Theme.paper/Theme.ink.

Build succeeded with `xcodebuild -scheme Alicia -destination
'platform=iOS Simulator,name=iPhone 17'` and isolated derived data. The Swift
save/wire harness passed 12 checks; the existing walk harness passed all 6 cases.
No physical-device, VoiceOver session, microphone/headset, live network or model
quality is claimed by these captures. Selected feedback now supplies accessible
selected/Saved state; actual VoiceOver use remains a device validation step.

## Refined feedback controls

- `quick-vote.png`: Claude alternative tab, independent Helpful rating, one-tap
  Prefer Claude saved without a reason, and optional Add why disclosure.
- `optional-why.png`: six reason chips, fixture-only text, separate training
  review permission off, and Save optional details.
- `quick-feedback-reduce-motion.png`: the same state with Reduce Motion read as
  1 before capture, restored to the prior 0 afterward.

The controls were operated through Simulator against the process-local DEBUG
preview store. A new model tab generated only a fake answer; the rating, vote,
reason chip and text save touched no production state. Simulator screenshots
verify layout and control behavior, not physical-device quality.
