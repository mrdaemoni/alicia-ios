# Immersive natural reading — A2-037

The shared reader brings the Scale of Us reading behavior into native SwiftUI:
quiet paragraphs, measured word focus, tap a word to seek, and follow-scroll that
yields to a manual drag. The Follow voice control restores following. Reduce
Motion uses immediate positioning. This ports interaction behavior; it does not
embed the website or introduce a third-party runtime.

Listen opens this reader. The global reading bar's title reopens it later.
Original podcasts and prepared morning briefings keep their original recordings.
Dialogue voice replies use the same reader. Together's review actions now ask for
natural server narration; no AVSpeechSynthesizer or device voice remains.
Preparation, unavailable media and retry are explicit. Opening text never starts
audio. A deliberate Listen or Read along does.

`POST /api/speak` asks for `required_backend: gemini`. Existing chunk playback
accepts additive exact `spoken_text`, chunk `text`, `cues`, `timing_status`, and
`speech_backend`. Cue times are measured chunk-relative seconds; character
indexes are Python Unicode scalar indexes into the exact chunk text. Invalid or
mismatched cues are ignored. No word timing is estimated from a character count,
reading speed, or shownotes. Paragraph boundaries remain visible. Without exact
alignment the text is readable and only an available chunk can receive focus.

Studio's **Read along with this episode** explicitly starts
`POST /api/episode_reading {episode_id}` and polls read-only GET while text is
prepared. Existing playback can continue. Once ready, the shared reader uses the
original podcast audio and resumes at the current Studio position. Switching back to Studio transfers that position
and stops the shared reader before Studio plays; callbacks from the paused player
cannot advance listening evidence or auto-select another track. The text is
labelled a machine transcript of that audio, not an approved script. If preparing
fails, normal episode playback remains available. Leaving the view cancels app
polling, not the Mac's durable preparation.

**Next episode** appears in Us and Studio from the latest actual positive player
progress, persisted on the phone, compared with optional server
`episode_day.latest_playback {episode_id, observed_at}`. Selection, file downloads,
app launches, seeks and stalled time do not advance it. Published numbered
seasons use chronological season/episode ordering within the same series; named
runs continue within their own collection. No matching successor means no guessed
button. Topic selection changes only when Hector presses Listen.

## Voice interpretation review

Recordings exposes A2-036's additive `enrichment`: coverage (including whether the
ending was covered), anchored findings, tentative goal answers, uncertainty, and
actual pass/provider receipts. These are machine interpretations, distinct from
submitted messages and human agreements. Right / Not right / Salient / Clarify
plus optional text send the exact analysis/item identity. A UUID and immutable
payload are stored before sending; an uncertain response exposes Retry and keeps
the text locked until acknowledged. A newer analysis gets a fresh view identity; older
uncertain feedback remains separately readable and retryable under its original
analysis and item. Async acknowledgment removes only that original receipt. Refresh itself is read-only. Stale findings
cannot receive new feedback. Original audio and transcript correction paths stay
separate.

## Validation and release

`scripts/test_narration.py` covers exact Unicode offsets, paragraph preservation,
invalid/missing alignment, chronological continuation and stale receipts.
`scripts/test_reading_media.py` exercises actual player lifecycle methods with
inert media; `test_reading_handoff.py` verifies Studio/reader ownership and
position transfer; `test_voice_enrichment.py` checks additive decoding and immutable
feedback receipts. `test_narration_ui.py` uses mock-only DEBUG previews and saves
measured-focus, unavailable and Reduce Motion screenshots. No fixture claims a
real listening observation, voice capture or physical-device validation.

Backend A2-036 and A2-038 must deploy before the dependent TestFlight build. The
shared A2-037 task records own the exact release evidence. Canonical main and
physical visual promotion remain separate from branch TestFlight testing.
