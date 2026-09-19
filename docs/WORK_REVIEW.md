# Review the work together

A2-033 adds an iOS review surface for the backend A2-032 contract. This document describes the implementation; the shared task RELEASE.md records what was actually deployed and uploaded.

Together has a goal selector and separate indicators for review and outcomes. Review counts describe prepared passages that Hector has reviewed; completion describes explicit goal status and reported agreement outcomes. Marking a passage important is neither agreement nor completion. A goal without agreed steps does not get an invented percentage.

Each prepared artifact keeps all original text in deterministic backend sections, including plain Q1/Q7 instruments and their candidate/counterexample passages. Agree and Disagree are exclusive; Important is independent. Answer this, Edit this and Add a note open a field directly under the original. Edits are retained as Hector's words alongside Alicia's original draft. Set aside hides a piece in a recoverable disclosure. The full artifact and individual passages use the shared natural-voice immersive reader; unavailable narration is visibly retryable. See `IMMERSIVE_READING.md`.

Every save uses the existing CollaborationStore outbox. The payload binds a result, section, original-content hash, review revision and durable receipt. A pending save cannot be edited into another request. Separate answer/edit/comment drafts survive navigation and app interruption. Confirmation clears only the acknowledged draft; a failed or stale save retains it. A newer review revision can be adopted explicitly without changing the draft words. New generated versions do not inherit old agreement silently.

Connection Use / Clarify / Dismiss controls use the same visual language at the top of the connection. Existing explicit agreement and outcome controls remain available.

Discuss this in Dialogue opens a visible, persistent goal/passage target. A typed send carries only target identifiers as `work_context`; the server resolves and validates the original passage before model or tool work. Hector's text remains distinct from context. Reply IDs keep a local navigation link when phone conversation history reloads. Clear removes the target. Targeted passage dialogue supports typing and keyboard dictation; the separate Mac voice recorder is disabled while that target is active because its current reviewed-Send contract does not carry a work-review section. Ordinary voice recording remains available after Clear and on existing voice surfaces.

Episode evidence opens its exact Studio episode without starting playback or changing the selected episode frame. Related goal links on episode pages return to Together. The normal Studio play/selection behavior remains explicit and unchanged.

## Verification

Run `scripts/test_collaboration.py` for actual Swift codecs, immutable pending saves, independent drafts, target restoration and existing outbox/notification guards. `scripts/test_work_review_ui.py` builds a temporary XCUITest target around the real app with inert fixtures. Tests cover separate dimensions/goal tabs, inline long answers and navigation, edits/contextual Dialogue, prominent connection decisions and Studio navigation. `--collaboration-preview --work-review-preview` never sends to live transport.

Build on iPhone 17 simulator; inspect screenshots and keyboard states. Simulator results do not establish physical-device typography, dictation accuracy or headset behavior. No new motion, SF Symbols, emoji or dependencies are introduced.

Backend A2-032 must be deployed before the A2-033 branch TestFlight build. The app branches from released source207279e/TestFlight15, preserving the morning and Mac voice fixes while canonical app main is older. No generated build numbers or secrets are committed.
