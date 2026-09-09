# Voice capture, revisions and save feedback

## September 8 field audit — A2-014

Both retained recordings are complete: 18.4 and 202.2 seconds across 23 CAF segments,
with matching bytes/hashes and successful decoding. There is no observed upload
truncation. Some submitted clauses repeat, and some words are uncertain. Full
local ASR recovery is review evidence, not an automatic human correction.

SpeechTranscriptBuffer replaces the latest hypothesis as a unit while its
segment timings remain unresolved. A later timed revision no longer causes the
same provisional words to be kept as a completed prefix. Earlier independently
timed words and actual repeated speech still survive. Recognition request
boundaries, retained raw audio and explicit-save semantics are unchanged.

Verification: 35 buffer/queue/lifecycle cases, including 10 new revision cases,
and iPhone 17 simulator compilation. Device hypothesis timing was not logged;
the deterministic reproduction explains a possible duplication path rather
than proving the exact callback sequence on Hector's phone. Physical recognition
quality and interruption behavior still require real use.

## Existing capture and receipt behavior — A2-013

The microphone surface shows whether capture is on, the actual route name,
audio seconds and level. Live text and retained original audio have separate
status. Bounded recognition handoffs preserve earlier words and temporarily
queue incoming audio. Timeouts or overflow require transcript review. The raw
recording continues independently. Finish gives the last hypothesis time to arrive.

Walk confirmation stays open until Done. A server-acknowledged reflection,
local recording, upload progress and audio-only save have distinct copy. Audio-only
saves never claim words reached Alicia. A later explicit correction is separate
from original audio and earlier text versions. Dialogue stops accepting dictation
when capture stops so later typing cannot be replaced by an old hypothesis.

The September7 retained voice evidence totaled333.3seconds in35 CAF segments;
only13 transcript characters were submitted. The private full-file local ASR
recovery is unconfirmed. Nothing was promoted to Hector's correction or learning.

Physical headset routing, speech accuracy and interruption behavior still need
Hector's next-device session. Simulator tests validate controls and receipts,
not the accuracy of a real microphone or a completed real-world walk.
