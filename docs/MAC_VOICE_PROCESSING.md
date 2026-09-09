# Mac voice processing — A2-016 candidate

New voice input follows capture → finish → upload → Mac transcription → review →
explicit send. Capture-only mode asks for microphone permission, preserves the
existing original-audio sink and meter, and does not start an Apple speech task.
The user can take their time. No model interrupts the recording.

Walk's Pause and app interruptions retain an unfinished recording. Finish drains
the sink before freezing an ordered segment manifest. Dialogue's recording button
finishes into the same review surface; interrupted Dialogue recordings can resume
or finish from the composer/Recordings. A new recording cannot extend a sealed
one. Earlier build recordings remain inspectable and are not automatically sealed.

Each recording directory contains original CAFs, an atomic `capture-order.json`,
and `recording.json`. Segment order is written before samples so recovery never
sorts UUIDs or guesses from wall-clock timestamps. Sealing requires every promised
file to be indexed, readable and hash/size matched. An open sink, missing tail or
known capture error refuses sealing. Original files remain available on failure.

The archive persists the immutable seal, optional `transcription` state, editable
review, retry event and immutable submission separately from legacy transcripts.
A machine draft is `transcription.draft` with `kind=mac_whisper` and open provenance;
it never enters human history or the existing submitted/correction versions by
itself. The first ready draft seeds an unedited review only once. A late result
cannot overwrite authored changes. Local write failure keeps the visible edit and
blocks Send until the phone has saved it.

The shared review surface is reachable in Walk, Dialogue and Recordings. It shows
upload progress, Mac state, the editable draft, original replay, processing details
and explicit Send. Its states distinguish local audio, audio received by the Mac,
transcription and words saved with Alicia. It does not promise background uploads:
foreground use resumes pending uploads; the Mac can continue after all sealed
parts arrive. Physical capture, recognition accuracy and phone lock/reconnect
remain device checks, not simulator claims.

## Service contract

- POST `/api/voice_evidence` with action `finalize`, recording/request UUIDs,
  ended_at, capture_status=finished, ordered expected_segments
  `{id,sequence,sha256,bytes}`, language_hint=auto.
- Same endpoint action `retry_transcription`, original seal request_id and a new
  durable event_id. An uncertain retry keeps that exact event.
- Existing GET `/api/voice_evidence` adds optional transcription; state is
  waiting_for_audio, queued, transcribing, ready, failed or cancelled.
- Walk sends reviewed text through the existing exact `/api/mode` receipt with
  recording_id, transcription_request_id and transcript_id, plus captured episode
  and question. It never rotates a pending payload after an uncertain response.
- Dialogue sends through `/api/chat` with client_request_id, text, voice,
  recording_id, transcription_request_id, transcript_id and original episode_id.
- A proactive answer uses `/api/reply` with the same IDs and original proactive_id.
  The captured VoiceContext also retains optional proactive_id; target identity
  does not follow subsequent Studio selection or the current composer target.
- GET `/api/voice_submission?request_id=...` returns the saved result. The phone
  persists attempted before POST and checks status after a lost response. Only a
  definite404 permits an identical repost. Auth/transport/5xx cannot do so. Failed
  and outcome_unknown stop automatic execution. A definite400/409 or a confirmed
  failed receipt exposes an explicit edit action that preserves reviewed words
  and creates a new request on the next Send. An outcome_unknown receipt cannot
  be reopened.

A completed receipt records the submitted voice version locally using the same
request UUID, marked uploaded, and refreshes shared history. It does not enqueue
an independent legacy transcript mutation. Deleted recordings reject late machine
results and pending local sends. Existing original audio replay, explicit later
corrections, short Alicia replies and model-comparison feedback remain available.

## Validation and integration

The temporary unit target in `scripts/test_voice_evidence.py` compiles the actual
archive/models with generated PCM and fake transport. It covers audio integrity,
recovery, complete manifests, pause/finish, deletion races, late draft edits,
immutable submissions, 404 recovery, rejected sends, exact proactive/episode
identity, completed receipts, Walk retries and HTTP classification.

`scripts/test_speech_transcript.py` retains buffer/PCM/revision tests and exercises
capture-only finish and microphone-only permission with inert dependencies.
`scripts/test_walk_save.py` preserves the prior typed/legacy Walk save contract.
`scripts/test_voice_mac_ui.py` uses only the explicit DEBUG
`--voice-evidence-preview --voice-mac-preview` fixture. The existing first flag
forces Mock before configuration. It checks reviewed Dialogue input and an
independent typed draft, the Walk review/original route, and waiting upload copy.
It also captures the microphone-on layout through a labelled inert fixture.
No real microphone, backend state, provider call or release is part of these tests.

Evidence belongs in `/Users/alicia/Documents/Alicia-development/tasks/A2-016/evidence/ios`.
The integrator must review the committed app/backend pair, run the final build,
and deploy the backward-compatible backend before a new TestFlight candidate.
No local model training or historical transcript replacement is implied.
