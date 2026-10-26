# Context enrichment — A2-007

A2-010 adds shared goals and agreements through docs/COLLABORATION.md. Its
purposeful-return policy supersedes the daily reservation below when the
collaboration endpoint is supported; context attention controls remain.

Hector wants a short conversation, an inspectable account of what was supplied,
and quick ways to correct or reprioritize that context. This follows his first
real morning using build 6. It is a candidate until the shared task RELEASE.md
records production and Apple evidence.

## Experience and evidence boundaries

- Behind each reply opens from the stable Dialogue screen, outside recycled
  chat rows. Separate keyboard focus for feedback, correction and reasons keeps
  typed input in place. Comparison polling waits while a field is focused.
- About you is available in Alicia and inside each reply's inspector. Inferred
  claims are labelled tentative; keeps, corrections and added notes retain
  Hector's words. These are selected memory items, not a complete psychological
  portrait or an asserted diagnosis.
- Supplied for this reply shows captured public input sections and source
  material. It does not reveal private model reasoning or operational/system
  instructions. Retrieval summaries are not certified verbatim source quotes.
  Opening a source reads its current file, clearly separate from the frozen
  excerpt. Old replies show only sources actually saved then.
- More, Normal and Less request attention in later prompts. Corrections are
  explicit human context. The latest More/corrected items come first, followed
  by current personal context. The section is bounded to 5,200 characters; long
  items use a labelled 1,200-character excerpt. Limited space means not every
  choice fits. The next reply exposes what was actually supplied. Less requests
  reduced emphasis; it cannot guarantee a source is absent elsewhere. These
  controls neither delete memory nor change model weights.
- The listening page reuses the existing Musubi presence with an outlined
  microphone and explicit On / Opening / Paused state. The recording engine,
  not the user's intention to record, determines On. Reduce Motion and app
  lifecycle use the existing presence behavior. Walk with this now uses ink on
  paper and a lighter invitation rather than a dark block.

## Comparisons and context exposure

Every new iOS reply immediately queues a tool-free opposite-provider answer
using the captured exchange. Qwen runs on the Mac mini; Claude is cloud-hosted.
Adapted context is labelled, and those pairs stay out of same-input training
exports. There is one automatic worker and capacity for eight pending/running
requests. Full queues or failures are visible and manually retryable. Opening
the inspector reads prepared results; it does not need to start the model.
Legacy unprepared replies still offer a request. No actions are rerun.

Votes remain contextual preferences with optional reasons and explicit export
permission. There is no automatic fine-tuning, model promotion or Labs result.
Context enrichment is a prompt-level feedback mechanism, not training consent.

## One gentle return

Hector chose: one gentle follow-up for a specific unresolved idea, quiet hours,
and a stop control. The existing reply/frame generation may prepare an optional
invitation of at most 300 characters with a 10–200 character exact anchor in
his latest statement. Greetings, short utterances and resolved requests should
produce none. Models still judge whether an idea is unresolved; the exact
anchor makes that choice inspectable rather than proving the judgment right.

The backend exposes only the newest candidate, at least two hours later,
between 09:00 and 19:00 America/Los_Angeles by default (ALICIA_TIMEZONE override),
within 24 hours of the statement. A later human input or context edit invalidates
older candidates. Walk frames bind to the exact human event. A new ordinary
reply with no invitation suppresses an older one.

The iPhone schedules a local notification while synced, with authorization and
its own quiet-hour check. At most one reservation per local day is made after a
successful schedule. Cancelling holds that day's reservation, favoring silence.
New input/walk entry cancels locally; Stop cancels immediately even if the server
save is unconfirmed. New activity on another device is seen on the next sync.
This is not APNs delivery: a disconnected phone may retain an older invitation,
and iOS permission/Focus settings can silence it. No new Telegram routine,
scheduler JobSpec or background model call is introduced.

## Wire and storage

- `GET /api/context_enrichment?reply_id=UUID` — current picture, decorated frozen
  items, exposure statement, follow-up setting and optional prepared candidate.
  Omit reply_id for the current picture.
- `GET /api/context_enrichment?reply_id=UUID&item_id=ID` — current captured source
  file. Identity must belong to that reply; resolved paths/symlinks must remain
  within ALICIA_VAULT_ROOT, be Markdown, and stay below 300 KB.
- `POST /api/context_enrichment` — `action` item/add_note/settings, UUID event_id,
  reply_id/item_id where relevant, priority more/normal/less, correction/text
  up to 2,000 characters, or explicit boolean followups_enabled. All routes
  require existing iOS authentication.
- `memory/context_enrichment.jsonl` — typed, bridge-validated, locked/fsynced
  append-only events. Identical receipts are no-ops; conflicting reuse fails.
  Saved requests preserve identity across later edits and uncertain retries.
- `dialogue_review.jsonl` adds context_items/revision/prepared_at and optional
  followup. `episode_day.jsonl` frame data adds followup/followup_for. Historical
  records remain valid and unmodified.
- `context_enrichment` loop checks whether a requested reply includes the choices
  revision and public context section available during preparation. It does not
  claim that every prioritized item fits or that a model obeyed it.

Validation and exact release receipts are recorded in the shared A2-007 task.
Tests use temporary journals, fixture sources and fake providers. Physical-device
microphone/headset, keyboard and notification delivery require Hector's use;
simulator evidence is not a physical walk or proof that a probe helped him think.
